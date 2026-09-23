"""Judge-file imports are validated as one atomic, replay-safe change."""
import json

from fastapi.testclient import TestClient
import pytest

from backend.main import create_app
from conftest import activity, authorization, commit, employee, history_csv, preview


def directory(client, headers):
    response = client.get('/api/hr/employees', headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize('wrapper', [True, False])
def test_new_employee_and_history_preview_then_commit(client, wrapper):
    headers = authorization(client, 'hr')
    response = preview(client, headers, employees=[employee()], history=[activity()], wrapper=wrapper)
    assert response.status_code == 200, response.text
    result = response.json()
    assert result['preview_id'] and result['expires_at']
    assert result['summary']['employees']['added'] == 1
    assert result['summary']['activities']['added'] == 1
    assert directory(client, headers)['total'] == 2
    assert client.get('/api/employees/E3', headers=headers).status_code == 404
    commit(client, headers, response)
    assert directory(client, headers)['total'] == 3
    profile = client.get('/api/employees/E3', headers=headers).json()
    assert profile['employee'] == employee()
    assert len(profile['history']) == 1
    assert 'R3' in json.dumps(profile['history'])


def test_import_persists_restart_without_rewriting_source_files(kit):
    source, _, _ = kit
    source_bytes = {file.name: file.read_bytes() for file in source.iterdir()}
    with TestClient(create_app(*kit)) as client:
        headers = authorization(client, 'hr')
        commit(client, headers, preview(client, headers, employees=[employee()], history=[activity()]))
    with TestClient(create_app(*kit)) as client:
        headers = authorization(client, 'hr')
        assert directory(client, headers)['total'] == 3
        profile = client.get('/api/employees/E3', headers=headers).json()
        assert profile['employee']['employee_id'] == 'E3'
        assert len(profile['history']) == 1
    assert {file.name: file.read_bytes() for file in source.iterdir()} == source_bytes


def test_identical_repeat_is_idempotent(client):
    headers = authorization(client, 'hr')
    commit(client, headers, preview(client, headers, employees=[employee()], history=[activity()]))
    repeated = preview(client, headers, employees=[employee()], history=[activity()])
    assert repeated.status_code == 200, repeated.text
    for kind in ('employees', 'activities'):
        assert repeated.json()['summary'][kind] == {'added': 0, 'updated': 0, 'unchanged': 1}
    commit(client, headers, repeated)
    assert directory(client, headers)['total'] == 3
    assert len(client.get('/api/employees/E3', headers=headers).json()['history']) == 1


def test_conflicts_reject_by_default_and_replace_only_when_requested(client):
    headers = authorization(client, 'hr')
    changed = employee('E1', full_name='Updated Synthetic Name')
    changed_history = activity('R1', 'E1', score=90)
    before = client.get('/api/employees/E1', headers=headers).json()
    conflict = preview(client, headers, employees=[changed], history=[changed_history])
    assert conflict.status_code == 409, conflict.text
    assert client.get('/api/employees/E1', headers=headers).json() == before
    replacement = preview(client, headers, employees=[changed], history=[changed_history], policy='replace')
    assert replacement.status_code == 200, replacement.text
    assert replacement.json()['summary']['employees']['updated'] == 1
    assert replacement.json()['summary']['activities']['updated'] == 1
    commit(client, headers, replacement)
    profile = client.get('/api/employees/E1', headers=headers).json()
    assert profile['employee'] == changed
    assert len(profile['history']) == 1
    assert profile['history'][0]['score'] == 90


@pytest.mark.parametrize('broken_employee,broken_activity', [
    (employee(manager_id='UNKNOWN'), activity()),
    (employee(skills={'UNKNOWN': 3}), activity()),
    (employee(role='Unknown role'), activity()),
    (employee(career_goal={'target_role': 'Unknown role', 'target_grade': 'Senior'}), activity()),
    (employee(), activity(event_id='UNKNOWN')),
    (employee(), activity(employee_id='UNKNOWN')),
])
def test_invalid_reference_rejects_entire_batch_without_partial_write(client, broken_employee, broken_activity):
    headers = authorization(client, 'hr')
    before = directory(client, headers)
    response = preview(client, headers, employees=[employee('E4'), broken_employee],
                       history=[activity('R4', 'E4'), broken_activity])
    assert response.status_code == 422, response.text
    assert directory(client, headers) == before
    assert client.get('/api/employees/E3', headers=headers).status_code == 404
    assert client.get('/api/employees/E4', headers=headers).status_code == 404


def test_manager_reference_can_point_to_employee_in_same_batch(client):
    headers = authorization(client, 'hr')
    response = preview(client, headers, employees=[employee('E3', manager_id='E4'), employee('E4', grade='Lead')])
    commit(client, headers, response)
    assert client.get('/api/employees/E3', headers=headers).json()['employee']['manager_id'] == 'E4'


def test_stale_preview_does_not_overwrite_a_newer_commit(client):
    headers = authorization(client, 'hr')
    old = preview(client, headers, employees=[employee('E3')])
    new = preview(client, headers, employees=[employee('E4')])
    commit(client, headers, new)
    response = client.post('/api/hr/import/commit', headers=headers,
                           json={'preview_id': old.json()['preview_id']})
    assert response.status_code == 409, response.text
    assert client.get('/api/employees/E4', headers=headers).status_code == 200
    assert client.get('/api/employees/E3', headers=headers).status_code == 404


def test_committed_preview_cannot_be_replayed(client):
    headers = authorization(client, 'hr')
    response = preview(client, headers, employees=[employee()])
    commit(client, headers, response)
    replay = client.post('/api/hr/import/commit', headers=headers,
                         json={'preview_id': response.json()['preview_id']})
    assert replay.status_code == 409, replay.text
    assert directory(client, headers)['total'] == 3


@pytest.mark.parametrize('contents', [
    b'not,csv,schema\n1,2,3\n',
    history_csv([activity('R3', 'E1')]) + b'extra,broken,row\n',
    history_csv([activity('R3', 'E1', completion_pct=100, status='in_progress')]),
])
def test_malformed_csv_is_rejected_atomically(client, contents):
    headers = authorization(client, 'hr')
    before = client.get('/api/employees/E1', headers=headers).json()
    response = client.post('/api/hr/import/preview', headers=headers,
                           files={'history_file': ('history.csv', contents, 'text/csv')})
    assert response.status_code == 422, response.text
    assert client.get('/api/employees/E1', headers=headers).json() == before


@pytest.mark.parametrize('employees,history', [
    ([employee(), employee()], None),
    ([employee()], [activity(), activity()]),
])
def test_duplicate_ids_within_upload_are_rejected(client, employees, history):
    headers = authorization(client, 'hr')
    response = preview(client, headers, employees=employees, history=history)
    assert response.status_code == 422, response.text
    assert directory(client, headers)['total'] == 2


def test_history_only_import_and_optional_nulls(client):
    headers = authorization(client, 'hr')
    row = activity('R3', 'E1', status='in_progress', completion_pct=20,
                   score=None, feedback_rating=None, due_date=None)
    commit(client, headers, preview(client, headers, history=[row]))
    profile = client.get('/api/employees/E1', headers=headers).json()
    assert len(profile['history']) == 2
    imported = next(item for item in profile['history'] if item['record_id'] == 'R3')
    assert imported['score'] is None
    assert imported['due_date'] is None


def test_malformed_json_and_unknown_policy_are_rejected(client):
    headers = authorization(client, 'hr')
    malformed = client.post('/api/hr/import/preview', headers=headers,
                            files={'employees_file': ('employees.json', b'{broken', 'application/json')})
    assert malformed.status_code == 422
    assert preview(client, headers, employees=[employee()], policy='silently-overwrite').status_code == 422
    assert directory(client, headers)['total'] == 2


def test_no_files_or_empty_files_cannot_create_preview(client):
    headers = authorization(client, 'hr')
    assert client.post('/api/hr/import/preview', headers=headers).status_code == 422
    assert preview(client, headers, employees=[], history=[]).status_code == 422
    assert directory(client, headers)['total'] == 2


def test_replacement_is_validated_against_retained_history(client):
    headers = authorization(client, 'hr')
    before = client.get('/api/employees/E1', headers=headers).json()
    # Existing R1 is from September 10; replacing the profile must not orphan
    # that retained history even though the upload contains no history file.
    response = preview(client, headers,
                       employees=[employee('E1', hire_date='2026-09-15', last_review_date='2026-09-20')],
                       policy='replace')
    assert response.status_code == 422, response.text
    assert client.get('/api/employees/E1', headers=headers).json() == before


@pytest.mark.parametrize('invalid_employee', [
    employee('E5/sub'),
    employee(manager_id=''),
    employee(skills={'S1': True}),
])
def test_invalid_identifiers_and_boolean_skill_levels_reject_entire_import(client, invalid_employee):
    headers = authorization(client, 'hr')
    before = directory(client, headers)
    response = preview(client, headers, employees=[employee('E4'), invalid_employee])
    assert response.status_code == 422, response.text
    assert directory(client, headers) == before
    assert client.get('/api/employees/E4', headers=headers).status_code == 404
