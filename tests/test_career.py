from copy import deepcopy
from datetime import timedelta
from concurrent.futures import ThreadPoolExecutor
import uuid
import pytest
from backend import career,game,analytics
from backend.engine import stamp
from conftest import authorization,mutate


def payload(r):
    assert r.status_code in (200,201),r.text
    return r.json()['data']


def complete(c,h,aid):
    plan=payload(mutate(c,h,'POST','/api/me/plan/items',dict(activity_id=aid,accept_no_goal_gain=True)))
    pid=next(p['id'] for p in plan['items'] if p['activity_id']==aid)
    payload(mutate(c,h,'POST',f'/api/me/plan/items/{pid}/start'))
    return pid,payload(mutate(c,h,'POST',f'/api/me/plan/items/{pid}/complete',dict(confirmed=True,note='personal note')))


def test_control_example_completion_is_not_assessment_or_xp(scenario):
    c,engine,_=scenario;h=authorization(c)
    p=payload(c.get('/api/me/progress',headers=h));assert p['assessed_readiness']==73.6111
    rec=payload(c.get('/api/me/recommendations',headers=h))
    assert [x['activity']['id'] for x in rec['items']]==['sql','analytics','communication']
    assert rec['items'][0]['standalone_delta_pp']==pytest.approx(6.25)
    pid,out=complete(c,h,'sql');assert out['progress']['estimated_readiness']==79.8611
    assert out['progress']['assessed_readiness']==73.6111
    assert payload(c.get('/api/me/season',headers=h))['confirmed_xp']==0
    retry=payload(mutate(c,h,'POST',f'/api/me/plan/items/{pid}/complete',dict(confirmed=True)))
    assert retry['already_completed']
    assert retry['completion']['id']==out['completion']['id']
    _,out=complete(c,h,'analytics');assert out['progress']['estimated_readiness']==85.4167
    with engine.transaction() as s:
        s['employees']['E1']['assessment_at']=stamp(engine.clock()+timedelta(seconds=1))
    assert payload(c.get('/api/me/progress',headers=h))['estimated_readiness']==73.6111
    assert payload(c.get('/api/me/history',headers=h))['total']==2


def test_missing_assessments_not_zero_and_prerequisites_use_assessment(scenario):
    c,engine,clock=scenario;h=authorization(c)
    complete(c,h,'sql')
    with engine.transaction() as s:
        s['activities']['analytics']['prerequisites']={'SQL':65}
    assert mutate(c,h,'POST','/api/me/plan/items',dict(activity_id='analytics')).json()['error']['code']=='PREREQUISITE_NOT_MET'
    with engine.transaction() as s:
        del s['employees']['E1']['skills']['Communication']
    p=payload(c.get('/api/me/progress',headers=h))
    assert p['status']=='needs_assessment' and p['estimated_readiness'] is None
    assert payload(c.get('/api/me/recommendations',headers=h))['items']==[]
    complete(c,h,'communication')
    p=payload(c.get('/api/me/progress',headers=h))
    assert next(r for r in p['skills'] if r['skill_id']=='Communication')['estimated_level'] is None


def test_idempotency_concurrent_plan_limit_and_owner(scenario):
    c,e,_=scenario;h=authorization(c);other=authorization(c,'colleague')
    rev=c.get('/api/reference',headers=h).json()['meta']['state_revision'];key=str(uuid.uuid4())
    r=mutate(c,h,'POST','/api/me/plan/items',dict(activity_id='sql'),rev,key)
    again=mutate(c,h,'POST','/api/me/plan/items',dict(activity_id='sql'),rev,key)
    assert r.json()==again.json()
    assert mutate(c,h,'POST','/api/me/plan/items',dict(activity_id='analytics'),rev,key).json()['error']['code']=='IDEMPOTENCY_CONFLICT'
    pid=payload(r)['items'][0]['id']
    assert mutate(c,other,'POST',f'/api/me/plan/items/{pid}/start').status_code==404
    payload(mutate(c,h,'POST','/api/me/plan/items',dict(activity_id='analytics')))
    with e.transaction() as s:s['activities']['extra']['available_from']=None
    rev=c.get('/api/reference',headers=h).json()['meta']['state_revision']
    with ThreadPoolExecutor(2) as pool:
        results=list(pool.map(lambda aid:mutate(c,h,'POST','/api/me/plan/items',dict(activity_id=aid),rev),['extra','communication']))
    assert sorted(r.status_code for r in results)==[201,409]
    assert len(payload(c.get('/api/me/plan',headers=h))['items'])==3
    assert mutate(c,h,'POST','/api/me/plan/items',dict(activity_id='communication')).status_code==409


def test_simulation_no_side_effect_and_stale_atomic_apply(scenario):
    c,e,_=scenario;h=authorization(c)
    body=dict(role_id='Engineer',grade_id='Middle',activity_ids=['sql','analytics'])
    before=payload(c.get('/api/me/plan',headers=h))
    sim=payload(c.post('/api/me/simulations',headers=h,json=body))
    assert sim['after']['estimated_readiness']==85.4167
    assert payload(c.get('/api/me/plan',headers=h))==before
    other=authorization(c,'colleague')
    assert mutate(c,other,'POST',f'/api/me/simulations/{sim["id"]}/apply',dict(confirm_replace_plan=True)).status_code==404
    result=payload(mutate(c,h,'POST',f'/api/me/simulations/{sim["id"]}/apply',dict(confirm_replace_plan=True)))
    assert len(result['plan']['items'])==2
    assert payload(c.get('/api/me/progress',headers=h))['estimated_readiness']==73.6111
    assert mutate(c,h,'POST',f'/api/me/simulations/{sim["id"]}/apply',dict(confirm_replace_plan=True)).json()['error']['code']=='STALE_STATE'


