"""Authenticated HTTP contracts for the full local release. No upload endpoints."""
from datetime import date, timedelta
from typing import Literal
from urllib.parse import quote

from fastapi import Depends, Header, Query, Request
from fastapi.responses import Response
from pydantic import BaseModel, ConfigDict, Field, field_validator

from . import career, game, analytics
from .assistant import CareerAssistant, context_for
from .engine import require, Problem, own, stamp, instant


class Input(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)


class Revision(Input):
    expected_revision:int=Field(ge=0,strict=True)


class GoalInput(Revision):
    role_id:str=Field(min_length=1,max_length=100)
    grade_id:Literal['Junior','Middle','Senior','Lead']
    confirm_archive_plan:bool=False


class PreferencesInput(Revision):
    weekly_minutes:int=Field(ge=30,le=600,multiple_of=30,strict=True)
    preferred_formats:list[Literal['online','offline','self_paced']]
    timezone:Literal['Asia/Almaty','Asia/Qyzylorda','UTC']


class AddInput(Revision):
    activity_id:str=Field(min_length=1,max_length=120)
    accept_no_goal_gain:bool=False
    accept_over_budget:bool=False


class CompleteInput(Revision):
    confirmed:Literal[True]
    note:str|None=Field(default=None,max_length=500)


class ExcludeInput(Revision):
    activity_id:str
    reason:Literal['time','format','known','other']


class OrderInput(Revision):
    item_ids:list[str]=Field(max_length=3)


class SimulationInput(Input):
    role_id:str
    grade_id:str
    activity_ids:list[str]=Field(max_length=3)


class ApplyInput(Revision):
    confirm_replace_plan:bool=False
    accept_over_budget:bool=False


class ExplainInput(Input):
    question:Literal['why','time','forecast','gaps']


class AttemptInput(Revision):
    answer:dict


class ReviewInput(Revision):
    evidence_text:str=Field(min_length=80,max_length=2000)


class DecisionInput(Revision):
    decision:Literal['approved','rejected']
    comment:str=Field(default='',max_length=2000)


class PurchaseInput(Revision):
    item_id:str
    expected_item_version:int=Field(ge=1,strict=True)
    expected_coin_price:int=Field(ge=1,strict=True)


class ClaimInput(Revision):
    item_id:str


class FulfillInput(Revision):
    target_status:Literal['approved','rejected','ready','delivered','cancelled']
    note:str=Field(default='',max_length=2000)
    actual_cost_kzt:int|None=Field(default=None,ge=0,strict=True)


class SeasonInput(Revision):
    name:str=Field(min_length=1,max_length=100)
    starts_at:str
    employee_ids:list[str]=Field(min_length=1,max_length=1000)
    virtual_budget_kzt:int=Field(ge=0,strict=True)
    economy_version:Literal['economy-v1']='economy-v1'

    @field_validator('starts_at')
    @classmethod
    def valid_start(cls, value):
        parsed=instant(value)
        if parsed.tzinfo is None:
            raise ValueError('Timezone is required')
        return stamp(parsed)


class SeasonPatch(Input):
    expected_revision:int=Field(ge=0,strict=True)
    name:str|None=Field(default=None,min_length=1,max_length=100)
    starts_at:str|None=None
    employee_ids:list[str]|None=Field(default=None,min_length=1,max_length=1000)
    virtual_budget_kzt:int|None=Field(default=None,ge=0,strict=True)

    @field_validator('starts_at')
    @classmethod
    def valid_start(cls, value):
        return SeasonInput.valid_start(value) if value else value


class ItemInput(Revision):
    id:str=Field(pattern=r'^[a-zA-Z0-9_-]{1,80}$')
    name:str=Field(min_length=1,max_length=150)
    category:Literal['Техника','Кухня','Дом и уют','Гаджеты','Путешествия и впечатления']
    description:str=Field(min_length=1,max_length=2000)
    delivery_terms:str=Field(min_length=1,max_length=1000)
    coin_price:int=Field(ge=1,le=100000,strict=True)
    unit_budget_kzt:int=Field(ge=0,le=10000000,strict=True)
    stock_total:int=Field(ge=0,le=100000,strict=True)
    active:bool=True


