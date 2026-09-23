from copy import deepcopy
from datetime import timedelta,datetime,time
from concurrent.futures import ThreadPoolExecutor
import uuid
import pytest
from fastapi.testclient import TestClient
from backend import game,game_rules,career
from backend.engine import stamp,instant,Problem
from backend.main import create_app
from conftest import authorization,mutate
from test_career import complete,payload


def season(s):return game.choose_season(s)

def assert_budget(s,ss):
    b=game.economy(s,ss)
    keys=['unearned_reserved','earned_liability','order_reserved','spent','released']
    assert all(b[k]>=0 for k in keys),b
    assert sum(b[k] for k in keys)==pytest.approx(b['committed_budget_kzt']),b


def test_pass_100_level_economy(scenario):
    _,e,clock=scenario
    with e.transaction() as s:
        ss=season(s)
        rewards=game_rules.pass_rewards()
        assert len(rewards)==100
        assert sum(p['coins'] for r in rewards for p in r['components'] if p['type']=='coins')==4800
        assert sum(p['budget_cap_kzt'] for r in rewards for p in r['components'] if p['type']=='gift')==670000
        assert sum(p['budget_cap_kzt'] for r in rewards for p in r['components'] if p['type']=='mini')==50000
        for points,want in [(0,0),(200,1),(999,4),(1000,5),(20000,100)]:
            s['xp']={}
            game.emit_xp(s,ss,'E1','test',str(points),points,stamp(clock[0]),clock[0])
            assert game.summary(s,ss,'E1',clock[0])['level']==want
        game.award_followups(s,ss,'E1',clock[0]);game.award_followups(s,ss,'E1',clock[0])
        assert game.wallet(s,'E1')['balance']==4800
        assert len(s['entitlements'])==31
        assert_budget(s,ss)
        assert all(game.item_view(s['items'][p['fallback_item_id']])['available_stock']>0 for p in s['pools'].values())


def test_daily_schema_attempts_ownership_idempotency_and_midnight(scenario):
    c,e,clock=scenario;h=authorization(c);other=authorization(c,'colleague')
    tasks=payload(c.get('/api/me/season/tasks',headers=h))['items']
    assert len(tasks)==2 and all('expected_answer' not in t and t['explanation'] is None for t in tasks)
    tid=tasks[0]['id']
    with e.transaction() as s:expected=s['tasks'][tid]['expected_answer']
    route=f'/api/me/season/tasks/{tid}/attempt'
    assert mutate(c,other,'POST',route,dict(answer=expected)).status_code==404
    assert mutate(c,h,'POST',route,dict(answer={})).status_code==422
    assert payload(c.get('/api/me/season/tasks',headers=h))['items'][0]['attempts_remaining']==3
    for index in range(3):
        out=payload(mutate(c,h,'POST',route,dict(answer={'value':-1000})))
        assert out['attempts_remaining']==2-index
        assert (out['explanation'] is not None)==(index==2)
    assert mutate(c,h,'POST',route,dict(answer=expected)).json()['error']['code']=='ATTEMPTS_EXHAUSTED'
    assert payload(c.get('/api/me/season/tasks',headers=h))['items'][0]['status']=='failed'
    tid=tasks[1]['id'];route=f'/api/me/season/tasks/{tid}/attempt'
    with e.transaction() as s:expected=s['tasks'][tid]['expected_answer']
    rev=c.get('/api/reference',headers=h).json()['meta']['state_revision'];key=str(uuid.uuid4())
    first=mutate(c,h,'POST',route,dict(answer=expected),rev,key)
    assert first.json()==mutate(c,h,'POST',route,dict(answer=expected),rev,key).json()
    payload(mutate(c,h,'POST',route,dict(answer=expected)))
    assert payload(c.get('/api/me/season',headers=h))['confirmed_xp']==150
    clock[0]=datetime.combine(game_rules.game_date(clock[0])+timedelta(days=1),time.min,game_rules.ZONE)
    assert mutate(c,h,'POST',route,dict(answer=expected)).json()['error']['code']=='TASK_EXPIRED'
    fresh=payload(c.get('/api/me/season/tasks',headers=h))['items']
    assert fresh[0]['id']!=tasks[0]['id'] and fresh[0]['attempts_remaining']==3


