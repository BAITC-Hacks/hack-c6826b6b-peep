"""Authorization is enforced by HTTP endpoints, independently of Flutter UI."""
import json

from fastapi.testclient import TestClient
import pytest

from backend.main import create_app
from conftest import authorization, employee, login, preview


def test_login_auth_me_and_logout_revokes_token(client):
    session = login(client)
    assert session['token']
    assert session['expires_at']
    assert session['user']['role'] == 'employee'
    headers = {'Authorization': f"Bearer {session['token']}"}
    assert client.get('/api/auth/me', headers=headers).status_code == 200
    assert client.post('/api/auth/logout', headers=headers).status_code in (200, 204)
    assert client.get('/api/auth/me', headers=headers).status_code == 401
    assert client.get('/api/me/profile', headers=headers).status_code == 401


@pytest.mark.parametrize('username,password', [
    ('employee.demo', 'wrong'), ('not-an-account', 'Employee123!'), ('hr.demo', 'Employee123!'),
])
def test_invalid_credentials_are_rejected(client, username, password):
    response = client.post('/api/auth/login', json={'username': username, 'password': password})
    assert response.status_code == 401
    assert password not in response.text


@pytest.mark.parametrize('path', ['/api/auth/me', '/api/me/profile', '/api/employees/E1', '/api/employees/E1/history', '/api/hr/employees', '/api/meta'])
def test_unauthenticated_and_forged_tokens_are_rejected(client, path):
    assert client.get(path).status_code == 401
    assert client.get(path, headers={'Authorization': 'Bearer hr.demo'}).status_code == 401


def test_employee_sees_only_own_profile_and_history(client):
    headers = authorization(client)
    response = client.get('/api/me/profile', headers=headers)
    assert response.status_code == 200
    profile = response.json()
    assert profile['employee']['employee_id'] == 'E1'
    assert len(profile['history']) == 1
    assert 'R1' in json.dumps(profile['history'])
    assert 'R2' not in json.dumps(profile['history'])
    assert 'Synthetic Person E2' not in response.text
    assert profile['calculation']['status'] == 'not_calculated'
    assert profile['employee']['skills'] == {'S1': 1}
    assert client.get('/api/employees/E1', headers=headers).status_code == 200
    assert client.get('/api/employees/E2', headers=headers).status_code == 403
    assert client.get('/api/employees/DOES_NOT_EXIST', headers=headers).status_code == 403
    own_history = client.get('/api/employees/E1/history', headers=headers)
    assert own_history.status_code == 200
    assert own_history.json()['history'] == profile['history']
    assert client.get('/api/employees/E2/history', headers=headers).status_code == 403
    assert client.get('/api/employees/DOES_NOT_EXIST/history', headers=headers).status_code == 403


def test_second_employee_is_bound_to_distinct_profile(client):
    headers = authorization(client, 'colleague')
    profile = client.get('/api/me/profile', headers=headers).json()
    assert profile['employee']['employee_id'] == 'E2'
    assert profile['goal'] == {'target_role': 'Engineer', 'target_grade': 'Senior'}
    assert 'R2' in json.dumps(profile['history'])
    assert 'R1' not in json.dumps(profile['history'])
    assert client.get('/api/employees/E1', headers=headers).status_code == 403


def test_hr_has_employee_directory_and_can_open_profile(client):
    headers = authorization(client, 'hr')
    directory = client.get('/api/hr/employees', headers=headers)
    assert directory.status_code == 200
    assert directory.json()['total'] == 2
    assert {item['employee_id'] for item in directory.json()['employees']} == {'E1', 'E2'}
    filtered = client.get('/api/hr/employees', params={'q': 'Person E2'}, headers=headers)
    assert filtered.status_code == 200
    assert [item['employee_id'] for item in filtered.json()['employees']] == ['E2']
    assert client.get('/api/employees/E2', headers=headers).status_code == 200
    assert client.get('/api/employees/DOES_NOT_EXIST', headers=headers).status_code == 404
    assert client.get('/api/me/profile', headers=headers).status_code == 403


def test_employee_cannot_use_hr_endpoints_or_import(client):
    headers = authorization(client)
    assert client.get('/api/hr/employees', headers=headers).status_code == 403
    assert preview(client, headers, employees=[employee()]).status_code == 403
    assert client.post('/api/hr/import/commit', headers=headers,
                       json={'preview_id': 'arbitrary'}).status_code == 403


def test_next_grade_is_a_suggestion_until_explicitly_selected(client):
    headers = authorization(client)
    profile = client.get('/api/me/profile', headers=headers).json()
    assert profile['employee']['career_goal'] is None
    assert profile['goal'] is None
    assert profile['suggested_goal'] == {'target_role': 'Engineer', 'target_grade': 'Middle'}
    assert profile['goal_source'] == 'suggested'
    response = client.put('/api/me/goal', headers=headers,
                          json={'target_role': 'Engineer', 'target_grade': 'Senior'})
    assert response.status_code == 200
    updated = client.get('/api/me/profile', headers=headers).json()
    assert updated['goal'] == {'target_role': 'Engineer', 'target_grade': 'Senior'}
    assert updated['goal_source'] == 'personal'
    assert updated['employee']['career_goal'] is None
    assert client.delete('/api/me/goal', headers=headers).status_code in (200, 204)
    reset = client.get('/api/me/profile', headers=headers).json()
    assert reset['goal'] is None
    assert reset['suggested_goal'] == profile['suggested_goal']


def test_reset_restores_source_goal_instead_of_erasing_source(client):
    headers = authorization(client, 'colleague')
    goal = {'target_role': 'Engineer', 'target_grade': 'Middle'}
    assert client.put('/api/me/goal', headers=headers, json=goal).status_code == 200
    profile = client.get('/api/me/profile', headers=headers).json()
    assert profile['goal'] == goal
    assert profile['employee']['career_goal']['target_grade'] == 'Senior'
    assert client.delete('/api/me/goal', headers=headers).status_code in (200, 204)
    reset = client.get('/api/me/profile', headers=headers).json()
    assert reset['goal']['target_grade'] == 'Senior'
    assert reset['goal_source'] == 'dataset'


@pytest.mark.parametrize('goal', [
    {'target_role': 'Unknown', 'target_grade': 'Senior'},
    {'target_role': 'Manager', 'target_grade': 'Middle'},
    {'target_role': 'Engineer', 'target_grade': 'Invalid'},
])
def test_invalid_goals_leave_profile_unchanged(client, goal):
    headers = authorization(client)
    before = client.get('/api/me/profile', headers=headers).json()
    assert client.put('/api/me/goal', headers=headers, json=goal).status_code == 422
    assert client.get('/api/me/profile', headers=headers).json() == before


def test_personal_goal_persists_restart_without_rewriting_source(kit):
    source, _, _ = kit
    before_files = {file.name: file.read_bytes() for file in source.iterdir()}
    goal = {'target_role': 'Engineer', 'target_grade': 'Senior'}
    with TestClient(create_app(*kit)) as client:
        assert client.put('/api/me/goal', headers=authorization(client), json=goal).status_code == 200
    with TestClient(create_app(*kit)) as client:
        profile = client.get('/api/me/profile', headers=authorization(client)).json()
        assert profile['goal'] == goal
        assert profile['employee']['career_goal'] is None
    assert {file.name: file.read_bytes() for file in source.iterdir()} == before_files
