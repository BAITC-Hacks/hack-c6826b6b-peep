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
        self.migrate_admin()

    def migrate_admin(self):
        # Rebuild only the constrained account table; keep usernames and all FK children.
        db = sqlite3.connect(self.path, timeout=10)
        try:
            db.execute('PRAGMA foreign_keys=OFF')
            db.execute('BEGIN IMMEDIATE')
            db.execute('CREATE TABLE IF NOT EXISTS employee_identities(employee_id TEXT PRIMARY KEY)')
            db.execute('INSERT OR IGNORE INTO employee_identities SELECT employee_id FROM employee_records')
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='quest_state'").fetchone():
                saved=db.execute('SELECT payload FROM quest_state WHERE id=1').fetchone()
                if saved:
                    for eid in json.loads(saved[0])['employees']:
                        db.execute('INSERT OR IGNORE INTO employee_identities VALUES (?)',(eid,))
            sql = db.execute("SELECT sql FROM sqlite_master WHERE name='accounts'").fetchone()[0]
            if 'super_admin' not in sql or 'employee_identities' not in sql:
                modern='super_admin' in sql
                db.execute('''CREATE TABLE accounts_admin (
                    username TEXT PRIMARY KEY, password_hash TEXT NOT NULL, salt TEXT NOT NULL,
                    role TEXT NOT NULL CHECK(role IN ('employee','hr','admin','super_admin')),
                    employee_id TEXT, display_name TEXT NOT NULL,
                    active INTEGER NOT NULL DEFAULT 1, must_change_password INTEGER NOT NULL DEFAULT 0,
                    entity_version INTEGER NOT NULL DEFAULT 1,
                    FOREIGN KEY(employee_id) REFERENCES employee_identities(employee_id))''')
                columns='username,password_hash,salt,role,employee_id,display_name'+(',active,must_change_password,entity_version' if modern else '')
                db.execute(f'INSERT INTO accounts_admin({columns}) SELECT {columns} FROM accounts')
                db.execute('DROP TABLE accounts')
                db.execute('ALTER TABLE accounts_admin RENAME TO accounts')
            if db.execute('PRAGMA foreign_key_check').fetchall():
                raise ValueError('Account migration foreign key check failed')
            db.commit()
            db.executescript((Path(__file__).parent/'migrations/003_admin_control.sql').read_text(encoding='utf-8'))
            db.execute('INSERT OR IGNORE INTO schema_migrations VALUES(4,CURRENT_TIMESTAMP)')
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

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
            db.execute('INSERT OR IGNORE INTO employee_identities VALUES (?)',(employee['employee_id'],))
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
            accounts = [('hr.demo', 'DEMO_HR_PASSWORD', 'hr', None, 'HR-команда'),
                        ('admin.demo', 'DEMO_ADMIN_PASSWORD', 'admin', None, 'Администратор'),
                        ('superadmin.demo', 'DEMO_SUPERADMIN_PASSWORD', 'super_admin', None, 'Системный администратор')]
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
                db.execute('INSERT INTO accounts(username,password_hash,salt,role,employee_id,display_name) VALUES (?,?,?,?,?,?)',
                           (username, password_hash(password, salt), salt, role, employee_id, display_name))

    def public_user(self, row, db=None):
        if db is None:
            with self.connection() as db:
                return self.public_user(row, db)
        from .permissions import capabilities
        grants = [r[0] for r in db.execute('SELECT permission FROM permission_grants WHERE username=?', (row['username'],))]
        return {key: row[key] for key in ('username', 'role', 'employee_id', 'display_name')} | {
            'capabilities': capabilities(row['role'], grants), 'must_change_password': bool(row['must_change_password'])}

    def login(self, username, password):
        with self.connection() as db:
            row = db.execute('SELECT * FROM accounts WHERE username=?', (username,)).fetchone()
        # Same slow hash path for unknown usernames; avoid a cheap username timing oracle.
        candidate = password_hash(password, row['salt'] if row else 'unknown-account')
        if row is None or not row['active'] or not hmac.compare_digest(candidate, row['password_hash']):
            return None
        token = secrets.token_urlsafe(32)
        expires = int(time.time()) + 8 * 60 * 60
        with self.connection(write=True) as db:
            fresh = db.execute('SELECT * FROM accounts WHERE username=?', (username,)).fetchone()
            if not fresh or not fresh['active'] or fresh['password_hash'] != row['password_hash']:
                return None
            state = db.execute('SELECT payload FROM quest_state WHERE id=1').fetchone() if db.execute("SELECT 1 FROM sqlite_master WHERE name='quest_state'").fetchone() else None
            hours = json.loads(state[0]).get('policies', {}).get('settings', {}).get('session_hours', 8) if state else 8
            expires = int(time.time()) + hours * 3600
            db.execute('DELETE FROM sessions WHERE expires_at<=?', (int(time.time()),))
            db.execute('INSERT INTO sessions VALUES (?,?,?)',
                       (hashlib.sha256(token.encode()).hexdigest(), username, expires))
        return dict(token=token, user=self.public_user(row), expires_at=expires)

    def session(self, token):
        if not token or len(token) > 256:
            return None
        with self.connection() as db:
            row = db.execute('''SELECT accounts.* FROM sessions JOIN accounts USING(username)
                                WHERE token_hash=? AND expires_at>? AND accounts.active=1''',
                             (hashlib.sha256(token.encode()).hexdigest(), int(time.time()))).fetchone()
            return self.public_user(row, db) if row else None

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