@pytest.mark.parametrize('kinds,expected,day100',[(('main','bonus'),27790,67),(('main',),14290,None)])
def test_full_season_daily_control_numbers(scenario,kinds,expected,day100):
    _,e,clock=scenario
    with e.transaction() as s:
        ss=season(s);start=instant(ss['starts_at']);first100=None
        for day in range(90):
            now=start+timedelta(days=day,hours=12)
            for task in game.daily_tasks(s,ss,'E1',now)['items']:
                if task['kind'] in kinds:
                    game.attempt(s,'E1',task['id'],s['tasks'][task['id']]['expected_answer'],now)
            if first100 is None and game.xp_total(s,ss['id'],'E1')>=20000:first100=day+1
        assert game.xp_total(s,ss['id'],'E1')==expected
        assert first100==day100
        assert game.streak(s,ss,'E1',now)['active_days']==90
        assert_budget(s,ss)


def test_freezes_and_late_review_rebuild_calendar(scenario):
    _,e,clock=scenario
    with e.transaction() as s:
        ss=season(s);start=instant(ss['starts_at']);eid='E1'
        def day(n):return start+timedelta(days=n,hours=12)
        for d in [0,2,4]:game.emit_xp(s,ss,eid,'daily',str(d),100,stamp(day(d)),day(d))
        result=game.streak(s,ss,eid,day(4))
        assert result['current_streak']==3 and result['freeze_remaining']==0
        result=game.streak(s,ss,eid,day(6))
        assert result['current_streak']==0
        # Late approval is credited to its completion day, releasing the used freeze.
        game.emit_xp(s,ss,eid,'activity','late',100,stamp(day(1)),day(6))
        result=game.streak(s,ss,eid,day(6))
        assert result['current_streak']==4 and result['freeze_remaining']==0
        assert result['active_days']==4
        game.award_followups(s,ss,eid,day(6));before=game.xp_total(s,ss['id'],eid)
        game.award_followups(s,ss,eid,day(6));assert game.xp_total(s,ss['id'],eid)==before


def test_review_limits_rejection_no_resubmit_then_approval(scenario):
    c,e,clock=scenario;h=authorization(c);hr=authorization(c,'hr')
    cs=[complete(c,h,aid)[1]['completion']['id'] for aid in ['sql','analytics','communication']]
    reviews=[]
    for cid in cs[:2]:reviews.append(payload(mutate(c,h,'POST',f'/api/me/completions/{cid}/reward-review',dict(evidence_text='Concrete evidence of a completed practice and a measured result. '*2))))
    path=f'/api/me/completions/{cs[2]}/reward-review'
    assert mutate(c,h,'POST',path,dict(evidence_text='Third evidence '*10)).json()['error']['code']=='DAILY_REVIEW_LIMIT'
    assert payload(c.get('/api/me/season',headers=h))['confirmed_xp']==0
    r=reviews[0]
    assert mutate(c,hr,'POST',f'/api/hr/reward-reviews/{r["id"]}/decision',dict(decision='rejected')).status_code==422
    payload(mutate(c,hr,'POST',f'/api/hr/reward-reviews/{r["id"]}/decision',dict(decision='rejected',comment='Needs a measured result')))
    assert payload(mutate(c,h,'POST',f'/api/me/completions/{cs[0]}/reward-review',dict(evidence_text='Resubmission '*10)))['status']=='rejected'
    payload(mutate(c,h,'POST',path,dict(evidence_text='Third evidence '*10)))
    before=payload(c.get('/api/me/progress',headers=h))
    clock[0]+=timedelta(days=2)
    r=reviews[1]
    payload(mutate(c,hr,'POST',f'/api/hr/reward-reviews/{r["id"]}/decision',dict(decision='approved')))
    assert mutate(c,hr,'POST',f'/api/hr/reward-reviews/{r["id"]}/decision',dict(decision='approved')).status_code==409
    summary=payload(c.get('/api/me/season',headers=h))
    assert summary['confirmed_xp']==200 and summary['level']==1
    assert payload(c.get('/api/me/progress',headers=h))==before
    assert payload(c.get('/api/me/wallet',headers=h))['balance']==5


def fund(s,ss,eid,now):
    game.emit_xp(s,ss,eid,'test','fixture',20000,stamp(now),now)
    game.award_followups(s,ss,eid,now)


