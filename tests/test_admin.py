"""Administrative security, migration, snapshots, concurrency and atomic accounting."""
from copy import deepcopy
from datetime import timedelta
import uuid

from fastapi.testclient import TestClient
from backend.main import create_app
from backend import game
from backend.engine import stamp
from conftest import authorization, login, mutate


def auth(client, role='superadmin'):
    password='SuperTest123!' if role=='superadmin' else 'AdminTest123!'
    session=login(client,role+'.demo',password)
    return {'Authorization':'Bearer '+session['token']}


def ok(response):
    assert response.status_code==200,response.text
    return response.json()['data']


def change(client,headers,path,payload,target='global'):
    return ok(mutate(client,headers,'POST','/api/admin/'+path,
                     dict(payload=payload,target_id=target,reason='Проверка административного изменения')))['id']


def publish(client,headers,key):
    preview=ok(mutate(client,headers,'POST',f'/api/admin/changes/{key}/preview'))
    assert preview['can_publish'],preview
    return ok(mutate(client,headers,'POST',f'/api/admin/changes/{key}/publish',
              dict(preview_id=preview['preview_id'],reason='Публикация проверенной версии'),revision=preview['base_revision']))


def test_permissions_not_inferred_from_login_or_client(client):
    employee=authorization(client);hr=authorization(client,'hr');admin=auth(client,'admin')
    assert client.get('/api/admin/users',headers=employee).status_code==403
    assert client.get('/api/admin/users',headers=hr).status_code==403
    assert client.get('/api/admin/overview',headers=admin).status_code==200
    assert mutate(client,admin,'POST','/api/admin/users/hr.demo/access',
                  dict(role='super_admin',active=True,permissions=[],reason='Bad promotion')).status_code==403
    assert client.post('/api/auth/login',json=dict(username='employee.demo',password='Employee123!',role='super_admin')).status_code==422
    assert '/api/admin/imports/preview' not in client.get('/openapi.json').json()['paths']


def test_access_revocation_last_super_and_unknown_permission(client):
    superadmin=auth(client); employee=authorization(client)
    result=mutate(client,superadmin,'POST','/api/admin/users/employee.demo/access',
                  dict(role='employee',active=False,permissions=[],reason='Блокировка тестового аккаунта'))
    ok(result)
    assert client.get('/api/me/profile',headers=employee).status_code==401
    assert client.get('/api/admin/employees/E1',headers=superadmin).status_code==200
    assert mutate(client,superadmin,'POST','/api/admin/users/superadmin.demo/access',
        dict(role='employee',active=True,permissions=[],reason='Попытка изменить собственный доступ')).status_code==403
    assert mutate(client,superadmin,'POST','/api/admin/users/hr.demo/access',
        dict(role='hr',active=True,permissions=['invented.root'],reason='Неизвестное разрешение')).status_code==422


def test_publish_stale_preview_and_retry(client):
    headers=auth(client)
    rules=ok(client.get('/api/admin/recommendation-policies',headers=headers))['value']
    rules['max_steps']=5
    key=change(client,headers,'recommendation-policies',rules)
    p=ok(mutate(client,headers,'POST',f'/api/admin/changes/{key}/preview'))
    change(client,headers,'recommendation-policies',{**rules,'max_steps':6})
    stale=mutate(client,headers,'POST',f'/api/admin/changes/{key}/publish',dict(preview_id=p['preview_id'],reason='Старый предпросмотр'))
    assert stale.status_code==409 and stale.json()['error']['code']=='STALE_PREVIEW'
    p=ok(mutate(client,headers,'POST',f'/api/admin/changes/{key}/preview'))
    body=dict(preview_id=p['preview_id'],reason='Проверенная публикация'); request_key=str(uuid.uuid4())
    first=mutate(client,headers,'POST',f'/api/admin/changes/{key}/publish',body,revision=p['base_revision'],key=request_key)
    second=mutate(client,headers,'POST',f'/api/admin/changes/{key}/publish',body,revision=p['base_revision'],key=request_key)
    assert first.json()==second.json();ok(first)
    assert ok(client.get('/api/runtime-config',headers=authorization(client)))['recommendations']['max_steps']==5


