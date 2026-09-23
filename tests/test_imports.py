"""Upload is explicitly excluded from this release, including old stage-2 URLs."""
import pytest
from conftest import authorization

@pytest.mark.parametrize('path',['/api/hr/import/preview','/api/hr/import/commit','/api/hr/import/upload','/api/dataset/summary'])
def test_upload_api_removed(client,path):
    assert client.post(path,headers=authorization(client,'hr'),json={}).status_code==404
