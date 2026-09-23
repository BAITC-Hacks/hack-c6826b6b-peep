"""Transactional source records, personal goals and revocable demo sessions."""
from contextlib import contextmanager
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import time
from pathlib import Path

from .data import Dataset


def encode(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def password_hash(password, salt):
    return hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 260_000).hex()


class Database:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connection() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS dataset_context (
                    id INTEGER PRIMARY KEY CHECK(id=1), context_json TEXT NOT NULL,
                    revision TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS employee_records (
                    employee_id TEXT PRIMARY KEY, source_json TEXT NOT NULL,
                    initial_json TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS history_records (
                    record_id TEXT PRIMARY KEY, employee_id TEXT NOT NULL,
                    source_json TEXT NOT NULL, initial_json TEXT NOT NULL,
                    FOREIGN KEY(employee_id) REFERENCES employee_records(employee_id)
                );
                CREATE TABLE IF NOT EXISTS personal_goals (
                    employee_id TEXT PRIMARY KEY, goal_json TEXT NOT NULL,
                    FOREIGN KEY(employee_id) REFERENCES employee_records(employee_id)
                );
                CREATE TABLE IF NOT EXISTS accounts (
                    username TEXT PRIMARY KEY, password_hash TEXT NOT NULL,
                    salt TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('employee','hr')),
                    employee_id TEXT, display_name TEXT NOT NULL,
                    FOREIGN KEY(employee_id) REFERENCES employee_records(employee_id)
                );
                CREATE TABLE IF NOT EXISTS sessions (
                    token_hash TEXT PRIMARY KEY, username TEXT NOT NULL,
                    expires_at INTEGER NOT NULL,
                    FOREIGN KEY(username) REFERENCES accounts(username)
                );
                CREATE TABLE IF NOT EXISTS import_previews (
                    id TEXT PRIMARY KEY, username TEXT NOT NULL, revision TEXT NOT NULL,
                    payload_json TEXT NOT NULL, report_json TEXT NOT NULL,
                    expires_at INTEGER NOT NULL, consumed INTEGER NOT NULL DEFAULT 0
                );
            ''')

    @contextmanager
    def connection(self, write=False):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        try:
            db.execute('BEGIN IMMEDIATE' if write else 'BEGIN')
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    def has_dataset(self):
        with self.connection() as db:
            return db.execute('SELECT 1 FROM dataset_context WHERE id=1').fetchone() is not None

    def read_dataset(self, db=None):
        if db is None:
            with self.connection() as connection:
                return self.read_dataset(connection)
        context = db.execute('SELECT context_json FROM dataset_context WHERE id=1').fetchone()
        if context is None:
            return None
        raw = json.loads(context['context_json'])
        raw['employees'] = [json.loads(row['source_json']) for row in db.execute('SELECT source_json FROM employee_records ORDER BY employee_id')]
        raw['activity_history'] = [json.loads(row['source_json']) for row in db.execute('SELECT source_json FROM history_records ORDER BY record_id')]
        return Dataset(raw)

    def write_dataset(self, db, dataset):
        raw = dataset.raw
        context = {key: value for key, value in raw.items() if key not in ('employees', 'activity_history')}
        db.execute('INSERT INTO dataset_context VALUES (1,?,?) ON CONFLICT(id) DO UPDATE SET context_json=excluded.context_json,revision=excluded.revision',
                   (encode(context), dataset.revision))
        # initial_json is immutable; source_json is the most recently accepted source record.
        for employee in raw['employees']:
            payload = encode(employee)
            db.execute('INSERT INTO employee_records VALUES (?,?,?) ON CONFLICT(employee_id) DO UPDATE SET source_json=excluded.source_json',
                       (employee['employee_id'], payload, payload))
        for record in raw['activity_history']:
            payload = encode(record)
            db.execute('INSERT INTO history_records VALUES (?,?,?,?) ON CONFLICT(record_id) DO UPDATE SET employee_id=excluded.employee_id,source_json=excluded.source_json',
                       (record['record_id'], record['employee_id'], payload, payload))

    def seed(self, dataset):
        with self.connection(write=True) as db:
            if db.execute('SELECT 1 FROM dataset_context WHERE id=1').fetchone() is None:
                self.write_dataset(db, dataset)

    def ensure_accounts(self):
        with self.connection(write=True) as db:
            ids = [row[0] for row in db.execute('SELECT employee_id FROM employee_records ORDER BY employee_id LIMIT 2')]
            accounts = [('hr.demo', 'DEMO_HR_PASSWORD', 'hr', None, 'HR-команда')]
            if ids:
                accounts.append(('employee.demo', 'DEMO_EMPLOYEE_PASSWORD', 'employee', ids[0], 'Сотрудник'))
            if len(ids) > 1:
                accounts.append(('colleague.demo', 'DEMO_COLLEAGUE_PASSWORD', 'employee', ids[1], 'Коллега'))
            for username, setting, role, employee_id, display_name in accounts:
                if db.execute('SELECT 1 FROM accounts WHERE username=?', (username,)).fetchone():
                    continue
                password = os.getenv(setting) or secrets.token_urlsafe(15)
                if not os.getenv(setting):
                    print(f'New local account {username}: {password} (shown once; keep locally)', flush=True)
                salt = secrets.token_hex(16)
                db.execute('INSERT INTO accounts VALUES (?,?,?,?,?,?)',
                           (username, password_hash(password, salt), salt, role, employee_id, display_name))

    @staticmethod
    def public_user(row):
        return {key: row[key] for key in ('username', 'role', 'employee_id', 'display_name')}

    def login(self, username, password):
        with self.connection() as db:
            row = db.execute('SELECT * FROM accounts WHERE username=?', (username,)).fetchone()
        # Same slow hash path for unknown usernames; avoid a cheap username timing oracle.
        candidate = password_hash(password, row['salt'] if row else 'unknown-account')
        if row is None or not hmac.compare_digest(candidate, row['password_hash']):
            return None
        token = secrets.token_urlsafe(32)
        expires = int(time.time()) + 8 * 60 * 60
        with self.connection(write=True) as db:
            db.execute('DELETE FROM sessions WHERE expires_at<=?', (int(time.time()),))
            db.execute('INSERT INTO sessions VALUES (?,?,?)',
                       (hashlib.sha256(token.encode()).hexdigest(), username, expires))
        return dict(token=token, user=self.public_user(row), expires_at=expires)

    def session(self, token):
        if not token or len(token) > 256:
            return None
        with self.connection() as db:
            row = db.execute('''SELECT accounts.* FROM sessions JOIN accounts USING(username)
                                WHERE token_hash=? AND expires_at>?''',
                             (hashlib.sha256(token.encode()).hexdigest(), int(time.time()))).fetchone()
            return self.public_user(row) if row else None

    def logout(self, token):
        with self.connection(write=True) as db:
            db.execute('DELETE FROM sessions WHERE token_hash=?', (hashlib.sha256(token.encode()).hexdigest(),))

    def goal(self, employee_id, db=None):
        if db is None:
            with self.connection() as connection:
                return self.goal(employee_id, connection)
        row = db.execute('SELECT goal_json FROM personal_goals WHERE employee_id=?', (employee_id,)).fetchone()
        return json.loads(row[0]) if row else None

    def save_goal(self, employee_id, goal):
        with self.connection(write=True) as db:
            if goal is None:
                db.execute('DELETE FROM personal_goals WHERE employee_id=?', (employee_id,))
            else:
                db.execute('INSERT INTO personal_goals VALUES (?,?) ON CONFLICT(employee_id) DO UPDATE SET goal_json=excluded.goal_json',
                           (employee_id, encode(goal)))