def test_shop_concurrency_snapshot_stock_and_refund(scenario):
    c,e,clock=scenario;h=authorization(c);other=authorization(c,'colleague');hr=authorization(c,'hr')
    with e.transaction() as s:
        ss=season(s)
        for eid in ['E1','E2']:fund(s,ss,eid,clock[0])
        item=next(i for i in s['items'].values() if i['shop_visible'] and i['coin_price']<4800)
        item['stock_total']=1;iid=item['id'];price=item['coin_price'];version=item['version']
    request=dict(item_id=iid,expected_coin_price=price,expected_item_version=version)
    assert mutate(c,h,'POST','/api/me/shop/orders',{**request,'expected_coin_price':price+1}).json()['error']['code']=='ITEM_PRICE_CHANGED'
    revision=c.get('/api/reference',headers=h).json()['meta']['state_revision']
    with ThreadPoolExecutor(2) as pool:
        results=list(pool.map(lambda auth:mutate(c,auth,'POST','/api/me/shop/orders',request,revision),[h,other]))
    assert sorted(r.status_code for r in results)==[200,409]
    winner=h if results[0].status_code==200 else other
    loser=other if winner==h else h
    order=payload(next(r for r in results if r.status_code==200))
    assert mutate(c,loser,'POST','/api/me/shop/orders',request).json()['error']['code']=='OUT_OF_STOCK'
    assert mutate(c,loser,'POST',f'/api/me/reward-orders/{order["id"]}/cancel').status_code==404
    assert mutate(c,hr,'PATCH',f'/api/hr/shop/items/{iid}',dict(stock_total=0)).status_code==422
    payload(mutate(c,hr,'PATCH',f'/api/hr/shop/items/{iid}',dict(coin_price=price+1)))
    saved=payload(c.get(f'/api/me/reward-orders/{order["id"]}',headers=winner))
    assert saved['item_snapshot']['coin_price']==price
    for _ in range(2):payload(mutate(c,winner,'POST',f'/api/me/reward-orders/{order["id"]}/cancel'))
    assert payload(c.get('/api/me/wallet',headers=winner))['balance']==4800
    with e.transaction() as s:
        assert len([r for r in s['ledger'].values() if r['source_type']=='order_refund'])==1
        assert s['items'][iid]['reserved']==0
        assert_budget(s,season(s))


def test_entitlements_delivery_deadline_autocancel_and_restart(scenario,kit):
    c,e,clock=scenario;h=authorization(c);hr=authorization(c,'hr')
    with e.transaction() as s:
        ss=season(s);fund(s,ss,'E1',clock[0]);sid=ss['id'];ent=next(iter(s['entitlements'].values()));rid=ent['id'];iid=s['pools'][ent['pool_id']]['fallback_item_id']
    out=payload(mutate(c,h,'POST',f'/api/me/rewards/{rid}/claim',dict(item_id=iid)));oid=out['id']
    assert payload(c.get('/api/me/wallet',headers=h))['balance']==4800
    assert mutate(c,h,'POST',f'/api/me/rewards/{rid}/claim',dict(item_id=iid)).status_code==409
    payload(mutate(c,hr,'POST',f'/api/hr/reward-orders/{oid}/transition',dict(target_status='approved')))
    clock[0]+=timedelta(days=110)
    c.get('/api/me/season',headers=h)
    assert payload(c.get(f'/api/me/reward-orders/{oid}',headers=h))['status']=='approved'
    assert mutate(c,h,'POST',f'/api/me/rewards/{rid}/claim',dict(item_id=iid)).status_code==409
    payload(mutate(c,hr,'POST',f'/api/hr/reward-orders/{oid}/transition',dict(target_status='ready')))
    assert mutate(c,hr,'POST',f'/api/hr/reward-orders/{oid}/transition',dict(target_status='delivered',note='test',actual_cost_kzt=999999)).status_code==422
    payload(mutate(c,hr,'POST',f'/api/hr/reward-orders/{oid}/transition',dict(target_status='delivered',note='Вручено в тестовой среде',actual_cost_kzt=0)))
    before=payload(c.get('/api/me/wallet',headers=h))
    with TestClient(create_app(*kit,clock=lambda:clock[0])) as restarted:
        hh=authorization(restarted)
        assert payload(restarted.get('/api/me/wallet',headers=hh))==before
        assert payload(restarted.get(f'/api/me/reward-orders/{oid}',headers=hh))['status']=='delivered'
    with e.transaction() as s:assert_budget(s,s['seasons'][sid])


