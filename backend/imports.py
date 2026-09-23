"""Validate an entire import before storing a preview; commit it in one SQLite transaction."""
import csv
import io
import json
import secrets
import time

from fastapi import HTTPException
from pydantic import ValidationError

from .data import Dataset
from .database import encode
from .models import Activity, Employee

MAX_BYTES = 5 * 1024 * 1024


def fail(message, status=422):
    raise HTTPException(status, message)


def validate_rows(model, rows, label, limit):
    if not isinstance(rows, list) or len(rows) > limit:
        fail(f'{label}: нужен массив, максимум {limit} записей')
    result = []
    id_field = 'employee_id' if model is Employee else 'record_id'
    seen = set()
    for index, row in enumerate(rows, 1):
        try:
            item = model.model_validate(row)
        except ValidationError as exc:
            locations = ', '.join('.'.join(str(p) for p in e['loc']) for e in exc.errors()[:4])
            fail(f'{label}, запись {index}: неверные или отсутствующие поля: {locations}')
        key = getattr(item, id_field)
        if not key.strip():
            fail(f'{label}, запись {index}: пустой {id_field}')
        if key in seen:
            fail(f'{label}: повтор {id_field} {key} внутри загружаемого файла')
        seen.add(key)
        result.append(item.model_dump(mode='json'))
    return result


def read_upload(upload):
    content = upload.file.read(MAX_BYTES + 1)
    if len(content) > MAX_BYTES:
        fail('Каждый файл должен быть не больше 5 МБ', 413)
    try:
        return content.decode('utf-8-sig')
    except UnicodeError:
        fail('Сохраните файл в UTF-8')


def parse_files(dataset, employees_file, history_file):
    if employees_file is None and history_file is None:
        fail('Выберите JSON с профилями и/или CSV с историей')
    employees, history = [], []
    if employees_file is not None:
        try:
            content = json.loads(read_upload(employees_file))
        except (ValueError, RecursionError):
            fail('Файл профилей содержит некорректный JSON')
        if isinstance(content, dict):
            meta = content.get('meta')
            if meta is not None and not isinstance(meta, dict):
                fail('Поле meta должно быть объектом')
            if meta and meta.get('as_of_date', dataset.as_of.isoformat()) != dataset.as_of.isoformat():
                fail('Дата набора в meta.as_of_date не совпадает с загруженным каталогом')
            content = content.get('employees')
        employees = validate_rows(Employee, content, 'Профили', 2000)
    if history_file is not None:
        text = read_upload(history_file)
        try:
            reader = csv.DictReader(io.StringIO(text), strict=True)
            fields = reader.fieldnames
            expected = set(Activity.model_fields)
            if fields is None or len(fields) != len(set(fields)) or set(fields) != expected:
                fail('CSV должен содержать ровно колонки исходной схемы: ' + ', '.join(Activity.model_fields))
            rows = []
            for index, row in enumerate(reader, 2):
                if None in row or any(value is None for value in row.values()):
                    fail(f'CSV, строка {index}: неверное число колонок')
                rows.append({k: (None if not v.strip() and k in ('due_date', 'score', 'feedback_rating') else v.strip())
                             for k, v in row.items()})
                if len(rows) > 20000:
                    fail('CSV: максимум 20000 записей за один импорт')
            history = validate_rows(Activity, rows, 'История', 20000)
        except csv.Error:
            fail('Некорректная структура CSV')
    if not employees and not history:
        fail('Выбранные файлы не содержат записей')
    return employees, history


def merge_dataset(dataset, employees, history, policy):
    raw = dict(dataset.raw)
    summary = {}
    conflicts = []
    for field, key, incoming, name in (
        ('employees', 'employee_id', employees, 'employees'),
        ('activity_history', 'record_id', history, 'activities'),
    ):
        existing = {row[key]: row for row in raw[field]}
        counts = dict(added=0, updated=0, unchanged=0)
        for row in incoming:
            old = existing.get(row[key])
            if old is None:
                counts['added'] += 1
            elif old == row:
                counts['unchanged'] += 1
            else:
                counts['updated'] += 1
                if policy == 'reject':
                    conflicts.append(f'{key}={row[key]}')
            existing[row[key]] = row
        raw[field] = list(existing.values())
        summary[name] = counts
    if conflicts:
        fail('Данные с этими ID отличаются: ' + ', '.join(conflicts[:8]) + '. Для замены выберите политику «Заменить».', 409)
    try:
        candidate = Dataset(raw)
    except (ValueError, KeyError, TypeError) as exc:
        fail(f'Импорт отменён: {exc}')
    return candidate, summary


def preview(database, username, employees_file, history_file, policy):
    if policy not in ('reject', 'replace'):
        fail('conflict_policy: допустимы reject или replace')
    dataset = database.read_dataset()
    if dataset is None:
        fail('Сначала подготовьте исходный каталог данных', 503)
    employees, history = parse_files(dataset, employees_file, history_file)
    candidate, summary = merge_dataset(dataset, employees, history, policy)
    warnings = []
    repeated = len(candidate.warnings) - len(dataset.warnings)
    if repeated > 0:
        warnings.append(f'Добавлены повторные завершения: {repeated}. Записи сохраняются, прирост навыков сейчас не рассчитывается.')
    preview_id = secrets.token_urlsafe(24)
    expires = int(time.time()) + 15 * 60
    result = dict(preview_id=preview_id, expires_at=expires, summary=summary, warnings=warnings)
    payload = dict(employees=employees, history=history, policy=policy)
    with database.connection(write=True) as db:
        db.execute('DELETE FROM import_previews WHERE expires_at<=?', (int(time.time()),))
        current = db.execute('SELECT revision FROM dataset_context WHERE id=1').fetchone()
        if current is None or current['revision'] != dataset.revision:
            fail('Данные изменились. Повторите проверку файлов.', 409)
        db.execute('INSERT INTO import_previews VALUES (?,?,?,?,?,?,0)',
                   (preview_id, username, dataset.revision, encode(payload), encode(result), expires))
    return result


def commit(database, username, preview_id):
    with database.connection(write=True) as db:
        row = db.execute('SELECT * FROM import_previews WHERE id=? AND username=?', (preview_id, username)).fetchone()
        if row is None:
            fail('Проверка импорта не найдена. Загрузите файлы заново.', 404)
        if row['consumed'] or row['expires_at'] <= time.time():
            fail('Проверка импорта уже использована или истекла. Загрузите файлы заново.', 409)
        dataset = database.read_dataset(db)
        if dataset is None or dataset.revision != row['revision']:
            fail('Данные изменились после проверки. Проверьте файлы заново.', 409)
        payload = json.loads(row['payload_json'])
        candidate, summary = merge_dataset(dataset, payload['employees'], payload['history'], payload['policy'])
        database.write_dataset(db, candidate)
        db.execute('UPDATE import_previews SET consumed=1 WHERE id=?', (preview_id,))
        result = json.loads(row['report_json'])
        result.update(committed=True, summary=summary)
        return result
