import asyncio
import json
from copy import deepcopy
import httpx
from backend.assistant import (
    CareerAssistant,
    OpenAIProvider,
    context_for,
    plan_context_for,
    verified,
    verified_plan,
)
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

    with e.transaction() as s:
        plan_context=plan_context_for(s,'E1',e.clock(),'balanced')
        encoded=json.dumps(plan_context)
        assert 'E1' not in encoded and 'Synthetic Person' not in encoded
        assert len(plan_context['candidates'])<=16
    r=c.post('/api/me/assistant/plan',headers=authorization(c),json={'focus':'balanced'})
    assert r.status_code==200
    result=r.json()['data']
    assert result['mode']=='template' and len(result['items'])<=3
    assert result['total_minutes']<=result['budget_remaining_minutes']


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


def test_provider_can_compose_only_a_verified_catalog_plan(scenario,monkeypatch):
    _,e,_=scenario
    with e.transaction() as s:
        context=plan_context_for(s,'E1',e.clock(),'balanced')
    monkeypatch.setenv('AI_MODE','llm')
    monkeypatch.setenv('OPENAI_API_KEY','local-test-key')
    chosen=context['candidates'][0]
    draft={
        'headline':'Маршрут готов к проверке',
        'summary':'Выбран совместимый шаг с полезным вкладом в цель.',
        'activity_ids':[chosen['id']],
        'rationale': [{
            'activity_id':chosen['id'],
            'reason':'Шаг связан с дефицитом и укладывается в доступный ритм.',
            'focus_skills':chosen['focus_skills'][:1],
        }],
    }
    assert verified_plan(draft,context)

    def respond(request):
        body=json.loads(request.content)
        assert body['text']['format']['name']=='career_plan_draft'
        return httpx.Response(200,json={'output':[{'type':'message','content':[{
            'type':'output_text','text':json.dumps(draft,ensure_ascii=False),
        }]}]})

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            result=await CareerAssistant(OpenAIProvider(client)).compose_plan(context,'E1',8)
            assert result['mode']=='llm'
            assert result['items'][0]['id']==chosen['id']
    asyncio.run(run())

    invalid={**draft,'activity_ids':['invented']}
    assert not verified_plan(invalid,context)
