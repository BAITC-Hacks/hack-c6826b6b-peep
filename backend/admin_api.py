"""Concrete administrative routes and typed DTOs for the existing FastAPI app."""
from copy import deepcopy
from datetime import timedelta
import hashlib
import hmac
import json
import secrets
import time
from typing import Literal

from fastapi import Depends, Header, Query, Request, UploadFile, File, Form
from fastapi.responses import Response, FileResponse
from pydantic import Field, create_model

from . import admin_schemas as dto, admin_service as service, career, game
from .database import encode, password_hash
from .engine import require, stamp, instant, uid, Problem
from .permissions import PERMISSIONS, DEFAULTS
from .policies import policy, pass_totals
from .quest_api import DecisionInput, FulfillInput

MODULES = [
 ('users','Аккаунты и доступ','Люди','users.read'),
 ('employees','Сотрудники','Люди','employees.read'),
 ('departments','Подразделения','Люди','employees.manage'),
 ('skills','Навыки','Развитие','reference.manage'),
 ('career-roles','Роли и требования','Развитие','reference.manage'),
 ('activities','Учебные активности','Развитие','learning.manage'),
 ('recommendations','Рекомендации','Развитие','recommendations.manage'),
 ('seasons','Сезоны и пропуск','Геймификация','seasons.manage'),
 ('economy','Правила XP и CQ','Геймификация','economy.manage'),
 ('quests','Задания','Геймификация','quests.manage'),
 ('achievements','Достижения','Геймификация','achievements.manage'),
 ('streaks','Серии','Геймификация','streaks.manage'),
 ('leaderboards','Рейтинг','Геймификация','leaderboards.manage'),
 ('nominations','Номинации','Геймификация','leaderboards.manage'),
 ('reviews','Проверка результатов','Развитие','reviews.manage'),
 ('shop','Каталог наград','Награды и магазин','shop.manage'),
 ('inventory','Склад','Награды и магазин','stock.manage'),
 ('reward-pools','Подарочные пулы','Награды и магазин','shop.manage'),
 ('reward-orders','Заявки и выдача','Награды и магазин','rewards.fulfill'),
 ('wallets','Кошельки','Награды и магазин','budgets.manage'),
 ('corrections','Корректировки','Награды и магазин','corrections.manage'),
 ('budgets','Бюджеты','Награды и магазин','budgets.manage'),
 ('content','Тексты','Контент','content.manage'),
 ('branding','Оформление','Контент','branding.manage'),
 ('assistant','Карьерный помощник','Контент','ai.manage'),
 ('settings','Настройки','Система','settings.manage'),
 ('changes','Черновики и публикации','Система',None),
 ('audit','Журнал действий','Система','audit.read'),
 ('system','Состояние и копии','Система','system.maintain'),
]

PATHS={'recommendations':'recommendation-policies','economy':'economy-policies','streaks':'streak-policies',
       'achievements':'achievement-definitions','leaderboards':'leaderboard-policies','shop':'shop/items',
       'assistant':'assistant-settings'}
PATHS['quests']='quest-templates'


