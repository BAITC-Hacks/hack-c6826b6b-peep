"""A small synthetic kit: tests never need the private hackathon dataset."""
import csv
import io
import json

from fastapi.testclient import TestClient
import pytest

from backend.main import create_app


HISTORY_FIELDS = [
    'record_id', 'employee_id', 'event_id', 'date', 'due_date', 'status',
    'completion_pct', 'score', 'feedback_rating', 'assigned_by',
]


def employee(employee_id='E3', **changes):
    result = dict(
        employee_id=employee_id, full_name=f'Synthetic Person {employee_id}',
        department='Engineering', role='Engineer', grade='Junior',
        manager_id=None, hire_date='2025-01-01', tenure_months=21,
        work_format='remote', preferred_language='ru', career_goal=None,
        skills={'S1': 1}, last_review_date='2026-09-01',
    )
    result.update(changes)
    return result


def activity(record_id='R3', employee_id='E3', **changes):
    result = dict(
        record_id=record_id, employee_id=employee_id, event_id='EV1',
        date='2026-09-10', due_date='2026-09-20', status='completed',
        completion_pct=100, score=80, feedback_rating=4, assigned_by='self',
    )
    result.update(changes)
    return result


def history_csv(rows):
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, fieldnames=HISTORY_FIELDS)
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode('utf-8')


def write_dataset(path):
    path.mkdir()
    meta = {'as_of_date': '2026-10-01'}
    source_employees = [
        employee('E1'),
        employee('E2', grade='Middle', skills={'S1': 2},
                 career_goal={'target_role': 'Engineer', 'target_grade': 'Senior'}),
    ]
    event = dict(
        event_id='EV1', title='Synthetic Learning', description='Synthetic event',
        type='course', format='online', duration_hours=2, mandatory=True,
        target_roles=['Engineer'], target_grades=['Junior', 'Middle', 'Senior'],
        develops_skills=[{'skill_id': 'S1', 'gain': 1, 'max_level': 4}],
        prerequisites={}, upcoming_sessions=['2026-10-05'],
    )
    documents = {
        'employees': {'meta': meta, 'employees': source_employees},
        'events': {'meta': meta, 'events': [event]},
        'skills': {
            'meta': meta,
            'skills': [dict(skill_id='S1', name='Synthetic Skill', type='hard',
                            category='engineering', description='Test skill')],
            'role_profiles': [dict(role='Engineer', grade=grade,
                                   required_skills={'S1': level}, critical_skills=['S1'])
                              for grade, level in [('Junior', 1), ('Middle', 2), ('Senior', 4), ('Lead', 5)]],
        },
    }
    for name, content in documents.items():
        (path / f'{name}.json').write_text(json.dumps(content), encoding='utf-8')
    (path / 'activity_history.csv').write_bytes(history_csv([
        activity('R1', 'E1'),
        activity('R2', 'E2', status='in_progress', completion_pct=40,
                 score=None, feedback_rating=None),
    ]))


@pytest.fixture
def kit(tmp_path):
    source = tmp_path / 'source'
    write_dataset(source)
    return source, tmp_path / 'state.sqlite3', tmp_path / 'no_web'


@pytest.fixture
def client(kit):
    with TestClient(create_app(*kit)) as result:
        yield result


def login(client, username='employee.demo', password='Employee123!'):
    response = client.post('/api/auth/login', json={'username': username, 'password': password})
    assert response.status_code == 200, response.text
    return response.json()


def authorization(client, role='employee'):
    credentials = {
        'employee': ('employee.demo', 'Employee123!'),
        'colleague': ('colleague.demo', 'Colleague123!'),
        'hr': ('hr.demo', 'Hr123!'),
    }
    session = login(client, *credentials[role])
    return {'Authorization': f"Bearer {session['token']}"}


def preview(client, headers, employees=None, history=None, policy='reject', wrapper=True):
    files = {}
    if employees is not None:
        payload = {'meta': {'as_of_date': '2026-10-01'}, 'employees': employees} if wrapper else employees
        files['employees_file'] = ('employees.json', json.dumps(payload).encode('utf-8'), 'application/json')
    if history is not None:
        files['history_file'] = ('activity_history.csv', history_csv(history), 'text/csv')
    return client.post('/api/hr/import/preview', headers=headers, files=files,
                       data={'conflict_policy': policy})


def commit(client, headers, preview_response):
    assert preview_response.status_code == 200, preview_response.text
    response = client.post('/api/hr/import/commit', headers=headers,
                           json={'preview_id': preview_response.json()['preview_id']})
    assert response.status_code == 201, response.text
    assert response.json()['committed'] is True
    return response