def test_edit_invalidates_preview(client):
    h=auth(client);body=ok(client.get('/api/admin/branding',headers=h))['value']
    key=change(client,h,'branding',body)
    p=ok(mutate(client,h,'POST',f'/api/admin/changes/{key}/preview'))
    ok(mutate(client,h,'POST','/api/admin/branding',dict(payload={**body,'banner':'Новый баннер'},change_id=key,target_id='global',reason='Изменение после расчёта')))
    assert mutate(client,h,'POST',f'/api/admin/changes/{key}/publish',dict(preview_id=p['preview_id'],reason='Устаревший расчёт')).status_code==409


def test_pass_amendment_delta_only_and_no_decrease(scenario):
    client,engine,clock=scenario; h=auth(client)
    with engine.transaction() as s:
        season=game.choose_season(s);sid=season['id'];season['virtual_budget_kzt']+=100000
        game.emit_xp(s,season,'E1','daily','seed',200,stamp(clock[0]),clock[0]);game.award_followups(s,season,'E1',clock[0])
        before=game.wallet(s,'E1')['balance'];rewards=deepcopy(season['rewards'])
    assert before==5
    rewards[0]['components'][0]['coins']=10
    key=ok(mutate(client,h,'PATCH',f'/api/admin/seasons/{sid}/pass',dict(payload={'rewards':rewards},reason='Увеличить награду первого уровня')))['id']
    publish(client,h,key)
    with engine.transaction() as s:
        assert game.wallet(s,'E1')['balance']==10
        game.award_followups(s,s['seasons'][sid],'E1',clock[0]);assert game.wallet(s,'E1')['balance']==10
    rewards[0]['components'][0]['coins']=1
    bad=ok(mutate(client,h,'PATCH',f'/api/admin/seasons/{sid}/pass',dict(payload={'rewards':rewards},reason='Попытка ухудшения награды')))['id']
    p=ok(mutate(client,h,'POST',f'/api/admin/changes/{bad}/preview'))
    assert p['can_publish'] is False and p['blocking_errors'][0]['code']=='PROMISED_REWARD'


def test_daily_reward_and_attempts_are_snapshots(scenario):
    client,engine,clock=scenario;h=auth(client);e=authorization(client)
    tasks=ok(client.get('/api/me/season/tasks',headers=e))['items'];first=tasks[0]
    sid=first['season_id'];rules=ok(client.get('/api/admin/economy-policies',params={'target_id':sid},headers=h))['value']
    key=change(client,h,'economy-policies',{**rules,'daily_xp':333,'attempts':6},sid);publish(client,h,key)
    unchanged=ok(client.get('/api/me/season/tasks',headers=e))['items'][0]
    assert unchanged['xp']==100 and unchanged['max_attempts']==3
    clock[0]+=timedelta(days=1)
    new=ok(client.get('/api/me/season/tasks',headers=e))['items'][0]
    assert new['xp']==333 and new['max_attempts']==6


def test_sku_snapshot_and_inventory_atomicity(scenario):
    client,engine,clock=scenario;h=auth(client);e=authorization(client)
    with engine.transaction() as s:
        sid=game.choose_season(s)['id'];game.coin(s,'E1',sid,'pass_level','fixture',50000,clock[0])
        item=next(i for i in s['items'].values() if i['shop_visible'])
        iid=item['id'];price=item['coin_price'];version=item['version']
    order=ok(mutate(client,e,'POST','/api/me/shop/orders',dict(item_id=iid,expected_item_version=version,expected_coin_price=price)))
    schema_fields=ok(client.get('/api/admin/shop/items',headers=h))['schema']['properties']
    payload={k:item[k] for k in schema_fields if k in item};payload['name']='Обновлённый товар';payload['coin_price']=price+10
    key=change(client,h,'shop/items',payload,iid);publish(client,h,key)
    old=ok(client.get('/api/me/reward-orders/'+order['id'],headers=e))
    assert old['item_snapshot']['coin_price']==price and old['item_snapshot']['name']!=payload['name']
    assert mutate(client,h,'POST','/api/admin/inventory/movements',dict(item_id=iid,delta=-1000,reason='Недопустимое списание')).status_code==409
    with engine.transaction() as s: assert s['items'][iid]['reserved']==1


