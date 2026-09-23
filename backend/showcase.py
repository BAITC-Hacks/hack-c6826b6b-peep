"""Create a separate showcase through normal domain rules; never alter the working DB.

python -m backend.showcase --db data/local/showcase.sqlite3
"""
import argparse
from copy import deepcopy
from datetime import datetime,time,timedelta
from pathlib import Path
import os

from .config import load_env
from .database import Database
from .data import Dataset
from .engine import Engine,utcnow,stamp,instant
from .game_rules import ZONE,game_date
from . import game,career

ROOT=Path(__file__).resolve().parent.parent


def build(path,source=None,now=None):
    load_env(ROOT/'.env')
    path=Path(path).resolve()
    working=Path(os.getenv('CAREER_DB',ROOT/'data/local/career.sqlite3')).resolve()
    if path==working or path.exists():
        raise ValueError('Choose a new, separate SQLite path; existing databases are never overwritten.')
    now=now or utcnow()
    today=datetime.combine(game_date(now),time.min,ZONE)
    current_start=today-timedelta(days=66)
    past_start=current_start-timedelta(days=104)
    db=Database(path);db.seed(Dataset.from_directory(source or ROOT/'data/sample'));db.ensure_accounts()
    clock=[past_start+timedelta(hours=12)]
    engine=Engine(db,clock=lambda:clock[0])
    with engine.transaction() as s:
        s['showcase']=True
        old=game.choose_season(s);old['name']='Витринный сценарий · Прошлый сезон'
        ids=list(old['roster'])
        def solve_days(ss,eid,days):
            for day in range(days):
                clock[0]=instant(ss['starts_at'])+timedelta(days=day,hours=12)
                for task in game.daily_tasks(s,ss,eid,clock[0])['items']:
                    game.attempt(s,eid,task['id'],s['tasks'][task['id']]['expected_answer'],clock[0])
        for i,eid in enumerate(ids):solve_days(old,eid,max(5,14-i*3))
        game.tick(s,current_start)
        current=game.make_season(s,'Витринный сценарий · Новый уровень',stamp(current_start),ids,len(ids)*1200000+50000,current_start)
        game.publish(s,current,current_start)
        for i,eid in enumerate(ids):solve_days(current,eid,[67,25,18,8][i])
        clock[0]=now
        # Two real local practice results, one checked and one awaiting HR.
        eid=ids[0]
        sid=next(iter(s['employees'][eid]['skills']))
        proto=deepcopy(next(iter(s['activities'].values())))
        for i in range(2):
            aid=f'showcase_practice_{i+1}'
            s['activities'][aid]={**proto,'id':aid,'title':['Разбор рабочего решения','Объясни результат команде'][i],
                'kind':'self_paced','duration_minutes':60,'gains':{sid:10},'prerequisites':{},'active':True,
                'available_from':None,'available_until':None,'starts_at':None,'ends_at':None}
            career.add_plan(s,eid,dict(activity_id=aid,accept_no_goal_gain=True,accept_over_budget=True),now)
            pid=next(p['id'] for p in career.active_plan(s,eid) if p['activity_id']==aid)
            career.transition(s,eid,pid,'start',{},now)
            result=career.transition(s,eid,pid,'complete',dict(confirmed=True,note='Витринная учебная практика.'),now)
            r=game.submit_review(s,eid,result['completion']['id'],'Учебный разбор: описана проблема, выделены допущения, выполнен расчёт на синтетическом примере и проверен результат. Это витринный сценарий.',now)
            if i==0:game.decide_review(s,r['id'],'approved','Проверено в витринном сценарии',now)
        ent=next(e for e in s['entitlements'].values() if e['employee_id']==eid and e['season_id']==current['id'] and e['level']==5)
        item=s['pools'][ent['pool_id']]['fallback_item_id']
        game.create_order(s,eid,{'item_id':item},now,ent['id'])
        item=next(i for i in s['items'].values() if i['shop_visible'] and i['coin_price']==50)
        order=game.create_order(s,eid,{'item_id':item['id'],'expected_item_version':item['version'],'expected_coin_price':item['coin_price']},now)
        game.transition_order(s,order['id'],'approved','Тестовая обработка',None,now)
        game.transition_order(s,order['id'],'ready','Тестовая готовность',None,now)
        s['revision']+=1
        s['audit'].append({'at':stamp(now),'actor':'showcase_cli','action':'generated_through_domain_rules'})
    return path


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--db',required=True)
    args=p.parse_args()
    try:result=build(args.db)
    except ValueError as exc:p.error(str(exc))
    print(f'Separate showcase created: {result}\nStart with CAREER_DB pointing to this file. The working database was not changed.')

if __name__=='__main__':main()
