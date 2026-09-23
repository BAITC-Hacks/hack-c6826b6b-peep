"""Foundation behavior retained after removing the technical snapshot endpoint."""
import json

from fastapi.testclient import TestClient

from backend.main import create_app
from conftest import authorization, write_dataset


def test_public_health_does_not_expose_dataset_or_profiles(client):
    response = client.get('/api/health')
    assert response.status_code == 200
    assert response.json()['status'] == 'ok'
    assert 'Synthetic Person' not in response.text
    assert not {'employees', 'activities', 'files', 'revision'} & response.json().keys()
    assert client.get('/api/dataset/summary').status_code == 404
    assert client.get('/api/employees').status_code == 404


def test_missing_dataset_keeps_health_available(tmp_path):
    with TestClient(create_app(tmp_path / 'missing', tmp_path / 'state.sqlite3', tmp_path / 'no_web')) as client:
        assert client.get('/api/health').status_code == 200
        assert client.get('/api/dataset/summary').status_code == 404


def test_invalid_reference_rejects_initial_dataset(tmp_path):
    source = tmp_path / 'source'
    write_dataset(source)
    source_file = source / 'employees.json'
    data = json.loads(source_file.read_text())
    data['employees'][0]['skills']['unknown'] = 2
    source_file.write_text(json.dumps(data))
    with TestClient(create_app(source, tmp_path / 'state.sqlite3', tmp_path / 'no_web')) as client:
        assert client.get('/api/health').status_code == 200
        response = client.post('/api/auth/login', json={'username': 'employee.demo', 'password': 'Employee123!'})
        assert response.status_code == 401
        assert client.get('/api/health').json()['dataset_ready'] is False


def test_authenticated_metadata_available_without_public_snapshot(client):
    assert client.get('/api/meta').status_code == 401
    response = client.get('/api/meta', headers=authorization(client))
    assert response.status_code == 200
    assert 'Synthetic Person' not in response.text