def test_correction_atomic_preview_and_signed_events(scenario):
    client,engine,clock=scenario;h=auth(client)
    with engine.transaction() as s:
        se=game.choose_season(s);sid=se['id'];game.emit_xp(s,se,'E1','daily','origin',150,stamp(clock[0]),clock[0])
        before=deepcopy(s['xp'])
    payload=dict(reason='Исправление подтверждённой ошибки тестового начисления',actions=[dict(type='xp',employee_id='E1',season_id=sid,delta=-50)])
    case=ok(mutate(client,h,'POST','/api/admin/corrections',payload))
    preview=ok(mutate(client,h,'POST',f'/api/admin/corrections/{case["id"]}/preview'))
    assert preview['can_publish'] and preview['xp_delta']==-50
    ok(mutate(client,h,'POST',f'/api/admin/corrections/{case["id"]}/apply',dict(preview_id=preview['preview_id'],reason=payload['reason'])))
    with engine.transaction() as s:
        assert s['xp']==before and game.xp_total(s,sid,'E1')==100
    payload['actions']=[dict(type='xp',employee_id='E1',season_id=sid,delta=-200),dict(type='coins',employee_id='E1',season_id=sid,delta=999999)]
    case=ok(mutate(client,h,'POST','/api/admin/corrections',payload));p=ok(mutate(client,h,'POST',f'/api/admin/corrections/{case["id"]}/preview'))
    assert not p['can_publish']
    with engine.transaction() as s: assert game.xp_total(s,sid,'E1')==100 and game.wallet(s,'E1')['balance']==0


def test_restart_keeps_published_settings_and_accounts(kit):
    with TestClient(create_app(*kit)) as c:
        h=auth(c);rules=ok(c.get('/api/admin/branding',headers=h))['value'];rules['banner']='Сохранённый баннер'
        publish(c,h,change(c,h,'branding',rules))
    with TestClient(create_app(*kit)) as c:
        h=auth(c)
        assert ok(c.get('/api/runtime-config',headers=h))['branding']['banner']=='Сохранённый баннер'
        assert ok(c.get('/api/admin/system/health',headers=h))['integrity']=='ok'


def test_passwords_never_in_audit_or_export(client):
    h=auth(client)
    ok(mutate(client,h,'POST','/api/admin/users',dict(username='new.employee',display_name='Новый сотрудник',
        employee_id='E1',password='TemporarySecret123!',reason='Создание тестового сотрудника')))
    session=login(client,'new.employee','TemporarySecret123!');user={'Authorization':'Bearer '+session['token']}
    assert client.get('/api/me/profile',headers=user).status_code==403
    response=client.post('/api/auth/password',headers=user,json=dict(current_password='TemporarySecret123!',new_password='ChangedSecret123!'))
    assert response.status_code==200
    assert client.get('/api/auth/me',headers=user).status_code==401
    for path in ['/api/admin/audit','/api/admin/config-exports','/api/runtime-config','/api/admin/users']:
        response=client.get(path,headers=h)
        assert 'TemporarySecret' not in response.text and 'ChangedSecret' not in response.text and 'password_hash' not in response.text


