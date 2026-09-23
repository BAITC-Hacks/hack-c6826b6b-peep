"""Versioned domain state. Every business mutation is a single SQLite transaction.

Source tables are immutable to this layer. JSON state is suitable for the local,
single-organisation prototype; transactions still serialize concurrent writers.
"""
from copy import deepcopy
from datetime import datetime, timezone, timedelta
from contextlib import contextmanager
import hashlib
import json
import secrets
import uuid

from .database import encode

UTC = timezone.utc


def utcnow():
    return datetime.now(UTC)


def stamp(dt):
    return dt.astimezone(UTC).isoformat().replace('+00:00', 'Z')


def instant(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00'))


def uid(prefix=''):
    return prefix + uuid.uuid4().hex


class Problem(Exception):
    def __init__(self, code, message, status=409, **details):
        self.code, self.message, self.status, self.details = code, message, status, details


def require(condition, code, message, status=409, **details):
    if not condition:
        raise Problem(code, message, status, **details)


def own(items, key, employee_id):
    row = items.get(key)
    require(row is not None and row['employee_id'] == employee_id,
            'NOT_FOUND', 'Запись не найдена', 404)
    return row


def initial_state(database, db, now):
    ds = database.read_dataset(db)
    if ds is None:
        raise Problem('NOT_READY', 'Стартовые данные недоступны', 503)
    employees, roles, activities = {}, {}, {}
    for e in ds.employees.values():
        employees[e.employee_id] = {
            **e.model_dump(mode='json'), 'id': e.employee_id,
            'source_skills': e.skills, 'source_scale': [0, 5],
            'skills': {k: v * 20 for k, v in e.skills.items()},
            'assessment_at': e.last_review_date.isoformat() + 'T23:59:59Z',
            'assessment_date_source': 'last_review_date',
            'source_goal': e.career_goal.model_dump() if e.career_goal else None,
        }
    for r in ds.roles.values():
        roles[r.role + '|' + r.grade] = {
            'role_id': r.role, 'grade_id': r.grade,
            'requirements': {k: {'level': v * 20, 'weight': 3 if k in r.critical_skills else 1}
                             for k, v in r.required_skills.items() if v > 0},
        }
    for a in ds.events.values():
        activities[a.event_id] = {
            'id': a.event_id, 'title': a.title, 'description': a.description,
            'format': a.format, 'kind': 'self_paced', 'active': True,
            'duration_minutes': max(1, round(a.duration_hours * 60)),
            'gains': {g.skill_id: min(20, g.gain * 20) for g in a.develops_skills},
            'prerequisites': {k: v * 20 for k, v in a.prerequisites.items()},
            'source': a.model_dump(mode='json'), 'starts_at': None, 'ends_at': None,
            'available_from': None, 'available_until': None,
            'outcome': 'Подготовьте краткий разбор: задача, применённый подход, результат и выводы.',
            'instructions': f'Локальная практика по теме «{a.title}».\n\n'
                f'{a.description}\n\n1. Выберите рабочую ситуацию по теме.\n'
                '2. Опишите исходную проблему и критерий успеха.\n'
                '3. Предложите решение и проверьте его на учебном примере.\n'
                '4. Запишите результат и ограничения. Отправьте выводы HR для проверки XP.\n\n'
                'Это самостоятельная практика Career Quest, без записи во внешнюю LMS.',
        }
    history = []
    for h in ds.activities:
        item = h.model_dump(mode='json')
        history.append({**item, 'activity_id': h.event_id, 'origin': 'imported',
                        'completed_at': h.date.isoformat() + 'T12:00:00Z' if h.status == 'completed' else None,
                        'started_at': h.date.isoformat() + 'T12:00:00Z' if h.status == 'in_progress' else None,
                        'attended_at': None, 'registered_at': None})
    goals = {r[0]: json.loads(r[1]) for r in db.execute('SELECT * FROM personal_goals')}
    return dict(version=1, revision=0, created_at=stamp(now), employees=employees, roles=roles,
                skills={k: v.model_dump() for k, v in ds.skills.items()}, activities=activities,
                imported_history=history, goals=goals, preferences={}, plan={}, completions={},
                exclusions={}, simulations={}, seasons={}, items={}, pools={}, xp={}, ledger={},
                entitlements={}, orders={}, reviews={}, tasks={}, badges={}, audit=[], idempotency={},
                task_secret=secrets.token_hex(32), snapshots={})


class Engine:
    def __init__(self, database, clock=utcnow):
        self.database, self.clock = database, clock
        with database.connection(write=True) as db:
            db.execute('CREATE TABLE IF NOT EXISTS quest_state (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)')
            if db.execute('SELECT 1 FROM quest_state WHERE id=1').fetchone() is None:
                from .game import seed_game
                state = initial_state(database, db, clock())
                seed_game(state, clock())
                db.execute('INSERT INTO quest_state VALUES (1,?)', (encode(state),))

    @contextmanager
    def transaction(self):
        with self.database.connection(write=True) as db:
            state = json.loads(db.execute('SELECT payload FROM quest_state WHERE id=1').fetchone()[0])
            yield state
            db.execute('UPDATE quest_state SET payload=? WHERE id=1', (encode(state),))

    def read(self, function):
        from .game import tick
        with self.transaction() as s:
            if tick(s, self.clock()):
                s['revision'] += 1
            result = function(s, self.clock())
            return {'data': result, 'meta': {'state_revision': s['revision'], 'server_time': stamp(self.clock())}}

    def mutate(self, user, route, body, key, function):
        require(key is not None, 'IDEMPOTENCY_REQUIRED', 'Для изменения нужен Idempotency-Key', 422)
        try:
            uuid.UUID(key)
        except (ValueError, TypeError, AttributeError):
            raise Problem('INVALID_KEY', 'Idempotency-Key должен быть UUID', 422)
        signature = hashlib.sha256(encode(body).encode()).hexdigest()
        lookup = f'{user["username"]}:{route}:{key}'
        # Time transitions are committed separately, even if the action is stale.
        self.read(lambda s, now: None)
        with self.transaction() as s:
            previous = s['idempotency'].get(lookup)
            if previous:
                require(previous['hash'] == signature, 'IDEMPOTENCY_CONFLICT', 'Ключ уже использован для другого действия')
                return previous['response']
            require(body.get('expected_revision') == s['revision'], 'STALE_STATE',
                    'Данные изменились. Обновите экран и повторите действие.', current_revision=s['revision'])
            before = encode(s)
            result = function(s, self.clock())
            if encode(s) != before:
                s['revision'] += 1
                s['audit'].append({'at': stamp(self.clock()), 'actor': user['username'], 'action': route,
                                   'revision': s['revision']})
            response = {'data': result, 'meta': {'state_revision': s['revision'], 'server_time': stamp(self.clock())}}
            s['idempotency'][lookup] = {'hash': signature, 'response': deepcopy(response), 'at': stamp(self.clock())}
            # Retain retry results for at least 24 hours, bounded by age rather than count.
            cutoff = self.clock() - timedelta(days=2)
            s['idempotency'] = {k: v for k, v in s['idempotency'].items() if instant(v['at']) > cutoff}
            return response
