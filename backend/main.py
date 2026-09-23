"""Stage 2: role-scoped profiles, persistent goals and validated imports."""
from contextlib import asynccontextmanager
import logging
import os
from pathlib import Path

from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles

from .data import Dataset
from .database import Database
from .imports import commit, preview
from .models import CommitRequest, Goal, LoginRequest
from .profiles import profile

ROOT = Path(__file__).resolve().parent.parent
logger = logging.getLogger(__name__)
bearer = HTTPBearer(auto_error=False)


def create_app(data_dir=None, db_path=None, web_dir=None):
    source = Path(data_dir or os.getenv('CAREER_DATA_DIR', ROOT / 'data/sample'))
    path = Path(db_path or os.getenv('CAREER_DB', ROOT / 'data/local/career.sqlite3'))

    @asynccontextmanager
    async def lifespan(app):
        db = Database(path)
        app.state.db = db
        try:
            if not db.has_dataset():
                db.seed(Dataset.from_directory(source))
            db.ensure_accounts()
        except (OSError, ValueError, KeyError, TypeError) as exc:
            logger.warning('Dataset initialisation failed (%s)', type(exc).__name__)
        yield

    app = FastAPI(title='Career Quest API', version='0.2.0', lifespan=lifespan,
                  description='Локальный прототип: роли сотрудника/HR, профиль, цель и импорт.')
    app.add_middleware(CORSMiddleware,
                       allow_origins=['http://localhost:8080', 'http://127.0.0.1:8080'],
                       allow_methods=['GET', 'POST', 'PUT', 'DELETE'],
                       allow_headers=['Authorization', 'Content-Type'])

    @app.middleware('http')
    async def private_responses(request, call_next):
        response = await call_next(request)
        if request.url.path.startswith('/api/'):
            response.headers['Cache-Control'] = 'no-store'
        return response

    def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        user = app.state.db.session(credentials.credentials) if credentials else None
        if user is None:
            raise HTTPException(401, 'Войдите в аккаунт заново', headers={'WWW-Authenticate': 'Bearer'})
        return user

    def hr(user=Depends(current_user)):
        if user['role'] != 'hr':
            raise HTTPException(403, 'Это действие доступно только HR')
        return user

    def employee(user=Depends(current_user)):
        if user['role'] != 'employee' or not user['employee_id']:
            raise HTTPException(403, 'У этого аккаунта нет личного профиля сотрудника')
        return user

    def dataset():
        result = app.state.db.read_dataset()
        if result is None:
            raise HTTPException(503, 'Данные пока недоступны. Подготовьте стартовый набор и перезапустите сервер.')
        return result

    def authorised_profile(employee_id, user):
        # Check ownership BEFORE looking up an ID, so existence cannot be probed by other employees.
        if user['role'] != 'hr' and user['employee_id'] != employee_id:
            raise HTTPException(403, 'Можно просматривать только свой профиль')
        ds = dataset()
        if employee_id not in ds.employees:
            raise HTTPException(404, 'Профиль сотрудника не найден')
        return profile(ds, employee_id, app.state.db.goal(employee_id))

    @app.get('/api/health', tags=['Infrastructure'])
    def health():
        return dict(status='ok', stage=2, dataset_ready=app.state.db.has_dataset(), ai_enabled=False)

    @app.post('/api/auth/login', tags=['Access'])
    def login(body: LoginRequest):
        result = app.state.db.login(body.username.strip().lower(), body.password)
        if result is None:
            raise HTTPException(401, 'Неверный логин или пароль', headers={'WWW-Authenticate': 'Bearer'})
        return result

    @app.get('/api/auth/me', tags=['Access'])
    def me(user=Depends(current_user)):
        return user

    @app.post('/api/auth/logout', tags=['Access'])
    def logout(user=Depends(current_user), credentials: HTTPAuthorizationCredentials = Depends(bearer)):
        app.state.db.logout(credentials.credentials)
        return {'logged_out': True}

    @app.get('/api/meta', tags=['Profiles'])
    def meta(user=Depends(current_user)):
        ds = dataset()
        return dict(roles=[r.model_dump(mode='json') for r in ds.roles.values()],
                    skills=[s.model_dump(mode='json') for s in ds.skills.values()])

    @app.get('/api/me/profile', tags=['Profiles'])
    def my_profile(user=Depends(employee)):
        return authorised_profile(user['employee_id'], user)

    @app.get('/api/employees/{employee_id}', tags=['Profiles'])
    def get_profile(employee_id: str, user=Depends(current_user)):
        return authorised_profile(employee_id, user)

    @app.get('/api/employees/{employee_id}/history', tags=['Profiles'])
    def history(employee_id: str, user=Depends(current_user)):
        return {'history': authorised_profile(employee_id, user)['history']}

    @app.put('/api/me/goal', tags=['Profiles'])
    def set_goal(body: Goal, user=Depends(employee)):
        ds = dataset()
        if (body.target_role, body.target_grade) not in ds.roles:
            raise HTTPException(422, 'Такой цели нет в каталоге ролей')
        app.state.db.save_goal(user['employee_id'], body.model_dump(mode='json'))
        return authorised_profile(user['employee_id'], user)

    @app.delete('/api/me/goal', tags=['Profiles'])
    def reset_goal(user=Depends(employee)):
        app.state.db.save_goal(user['employee_id'], None)
        return authorised_profile(user['employee_id'], user)

    @app.get('/api/hr/employees', tags=['HR'])
    def employees(q: str = Query(default='', max_length=100), user=Depends(hr)):
        ds = dataset()
        with app.state.db.connection() as db:
            personal = {r[0] for r in db.execute('SELECT employee_id FROM personal_goals')}
        rows = [dict(employee_id=e.employee_id, full_name=e.full_name, role=e.role, grade=e.grade,
                     department=e.department, has_goal=e.career_goal is not None or e.employee_id in personal)
                for e in ds.employees.values()
                if q.strip().casefold() in f'{e.employee_id} {e.full_name} {e.role} {e.department}'.casefold()]
        return dict(employees=rows, total=len(rows))

    @app.post('/api/hr/import/preview', tags=['Import'])
    def import_preview(employees_file: UploadFile | None = File(default=None),
                       history_file: UploadFile | None = File(default=None),
                       conflict_policy: str = Form(default='reject'), user=Depends(hr)):
        return preview(app.state.db, user['username'], employees_file, history_file, conflict_policy)

    @app.post('/api/hr/import/commit', status_code=201, tags=['Import'])
    def import_commit(body: CommitRequest, user=Depends(hr)):
        return commit(app.state.db, user['username'], body.preview_id)

    @app.get('/api/{path:path}', include_in_schema=False)
    def unknown_api(path: str):
        raise HTTPException(404, 'API не найден')

    web = Path(web_dir) if web_dir else ROOT / 'frontend/build/web'
    if web.is_dir():
        app.mount('/', StaticFiles(directory=web, html=True), name='web')
    return app


app = create_app()