def correct(client,headers,actions,can_apply=True):
    reason='Исправление подтверждённой ошибки в тестовой базе'
    case=ok(mutate(client,headers,'POST','/api/admin/corrections',dict(reason=reason,actions=actions)))
    p=ok(mutate(client,headers,'POST',f'/api/admin/corrections/{case["id"]}/preview'))
    assert p['can_publish']==can_apply,p
    if can_apply:
        ok(mutate(client,headers,'POST',f'/api/admin/corrections/{case["id"]}/apply',dict(preview_id=p['preview_id'],reason=reason)))
    return p


def test_legacy_hr_cannot_bypass_capabilities(client):
    h=authorization(client,'hr')
    assert mutate(client,h,'POST','/api/hr/seasons',dict(name='Forbidden',starts_at='2027-01-01T00:00:00+05:00',employee_ids=['E1'],virtual_budget_kzt=2000000)).status_code==403
    assert mutate(client,h,'PATCH','/api/hr/shop/items/anything',dict(coin_price=100)).status_code==403


def test_dynamic_roles_requirements_and_runtime_content(scenario):
    c,e,clock=scenario;h=auth(c);employee=authorization(c)
    before=ok(c.get('/api/me/progress',headers=employee))
    role=dict(role_id='Engineer',grade_id='Middle',rank=2,active=True,requirements={'SQL':{'level':70,'weight':3},'Analytics':{'level':60,'weight':2},'Communication':{'level':60,'weight':1}})
    publish(c,h,change(c,h,'career-roles',role,'Engineer|Middle'))
    after=ok(c.get('/api/me/progress',headers=employee))
    assert after['estimated_readiness']>before['estimated_readiness']
    assert [(r['skill_id'],r['assessed_level']) for r in sorted(after['skills'],key=lambda r:r['skill_id'])]==[(r['skill_id'],r['assessed_level']) for r in sorted(before['skills'],key=lambda r:r['skill_id'])]
    new_role={**role,'grade_id':'Principal','rank':5}
    publish(c,h,change(c,h,'career-roles',new_role,'Engineer|Principal'))
    assert any(r['grade_id']=='Principal' for r in ok(c.get('/api/reference',headers=employee))['roles'])
    ok(mutate(c,employee,'PUT','/api/me/goal',dict(role_id='Engineer',grade_id='Principal',confirm_archive_plan=True)))
    content=dict(locale='ru',entries=[dict(key='season.title',value='Мой сезон')])
    publish(c,h,change(c,h,'content',content))
    assert ok(c.get('/api/runtime-config',headers=employee))['content']==content


def test_partial_assessment_keeps_other_skill_gains_and_plan_snapshot(scenario):
    from backend import career
    c,e,clock=scenario;h=auth(c)
    with e.transaction() as s:
        s['completions']['done']=dict(id='done',employee_id='E1',activity_id='sql',completed_at=stamp(clock[0]-timedelta(hours=1)),gains={'SQL':10})
        career.add_plan(s,'E1',dict(activity_id='analytics',accept_over_budget=True),clock[0])
        original=career.plan(s,'E1',clock[0])['forecast']['estimated_readiness']
        s['activities']['analytics']['gains']={'Analytics':20}
        assert career.plan(s,'E1',clock[0])['forecast']['estimated_readiness']==original
    ok(mutate(c,h,'POST','/api/admin/employees/E1/assessments',dict(assessed_at=stamp(clock[0]),skills={'Communication':65},source='Новая оценка',reason='Оценка отдельного навыка')))
    with e.transaction() as s:
        assert career.levels(s,'E1')['SQL']==70
        assert s['employees']['E1']['skills']['SQL']==60