def test_finalization_eligibility_rank_podium_privacy_and_new_season(scenario):
    c,e,clock=scenario;h=authorization(c)
    with e.transaction() as s:
        ss=season(s);sid=ss['id'];start=instant(ss['starts_at'])
        for eid in ['E2','E1']:
            for day in range(5):game.emit_xp(s,ss,eid,'daily',str(day),250,stamp(start+timedelta(days=day,hours=12)),clock[0])
            game.award_followups(s,ss,eid,start+timedelta(days=5))
        final=instant(ss['review_deadline'])
        game.tick(s,final);before=deepcopy(s['ledger']);game.tick(s,final)
        assert before==s['ledger']
        rows=s['snapshots'][sid]
        assert rows[0]['employee_id']=='E1' and rows[0]['title']=='Сотрудник сезона'
        assert [r['prize_rank'] for r in rows]==[1,2]
        assert all(not set(r)&{'skills','goal','wallet','evidence_text','salary'} for r in rows)
        assert_budget(s,ss)
        assert game.economy(s,ss)['unearned_reserved']==0
        balance=game.wallet(s,'E1')['balance']
        new=game.make_season(s,'Next',stamp(instant(ss['ends_at'])),['E1'],1250000,final)
        game.publish(s,new,final)
        assert game.summary(s,new,'E1',final)['confirmed_xp']==0
        assert game.wallet(s,'E1')['balance']==balance


def test_no_unearned_podium_and_publication_insufficient_budget(scenario):
    _,e,clock=scenario
    with e.transaction() as s:
        ss=season(s);game.tick(s,instant(ss['review_deadline']))
        assert all(r['prize_rank'] is None for r in s['snapshots'][ss['id']])
        assert not any(r['source_type']=='season_podium' for r in s['ledger'].values())
        next_=game.make_season(s,'Next',ss['ends_at'],['E1'],0,clock[0])
        with pytest.raises(Problem) as error:game.publish(s,next_,clock[0])
        assert error.value.code=='INSUFFICIENT_BUDGET' and next_['status']=='draft'


def test_showcase_is_separate_and_generated_through_rules(kit,tmp_path,monkeypatch):
    from backend.showcase import build
    from backend.database import Database
    from backend.engine import Engine
    now=datetime(2026,9,23,12,tzinfo=game_rules.ZONE)
    path=tmp_path/'showcase'/'demo.sqlite3'
    build(path,source=kit[0],now=now)
    engine=Engine(Database(path),clock=lambda:now)
    with engine.transaction() as s:
        ss=season(s)
        assert s['showcase'] and game.summary(s,ss,'E1',now)['level']==100
        assert len(s['snapshots'])==1
        assert len([x for x in s['tasks'].values() if x['employee_id']=='E1' and x['season_id']==ss['id']])==134
        assert len(s['reviews'])==2 and len(s['orders'])==2
        for ss in s['seasons'].values():assert_budget(s,ss)
    with pytest.raises(ValueError):build(path,source=kit[0],now=now)
    assert not kit[1].exists()


def test_auto_cancel_once_and_closed_wallet_carry(scenario):
    c,e,clock=scenario
    with e.transaction() as s:
        ss=season(s);fund(s,ss,'E1',clock[0]);old=ss['id']
        item=s['items']['shop_notebook']
        order=game.create_order(s,'E1',dict(item_id=item['id'],expected_item_version=item['version'],expected_coin_price=item['coin_price']),clock[0])
        game.tick(s,clock[0]+timedelta(days=7))
        game.tick(s,clock[0]+timedelta(days=8))
        assert game.wallet(s,'E1')['balance']==4800
        assert s['items'][item['id']]['reserved']==0
        assert len([r for r in s['ledger'].values() if r['source_type']=='order_refund'])==1
        game.tick(s,instant(ss['claim_deadline']))
        assert game.economy(s,ss)['earned_liability']==480000
        new=game.make_season(s,'New',ss['claim_deadline'],['E1'],1250000,clock[0]);game.publish(s,new,instant(ss['claim_deadline']))
        order=game.create_order(s,'E1',dict(item_id=item['id'],expected_item_version=item['version'],expected_coin_price=item['coin_price']),instant(ss['claim_deadline']))
        assert order['funding']=={old:5000}
        assert_budget(s,ss);assert_budget(s,new)
        game.transition_order(s,order['id'],'cancelled','Cancelled',None,instant(ss['claim_deadline']),'E1')
        assert_budget(s,ss);assert_budget(s,new)
