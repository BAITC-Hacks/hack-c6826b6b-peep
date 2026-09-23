"""Career Quest: local career planning and transactional seasonal rewards."""
from contextlib import asynccontextmanager, suppress
import asyncio
from collections import defaultdict
import logging
import os
from pathlib import Path
import time
import uuid

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles

from .config import load_env
from .data import Dataset
from .database import Database
from .engine import Engine, Problem, utcnow
from .models import LoginRequest
from .quest_api import install

ROOT=Path(__file__).resolve().parent.parent
load_env(ROOT / '.env')
logger=logging.getLogger(__name__)
bearer=HTTPBearer(auto_error=False)


def create_app(data_dir=None,db_path=None,web_dir=None,clock=utcnow):
    source=Path(data_dir or os.getenv('CAREER_DATA_DIR',ROOT/'data/sample'))
    path=Path(db_path or os.getenv('CAREER_DB',os.getenv('DATABASE_PATH',ROOT/'data/local/career.sqlite3')))
    @asynccontextmanager
    async def lifespan(app):
        db=Database(path)
        app.state.db=db
        app.state.engine=None
        try:
            if not db.has_dataset(): db.seed(Dataset.from_directory(source))
            db.ensure_accounts()
            app.state.engine=Engine(db,clock)
        except (OSError, ValueError) as exc:
            logger.error('Initial data unavailable (%s); health remains available',type(exc).__name__)
        async def ticker():
            while True:
                await asyncio.sleep(60)
                try:
                    if app.state.engine: await asyncio.to_thread(app.state.engine.read,lambda s,n:None)
                except Exception: logger.exception('Season tick failed')
        task=asyncio.create_task(ticker())
        try: yield
        finally:
            task.cancel()
            with suppress(asyncio.CancelledError): await task

    def known_query(request:Request):
        route=request.scope.get('route')
        root=getattr(route,'dependant',None)
        if root is None: return
        def names(dependant):
            result={p.alias for p in dependant.query_params}
            for child in dependant.dependencies: result.update(names(child))
            return result
        extra=set(request.query_params)-names(root)
        if extra: raise Problem('UNKNOWN_QUERY','Неизвестные параметры запроса',422,fields=sorted(extra))
    app=FastAPI(title='Career Quest API',version='1.0.0',lifespan=lifespan,dependencies=[Depends(known_query)])
    origins=os.getenv('ALLOWED_ORIGINS','http://localhost:8080,http://127.0.0.1:8080').split(',')
    app.add_middleware(CORSMiddleware,allow_origins=[x.strip() for x in origins],
        allow_methods=['GET','POST','PUT','PATCH','DELETE'],allow_headers=['Authorization','Content-Type','Idempotency-Key'])

    @app.middleware('http')
    async def private_responses(request,call_next):
        request.state.request_id=uuid.uuid4().hex
        response=await call_next(request)
        if request.url.path.startswith('/api/'):
            response.headers['Cache-Control']='no-store'
            response.headers['X-Request-ID']=request.state.request_id
        return response

    def error(request,code,message,status,details=None,headers=None):
        return JSONResponse({'error':{'code':code,'message':message,'details':details or {},'request_id':getattr(request.state,'request_id','')}},status_code=status,headers=headers)

    @app.exception_handler(Problem)
    async def problem_handler(request,exc):
        return error(request,exc.code,exc.message,exc.status,exc.details)

    @app.exception_handler(HTTPException)
    async def http_handler(request,exc):
        return error(request,{401:'UNAUTHORIZED',403:'FORBIDDEN',404:'NOT_FOUND',429:'RATE_LIMITED'}.get(exc.status_code,'REQUEST_FAILED'),str(exc.detail),exc.status_code,headers=exc.headers)

    @app.exception_handler(RequestValidationError)
    async def validation_handler(request,exc):
        return error(request,'VALIDATION_ERROR','Проверьте формат и обязательные поля запроса',422,
                     {'fields':[{'field':'.'.join(map(str,e['loc'])),'message':e['msg']} for e in exc.errors()]})

    @app.exception_handler(Exception)
    async def unexpected_handler(request,exc):
        logger.error('Request failed id=%s type=%s',request.state.request_id,type(exc).__name__)
        return error(request,'SERVICE_ERROR','Не удалось выполнить действие. Попробуйте ещё раз.',500)

    def current_user(credentials:HTTPAuthorizationCredentials|None=Depends(bearer)):
        user=app.state.db.session(credentials.credentials) if credentials else None
        if user is None: raise HTTPException(401,'Войдите в аккаунт заново',headers={'WWW-Authenticate':'Bearer'})
        return user

    def hr(user=Depends(current_user)):
        if user['role']!='hr': raise HTTPException(403,'Это действие доступно только HR')
        return user

    def employee(user=Depends(current_user)):
        if user['role']!='employee' or not user['employee_id']: raise HTTPException(403,'У аккаунта нет личного профиля сотрудника')
        return user

    failures=defaultdict(list)
    @app.get('/api/health')
    def health():
        return dict(status='ok',version='1.0.0',dataset_ready=app.state.db.has_dataset(),
                    ai_enabled=os.getenv('AI_MODE')=='llm' and bool(os.getenv('OPENAI_API_KEY')))

    @app.post('/api/auth/login')
    def login(body:LoginRequest,request:Request):
        username=body.username.strip().lower()
        key=(request.client.host if request.client else 'local',username)
        now=time.monotonic()
        failures[key]=[t for t in failures[key] if t>now-300]
        if len(failures[key])>=10: raise HTTPException(429,'Слишком много попыток. Подождите пять минут.',headers={'Retry-After':'300'})
        result=app.state.db.login(username,body.password)
        if result is None:
            failures[key].append(now)
            raise HTTPException(401,'Неверный логин или пароль',headers={'WWW-Authenticate':'Bearer'})
        failures.pop(key,None)
        return result

    @app.get('/api/auth/me')
    def me(user=Depends(current_user)): return user

    @app.post('/api/auth/logout')
    def logout(user=Depends(current_user),credentials:HTTPAuthorizationCredentials=Depends(bearer)):
        app.state.db.logout(credentials.credentials)
        return {'logged_out':True}

    install(app,current_user,employee,hr)

    @app.get('/api/employees/{eid}')
    def old_profile(eid:str,user=Depends(current_user)):
        if user['role']!='hr' and user['employee_id']!=eid: raise HTTPException(404,'Профиль не найден')
        from .quest_api import career
        def get(s,n):
            if eid not in s['employees']: raise HTTPException(404,'Профиль не найден')
            return dict(employee=s['employees'][eid],**career.goal(s,eid),progress=career.progress(s,eid))
        return app.state.engine.read(get)

    @app.api_route('/api/{path:path}',methods=['GET','POST','PUT','PATCH','DELETE'],include_in_schema=False)
    def unknown_api(path:str): raise HTTPException(404,'API не найден')

    web=Path(web_dir) if web_dir else ROOT/'frontend/build/web'
    if web.is_dir(): app.mount('/',StaticFiles(directory=web,html=True),name='web')
    return app


app=create_app()