def test_corrected_review_activity_and_signed_history(scenario):
    c,e,clock=scenario;h=auth(c)
    with e.transaction() as s:
        se=game.choose_season(s);sid=se['id']
        s['completions']['done']=dict(id='done',employee_id='E1',activity_id='sql',completed_at=stamp(clock[0]),gains={'SQL':10})
        s['reviews']['r']=dict(id='r',completion_id='done',employee_id='E1',season_id=sid,status='rejected',xp_amount=100,effective_at=stamp(clock[0]))
    correct(c,h,[dict(type='review',source_id='r',decision='approved')])
    with e.transaction() as s:
        assert game.leaderboard(s,s['seasons'][sid])['entries'][0]['confirmed_activity_count']==1
        assert len(game.confirmed_days(s,sid,'E1'))==1
        earned=game.xp_total(s,sid,'E1')
    correct(c,h,[dict(type='review',source_id='r',decision='rejected')])
    with e.transaction() as s:
        assert game.xp_total(s,sid,'E1')==earned-100
        assert game.confirmed_days(s,sid,'E1')==set()
        assert len(s['review_revisions'])==2


def test_revalue_closed_season_exact_outstanding_reserve(scenario):
    c,e,clock=scenario;h=auth(c)
    with e.transaction() as s:
        se=game.choose_season(s);sid=se['id'];se['status']='closed'
        game.coin(s,'E1',sid,'pass_level','fixture',50,clock[0]);se['virtual_budget_kzt']+=1000
        commitment=se['committed_budget_kzt']
    p=correct(c,h,[dict(type='revalue',season_id=sid,coin_backing=120)])
    assert p['budget_delta_kzt']==1000 and p['coin_delta']==0
    with e.transaction() as s:
        assert game.wallet(s,'E1')['balance']==50
        assert game.economy(s,s['seasons'][sid])['wallet_liability_kzt']==6000
        assert s['seasons'][sid]['committed_budget_kzt']==commitment+1000


def test_final_result_amendment_is_difference_not_second_prize(scenario):
    c,e,clock=scenario;h=auth(c)
    with e.transaction() as s:
        se=game.choose_season(s);sid=se['id'];se['virtual_budget_kzt']+=100000
        se['policies']['leaderboards'].update(min_xp=0,min_days=0)
        game.emit_xp(s,se,'E1','daily','fixture',150,stamp(clock[0]),clock[0])
        game.finalize(s,se,clock[0]);original=game.wallet(s,'E1')['balance']
    actions=[dict(type='xp',employee_id='E2',season_id=sid,delta=200),dict(type='recalculate_results',season_id=sid,retain_prior_prizes=True)]
    p=correct(c,h,actions);assert p['coin_delta']==100
    repeated=correct(c,h,[dict(type='recalculate_results',season_id=sid,retain_prior_prizes=True)])
    assert repeated['coin_delta']==0
    with e.transaction() as s:
        assert game.wallet(s,'E1')['balance']==original
        assert len(s['result_revisions'])==2


def test_quest_snapshot_archive_and_answers_not_exported(scenario):
    c,e,clock=scenario;h=auth(c);employee=authorization(c)
    with e.transaction() as s:sid=game.choose_season(s)['id']
    quest=dict(id='safety',title='Проверка',instructions='Выберите вариант',kind='structured',answer_fields=[dict(key='choice',label='Вариант',type='choice',options=['Да','Нет'])],expected_answer={'choice':'Да'},xp=70)
    publish(c,h,change(c,h,'quest-templates',{'items':[quest]},sid))
    tasks=ok(c.get('/api/me/season/tasks',headers=employee))['items'];custom=next(t for t in tasks if t['kind']=='safety')
    assert 'expected_answer' not in str(tasks)
    publish(c,h,change(c,h,'quest-templates',{'items':[{**quest,'xp':90,'active':False}]},sid))
    saved=next(t for t in ok(c.get('/api/me/season/tasks',headers=employee))['items'] if t['kind']=='safety')
    assert saved['xp']==70 and saved['id']==custom['id']
    assert 'expected_answer' not in c.get('/api/admin/config-exports',headers=h).text