def install(app,current_user):
    def allowed(permission):
        def dependency(user=Depends(current_user)):
            service.check(user,permission); return user
        return dependency
    def admin(user=Depends(current_user)):
        require(user.get('capabilities'),'FORBIDDEN','Раздел доступен администраторам',403)
        return user
    def read(fn): return app.state.engine.read(fn,include_db=True)
    def mutate(user,permission,route,body,key,fn):
        def run(s,n,db):
            actual=service.fresh_user(app.state.db,db,user,permission)
            return fn(s,n,db,actual)
        return app.state.engine.mutate(user,route,body.model_dump(),key,run,include_db=True)
    def page_rows(rows,search='',page=1,page_size=25,sort='name'):
        rows=[r for r in rows if search.casefold() in encode(service.redact(r)).casefold()]
        rows.sort(key=lambda r:str(r.get(sort,r.get('name',r.get('id',r.get('username',''))))).casefold())
        return dict(items=rows[(page-1)*page_size:page*page_size],total=len(rows),page=page,page_size=page_size)
    def user_view(db,row):
        value=app.state.db.public_user(row,db)
        value.update(id=row['username'],active=bool(row['active']),version=row['entity_version'],
                     permissions=[r[0] for r in db.execute('SELECT permission FROM permission_grants WHERE username=?',(row['username'],))],
                     sessions=db.execute('SELECT COUNT(*) FROM sessions WHERE username=? AND expires_at>?',(row['username'],int(time.time()))).fetchone()[0])
        return value

    @app.get('/api/runtime-config')
    def runtime(user=Depends(current_user)):
        def get(s,n,db):
            return dict(config_version=s.get('config_version',1),branding=policy(s,'branding'),content=policy(s,'content'),
                        recommendations=policy(s,'recommendations'),settings={k:v for k,v in policy(s,'settings').items()
                        if k in ('organization','locale','maintenance','maintenance_message','shop_paused','quests_paused')})
        result=read(get)
        return Response(encode(result),media_type='application/json',headers={'ETag':f'"config-{result["data"]["config_version"]}"'})

    @app.get('/api/admin/overview')
    def overview(user=Depends(admin)):
        def get(s,n,db):
            modules=[dict(id=k,title=t,group=g,path=PATHS.get(k,k)) for k,t,g,p in MODULES if p is None or p in user['capabilities']]
            counts={}
            for perm,key,collection in [('employees.read','employees','employees'),('reviews.manage','pending_reviews','reviews'),('rewards.fulfill','pending_orders','orders')]:
                if perm in user['capabilities']:
                    counts[key]=sum(1 for r in s[collection].values() if key=='employees' or r.get('status') in ('pending','requested'))
            return dict(environment='SHOWCASE' if s.get('showcase') else 'DEMO',modules=modules,counts=counts,
                        drafts=sum(1 for r in db.execute("SELECT domain FROM change_sets WHERE status!='published'") if service.DOMAIN_PERMISSION.get(r[0]) in user['capabilities']),
                        config_version=s.get('config_version',1),capabilities=user['capabilities'],
                        current_season=game.season_summary(game.choose_season(s)))
        return read(get)

    @app.get('/api/admin/forms')
    def forms(user=Depends(admin)):
        models={'user_create':(dto.UserCreate,'users.manage'),'user_edit':(dto.UserEdit,'users.manage'),
                'access':(dto.Access,'users.roles'),'password_reset':(dto.PasswordReset,'users.manage'),
                'reason':(dto.Reason,None),'season':(dto.Season,'seasons.manage'),
                'assessment':(dto.Assessment,'employees.assessments'),'goal':(dto.Goal,'employees.goals'),
                'inventory':(dto.Inventory,'stock.manage'),'budget':(dto.Budget,'budgets.manage'),
                'correction':(dto.Correction,'corrections.manage')}
        models.update(plan_action=(dto.PlanAction,'employees.goals'),season_edit=(dto.SeasonEdit,'seasons.manage'),
                      season_members=(dto.SeasonMembers,'seasons.manage'),recommendation_test=(dto.RecommendationTest,'recommendations.manage'),
                      assistant_test=(dto.AssistantTest,'ai.manage'))
        models['quest_test']=(dto.Quest,'quests.manage')
        result={k:m.model_json_schema() for k,(m,p) in models.items() if p is None or p in user['capabilities']}
        if 'access' in result: result['access']['properties']['permissions']['items']['enum']=sorted(PERMISSIONS)
        return read(lambda s,n,db:result)

    @app.post('/api/admin/media')
    async def media_upload(request:Request,file:UploadFile=File(...),expected_revision:int=Form(...),
                           alt:str=Form(...,min_length=1,max_length=300),user=Depends(allowed('branding.manage')),
                           idempotency_key:str|None=Header(None)):
        import io
        import warnings
        from PIL import Image,UnidentifiedImageError
        content=await file.read(5*1024*1024+1)
        require(len(content)<=5*1024*1024,'FILE_TOO_LARGE','Максимум 5 MiB',422)
        try:
            with warnings.catch_warnings():
                warnings.simplefilter('error',Image.DecompressionBombWarning)
                picture=Image.open(io.BytesIO(content))
                require(picture.format in ('PNG','JPEG','WEBP'),'INVALID_IMAGE','Разрешены PNG, JPEG и WebP',422)
                require(picture.width*picture.height<=16_000_000,'IMAGE_TOO_LARGE','Максимум 16 мегапикселей',422)
                picture.load()
                output=io.BytesIO();picture.convert('RGBA').save(output,format='PNG')
                clean=output.getvalue()
        except (UnidentifiedImageError,OSError,ValueError,Image.DecompressionBombError,Image.DecompressionBombWarning):
            raise Problem('INVALID_IMAGE','Не удалось проверить содержимое изображения',422)
        payload=dict(expected_revision=expected_revision,digest=hashlib.sha256(clean).hexdigest(),alt=alt)
        def run(s,n,db):
            actor=service.fresh_user(app.state.db,db,user,'branding.manage')
            key=uid('media_');folder=app.state.db.path.parent/'media';folder.mkdir(exist_ok=True)
            (folder/(key+'.png')).write_bytes(clean)
            value=dict(id=key,url='/api/media/'+key,alt=alt,mime='image/png',size_bytes=len(clean),width=picture.width,height=picture.height)
            s.setdefault('media_assets',{})[key]=value
            service.audit(db,actor,'media.upload',key,{},value,'Загрузка изображения',n,request.state.request_id)
            return value
        return app.state.engine.mutate(user,'admin.media',payload,idempotency_key,run,include_db=True)

    @app.get('/api/media/{key}')
    def media_file(key:str):
        import re
        require(re.fullmatch(r'media_[0-9a-f]{32}',key),'NOT_FOUND','Изображение не найдено',404)
        path=app.state.db.path.parent/'media'/(key+'.png')
        require(path.is_file(),'NOT_FOUND','Изображение не найдено',404)
        return FileResponse(path,media_type='image/png',headers={'X-Content-Type-Options':'nosniff'})

    @app.get('/api/admin/media')
    def media_list(user=Depends(allowed('branding.manage'))):
        return read(lambda s,n,db:dict(items=list(s.get('media_assets',{}).values())))

    @app.get('/api/admin/users')
    def users(search:str='',page:int=Query(1,ge=1),page_size:int=Query(25,ge=1,le=100),sort:Literal['username','display_name','role']='username',user=Depends(allowed('users.read'))):
        return read(lambda s,n,db:page_rows([user_view(db,r) for r in db.execute('SELECT * FROM accounts')],search,page,page_size,sort))

    @app.get('/api/admin/users/{username}')
    def user_card(username:str,user=Depends(allowed('users.read'))):
        def get(s,n,db):
            row=db.execute('SELECT * FROM accounts WHERE username=?',(username,)).fetchone()
            require(row,'NOT_FOUND','Аккаунт не найден',404)
            return dict(user=user_view(db,row),known_permissions=sorted(PERMISSIONS),
                        sessions=[dict(expires_at=r[0]) for r in db.execute('SELECT expires_at FROM sessions WHERE username=?',(username,))])
        return read(get)

    @app.post('/api/admin/users')
    def create_user(body:dto.UserCreate,request:Request,user=Depends(allowed('users.manage')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            require(not db.execute('SELECT 1 FROM accounts WHERE username=?',(body.username,)).fetchone(),'DUPLICATE_USER','Этот логин уже занят')
            require(body.employee_id is None or body.employee_id in s['employees'],'NOT_FOUND','Сотрудник не найден',422)
            salt=secrets.token_hex(16)
            db.execute('INSERT INTO accounts(username,password_hash,salt,role,employee_id,display_name,must_change_password) VALUES (?,?,?,?,?,?,1)',
                       (body.username,password_hash(body.password,salt),salt,'employee',body.employee_id,body.display_name))
            result=dict(username=body.username,role='employee',must_change_password=True)
            service.audit(db,actor,'user.create',body.username,{},result,body.reason,n,request.state.request_id)
            return result
        return mutate(user,'users.manage','admin.user.create',body,idempotency_key,run)

    @app.patch('/api/admin/users/{username}')
    def edit_user(username:str,body:dto.UserEdit,request:Request,user=Depends(allowed('users.manage')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            row=db.execute('SELECT * FROM accounts WHERE username=?',(username,)).fetchone()
            require(row,'NOT_FOUND','Аккаунт не найден',404)
            require(row['role']!='super_admin' or actor['role']=='super_admin','FORBIDDEN','Требуется super_admin',403)
            require(body.employee_id is None or body.employee_id in s['employees'],'NOT_FOUND','Сотрудник не найден',422)
            db.execute('UPDATE accounts SET display_name=?,employee_id=?,entity_version=entity_version+1 WHERE username=?',(body.display_name,body.employee_id,username))
            db.execute('DELETE FROM sessions WHERE username=?',(username,))
            service.audit(db,actor,'user.edit',username,user_view(db,row),body.model_dump(),body.reason,n,request.state.request_id)
            return dict(status='applied')
        return mutate(user,'users.manage','admin.user.edit:'+username,body,idempotency_key,run)

    @app.post('/api/admin/users/{username}/access')
    def access(username:str,body:dto.Access,request:Request,user=Depends(allowed('users.roles')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            row=db.execute('SELECT * FROM accounts WHERE username=?',(username,)).fetchone()
            require(row,'NOT_FOUND','Аккаунт не найден',404)
            require(username!=actor['username'],'SELF_ACCESS_CHANGE','Собственные ограничения изменять нельзя',403)
            require(set(body.permissions)<=PERMISSIONS,'UNKNOWN_PERMISSION','Неизвестное разрешение',422)
            require(body.role in ('admin','hr') or not body.permissions,'INVALID_GRANTS','Дополнительные права назначаются admin/HR',422)
            require(actor['role']=='super_admin' or row['role']!='super_admin' and body.role!='super_admin','FORBIDDEN','Назначение super_admin не делегируется',403)
            require(actor['role']=='super_admin' or set(body.permissions)<=set(actor['capabilities']),'FORBIDDEN','Нельзя делегировать отсутствующее право',403)
            if row['role']=='super_admin' and row['active'] and (body.role!='super_admin' or not body.active):
                require(db.execute("SELECT COUNT(*) FROM accounts WHERE role='super_admin' AND active=1").fetchone()[0]>1,'LAST_SUPER_ADMIN','Нельзя отключить последнего super_admin')
            before=user_view(db,row)
            db.execute('UPDATE accounts SET role=?,active=?,entity_version=entity_version+1 WHERE username=?',(body.role,body.active,username))
            db.execute('DELETE FROM permission_grants WHERE username=?',(username,))
            for permission in set(body.permissions):
                db.execute('INSERT INTO permission_grants VALUES (?,?,?,?)',(username,permission,actor['username'],stamp(n)))
            db.execute('DELETE FROM sessions WHERE username=?',(username,))
            service.audit(db,actor,'user.access',username,before,body.model_dump(),body.reason,n,request.state.request_id)
            return dict(status='applied',sessions_revoked=True)
        return mutate(user,'users.roles','admin.access:'+username,body,idempotency_key,run)

    @app.post('/api/admin/users/{username}/password-reset')
    def reset_password(username:str,body:dto.PasswordReset,request:Request,user=Depends(allowed('users.manage')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            row=db.execute('SELECT * FROM accounts WHERE username=?',(username,)).fetchone()
            require(row,'NOT_FOUND','Аккаунт не найден',404)
            require(row['role'] not in ('admin','super_admin','hr') or actor['role']=='super_admin','FORBIDDEN','Пароли привилегированных аккаунтов сбрасывает super_admin',403)
            salt=secrets.token_hex(16)
            db.execute('UPDATE accounts SET password_hash=?,salt=?,must_change_password=1,entity_version=entity_version+1 WHERE username=?',
                       (password_hash(body.temporary_password,salt),salt,username))
            db.execute('DELETE FROM sessions WHERE username=?',(username,))
            service.audit(db,actor,'user.password_reset',username,{},dict(sessions_revoked=True),body.reason,n,request.state.request_id)
            return dict(status='applied',must_change_password=True)
        return mutate(user,'users.manage','admin.password:'+username,body,idempotency_key,run)

    @app.post('/api/admin/users/{username}/revoke-sessions')
    def revoke(username:str,body:dto.Reason,request:Request,user=Depends(allowed('users.sessions')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            row=db.execute('SELECT role FROM accounts WHERE username=?',(username,)).fetchone()
            require(row,'NOT_FOUND','Аккаунт не найден',404)
            require(row[0]!='super_admin' or actor['role']=='super_admin','FORBIDDEN','Требуется super_admin',403)
            db.execute('DELETE FROM sessions WHERE username=?',(username,))
            service.audit(db,actor,'user.revoke',username,{},dict(sessions_revoked=True),body.reason,n,request.state.request_id)
            return dict(status='applied')
        return mutate(user,'users.sessions','admin.revoke:'+username,body,idempotency_key,run)

    def resource(domain,model):
        path=PATHS.get(domain,domain); permission=service.DOMAIN_PERMISSION[domain]
        read_permission='employees.read' if domain=='employees' else permission
        Draft=create_model(model.__name__+'Draft',__base__=dto.Reason,
                           payload=(model,...),target_id=(str,'global'),change_id=(str|None,None))
        def get(search:str='',page:int=Query(1,ge=1),page_size:int=Query(25,ge=1,le=100),
                sort:Literal['name','id','title','updated_at']='name',target_id:str='global',user=Depends(allowed(read_permission))):
            def run(s,n,db):
                result=dict(schema=model.model_json_schema() if permission in user['capabilities'] else None,domain=domain)
                if domain in service.COLLECTIONS:
                    rows=list(s[service.COLLECTIONS[domain]].values())
                    if domain=='shop': rows=[game.item_view(r) for r in rows]
                    result.update(page_rows(rows,search,page,page_size,sort))
                else: result['value']=service.current(s,domain,target_id)
                return result
            return read(run)
        def post(body,request:Request,user=Depends(allowed(permission)),idempotency_key:str|None=Header(None)):
            return mutate(user,permission,'admin.draft:'+domain,body,idempotency_key,
                lambda s,n,db,actor:service.draft(db,s,actor,domain,body.target_id,body.payload.model_dump(),body.reason,n,body.change_id))
        post.__annotations__['body']=Draft
        app.add_api_route('/api/admin/'+path,get,methods=['GET'],name='admin_'+domain.replace('-','_'))
        app.add_api_route('/api/admin/'+path,post,methods=['POST'],name='draft_'+domain.replace('-','_'))
    for domain,model in (dto.POLICY_MODELS|dto.ENTITY_MODELS).items():
        if domain!='pass': resource(domain,model)

    @app.get('/api/admin/changes')
    def changes(search:str='',page:int=Query(1,ge=1),page_size:int=Query(25,ge=1,le=100),user=Depends(admin)):
        def get(s,n,db):
            rows=[dict(r) for r in db.execute('SELECT * FROM change_sets') if service.DOMAIN_PERMISSION.get(r['domain']) in user['capabilities']]
            for row in rows: row['payload']=json.loads(row['payload'])
            return page_rows(rows,search,page,page_size,'created_at')
        return read(get)

    @app.get('/api/admin/changes/{key}')
    def change_card(key:str,user=Depends(admin)):
        def get(s,n,db):
            change=service.get_change(db,key); service.check(user,service.DOMAIN_PERMISSION[change['domain']])
            return dict(change=change,versions=[dict(r)|{'payload':json.loads(r['payload'])} for r in db.execute('SELECT * FROM config_versions WHERE domain=? AND target_id=? ORDER BY version DESC',(change['domain'],change['target_id']))])
        return read(get)

    @app.post('/api/admin/changes/{key}/preview')
    @app.post('/api/admin/changes/{key}/validate')
    def preview(key:str,body:dto.Revision,user=Depends(admin),idempotency_key:str|None=Header(None)):
        change=read(lambda s,n,db:service.get_change(db,key))['data']
        return mutate(user,service.DOMAIN_PERMISSION[change['domain']],'admin.preview:'+key,body,idempotency_key,
                      lambda s,n,db,actor:service.preview(db,s,actor,key,n))

    @app.post('/api/admin/changes/{key}/publish')
    def publish(key:str,body:dto.Publish,request:Request,user=Depends(admin),idempotency_key:str|None=Header(None)):
        change=read(lambda s,n,db:service.get_change(db,key))['data']
        return mutate(user,service.DOMAIN_PERMISSION[change['domain']],'admin.publish:'+key,body,idempotency_key,
                      lambda s,n,db,actor:service.publish_change(db,s,actor,key,body.model_dump(),n,request.state.request_id))

    @app.post('/api/admin/changes/{key}/clone')
    @app.post('/api/admin/changes/{key}/restore-as-draft')
    def clone(key:str,body:dto.Reason,user=Depends(admin),idempotency_key:str|None=Header(None)):
        change=read(lambda s,n,db:service.get_change(db,key))['data']
        return mutate(user,service.DOMAIN_PERMISSION[change['domain']],'admin.clone:'+key,body,idempotency_key,
                      lambda s,n,db,actor:service.draft(db,s,actor,change['domain'],change['target_id'],change['payload'],body.reason,n))

    @app.get('/api/admin/seasons')
    def seasons(user=Depends(allowed('seasons.manage'))):
        return read(lambda s,n,db:dict(items=[{**game.season_summary(se),'employee_ids':list(se['roster']),
                    'totals':pass_totals(se),'virtual_budget_kzt':se['virtual_budget_kzt'],'paused':se.get('paused',False)} for se in s['seasons'].values()]))

    @app.post('/api/admin/seasons')
    def season_create(body:dto.Season,request:Request,user=Depends(allowed('seasons.manage')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            value=game.make_season(s,body.name,body.starts_at,body.employee_ids,body.virtual_budget_kzt,n)
            privileged={r[0] for r in db.execute("SELECT employee_id FROM accounts WHERE role!='employee' AND employee_id IS NOT NULL")}
            for eid in privileged:
                if eid in value['roster']: value['roster'][eid]['prize_eligible']=False
            service.audit(db,actor,'season.create',value['id'],{},game.season_summary(value),body.reason,n,request.state.request_id)
            return value
        return mutate(user,'seasons.manage','admin.season.create',body,idempotency_key,run)

    @app.get('/api/admin/seasons/{sid}/pass')
    def season_pass(sid:str,user=Depends(allowed('pass.manage'))):
        return read(lambda s,n,db:dict(value=service.current(s,'pass',sid),schema=dto.Pass.model_json_schema(),domain='pass',totals=pass_totals(game.choose_season(s,sid))))

    PassDraft=create_model('PassDraft',__base__=dto.Reason,payload=(dto.Pass,...),change_id=(str|None,None))
    @app.patch('/api/admin/seasons/{sid}/pass')
    def pass_draft(sid:str,body:PassDraft,user=Depends(allowed('pass.manage')),idempotency_key:str|None=Header(None)):
        return mutate(user,'pass.manage','admin.pass:'+sid,body,idempotency_key,
                      lambda s,n,db,actor:service.draft(db,s,actor,'pass',sid,body.payload.model_dump(),body.reason,n,body.change_id))

    @app.post('/api/admin/seasons/{sid}/publication')
    def season_publication(sid:str,body:dto.Reason,user=Depends(allowed('seasons.publish')),idempotency_key:str|None=Header(None)):
        return mutate(user,'seasons.publish','admin.season.publication:'+sid,body,idempotency_key,
                      lambda s,n,db,actor:service.draft(db,s,actor,'season-publication',sid,{},body.reason,n))

    @app.post('/api/admin/seasons/{sid}/pause')
    def pause(sid:str,body:dto.Reason,request:Request,user=Depends(allowed('seasons.manage')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            se=game.choose_season(s,sid); before=se.get('paused',False); se['paused']=not before
            service.audit(db,actor,'season.pause',sid,dict(paused=before),dict(paused=se['paused']),body.reason,n,request.state.request_id)
            return dict(paused=se['paused'])
        return mutate(user,'seasons.manage','admin.pause:'+sid,body,idempotency_key,run)

    @app.patch('/api/admin/seasons/{sid}')
    def season_edit(sid:str,body:dto.SeasonEdit,request:Request,user=Depends(allowed('seasons.manage')),idempotency_key:str|None=Header(None)):
        return mutate(user,'seasons.manage','admin.season.edit:'+sid,body,idempotency_key,
            lambda s,n,db,actor:service.draft(db,s,actor,'season-edit',sid,body.model_dump(exclude={'expected_revision','reason'}),body.reason,n))

    @app.post('/api/admin/seasons/{sid}/members')
    def members(sid:str,body:dto.SeasonMembers,request:Request,user=Depends(allowed('seasons.manage')),idempotency_key:str|None=Header(None)):
        return mutate(user,'seasons.manage','admin.season.members:'+sid,body,idempotency_key,
            lambda s,n,db,actor:service.draft(db,s,actor,'season-members',sid,body.model_dump(exclude={'expected_revision','reason'}),body.reason,n))

    @app.post('/api/admin/employees/{eid}/plan-actions')
    def plan_action(eid:str,body:dto.PlanAction,request:Request,user=Depends(allowed('employees.goals')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            require(eid in s['employees'],'NOT_FOUND','Сотрудник не найден',404);before=career.plan(s,eid,n)
            command=body.model_dump()
            if body.action in ('add','replace'):
                require(body.activity_id,'INVALID_ACTIVITY','Выберите активность',422)
                career.add_plan(s,eid,command,n,body.plan_id if body.action=='replace' else None)
            elif body.action=='archive':career.transition(s,eid,body.plan_id,'archive',{},n)
            else:
                items=career.active_plan(s,eid)
                require(set(body.item_ids)=={r['id'] for r in items} and len(body.item_ids)==len(items),'INVALID_ORDER','Передайте каждый активный шаг один раз',422)
                for index,pid in enumerate(body.item_ids):s['plan'][pid]['position']=index
            result=career.plan(s,eid,n)
            s['admin_history'].append(dict(employee_id=eid,at=stamp(n),title='Администратор изменил план',reason=body.reason,actor=actor['username']))
            service.audit(db,actor,'employee.plan',eid,before,result,body.reason,n,request.state.request_id);return result
        return mutate(user,'employees.goals','admin.plan:'+eid,body,idempotency_key,run)

    @app.post('/api/admin/recommendation-policies/simulate')
    def simulate(body:dto.RecommendationTest,user=Depends(allowed('recommendations.manage'))):
        def get(s,n,db):
            require(body.employee_id in s['employees'],'NOT_FOUND','Сотрудник не найден',404)
            trial=deepcopy(s);trial['policies']['recommendations']=body.payload.model_dump()
            return dict(before=career.recommendations(s,body.employee_id,n),after=career.recommendations(trial,body.employee_id,n),read_only=True)
        return read(get)

    @app.post('/api/admin/quest-templates/test')
    def test_quest(body:dto.Quest,user=Depends(allowed('quests.manage'))):
        def get(s,n,db):
            from .game_rules import task_variant,normalise_answer,game_date
            season=game.choose_season(s);results=[]
            for index in range(20):
                task=task_variant(s['task_secret'],season,'test',game_date(n)+timedelta(days=index),body.generator) if body.kind=='generator' else {
                    **body.model_dump(), 'custom':True}
                normalise_answer(task,task['expected_answer'])
                results.append(dict(index=index+1,instructions=task['instructions'],expected_answer=task['expected_answer'],valid=True))
            return dict(items=results,total=20,read_only=True)
        return read(get)

    @app.post('/api/admin/assistant-settings/test')
    async def test_assistant(body:dto.AssistantTest,user=Depends(allowed('ai.manage'))):
        from .assistant import CareerAssistant,context_for
        def get(s,n,db):
            require(body.employee_id in s['employees'],'NOT_FOUND','Сотрудник не найден',404)
            return context_for(s,body.employee_id,n,'why')
        result=read(get)
        answer=await CareerAssistant().explain(result['data'],body.employee_id,result['meta']['state_revision'],body.payload.model_dump())
        return {'data':dict(**answer,read_only=True),'meta':result['meta']}

    @app.get('/api/admin/employees/{eid}')
    def employee_card(eid:str,user=Depends(allowed('employees.read'))):
        def get(s,n,db):
            require(eid in s['employees'],'NOT_FOUND','Сотрудник не найден',404)
            return dict(employee=s['employees'][eid],progress=career.progress(s,eid),plan=career.plan(s,eid,n),
                        goal=career.goal(s,eid),history=career.history(s,eid),admin_history=[r for r in s['admin_history'] if r['employee_id']==eid],
                        assessments=[r for r in s['assessment_revisions'] if r['employee_id']==eid],read_only_preview=True)
        return read(get)

    @app.post('/api/admin/employees/{eid}/assessments')
    def assessment(eid:str,body:dto.Assessment,request:Request,user=Depends(allowed('employees.assessments')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            e=s['employees'].get(eid); require(e,'NOT_FOUND','Сотрудник не найден',404)
            date=instant(body.assessed_at)
            require(date.tzinfo is not None and instant(e['assessment_at'])<date<=n,'INVALID_ASSESSMENT_DATE','Новая оценка должна быть позже последней и не в будущем',422)
            require(set(body.skills)<=set(s['skills']),'INVALID_SKILL','Неизвестный навык',422)
            before=deepcopy(e)
            s['assessment_revisions'].append(dict(id=uid('assessment_'),employee_id=eid,before=e['skills'],after=body.skills,
                previous_at=e['assessment_at'],assessed_at=stamp(date),source=body.source,reason=body.reason,actor=actor['username']))
            dates=e.setdefault('skill_assessed_at',{k:e['assessment_at'] for k in e['skills']})
            dates.update({k:stamp(date) for k in body.skills})
            e.update(skills={**e['skills'],**body.skills},assessment_at=stamp(date))
            service.audit(db,actor,'employee.assessment',eid,before,e,body.reason,n,request.state.request_id)
            return career.progress(s,eid)
        return mutate(user,'employees.assessments','admin.assessment:'+eid,body,idempotency_key,run)

    @app.post('/api/admin/employees/{eid}/goals')
    def goal(eid:str,body:dto.Goal,request:Request,user=Depends(allowed('employees.goals')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            require(eid in s['employees'],'NOT_FOUND','Сотрудник не найден',404)
            value=dict(target_role=body.role_id,target_grade=body.grade_id)
            require(career.target(s,value),'INVALID_GOAL','Цель отсутствует в справочнике',422)
            before=career.goal(s,eid)
            if body.kind=='personal': career.set_goal(s,eid,value,n,body.confirm_archive_plan)
            else: s['employees'][eid]['source_goal']=value
            s['admin_history'].append(dict(employee_id=eid,at=stamp(n),title='Администратор изменил цель',reason=body.reason,actor=actor['username']))
            service.audit(db,actor,'employee.goal',eid,before,career.goal(s,eid),body.reason,n,request.state.request_id)
            return career.goal(s,eid)
        return mutate(user,'employees.goals','admin.goal:'+eid,body,idempotency_key,run)

    @app.get('/api/admin/inventory/movements')
    def inventory(user=Depends(allowed('stock.manage'))):
        return read(lambda s,n,db:dict(items=[game.item_view(i) for i in s['items'].values()],movements=s['inventory_movements']))

    @app.post('/api/admin/inventory/movements')
    def movement(body:dto.Inventory,request:Request,user=Depends(allowed('stock.manage')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            item=s['items'].get(body.item_id); require(item,'NOT_FOUND','Товар не найден',404)
            require(not item.get('protected_pool') or body.delta>=0,'GUARANTEED_REWARD','Гарантированный запас нельзя списать')
            require(game.item_view(item)['available_stock']+body.delta>=0,'NEGATIVE_STOCK','Доступный остаток не может быть отрицательным')
            before=deepcopy(item); item['stock_total']+=body.delta; item['version']+=1
            event=dict(id=uid('stock_'),item_id=body.item_id,delta=body.delta,at=stamp(n),reason=body.reason,actor=actor['username'])
            s['inventory_movements'].append(event)
            service.audit(db,actor,'inventory.move',body.item_id,before,item,body.reason,n,request.state.request_id)
            return event
        return mutate(user,'stock.manage','admin.inventory',body,idempotency_key,run)

    @app.get('/api/admin/reviews')
    def reviews(user=Depends(allowed('reviews.manage'))):
        return read(lambda s,n,db:dict(items=list(s['reviews'].values())))

    @app.post('/api/admin/reviews/{rid}/decision')
    def decision(rid:str,body:DecisionInput,request:Request,user=Depends(allowed('reviews.manage')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            before=deepcopy(s['reviews'].get(rid)); result=game.decide_review(s,rid,body.decision,body.comment,n)
            service.audit(db,actor,'review.decision',rid,before,result,body.comment,n,request.state.request_id); return result
        return mutate(user,'reviews.manage','admin.review:'+rid,body,idempotency_key,run)

    @app.get('/api/admin/reward-orders')
    def orders(user=Depends(allowed('rewards.fulfill'))):
        return read(lambda s,n,db:dict(items=[game.order_view(o) for o in s['orders'].values()]))

    @app.post('/api/admin/reward-orders/{oid}/transition')
    def transition(oid:str,body:FulfillInput,request:Request,user=Depends(allowed('rewards.fulfill')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            before=deepcopy(s['orders'].get(oid)); result=game.transition_order(s,oid,body.target_status,body.note,body.actual_cost_kzt,n)
            service.audit(db,actor,'order.transition',oid,before,result,body.note,n,request.state.request_id); return result
        return mutate(user,'rewards.fulfill','admin.order:'+oid,body,idempotency_key,run)

    @app.get('/api/admin/wallets')
    def wallets(user=Depends(allowed('budgets.manage'))):
        return read(lambda s,n,db:dict(items=[dict(id=eid,name=e['full_name'],balance=game.wallet(s,eid)['balance']) for eid,e in s['employees'].items()]))

    @app.get('/api/admin/wallets/{eid}/ledger')
    def ledger(eid:str,user=Depends(allowed('budgets.manage'))):
        return read(lambda s,n,db:game.wallet(s,eid))

    @app.get('/api/admin/budgets')
    def budgets(user=Depends(allowed('budgets.manage'))):
        return read(lambda s,n,db:dict(items=[dict(id=se['id'],name=se['name'],**game.economy(s,se)) for se in s['seasons'].values()],movements=s['budget_movements']))

    @app.post('/api/admin/budget-movements')
    def finance(body:dto.Budget,request:Request,user=Depends(allowed('budgets.manage')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            se=game.choose_season(s,body.season_id); before=se['virtual_budget_kzt']; se['virtual_budget_kzt']+=body.amount_kzt
            event=dict(id=uid('budget_'),season_id=se['id'],amount_kzt=body.amount_kzt,reason=body.reason,at=stamp(n),actor=actor['username'])
            s['budget_movements'].append(event)
            service.audit(db,actor,'budget.fund',se['id'],before,se['virtual_budget_kzt'],body.reason,n,request.state.request_id)
            return event
        return mutate(user,'budgets.manage','admin.budget',body,idempotency_key,run)

    @app.get('/api/admin/corrections')
    def corrections(user=Depends(allowed('corrections.manage'))):
        return read(lambda s,n,db:dict(items=[dict(r)|{'payload':json.loads(r['payload'])} for r in db.execute('SELECT * FROM correction_cases')],schema=dto.Correction.model_json_schema()))

    @app.post('/api/admin/corrections')
    def create_correction(body:dto.Correction,user=Depends(allowed('corrections.manage')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            key=uid('correction_'); db.execute('INSERT INTO correction_cases VALUES (?,?,?,?,?)',(key,encode(body.model_dump()),actor['username'],'draft',stamp(n)))
            return dict(id=key,status='draft')
        return mutate(user,'corrections.manage','admin.correction',body,idempotency_key,run)

    @app.post('/api/admin/corrections/{key}/preview')
    def correction_preview(key:str,body:dto.Revision,user=Depends(allowed('corrections.manage')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            row=db.execute('SELECT * FROM correction_cases WHERE id=?',(key,)).fetchone(); require(row and row['status']!='applied','CORRECTION_LOCKED','Корректировка недоступна')
            payload=json.loads(row['payload']); trial=deepcopy(s); errors=[]; before=service.totals(s)
            try: service.correction_actions(trial,payload,n,key)
            except Problem as e: errors.append(dict(code=e.code,message=e.message,details=e.details))
            after=service.totals(trial) if not errors else before
            result=dict(preview_id=uid('preview_'),base_revision=s['revision']+1,expires_at=stamp(n+timedelta(minutes=15)),
                        totals_before=before,totals_after=after,blocking_errors=errors,can_publish=not errors,
                        xp_delta=after['xp']-before['xp'],coin_delta=after['coins']-before['coins'],budget_delta_kzt=after['budget_kzt']-before['budget_kzt'])
            payload['preview']=result; payload['preview_actor']=actor['username']
            db.execute("UPDATE correction_cases SET payload=?,status='previewed' WHERE id=?",(encode(payload),key)); return result
        return mutate(user,'corrections.manage','admin.correction.preview:'+key,body,idempotency_key,run)

    @app.post('/api/admin/corrections/{key}/apply')
    def correction_apply(key:str,body:dto.Publish,request:Request,user=Depends(allowed('corrections.manage')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            row=db.execute('SELECT * FROM correction_cases WHERE id=?',(key,)).fetchone(); require(row and row['status']=='previewed','CORRECTION_LOCKED','Корректировка недоступна')
            payload=json.loads(row['payload']); p=payload['preview']
            require(p['preview_id']==body.preview_id and payload['preview_actor']==actor['username'] and p['base_revision']==s['revision'] and instant(p['expires_at'])>n,'STALE_PREVIEW','Пересчитайте последствия')
            require(p['can_publish'],'INVALID_CORRECTION','Исправьте ошибки')
            result=service.correction_actions(s,payload,n,key)
            db.execute("UPDATE correction_cases SET status='applied' WHERE id=?",(key,))
            service.audit(db,actor,'correction.apply',key,p['totals_before'],result,payload['reason'],n,request.state.request_id)
            return dict(id=key,status='applied',totals=result)
        return mutate(user,'corrections.manage','admin.correction.apply:'+key,body,idempotency_key,run)

    @app.get('/api/admin/audit')
    def audit(search:str='',page:int=Query(1,ge=1),page_size:int=Query(25,ge=1,le=100),user=Depends(allowed('audit.read'))):
        return read(lambda s,n,db:page_rows([dict(r) for r in db.execute('SELECT * FROM admin_audit ORDER BY occurred_at DESC')],search,page,page_size,'occurred_at'))

    @app.get('/api/admin/config-exports')
    def config_export(user=Depends(allowed('exports.create'))):
        def get(s,n,db):
            values=[dict(r)|{'payload':service.redact(json.loads(r['payload']))} for r in db.execute('SELECT domain,target_id,version,payload,checksum FROM config_versions')
                    if service.DOMAIN_PERMISSION.get(r['domain']) in user['capabilities'] and r['domain'] not in ('employees',)]
            return dict(schema_version=1,versions=values,checksum=hashlib.sha256(encode(values).encode()).hexdigest())
        return read(get)

    @app.get('/api/admin/system/health')
    def system(user=Depends(allowed('system.maintain'))):
        return read(lambda s,n,db:dict(integrity=db.execute('PRAGMA quick_check').fetchone()[0],state_revision=s['revision'],
                    migrations=[r[0] for r in db.execute('SELECT version FROM schema_migrations')],
                    jobs=[dict(r)|{'result':json.loads(r['result'])} for r in db.execute('SELECT * FROM admin_jobs')],
                    deployment_settings=['Порт, путь SQLite и ключ OpenAI задаются в окружении сервера']))

    @app.post('/api/admin/system/backups')
    def backup(body:dto.Reason,request:Request,user=Depends(allowed('system.maintain')),idempotency_key:str|None=Header(None)):
        def run(s,n,db,actor):
            key=uid('backup_'); folder=app.state.db.path.parent/'backups'; folder.mkdir(exist_ok=True)
            content=db.serialize(); path=folder/(key+'.sqlite3'); path.write_bytes(content)
            result=dict(id=key,size_bytes=len(content),sha256=hashlib.sha256(content).hexdigest(),server_only=True)
            db.execute('INSERT INTO admin_jobs VALUES (?,?,?,?,?,?)',(key,'backup','completed',actor['username'],stamp(n),encode(result)))
            service.audit(db,actor,'system.backup',key,{},result,body.reason,n,request.state.request_id); return result
        return mutate(user,'system.maintain','admin.backup',body,idempotency_key,run)
