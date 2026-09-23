"""Full-release authorization and persistence contracts, independent of the UI."""
import json
from fastapi.testclient import TestClient
import pytest
from backend.main import create_app
from conftest import authorization, login, mutate


def test_login_and_revocation(client):
    session=login(client)
    assert session['expires_at'] and len(session['token'])>30
    h={'Authorization':'Bearer '+session['token']}
    assert client.get('/api/auth/me',headers=h).json()['role']=='employee'
    assert client.post('/api/auth/logout',headers=h).status_code==200
    assert client.get('/api/me/profile',headers=h).status_code==401

@pytest.mark.parametrize('path',['/api/me/profile','/api/me/history','/api/hr/employees','/api/me/wallet','/api/meta'])
def test_requires_real_session(client,path):
    for headers in ({},{'Authorization':'Bearer hr.demo'}):
        assert client.get(path,headers=headers).status_code==401

@pytest.mark.parametrize('username,password',[('employee.demo','wrong'),('unknown','Employee123!'),('hr.demo','Employee123!')])
def test_bad_login_generic(client,username,password):
    r=client.post('/api/auth/login',json=dict(username=username,password=password))
    assert r.status_code==401
    assert password not in r.text
    assert r.json()['error']['code']=='UNAUTHORIZED'

@pytest.mark.parametrize('role,eid,other',[('employee','E1','E2'),('colleague','E2','E1')])
def test_profile_and_history_are_private(client,role,eid,other):
    h=authorization(client,role)
    p=client.get('/api/me/profile',headers=h).json()['data']
    assert p['employee']['employee_id']==eid
    assert client.get('/api/employees/'+other,headers=h).status_code==404
    history=client.get('/api/me/history',headers=h).json()['data']['items']
    assert all(src['employee_id']==eid for row in history for src in row['sources'])
    assert client.get('/api/hr/employees/'+other,headers=h).status_code==403

@pytest.mark.parametrize('path',['/api/hr/overview','/api/hr/employees','/api/hr/seasons','/api/hr/reward-reviews','/api/hr/reward-orders','/api/hr/shop/items','/api/hr/reports/skill-gaps.csv'])
def test_all_hr_reads_forbidden_to_employee(client,path):
    assert client.get(path,headers=authorization(client)).status_code==403


def test_all_hr_writes_forbidden_to_employee(client):
    h=authorization(client)
    # Even incomplete bodies must not bypass role validation.
    for method,path in [('POST','/api/hr/seasons'),('PATCH','/api/hr/seasons/x'),('POST','/api/hr/seasons/x/publish'),('POST','/api/hr/reward-reviews/x/decision'),('POST','/api/hr/reward-orders/x/transition'),('POST','/api/hr/shop/items'),('PATCH','/api/hr/shop/items/x')]:
        assert client.request(method,path,headers=h,json={}).status_code==403,(method,path)


def test_hr_directory_and_own_employee_routes(client):
    h=authorization(client,'hr')
    result=client.get('/api/hr/employees',headers=h).json()['data']
    assert result['total']==2
    assert client.get('/api/hr/employees/E2',headers=h).status_code==200
    assert client.get('/api/me/profile',headers=h).status_code==403


def test_goal_suggestion_override_reset_and_source_preservation(client):
    h=authorization(client)
    g=client.get('/api/me/goal',headers=h).json()['data']
    assert g['goal'] is None and g['goal_source']=='suggested'
    assert g['suggested_goal']['target_grade']=='Middle'
    assert mutate(client,h,'PUT','/api/me/goal',dict(role_id='Engineer',grade_id='Senior')).status_code==200
    assert client.get('/api/me/profile',headers=h).json()['data']['employee']['source_goal'] is None
    assert mutate(client,h,'DELETE','/api/me/goal').status_code==200
    assert client.get('/api/me/goal',headers=h).json()['data']['goal'] is None
    h=authorization(client,'colleague')
    assert mutate(client,h,'PUT','/api/me/goal',dict(role_id='Engineer',grade_id='Middle')).status_code==200
    assert mutate(client,h,'DELETE','/api/me/goal').status_code==200
    assert client.get('/api/me/goal',headers=h).json()['data']['goal']['target_grade']=='Senior'


def test_goal_and_source_survive_restart(kit):
    originals={f.name:f.read_bytes() for f in kit[0].iterdir()}
    with TestClient(create_app(*kit)) as c:
        h=authorization(c)
        assert mutate(c,h,'PUT','/api/me/goal',dict(role_id='Engineer',grade_id='Senior')).status_code==200
    with TestClient(create_app(*kit)) as c:
        assert c.get('/api/me/goal',headers=authorization(c)).json()['data']['goal']['target_grade']=='Senior'
    assert originals=={f.name:f.read_bytes() for f in kit[0].iterdir()}