class ItemPatch(Revision):
    name:str|None=Field(default=None,min_length=1,max_length=150)
    description:str|None=Field(default=None,min_length=1,max_length=2000)
    delivery_terms:str|None=Field(default=None,min_length=1,max_length=1000)
    coin_price:int|None=Field(default=None,ge=1,le=100000,strict=True)
    stock_total:int|None=Field(default=None,ge=0,le=100000,strict=True)
    active:bool|None=None


class PoolInput(Revision):
    item_ids:list[str]
    fallback_item_id:str
    cap:int=Field(ge=0,strict=True)


def install(app,current_user,employee,hr):
    assistant=CareerAssistant()
    def engine():
        require(app.state.engine is not None,'NOT_READY','Стартовые данные недоступны',503)
        return app.state.engine
    def read(fn): return engine().read(fn)
    def mutate(user,route,body,key,fn): return engine().mutate(user,route,body.model_dump(),key,fn)
    def public_profile(s,eid,now):
        e=s['employees'].get(eid)
        require(e,'NOT_FOUND','Сотрудник не найден',404)
        return dict(employee=e,**career.goal(s,eid),preferences=career.preferences(s,eid),progress=career.progress(s,eid),plan=career.plan(s,eid,now))
    def member_season(s,sid,eid): return game.choose_season(s,sid,eid)

    @app.get('/api/reference')
    @app.get('/api/meta')
    def reference(user=Depends(current_user)):
        return read(lambda s,n:dict(roles=list(s['roles'].values()),skills=list(s['skills'].values()),allowed_formats=career.FORMATS,timezones=career.TIMEZONES,showcase=s.get('showcase',False)))

    @app.get('/api/me/profile')
    def profile(user=Depends(employee)):
        return read(lambda s,n:public_profile(s,user['employee_id'],n))

    @app.get('/api/me/dashboard')
    def dashboard(user=Depends(employee)):
        def get(s,n):
            eid=user['employee_id']
            result=public_profile(s,eid,n)
            result['recommendations']=career.recommendations(s,eid,n)
            season=game.choose_season(s)
            result['gamification']=game.summary(s,season,eid,n) if eid in season['roster'] else None
            return result
        return read(get)

    @app.patch('/api/me/preferences')
    def preferences(body:PreferencesInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        def update(s,n):
            row=body.model_dump(exclude={'expected_revision'})
            row['preferred_formats']=sorted(set(row['preferred_formats'])) or career.FORMATS
            s['preferences'][user['employee_id']]=row
            return row
        return mutate(user,'preferences',body,idempotency_key,update)

    @app.get('/api/me/goal')
    def my_goal(user=Depends(employee)):
        return read(lambda s,n:career.goal(s,user['employee_id']))

    @app.put('/api/me/goal')
    def set_goal(body:GoalInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'goal',body,idempotency_key,lambda s,n:career.set_goal(s,user['employee_id'],dict(target_role=body.role_id,target_grade=body.grade_id),n,body.confirm_archive_plan))

    @app.delete('/api/me/goal')
    def reset_goal(expected_revision:int=Query(ge=0),confirm_archive_plan:bool=False,user=Depends(employee),idempotency_key:str|None=Header(None)):
        body=GoalInput(expected_revision=expected_revision,role_id='reset',grade_id='Junior',confirm_archive_plan=confirm_archive_plan)
        return mutate(user,'reset_goal',body,idempotency_key,lambda s,n:career.set_goal(s,user['employee_id'],None,n,confirm_archive_plan))

    @app.get('/api/me/progress')
    def progress(user=Depends(employee)):
        return read(lambda s,n:career.progress(s,user['employee_id']))

    @app.get('/api/me/recommendations')
    def recommendations(user=Depends(employee)):
        return read(lambda s,n:career.recommendations(s,user['employee_id'],n))

    @app.post('/api/me/recommendation-exclusions')
    def exclude(body:ExcludeInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        def update(s,n):
            eid=user['employee_id']; g=career.goal(s,eid)['goal']
            require(g,'NO_GOAL','Сначала выберите цель')
            require(body.activity_id in s['activities'],'NOT_FOUND','Активность не найдена',404)
            s['exclusions'].setdefault(eid,{}).setdefault(g['target_role']+'|'+g['target_grade'],{})[body.activity_id]=body.reason
            return career.recommendations(s,eid,n)
        return mutate(user,'exclude',body,idempotency_key,update)

    @app.delete('/api/me/recommendation-exclusions')
    def restore(expected_revision:int=Query(ge=0),user=Depends(employee),idempotency_key:str|None=Header(None)):
        def update(s,n):
            eid=user['employee_id']; g=career.goal(s,eid)['goal']
            if g: s['exclusions'].get(eid,{}).pop(g['target_role']+'|'+g['target_grade'],None)
            return career.recommendations(s,eid,n)
        return mutate(user,'restore',Revision(expected_revision=expected_revision),idempotency_key,update)

    @app.get('/api/activities')
    def activities(search:str=Query('',max_length=200),skill_id:str|None=None,format:Literal['online','offline','self_paced']|None=None,
                   max_minutes:int|None=Query(None,ge=1),available:bool|None=None,page:int=Query(1,ge=1),user=Depends(current_user)):
        def get(s,n):
            rows=[]
            for a in s['activities'].values():
                if not a['active'] or search.casefold() not in (a['title']+' '+a['description']).casefold(): continue
                if skill_id and skill_id not in a['gains'] or format and a['format']!=format or max_minutes and a['duration_minutes']>max_minutes: continue
                reason=career.blocked(s,user['employee_id'],a,n) if user['role']=='employee' else None
                if available is not None and available!=(reason is None): continue
                rows.append({**a,'blocked_reason':reason})
            rows.sort(key=lambda a:(a['title'],a['id']))
            return dict(items=rows[(page-1)*20:page*20],total=len(rows),page=page)
        return read(get)

    @app.get('/api/activities/{aid}')
    def activity(aid:str,user=Depends(current_user)):
        def get(s,n):
            a=s['activities'].get(aid); require(a,'NOT_FOUND','Активность не найдена',404)
            eid=user['employee_id']
            return dict(activity=a,blocked_reason=career.blocked(s,eid,a,n) if eid else None,
                plan_item=next((p for p in career.active_plan(s,eid) if p['activity_id']==aid),None) if eid else None,
                completion=next((c for c in s['completions'].values() if c['employee_id']==eid and c['activity_id']==aid),None) if eid else None)
        return read(get)

    @app.get('/api/me/plan')
    def plan(user=Depends(employee)):
        return read(lambda s,n:career.plan(s,user['employee_id'],n))

    @app.post('/api/me/plan/items',status_code=201)
    def add(body:AddInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'plan_add',body,idempotency_key,lambda s,n:career.add_plan(s,user['employee_id'],body.model_dump(),n))

    @app.put('/api/me/plan/order')
    def order(body:OrderInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        def update(s,n):
            items=career.active_plan(s,user['employee_id'])
            require(len(body.item_ids)==len(set(body.item_ids)) and set(body.item_ids)=={p['id'] for p in items},'INVALID_ORDER','Передайте все активные шаги ровно по одному разу',422)
            for i,pid in enumerate(body.item_ids): s['plan'][pid]['position']=i
            return career.plan(s,user['employee_id'],n)
        return mutate(user,'plan_order',body,idempotency_key,update)

    @app.post('/api/me/plan/items/{pid}/replace')
    def replace(pid:str,body:AddInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'replace:'+pid,body,idempotency_key,lambda s,n:career.add_plan(s,user['employee_id'],body.model_dump(),n,pid))

    @app.post('/api/me/plan/items/{pid}/start')
    def start(pid:str,body:Revision,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'start:'+pid,body,idempotency_key,lambda s,n:career.transition(s,user['employee_id'],pid,'start',body.model_dump(),n))

    @app.post('/api/me/plan/items/{pid}/archive')
    def archive(pid:str,body:Revision,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'archive:'+pid,body,idempotency_key,lambda s,n:career.transition(s,user['employee_id'],pid,'archive',body.model_dump(),n))

    @app.post('/api/me/plan/items/{pid}/complete')
    def complete(pid:str,body:CompleteInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'complete:'+pid,body,idempotency_key,lambda s,n:career.transition(s,user['employee_id'],pid,'complete',body.model_dump(),n))

    @app.get('/api/me/history')
    def history(status:str|None=None,origin:Literal['imported','self_report']|None=None,format:str|None=None,
                date_from:date|None=None,date_to:date|None=None,page:int=Query(1,ge=1),user=Depends(employee)):
        def get(s,n):
            rows=career.history(s,user['employee_id'])
            rows=[r for r in rows if (not status or r['status']==status) and (not origin or any(x['origin']==origin for x in r['sources']))
                and (not format or r['activity']['format']==format)
                and (not date_from or (r.get('completed_at') or r.get('started_at') or '')[:10]>=date_from.isoformat())
                and (not date_to or (r.get('completed_at') or r.get('started_at') or '')[:10]<=date_to.isoformat())]
            return dict(items=rows[(page-1)*20:page*20],total=len(rows),page=page)
        return read(get)

    @app.get('/api/me/achievements')
    def achievements(user=Depends(employee)):
        return read(lambda s,n:dict(items=[b for b in s['badges'].values() if b['employee_id']==user['employee_id']]))

    @app.post('/api/me/simulations')
    def simulation(body:SimulationInput,user=Depends(employee)):
        return read(lambda s,n:career.simulate(s,user['employee_id'],body.model_dump(),n))

    @app.post('/api/me/simulations/{sid}/apply')
    def apply(sid:str,body:ApplyInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'simulation:'+sid,body,idempotency_key,lambda s,n:career.apply_simulation(s,user['employee_id'],sid,body.model_dump(),n))

    @app.get('/api/me/passport')
    def passport(user=Depends(employee)):
        return read(lambda s,n:analytics.passport(s,user['employee_id'],n))

    @app.get('/api/me/passport/download')
    def download_passport(user=Depends(employee)):
        data=read(lambda s,n:analytics.passport(s,user['employee_id'],n))['data']
        return Response(analytics.passport_markdown(data),media_type='text/markdown',headers={'Content-Disposition':f'attachment; filename="career-passport-{user["employee_id"]}.md"'})

    @app.post('/api/me/assistant/explain')
    async def explain(body:ExplainInput,user=Depends(employee)):
        result=read(lambda s,n:context_for(s,user['employee_id'],n,body.question))
        answer=await assistant.explain(result['data'],user['employee_id'],result['meta']['state_revision'])
        return {'data':answer,'meta':result['meta']}

    def hr_filters(department:str|None=None,role_id:str|None=None,grade_id:str|None=None,date_from:date|None=None,date_to:date|None=None,
                   reference:Literal['current_role','goal']='current_role',basis:Literal['assessed','estimated']='assessed'):
        if date_from and date_to:
            require(date_from<=date_to and (date_to-date_from).days<=366,'INVALID_PERIOD','Период должен быть от 0 до 366 дней',422)
        return locals()

    @app.get('/api/hr/overview')
    def overview(filters=Depends(hr_filters),user=Depends(hr)):
        return read(lambda s,n:analytics.report(s,filters,n))

    @app.get('/api/hr/skill-gaps')
    def skill_gaps(filters=Depends(hr_filters),user=Depends(hr)):
        return read(lambda s,n:dict(items=analytics.report(s,filters,n)['skills']))

    @app.get('/api/hr/activities')
    def hr_activities(filters=Depends(hr_filters),user=Depends(hr)):
        return read(lambda s,n:dict(items=analytics.report(s,filters,n)['activities']))

    @app.get('/api/hr/employees')
    def employees(search:str=Query('',max_length=200),q:str=Query('',max_length=200),has_goal:bool|None=None,participated:bool|None=None,
                  skill_id:str|None=None,has_gap:bool|None=None,page:int=Query(1,ge=1),filters=Depends(hr_filters),user=Depends(hr)):
        def get(s,n):
            report=analytics.report(s,filters,n)
            rows=report['employees']
            text=(search or q).casefold()
            rows=[r for r in rows if text in f'{r["full_name"]} {r["role"]} {r["department"]}'.casefold() and
                (has_goal is None or bool(r['goal'])==has_goal) and (participated is None or r['participated']==participated)]
            if skill_id and has_gap is not None:
                ids={eid for c in report['skills'] if c['skill_id']==skill_id for eid in c['employee_ids']}
                rows=[r for r in rows if (r['employee_id'] in ids)==has_gap]
            return dict(items=rows[(page-1)*20:page*20],total=len(rows),page=page)
        return read(get)

    @app.get('/api/hr/employees/{eid}')
    def hr_profile(eid:str,user=Depends(hr)):
        return read(lambda s,n:public_profile(s,eid,n))

    @app.get('/api/hr/employees/{eid}/{section}')
    def hr_employee_section(eid:str,section:Literal['progress','plan','history','recommendations'],user=Depends(hr)):
        def get(s,n):
            require(eid in s['employees'],'NOT_FOUND','Профиль не найден',404)
            if section=='progress': return career.progress(s,eid)
            if section=='plan': return career.plan(s,eid,n)
            if section=='history': return dict(items=career.history(s,eid))
            return career.recommendations(s,eid,n)
        return read(get)

    @app.get('/api/hr/reports/skill-gaps.csv')
    def export(filters=Depends(hr_filters),user=Depends(hr)):
        rows=read(lambda s,n:analytics.report(s,filters,n)['skills'])['data']
        return Response(analytics.skill_csv(rows),media_type='text/csv',headers={'Content-Disposition':'attachment; filename="skill-gaps.csv"'})

    install_game(app,read,mutate,current_user,employee,hr)


def install_game(app,read,mutate,current_user,employee,hr):
    @app.get('/api/seasons/current')
    def current(user=Depends(current_user)):
        return read(lambda s,n:game.season_summary(game.choose_season(s),user['employee_id']))

    @app.get('/api/seasons/hall-of-fame')
    def hall(user=Depends(current_user)):
        return read(lambda s,n:dict(items=[{'season':game.season_summary(s['seasons'][sid]),'winners':[r for r in rows if r['prize_rank']]}
                                           for sid,rows in s['snapshots'].items()]))

    @app.get('/api/seasons/{sid}')
    def season(sid:str,user=Depends(current_user)):
        def get(s,n):
            season=game.choose_season(s,sid)
            require(season['status']!='draft' or user['role']=='hr','NOT_FOUND','Сезон не найден',404)
            return dict(**game.season_summary(season,user['employee_id']),rewards=season['rewards'],member_count=len(season['roster']))
        return read(get)

    @app.get('/api/me/season')
    def me_season(season_id:str|None=None,user=Depends(employee)):
        return read(lambda s,n:game.summary(s,game.choose_season(s,season_id,user['employee_id']),user['employee_id'],n))

    @app.get('/api/me/season/pass')
    def pass_(season_id:str|None=None,user=Depends(employee)):
        return read(lambda s,n:dict(items=game.pass_state(s,game.choose_season(s,season_id,user['employee_id']),user['employee_id'])))

    @app.get('/api/me/season/tasks')
    def tasks(season_id:str|None=None,user=Depends(employee)):
        return read(lambda s,n:game.daily_tasks(s,game.choose_season(s,season_id,user['employee_id']),user['employee_id'],n))

    @app.post('/api/me/season/tasks/{tid}/attempt')
    def attempt(tid:str,body:AttemptInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'attempt:'+tid,body,idempotency_key,lambda s,n:game.attempt(s,user['employee_id'],tid,body.answer,n))

    @app.get('/api/me/season/streak')
    def streak(season_id:str|None=None,user=Depends(employee)):
        return read(lambda s,n:game.streak(s,game.choose_season(s,season_id,user['employee_id']),user['employee_id'],n))

    @app.get('/api/me/season/xp')
    def xp(season_id:str|None=None,page:int=Query(1,ge=1),user=Depends(employee)):
        def get(s,n):
            season=game.choose_season(s,season_id,user['employee_id'])
            rows=sorted([r for r in s['xp'].values() if r['season_id']==season['id'] and r['employee_id']==user['employee_id']],key=lambda r:r['effective_at'],reverse=True)
            return dict(items=rows[(page-1)*20:page*20],total=len(rows),page=page)
        return read(get)

    @app.post('/api/me/completions/{cid}/reward-review')
    def submit_review(cid:str,body:ReviewInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'review:'+cid,body,idempotency_key,lambda s,n:game.submit_review(s,user['employee_id'],cid,body.evidence_text,n))

    @app.get('/api/me/reward-reviews')
    def my_reviews(user=Depends(employee)):
        return read(lambda s,n:dict(items=[r for r in s['reviews'].values() if r['employee_id']==user['employee_id']]))

    @app.get('/api/seasons/{sid}/leaderboard')
    def leaders(sid:str,scope:Literal['overall','department','week']='overall',week:int|None=Query(None,ge=0,le=12),page:int=Query(1,ge=1),user=Depends(current_user)):
        def get(s,n):
            season=game.choose_season(s,sid)
            require(season['status']!='draft' or user['role']=='hr','NOT_FOUND','Сезон не найден',404)
            require(scope!='department' or user['employee_id'],'INVALID_SCOPE','Для HR используйте общий рейтинг',422)
            week_index=week if week is not None else max(0,min(12,(game.game_date(n)-game.game_date(instant(season['starts_at']))).days//7))
            return game.leaderboard(s,season,user['employee_id'],scope,week_index,page)
        return read(get)

    @app.get('/api/seasons/{sid}/participants/{eid}')
    def participant(sid:str,eid:str,user=Depends(current_user)):
        def get(s,n):
            season=game.choose_season(s,sid)
            require(season['status']!='draft' or user['role']=='hr','NOT_FOUND','Сезон не найден',404)
            game.participant(season,eid)
            return game.leaderboard(s,season,eid)['self']
        return read(get)

    @app.get('/api/seasons/{sid}/certificate')
    def certificate(sid:str,user=Depends(current_user)):
        def get(s,n):
            rows=s['snapshots'].get(sid,[])
            winner=next((r for r in rows if r['prize_rank']==1),None)
            require(winner and (user['role']=='hr' or user['employee_id']==winner['employee_id']),'NOT_FOUND','Сертификат недоступен',404)
            return f'# Сотрудник сезона\n\n{winner["display_name"]}\n\n{s["seasons"][sid]["name"]}\n\nПодтверждённый XP: {winner["confirmed_xp"]}. Активных дней: {winner["active_days"]}.\n\nИгровая награда Career Quest, не аттестация профессиональной квалификации.'
        return Response(read(get)['data'],media_type='text/markdown',headers={'Content-Disposition':'attachment; filename="season-certificate.md"'})

    @app.get('/api/me/wallet')
    def wallet(page:int=Query(1,ge=1),user=Depends(employee)):
        def get(s,n):
            result=game.wallet(s,user['employee_id']); rows=result['entries']
            return dict(balance=result['balance'],items=rows[(page-1)*20:page*20],total=len(rows),page=page)
        return read(get)

    @app.get('/api/shop/items')
    def shop(category:str|None=None,min_price:int=Query(0,ge=0),max_price:int|None=Query(None,ge=0),affordable:bool=False,in_stock:bool=False,
             sort:Literal['price_asc','price_desc','name']='price_asc',page:int=Query(1,ge=1),user=Depends(current_user)):
        def get(s,n):
            balance=game.wallet(s,user['employee_id'])['balance'] if user['employee_id'] else None
            rows=[game.item_view(i) for i in s['items'].values() if i['shop_visible'] and i['active'] and (not category or i['category']==category)
                and i['coin_price']>=min_price and (max_price is None or i['coin_price']<=max_price)
                and (not affordable or balance is not None and i['coin_price']<=balance)]
            rows=[r for r in rows if not in_stock or r['available_stock']>0]
            rows.sort(key=lambda r:((r['coin_price'] if sort=='price_asc' else -r['coin_price']) if sort!='name' else r['name'],r['id']))
            return dict(items=rows[(page-1)*20:page*20],total=len(rows),page=page,balance=balance)
        return read(get)

    @app.get('/api/shop/items/{iid}')
    def shop_item(iid:str,user=Depends(current_user)):
        def get(s,n):
            item=s['items'].get(iid)
            require(item and item['shop_visible'],'NOT_FOUND','Товар не найден',404)
            return game.item_view(item)
        return read(get)

    @app.post('/api/me/shop/orders')
    def purchase(body:PurchaseInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'purchase',body,idempotency_key,lambda s,n:game.create_order(s,user['employee_id'],body.model_dump(),n))

    @app.get('/api/me/rewards')
    def rewards(status:str|None=None,user=Depends(employee)):
        return read(lambda s,n:dict(entitlements=[e for e in s['entitlements'].values() if e['employee_id']==user['employee_id'] and (not status or e['status']==status)],
            orders=[game.order_view(o,user['employee_id']) for o in s['orders'].values() if o['employee_id']==user['employee_id'] and (not status or o['status']==status)]))

    @app.get('/api/me/rewards/{rid}/options')
    def options(rid:str,user=Depends(employee)):
        def get(s,n):
            e=own(s['entitlements'],rid,user['employee_id'])
            return dict(entitlement=e,items=[game.item_view(s['items'][i]) for i in s['pools'][e['pool_id']]['item_ids'] if s['items'][i]['active']])
        return read(get)

    @app.post('/api/me/rewards/{rid}/claim')
    def claim(rid:str,body:ClaimInput,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'claim:'+rid,body,idempotency_key,lambda s,n:game.create_order(s,user['employee_id'],body.model_dump(),n,rid))

    @app.get('/api/me/reward-orders/{oid}')
    def order(oid:str,user=Depends(employee)):
        return read(lambda s,n:game.order_view(own(s['orders'],oid,user['employee_id']),user['employee_id']))

    @app.post('/api/me/reward-orders/{oid}/cancel')
    def cancel(oid:str,body:Revision,user=Depends(employee),idempotency_key:str|None=Header(None)):
        return mutate(user,'cancel:'+oid,body,idempotency_key,lambda s,n:game.transition_order(s,oid,'cancelled','Отменено сотрудником',None,n,user['employee_id']))

    @app.get('/api/hr/seasons')
    def seasons(user=Depends(hr)):
        return read(lambda s,n:dict(items=[{**game.season_summary(x),'employee_ids':list(x['roster']),'virtual_budget_kzt':x['virtual_budget_kzt']} for x in s['seasons'].values()]))

    @app.post('/api/hr/seasons')
    def create_season(body:SeasonInput,user=Depends(hr),idempotency_key:str|None=Header(None)):
        return mutate(user,'create_season',body,idempotency_key,lambda s,n:game.make_season(s,body.name,body.starts_at,body.employee_ids,body.virtual_budget_kzt,n))

    @app.patch('/api/hr/seasons/{sid}')
    def edit_season(sid:str,body:SeasonPatch,user=Depends(hr),idempotency_key:str|None=Header(None)):
        def update(s,n):
            season=game.choose_season(s,sid)
            changes=body.model_dump(exclude_none=True,exclude={'expected_revision'})
            require(season['status'] in ('draft','scheduled'),'SEASON_LOCKED','Опубликованные правила сезона менять нельзя')
            if season['status']=='scheduled':
                require(set(changes)<= {'starts_at'} and instant(season['starts_at'])>n,'SEASON_LOCKED','Можно только перенести будущий старт')
            if 'starts_at' in changes:
                start=instant(changes['starts_at'])
                require(start.tzinfo is not None and start.astimezone(game.ZONE).time().isoformat()=='00:00:00','INVALID_START','Начало сезона — полночь Asia/Almaty',422)
                if season['status']=='scheduled': require(start>n,'INVALID_START','Новая дата старта должна быть в будущем',422)
                end=start+timedelta(days=90)
                for other in s['seasons'].values():
                    if other['id']!=sid and other['status']!='draft':
                        require(not (start<instant(other['ends_at']) and instant(other['starts_at'])<end),'SEASON_OVERLAP','Периоды заработка пересекаются')
                season.update(starts_at=stamp(start),ends_at=stamp(end),review_deadline=stamp(end+timedelta(days=7)),claim_deadline=stamp(end+timedelta(days=14)))
            if 'employee_ids' in changes:
                ids=changes.pop('employee_ids')
                require(ids and len(ids)==len(set(ids)) and all(e in s['employees'] for e in ids),'INVALID_ROSTER','Проверьте список участников',422)
                season['roster']={eid:{'display_name':s['employees'][eid]['full_name'],'department':s['employees'][eid]['department']} for eid in ids}
                game.make_pools(s,season)
            season.update({k:v for k,v in changes.items() if k!='starts_at'})
            return game.season_summary(season)
        return mutate(user,'season_edit:'+sid,body,idempotency_key,update)

    @app.post('/api/hr/seasons/{sid}/publish')
    def publish(sid:str,body:Revision,user=Depends(hr),idempotency_key:str|None=Header(None)):
        return mutate(user,'publish:'+sid,body,idempotency_key,lambda s,n:game.publish(s,game.choose_season(s,sid),n))

    @app.get('/api/hr/seasons/{sid}/economy')
    def economy(sid:str,user=Depends(hr)):
        return read(lambda s,n:game.economy(s,game.choose_season(s,sid)))

    @app.get('/api/hr/reward-reviews')
    def reviews(status:Literal['pending','approved','rejected']|None=None,season_id:str|None=None,employee_id:str|None=None,user=Depends(hr)):
        return read(lambda s,n:dict(items=[{**r,'employee_name':s['employees'][r['employee_id']]['full_name'],
            'activity':s['activities'][s['completions'][r['completion_id']]['activity_id']]} for r in s['reviews'].values()
            if (not status or r['status']==status) and (not season_id or r['season_id']==season_id) and (not employee_id or r['employee_id']==employee_id)]))

    @app.post('/api/hr/reward-reviews/{rid}/decision')
    def decision(rid:str,body:DecisionInput,user=Depends(hr),idempotency_key:str|None=Header(None)):
        return mutate(user,'decision:'+rid,body,idempotency_key,lambda s,n:game.decide_review(s,rid,body.decision,body.comment,n))

    @app.get('/api/hr/reward-orders')
    def hr_orders(status:str|None=None,payment_kind:Literal['coins','pass_entitlement']|None=None,employee_id:str|None=None,user=Depends(hr)):
        return read(lambda s,n:dict(items=[game.order_view(o)|{'employee_name':s['employees'][o['employee_id']]['full_name']} for o in s['orders'].values()
            if (not status or o['status']==status) and (not payment_kind or o['payment_kind']==payment_kind) and (not employee_id or o['employee_id']==employee_id)]))

    @app.post('/api/hr/reward-orders/{oid}/transition')
    def fulfill(oid:str,body:FulfillInput,user=Depends(hr),idempotency_key:str|None=Header(None)):
        return mutate(user,'fulfill:'+oid,body,idempotency_key,lambda s,n:game.transition_order(s,oid,body.target_status,body.note,body.actual_cost_kzt,n))

    @app.get('/api/hr/shop/items')
    def hr_shop(user=Depends(hr)):
        return read(lambda s,n:dict(items=[game.item_view(i) for i in s['items'].values() if i['shop_visible']]))

    @app.post('/api/hr/shop/items')
    def create_item(body:ItemInput,user=Depends(hr),idempotency_key:str|None=Header(None)):
        def update(s,n):
            require(body.id not in s['items'],'DUPLICATE_ITEM','Такой ID уже существует')
            require(body.unit_budget_kzt<=body.coin_price*100,'INVALID_BUDGET','Лимит товара превышает обеспечение монет',422)
            s['items'][body.id]=body.model_dump(exclude={'expected_revision'})|dict(shop_visible=True,reserved=0,delivered=0,version=1,image_asset=body.category)
            return game.item_view(s['items'][body.id])
        return mutate(user,'create_item',body,idempotency_key,update)

    @app.patch('/api/hr/shop/items/{iid}')
    def edit_item(iid:str,body:ItemPatch,user=Depends(hr),idempotency_key:str|None=Header(None)):
        def update(s,n):
            item=s['items'].get(iid)
            require(item and item['shop_visible'],'NOT_FOUND','Товар не найден',404)
            changes=body.model_dump(exclude_none=True,exclude={'expected_revision'})
            require(changes.get('stock_total',item['stock_total'])>=item['reserved']+item['delivered'],'INVALID_STOCK','Остаток меньше уже зарезервированного и выданного',422)
            require(changes.get('coin_price',item['coin_price'])*100>=item['unit_budget_kzt'],'INVALID_BUDGET','Цена не покрывает лимит обеспечения',422)
            if any(item[k]!=v for k,v in changes.items()):
                item.update(changes); item['version']+=1
            return game.item_view(item)
        return mutate(user,'edit_item:'+iid,body,idempotency_key,update)

    @app.get('/api/hr/reward-pools')
    def pools(season_id:str|None=None,user=Depends(hr)):
        return read(lambda s,n:dict(items=[p for p in s['pools'].values() if not season_id or p['season_id']==season_id]))

    @app.put('/api/hr/reward-pools/{pid}')
    def edit_pool(pid:str,body:PoolInput,user=Depends(hr),idempotency_key:str|None=Header(None)):
        def update(s,n):
            pool=s['pools'].get(pid); require(pool,'NOT_FOUND','Пул не найден',404)
            season=s['seasons'][pool['season_id']]
            require(body.cap==pool['cap'],'INVALID_CAP','Лимит закреплён экономикой пропуска',422)
            require(body.fallback_item_id in body.item_ids,'INVALID_POOL','Нужен запасной сертификат',422)
            require(all(i in s['items'] and s['items'][i]['unit_budget_kzt']<=body.cap for i in body.item_ids),'INVALID_POOL','Товар не существует или превышает лимит',422)
            if season['status']!='draft':
                require(set(pool['item_ids'])<=set(body.item_ids) and pool['fallback_item_id']==body.fallback_item_id,'SEASON_LOCKED','Опубликованный пул можно только дополнять')
            pool.update(item_ids=sorted(set(body.item_ids)),fallback_item_id=body.fallback_item_id)
            return pool
        return mutate(user,'edit_pool:'+pid,body,idempotency_key,update)