def test_media_validates_actual_content_and_backup_integrity(client):
    import io,sqlite3
    from PIL import Image
    h=auth(client);b=io.BytesIO();Image.new('RGB',(5,7)).save(b,format='PNG')
    revision=ok(client.get('/api/admin/overview',headers=h))
    rev=client.get('/api/reference',headers=h).json()['meta']['state_revision']
    response=client.post('/api/admin/media',headers={**h,'Idempotency-Key':str(uuid.uuid4())},data={'expected_revision':rev,'alt':'Тест'},files={'file':('logo.png',b.getvalue(),'image/png')})
    image=ok(response);assert image['width']==5 and image['height']==7
    assert client.get(image['url']).headers['content-type']=='image/png'
    bad=client.post('/api/admin/media',headers={**h,'Idempotency-Key':str(uuid.uuid4())},data={'expected_revision':rev,'alt':'Неверный файл'},files={'file':('x.png',b'<script>bad</script>','image/png')})
    assert bad.status_code==422
    backup=ok(mutate(client,h,'POST','/api/admin/system/backups',dict(reason='Проверка резервной копии')))
    path=client.app.state.db.path.parent/'backups'/(backup['id']+'.sqlite3')
    with sqlite3.connect(path) as db:assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'


def test_new_employee_account_and_season_members_preview_preserve_source(client):
    h=auth(client);db=client.app.state.db
    original=db.read_dataset().revision
    employee=dict(id='NEW1',full_name='Новый участник',department='Engineering',role='Engineer',grade='Junior')
    publish(client,h,change(client,h,'employees',employee,'NEW1'))
    ok(mutate(client,h,'POST','/api/admin/users',dict(username='new.person',display_name='Новый участник',employee_id='NEW1',password='TemporaryNew123!',reason='Новый тестовый аккаунт')))
    assert db.read_dataset().revision==original
    seasons=ok(client.get('/api/admin/seasons',headers=h))['items'];sid=seasons[0]['id']
    draft=ok(mutate(client,h,'POST',f'/api/admin/seasons/{sid}/members',dict(employee_ids=['E1','E2','NEW1'],reason='Добавление участника с новым резервом')))
    p=ok(mutate(client,h,'POST',f'/api/admin/changes/{draft["id"]}/preview'))
    assert not p['can_publish'] and p['blocking_errors'][0]['code']=='INSUFFICIENT_BUDGET'
    ok(mutate(client,h,'POST','/api/admin/budget-movements',dict(season_id=sid,amount_kzt=1200000,reason='Финансирование нового участника')))
    publish(client,h,draft['id'])
    with client.app.state.engine.transaction() as s:
        assert len(game.leaderboard(s,s['seasons'][sid])['entries'])==3


def test_nomination_reserve_and_common_ledger(scenario):
    c,e,clock=scenario;h=auth(c)
    with e.transaction() as s:
        se=game.choose_season(s);sid=se['id']
        se['policies']['leaderboards'].update(min_xp=0,min_days=0)
    nomination=dict(items=[dict(id='growth',name='Лидер развития',criterion='confirmed_xp',per_department=False,coins=10,active=True)])
    key=change(c,h,'nominations',nomination,sid)
    p=ok(mutate(c,h,'POST',f'/api/admin/changes/{key}/preview'));assert not p['can_publish']
    ok(mutate(c,h,'POST','/api/admin/budget-movements',dict(season_id=sid,amount_kzt=1000,reason='Резерв номинации')))
    publish(c,h,key)
    with e.transaction() as s:
        se=s['seasons'][sid];game.emit_xp(s,se,'E1','daily','fixture',100,stamp(clock[0]),clock[0]);game.finalize(s,se,clock[0])
        paid=[r for r in s['ledger'].values() if r['source_type']=='nomination']
        assert len(paid)==1 and paid[0]['amount']==10
        game.finalize(s,se,clock[0]);assert len([r for r in s['ledger'].values() if r['source_type']=='nomination'])==1