def test_goal_confirm_archive_and_replace_rollback(scenario):
    c,e,_=scenario;h=authorization(c)
    plan=payload(mutate(c,h,'POST','/api/me/plan/items',dict(activity_id='sql')))
    pid=plan['items'][0]['id']
    assert mutate(c,h,'POST',f'/api/me/plan/items/{pid}/replace',dict(activity_id='missing')).status_code==404
    assert payload(c.get('/api/me/plan',headers=h))['items'][0]['id']==pid
    assert mutate(c,h,'PUT','/api/me/goal',dict(role_id='Engineer',grade_id='Senior')).json()['error']['code']=='CONFIRMATION_REQUIRED'
    payload(mutate(c,h,'PUT','/api/me/goal',dict(role_id='Engineer',grade_id='Senior',confirm_archive_plan=True)))
    assert payload(c.get('/api/me/plan',headers=h))['items']==[]


def test_scheduled_windows_conflict_and_self_paced_expiry(scenario):
    c,e,clock=scenario;h=authorization(c)
    with e.transaction() as s:
        for k in ['sql','analytics']:
            s['activities'][k].update(kind='scheduled',starts_at=stamp(clock[0]+timedelta(hours=1)),ends_at=stamp(clock[0]+timedelta(hours=2)))
    pid=payload(mutate(c,h,'POST','/api/me/plan/items',dict(activity_id='sql')))['items'][0]['id']
    assert mutate(c,h,'POST','/api/me/plan/items',dict(activity_id='analytics')).json()['error']['code']=='SCHEDULE_CONFLICT'
    assert mutate(c,h,'POST',f'/api/me/plan/items/{pid}/start').status_code==409
    clock[0]+=timedelta(hours=1)
    payload(mutate(c,h,'POST',f'/api/me/plan/items/{pid}/start'))
    assert mutate(c,h,'POST',f'/api/me/plan/items/{pid}/complete',dict(confirmed=True)).status_code==409
    clock[0]+=timedelta(hours=1)
    payload(mutate(c,h,'POST',f'/api/me/plan/items/{pid}/complete',dict(confirmed=True)))


def test_hr_null_ratios_csv_and_passport_privacy(scenario):
    c,e,clock=scenario;hr=authorization(c,'hr');h=authorization(c)
    p=payload(c.get('/api/hr/overview?department=unknown',headers=hr))
    assert p['kpis']['participation']['value'] is None
    with e.transaction() as s:s['employees']['E1']['department']='=SUM(1,2)'
    csv=c.get('/api/hr/reports/skill-gaps.csv',headers=hr)
    assert csv.content.startswith(b'\xef\xbb\xbf') and "'=SUM(1,2)" in csv.text
    complete(c,h,'sql')
    md=c.get('/api/me/passport/download',headers=h).text
    assert 'personal note' not in md and 'E2' not in md


def test_gain_cap_allocation_and_imported_history_do_not_change_assessment(scenario):
    c,e,clock=scenario;h=authorization(c)
    with e.transaction() as s:
        s['employees']['E1']['skills']['SQL']=95
        s['activities']['extra']['available_from']=None
    complete(c,h,'sql');complete(c,h,'extra')
    p=payload(c.get('/api/me/progress',headers=h))
    skill=next(r for r in p['skills'] if r['skill_id']=='SQL')
    assert skill['assessed_level']==95 and skill['estimated_level']==100
    assert sum(r['effective_gain'] for r in skill['contributions'])==5
    with e.transaction() as s:
        s['imported_history'].append(dict(employee_id='E1',activity_id='communication',status='completed',origin='imported',completed_at=stamp(clock[0]),started_at=None,registered_at=None,attended_at=None))
    p=payload(c.get('/api/me/progress',headers=h))
    assert next(r for r in p['skills'] if r['skill_id']=='Communication')['estimated_level']==50


def test_attendance_counts_registration_without_fabricating_attendance(scenario):
    c,e,clock=scenario;hr=authorization(c,'hr')
    with e.transaction() as s:
        start=clock[0]-timedelta(hours=2);end=clock[0]-timedelta(hours=1)
        s['activities']['sql'].update(kind='scheduled',starts_at=stamp(start),ends_at=stamp(end))
        for eid in ['E1','E2']:
            s['imported_history'].append(dict(employee_id=eid,activity_id='sql',status='registered',origin='imported',registered_at=stamp(start-timedelta(days=1)),attended_at=stamp(start+timedelta(minutes=1)) if eid=='E1' else None,started_at=None,completed_at=None))
    row=payload(c.get('/api/hr/activities',headers=hr))['items'][0]
    assert row['attendance']==dict(numerator=1,denominator=2,value=.5)
    assert row['participants']==1


def test_unknown_filters_and_bad_dates_are_422(scenario):
    c,_,_=scenario;h=authorization(c);hr=authorization(c,'hr')
    assert c.get('/api/activities?employe_id=E2',headers=h).status_code==422
    assert c.get('/api/hr/overview?date_from=2030-01-01',headers=hr).status_code==422
    assert mutate(c,hr,'POST','/api/hr/seasons',dict(name='Bad',starts_at='nonsense',employee_ids=['E1'],virtual_budget_kzt=1250000)).status_code==422
