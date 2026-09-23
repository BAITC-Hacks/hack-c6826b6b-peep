import asyncio
import json
from copy import deepcopy
import httpx
from backend.assistant import CareerAssistant,OpenAIProvider,context_for,verified
from conftest import authorization


def test_context_is_anonymous_and_endpoint_falls_back(scenario):
    c,e,_=scenario
    with e.transaction() as s:
        context=context_for(s,'E1',e.clock(),'why')
        encoded=json.dumps(context)
        assert 'E1' not in encoded and 'Synthetic Person' not in encoded
        assert not set(context)&{'salary','department','employee_id','full_name','notes'}
    r=c.post('/api/me/assistant/explain',headers=authorization(c),json={'question':'why'})
    assert r.status_code==200 and r.json()['data']['mode']=='template'


def test_provider_request_contract_verification_cache_and_fallback(scenario,monkeypatch):
    _,e,_=scenario
    with e.transaction() as s:context=context_for(s,'E1',e.clock(),'why')
    monkeypatch.setenv('AI_MODE','llm');monkeypatch.setenv('OPENAI_API_KEY','local-test-key')
    calls=[]
    def respond(request):
        calls.append(request)
        body=json.loads(request.content)
        assert body['store'] is False and body['text']['format']['type']=='json_schema'
        assert request.headers['Authorization']=='Bearer local-test-key'
        return httpx.Response(200,json={'output':[{'type':'message','content':[{'type':'output_text','text':json.dumps({'summary':'Практика помогает закрыть дефицит навыка.','activity_ids':['sql'],'claims':[]})}]}]})
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            ai=CareerAssistant(OpenAIProvider(client))
            result=await ai.explain(context,'E1',3)
            assert result['mode']=='llm'
            assert result==await ai.explain(context,'E1',3)
            assert len(calls)==1
        class Broken:
            async def explain(self,context):raise RuntimeError('secret exception')
        result=await CareerAssistant(Broken()).explain(context,'E1',4)
        assert result['mode']=='template' and 'secret' not in result['text']
    asyncio.run(run())
    base={'summary':'Объяснение шага.','activity_ids':['sql'],'claims':[]}
    assert verified(base,context)
    for bad in [dict(activity_ids=['invented']),dict(summary='Гарантирую рост на 99%'),dict(claims=[{'metric_key':'estimated_readiness','value':float('nan')}]),dict(claims=[{'metric_key':'estimated_readiness','value':100}])]:
        assert not verified({**base,**bad},context)
