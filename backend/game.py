"""Transactional seasons, rewards and inventory. Mutations run under Engine lock."""
from collections import Counter, defaultdict
from copy import deepcopy
from datetime import datetime, time, timedelta
import json
from pathlib import Path

from .engine import require, Problem, own, uid, instant, stamp
from .game_rules import ZONE, MINIS, STREAK_XP, game_date, pass_rewards, streak_calendar, task_variant, normalise_answer
from .policies import policy, level_for, pass_totals


def wallet(s, eid):
    entries = [r for r in s['ledger'].values() if r['employee_id'] == eid]
    return dict(balance=sum(r['amount'] for r in entries), entries=sorted(entries, key=lambda r: (r['at'], r['id']), reverse=True))


def coin(s, eid, sid, kind, source, amount, now, allocations=None):
    key = f'{eid}:{kind}:{source}'
    if key in s['ledger']:
        return False
    s['ledger'][key] = dict(id=key, employee_id=eid, season_id=sid, source_type=kind, source_id=source,
                           amount=amount, allocations=allocations or {sid: amount}, at=stamp(now))
    require(wallet(s, eid)['balance'] >= 0, 'INSUFFICIENT_COINS', 'Недостаточно CQ-монет')
    return True


def xp_total(s, sid, eid):
    return sum(x['amount'] for x in list(s['xp'].values())+list(s.get('xp_adjustments',{}).values()) if x['season_id'] == sid and x['employee_id'] == eid)


def emit_xp(s, season, eid, kind, source, amount, effective_at, now):
    key = f'{season["id"]}:{eid}:{kind}:{source}'
    if key in s['xp']:
        return False
    require(season['status'] not in ('finalized', 'closed'), 'SEASON_LOCKED', 'Итоги сезона уже зафиксированы')
    s['xp'][key] = dict(id=key, season_id=season['id'], employee_id=eid, source_type=kind,
                       source_id=source, amount=amount, effective_at=effective_at, created_at=stamp(now))
    return True


def participant(season, eid):
    require(eid in season['roster'], 'NOT_SEASON_MEMBER', 'Вы не участвуете в этом сезоне; карьерные функции доступны')


def choose_season(s, sid=None, eid=None):
    if sid:
        season = s['seasons'].get(sid)
        require(season, 'NOT_FOUND', 'Сезон не найден', 404)
    else:
        published = [x for x in s['seasons'].values() if x['status'] != 'draft']
        season = next((x for x in published if x['status'] == 'active'), None)
        season = season or next((x for x in sorted(published, key=lambda x: x['starts_at']) if x['status'] == 'scheduled'), None)
        season = season or next(iter(sorted(published, key=lambda x: x['starts_at'], reverse=True)), None)
        require(season, 'NO_SEASON', 'Сезон пока не опубликован', 404)
    if eid:
        participant(season, eid)
    return season


def season_summary(season, eid=None):
    return {k: season[k] for k in ('id', 'name', 'status', 'starts_at', 'ends_at', 'review_deadline', 'claim_deadline', 'timezone', 'economy_version')} | {'is_member': eid in season['roster']}


def make_season(s, name, starts_at, ids, budget, now):
    start = instant(starts_at)
    require(start.tzinfo is not None and start.astimezone(ZONE).time() == time(0),
            'INVALID_START', 'Начало сезона — полночь Asia/Almaty', 422)
    require(ids and len(ids) == len(set(ids)) and all(e in s['employees'] for e in ids),
            'INVALID_ROSTER', 'Выберите существующих участников без повторов', 422)
    key = uid('season_')
    rules=policy(s,'economy')
    end = start + timedelta(days=rules['season_days'])
    season = dict(id=key, name=name, status='draft', starts_at=stamp(start), ends_at=stamp(end),
                  review_deadline=stamp(end + timedelta(days=rules['review_days'])), claim_deadline=stamp(end + timedelta(days=rules['claim_days'])),
                  timezone='Asia/Almaty', economy_version='economy-v1', virtual_budget_kzt=budget,
                  roster={eid: {'display_name': s['employees'][eid]['full_name'], 'department': s['employees'][eid]['department']} for eid in ids},
                  rewards=pass_rewards(), created_at=stamp(now))
    season['policies']={k:deepcopy(policy(s,k)) for k in ('economy','streaks','leaderboards','achievements','quests','nominations')}
    season['policy_version']=1
    s['seasons'][key] = season
    make_pools(s, season)
    return season


def make_pools(s, season):
    n = len(season['roster'])
    codes = {part['pool_code']: part for r in season['rewards'] for part in r['components'] if part['type'] in ('mini', 'gift')}
    for code, part in codes.items():
        pid = season['id'] + ':' + code
        cap = part['budget_cap_kzt']
        key = pid + ':fallback'
        multiplier = sum(1 for r in season['rewards'] for p in r['components'] if p.get('pool_code')==code)
        name = 'Сертификат на подарки' if part['type'] == 'gift' else part['name']
        previous=s['items'].get(key)
        s['items'][key] = dict(id=key, name=name, category='Подарки пропуска', coin_price=None,
            unit_budget_kzt=cap, stock_total=n*multiplier, reserved=0, delivered=0, active=True, version=1,
            shop_visible=False, protected_pool=pid, description=f'{name}, лимит {cap} ₸. Тестовая выдача через HR.',
            delivery_terms='Получение в HR-службе. Без заказа у продавца и реальной оплаты.', image_asset='gift')
        if previous:
            s['items'][key].update(stock_total=max(previous['stock_total'],n*multiplier),
                reserved=previous['reserved'],delivered=previous['delivered'],version=previous['version']+1)
        options = [key]
        if part['type'] == 'gift':
            options += [i['id'] for i in s['items'].values() if i['shop_visible'] and i['unit_budget_kzt'] <= cap]
        old=s['pools'].get(pid,{})
        s['pools'][pid] = dict(id=pid, season_id=season['id'], code=code, cap=cap,
                             item_ids=sorted(set(options+old.get('item_ids',[]))), fallback_item_id=old.get('fallback_item_id',key))


def publish(s, season, now):
    require(season['status'] == 'draft', 'SEASON_LOCKED', 'Этот сезон уже опубликован')
    required = pass_totals(season)['total_kzt']
    require(season['virtual_budget_kzt'] >= required, 'INSUFFICIENT_BUDGET', f'Нужен виртуальный резерв {required} ₸', required_kzt=required)
    require(instant(season['ends_at']) > now, 'INVALID_START', 'Период сезона уже завершился', 422)
    for other in s['seasons'].values():
        if other['id'] != season['id'] and other['status'] != 'draft':
            require(not (instant(season['starts_at']) < instant(other['ends_at']) and instant(other['starts_at']) < instant(season['ends_at'])),
                    'SEASON_OVERLAP', 'Периоды заработка сезонов пересекаются')
    from .admin_schemas import Pass
    Pass.model_validate({'rewards':season['rewards']})
    for pool in [p for p in s['pools'].values() if p['season_id'] == season['id']]:
        fallback = s['items'].get(pool['fallback_item_id'])
        copies = sum(1 for r in season['rewards'] for c in r['components'] if c.get('pool_code') == pool['code']) * len(season['roster'])
        require(fallback and not fallback['shop_visible'] and fallback.get('protected_pool') == pool['id'] and
                fallback['active'] and fallback['stock_total'] >= copies and fallback['unit_budget_kzt'] <= pool['cap'],
                'INVALID_REWARD_POOL', 'Недостаточно резервных подарков в пуле', 422)
        for item_id in pool['item_ids']:
            require(item_id in s['items'] and s['items'][item_id]['unit_budget_kzt'] <= pool['cap'], 'INVALID_REWARD_POOL', 'Товар превышает лимит пула', 422)
    season['status'] = 'active' if instant(season['starts_at']) <= now else 'scheduled'
    season['published_at'] = stamp(now)
    season['committed_budget_kzt'] = required
    return season_summary(season)


def seed_game(s, now):
    for item in json.loads((Path(__file__).resolve().parent.parent / 'data/gamification/shop.json').read_text(encoding='utf-8')):
        s['items'][item['id']] = {**item, 'active': True, 'version': 1, 'stock_total': 4, 'reserved': 0, 'delivered': 0,
            'shop_visible': True, 'image_asset': item['category'],
            'description': item['name'] + '. Учебный SKU: сертификат на эту категорию в пределах указанного лимита. Конкретная модель не обещается.',
            'delivery_terms': 'Тестовая выдача сертификата в HR-службе. Монтаж, доставка, бронирование и платежи не выполняются.'}
    ids = sorted(s['employees'])[:4]
    start = datetime.combine(game_date(now), time.min, ZONE)
    season = make_season(s, 'Сезон 1. Новый уровень', stamp(start), ids, len(ids)*1200000+50000, now)
    publish(s, season, now)


def confirmed_events(s, sid, eid):
    reviews={r['completion_id']:r for r in s['reviews'].values() if r['season_id']==sid and r['employee_id']==eid}
    events=[x for x in s['xp'].values() if x['season_id']==sid and x['employee_id']==eid and
            (x['source_type']=='daily' or x['source_type']=='activity' and
             (x['source_id'] not in reviews or reviews[x['source_id']]['status']=='approved'))]
    recorded={x['source_id'] for x in events if x['source_type']=='activity'}
    events += [dict(source_type='activity',source_id=r['completion_id'],effective_at=r['effective_at'])
               for r in reviews.values() if r['status']=='approved' and r['completion_id'] not in recorded]
    return events


def confirmed_days(s, sid, eid):
    return {game_date(instant(x['effective_at'])).isoformat() for x in confirmed_events(s,sid,eid)}


def streak(s, season, eid, now):
    pending = {game_date(instant(r['effective_at'])).isoformat() for r in s['reviews'].values()
               if r['season_id'] == season['id'] and r['employee_id'] == eid and r['status'] == 'pending'}
    return streak_calendar(season, confirmed_days(s, season['id'], eid), pending, now)


def award_followups(s, season, eid, now):
    sid = season['id']
    reviews = sorted([r for r in s['reviews'].values() if r['season_id'] == sid and r['employee_id'] == eid and r['status'] == 'approved'], key=lambda r: (r['effective_at'], r['id']))
    def badge(code, amount, at, name):
        key = f'{sid}:{eid}:{code}'
        if key not in s['badges']:
            s['badges'][key] = dict(id=key, code=code, name=name, season_id=sid, employee_id=eid, xp_awarded=amount, effective_at=at)
            if amount:
                emit_xp(s, season, eid, 'achievement', code, amount, at, now)
    covered = set()
    for review in reviews:
        covered |= {k for k, v in s['completions'][review['completion_id']]['gains'].items() if v > 0}
    counts=dict(verified_activities=len(reviews),distinct_skills=len(covered),active_days=len(confirmed_days(s,sid,eid)))
    for definition in policy(s,'achievements',season)['items']:
        if definition['active'] and counts[definition['condition']]>=definition['threshold']:
            badge(definition['code'],definition['xp'],reviews[-1]['effective_at'] if reviews else stamp(now),definition['name'])
    calendar = streak(s, season, eid, now)
    for count, day in calendar['milestones'].items():
        at = stamp(datetime.combine(datetime.fromisoformat(day).date(), time(12), ZONE))
        amounts={m['days']:m['xp'] for m in policy(s,'streaks',season)['milestones']}
        badge(f'streak_{count}', amounts[count], at, f'Серия: {count} активных дней')
    first = game_date(instant(season['starts_at']))
    rules=policy(s,'economy',season)
    for week in range((rules['season_days']+6)//7):
        days = sorted(d for d in confirmed_days(s, sid, eid) if week*7 <= (datetime.fromisoformat(d).date()-first).days < (week+1)*7)
        if len(days) >= rules['weekly_days']:
            at = stamp(datetime.combine(datetime.fromisoformat(days[rules['weekly_days']-1]).date(), time(12), ZONE))
            badge(f'week_{week}', rules['weekly_xp'], at, 'Недельная миссия')
    level = level_for(season,xp_total(s, sid, eid))
    for reward in season['rewards'][:level]:
        for index, part in enumerate(reward['components']):
            source = f'{sid}:{reward["level"]}:{index}'
            if part['type'] == 'coins':
                paid=sum(r['amount'] for r in s['ledger'].values() if r['employee_id']==eid and
                         r['source_type'] in ('pass_level','pass_amendment') and
                         (r['source_id']==source or r['source_id'].startswith(source+':version:')))
                if part['coins']>paid:
                    kind='pass_amendment' if paid else 'pass_level'
                    source_key=source+':version:'+str(season.get('policy_version',1)) if paid else source
                    coin(s,eid,sid,kind,source_key,part['coins']-paid,now)
            elif part['type'] in ('mini', 'gift'):
                key = f'{eid}:{source}'
                s['entitlements'].setdefault(key, dict(id=key, employee_id=eid, season_id=sid,
                    level=reward['level'], component=index, name=part['name'], cap=part['budget_cap_kzt'],
                    pool_id=f'{sid}:{part["pool_code"]}', status='available', opened_at=stamp(now)))
                if s['entitlements'][key]['status']=='available':
                    s['entitlements'][key]['cap']=max(s['entitlements'][key]['cap'],part['budget_cap_kzt'])
            else:
                badge(part['cosmetic_code'], 0, stamp(now), part['name'])
    if level == len(season['rewards']):
        badge('pass_complete', 0, stamp(now), 'Пропуск завершён')


def pass_state(s, season, eid):
    participant(season, eid)
    xp = xp_total(s, season['id'], eid)
    rows = deepcopy(season['rewards'])
    for r in rows:
        r['unlocked'] = xp >= r['required_total_xp']
        for index, part in enumerate(r['components']):
            part['status'] = 'locked'
            if r['unlocked']:
                part['status'] = 'credited' if part['type'] == 'coins' else 'fulfilled' if part['type'] == 'cosmetic' else 'available'
                e = s['entitlements'].get(f'{eid}:{season["id"]}:{r["level"]}:{index}')
                if e:
                    part.update(status=e['status'], entitlement_id=e['id'], pool_id=e['pool_id'])
    return rows


def leaderboard(s, season, eid=None, scope='overall', week=None, page=1):
    sid = season['id']
    frozen = s['snapshots'].get(sid)
    rows = deepcopy(frozen) if frozen and scope != 'week' else []
    if not rows and not frozen or scope == 'week':
        for person, snap in season['roster'].items():
            events = [x for x in s['xp'].values() if x['season_id'] == sid and x['employee_id'] == person]
            if scope == 'week':
                start = instant(season['starts_at']) + timedelta(days=(week or 0)*7)
                events = [x for x in events if start <= instant(x['effective_at']) < start + timedelta(days=7)]
            adjustments=[x for x in s.get('xp_adjustments',{}).values() if x['season_id']==sid and x['employee_id']==person]
            if scope=='week': adjustments=[x for x in adjustments if start<=instant(x['effective_at'])<start+timedelta(days=7)]
            points = sum(x['amount'] for x in events+adjustments)
            confirmed=confirmed_events(s,sid,person)
            if scope=='week':confirmed=[x for x in confirmed if start<=instant(x['effective_at'])<start+timedelta(days=7)]
            days = {game_date(instant(x['effective_at'])).isoformat() for x in confirmed}
            count = sum(x['source_type'] == 'activity' for x in confirmed)
            rules=policy(s,'leaderboards',season)
            rows.append(dict(employee_id=person, display_name=snap['display_name'], department=snap['department'], confirmed_xp=points, level=level_for(season,xp_total(s, sid, person)),
                             active_days=len(days), confirmed_activity_count=count,
                             badges=[b['name'] for b in s['badges'].values() if b['season_id'] == sid and b['employee_id'] == person],
                             title=None, prize_eligible=points >= rules['min_xp'] and len(days) >= rules['min_days'] and snap.get('prize_eligible',True), prize_rank=None))
        rows.sort(key=lambda r: tuple(-r[k] for k in policy(s,'leaderboards',season)['criteria'])+(r['employee_id'],))
        for index, row in enumerate(rows):
            row['rank'] = index+1 if row['confirmed_xp'] else None
    if scope == 'department':
        participant(season, eid)
        rows = [r for r in rows if r['department'] == season['roster'][eid]['department']]
        for index, r in enumerate(rows):
            r['rank'] = index+1 if r['confirmed_xp'] else None
    for row in rows:
        row['is_self'] = row['employee_id'] == eid
    self_row = next((r for r in rows if r['employee_id'] == eid), None)
    index = rows.index(self_row) if self_row else -1
    return dict(season_id=sid, is_final=bool(frozen), scope=scope, entries=rows[(page-1)*20:page*20], total=len(rows),
                self=self_row, neighbors=rows[max(0,index-2):index+3] if index >= 0 else [])


def summary(s, season, eid, now):
    participant(season, eid)
    xp = xp_total(s, season['id'], eid)
    calendar = streak(s, season, eid, now)
    level = level_for(season,xp)
    return dict(season=season_summary(season, eid), confirmed_xp=xp, level=level,
                xp_to_next=season['rewards'][level]['required_total_xp']-xp if level<len(season['rewards']) else 0,
                level_start_xp=season['rewards'][level-1]['required_total_xp'] if level else 0,
                level_target_xp=season['rewards'][min(level,len(season['rewards'])-1)]['required_total_xp'],
                max_level=len(season['rewards']), max_xp=season['rewards'][-1]['required_total_xp'],wallet_balance=wallet(s,eid)['balance'],
                pass_progress=min(1,xp/season['rewards'][-1]['required_total_xp']), rank=(leaderboard(s,season,eid)['self'] or {}).get('rank'),
                pending_xp=sum(r['xp_amount'] for r in s['reviews'].values() if r['season_id'] == season['id'] and r['employee_id'] == eid and r['status'] == 'pending'),
                current_streak=calendar['current_streak'], best_streak=calendar['best_streak'],
                freeze_remaining=calendar['freeze_remaining'], active_days=calendar['active_days'],
                next_reward=season['rewards'][level] if level < len(season['rewards']) else None,
                unclaimed_gifts_count=sum(e['employee_id'] == eid and e['status'] == 'available' for e in s['entitlements'].values()))


def daily_tasks(s, season, eid, now):
    participant(season, eid)
    date = game_date(now)
    if season['status'] != 'active' or season.get('paused') or policy(s,'settings')['quests_paused']:
        return dict(items=[], status=season['status'])
    rows = []
    rules=policy(s,'economy',season)
    for index in range(rules['daily_count']):
        kind='main' if index==0 else 'bonus' if index==1 else f'bonus{index}'
        key = f'{season["id"]}:{eid}:{date}:{kind}'
        if key not in s['tasks']:
            variant = task_variant(s['task_secret'], season, eid, date, kind)
            s['tasks'][key] = dict(id=key, season_id=season['id'], employee_id=eid, kind=kind,
                title='Ежедневный шаг' if kind=='main' else 'Кейс дня',game_date=date.isoformat(),
                xp=rules['daily_xp'] if kind == 'main' else rules['bonus_xp'], max_attempts=rules['attempts'],
                policy_version=season.get('policy_version',1), attempts=0, status='available', **variant)
        task = s['tasks'][key]
        rows.append({k:v for k,v in task.items() if k not in ('expected_answer','explanation','employee_id')}
                    | {'attempts_remaining':task.get('max_attempts',3)-task['attempts'], 'explanation':task['explanation'] if task['status'] != 'available' else None})
    templates=[q for q in policy(s,'quests',season)['items'] if q['active'] and date.weekday() in q['weekdays']]
    for q in templates:
        key=f'{season["id"]}:{eid}:{date}:custom:{q["id"]}'
        if key not in s['tasks']:
            variant=task_variant(s['task_secret'],season,eid,date,q['generator']) if q['kind']=='generator' else {
                'answer_fields':deepcopy(q['answer_fields']),'expected_answer':deepcopy(q['expected_answer']),
                'explanation':q['explanation'],'instructions':q['instructions'],'public_payload':{},'custom':True}
            s['tasks'][key]=dict(id=key,season_id=season['id'],employee_id=eid,kind=q['id'],title=q['title'],
                game_date=date.isoformat(),xp=q['xp'],max_attempts=q['max_attempts'],attempts=0,status='available',
                policy_version=season.get('policy_version',1),**variant)
        task=s['tasks'][key]
        rows.append({k:v for k,v in task.items() if k not in ('expected_answer','explanation','employee_id')}
                    | {'attempts_remaining':task.get('max_attempts',3)-task['attempts'],'explanation':task['explanation'] if task['status']!='available' else None})
    visible={r['id'] for r in rows}
    for task in s['tasks'].values():
        if task['season_id']==season['id'] and task['employee_id']==eid and task['game_date']==date.isoformat() and task['id'] not in visible:
            rows.append({k:v for k,v in task.items() if k not in ('expected_answer','explanation','employee_id')}
                        | {'attempts_remaining':task.get('max_attempts',3)-task['attempts'],'explanation':task['explanation'] if task['status']!='available' else None})
    week = (date-game_date(instant(season['starts_at']))).days//7
    start = game_date(instant(season['starts_at']))+timedelta(days=week*7)
    count = sum(start.isoformat() <= d < (start+timedelta(days=7)).isoformat() for d in confirmed_days(s,season['id'],eid))
    return dict(items=rows, weekly_days=count, weekly_required=rules['weekly_days'], weekly_xp=rules['weekly_xp'],
                resets_at=stamp(datetime.combine(date+timedelta(days=1),time.min,ZONE)))


def award_result(s, season, eid, before_xp, before_coins, before_events, before_gifts, before_badges, now):
    total=xp_total(s,season['id'],eid)
    return dict(accepted=True,awarded_xp=total-before_xp,
        new_xp_events=[x for key,x in s['xp'].items() if key not in before_events],
        unlocked_levels=list(range(level_for(season,before_xp)+1,level_for(season,total)+1)),
        credited_coins=wallet(s,eid)['balance']-before_coins,
        new_entitlements=[key for key in s['entitlements'] if key not in before_gifts],
        badges=[b for key,b in s['badges'].items() if key not in before_badges],
        gamification=summary(s,season,eid,now))


def award_before(s,season,eid):
    return (xp_total(s,season['id'],eid),wallet(s,eid)['balance'],set(s['xp']),set(s['entitlements']),set(s['badges']))


def attempt(s, eid, tid, answer, now):
    task = own(s['tasks'],tid,eid)
    season = choose_season(s, task['season_id'], eid)
    require(not season.get('paused') and not policy(s,'settings')['quests_paused'], 'QUESTS_PAUSED','Приём заданий временно приостановлен')
    require(task['game_date'] == game_date(now).isoformat() and season['status'] == 'active', 'TASK_EXPIRED','Это задание уже завершило свой игровой день')
    if task['status'] == 'completed':
        return dict(correct=True, attempts_remaining=task.get('max_attempts',3)-task['attempts'], explanation=task['explanation'], already_completed=True, gamification=summary(s,season,eid,now))
    require(task['attempts'] < task.get('max_attempts',3),'ATTEMPTS_EXHAUSTED','Все попытки использованы')
    before=award_before(s,season,eid)
    normalised = normalise_answer(task,answer)
    task['attempts'] += 1
    correct = normalised == task['expected_answer']
    if correct:
        task['status'] = 'completed'
        emit_xp(s,season,eid,'daily',tid,task['xp'],stamp(now),now)
        award_followups(s,season,eid,now)
    elif task['attempts'] == task.get('max_attempts',3):
        task['status'] = 'failed'
    return dict(correct=correct, attempts_remaining=task.get('max_attempts',3)-task['attempts'],
                award=award_result(s,season,eid,*before,now) if correct else None,
                explanation=task['explanation'] if correct or task['status']=='failed' else None,
                gamification=summary(s,season,eid,now))


def submit_review(s,eid,cid,evidence,now):
    c = own(s['completions'],cid,eid)
    prior = next((r for r in s['reviews'].values() if r['completion_id']==cid),None)
    if prior:
        return prior
    season = next((x for x in s['seasons'].values() if x['status'] != 'draft' and instant(x['starts_at'])<=instant(c['completed_at'])<instant(x['ends_at'])),None)
    require(season,'SEASON_NOT_ACTIVE','Выполнение не попало в период заработка сезона')
    participant(season,eid)
    deadline = min(instant(c['completed_at'])+timedelta(days=7),instant(season['ends_at'])+timedelta(days=3))
    require(now<=deadline and season['status'] in ('active','settling'),'REVIEW_WINDOW_CLOSED','Срок подачи результата истёк')
    day = game_date(instant(c['completed_at']))
    count = sum(r['employee_id']==eid and r['status'] in ('pending','approved') and game_date(instant(r['effective_at']))==day for r in s['reviews'].values())
    rules=policy(s,'economy',season)
    activity=c.get('activity_snapshot',s['activities'][c['activity_id']])
    require(activity.get('reward_eligible',True),'NOT_REWARD_ELIGIBLE','Активность не участвует в наградах')
    require(count<rules['reviews_per_day'],'DAILY_REVIEW_LIMIT','Лимит заявок на награду за день выполнения исчерпан')
    key=uid('review_')
    s['reviews'][key] = dict(id=key,completion_id=cid,employee_id=eid,season_id=season['id'],status='pending',evidence_text=evidence,
        xp_amount=round(min(rules['activity_max'],max(rules['activity_min'],rules['activity_multiplier']*activity['duration_minutes']))),
        policy_version=season.get('policy_version',1),activity_snapshot=deepcopy(activity),effective_at=c['completed_at'],submitted_at=stamp(now),decision_note=None)
    return s['reviews'][key]


def decide_review(s,rid,decision,comment,now):
    r=s['reviews'].get(rid)
    require(r,'NOT_FOUND','Проверка не найдена',404)
    require(r['status']=='pending','REVIEW_ALREADY_DECIDED','Результат уже рассмотрен')
    season=s['seasons'][r['season_id']]
    require(now<instant(season['review_deadline']),'REVIEW_WINDOW_CLOSED','Срок проверки истёк')
    require(decision!='rejected' or comment.strip(),'REASON_REQUIRED','Укажите причину отказа',422)
    before=award_before(s,season,r['employee_id'])
    r.update(status=decision,decision_note=comment,decided_at=stamp(now))
    if decision=='approved':
        emit_xp(s,season,r['employee_id'],'activity',r['completion_id'],r['xp_amount'],r['effective_at'],now)
        award_followups(s,season,r['employee_id'],now)
    return {**r,'award':award_result(s,season,r['employee_id'],*before,now) if decision=='approved' else None}


def item_view(item):
    return {**item, 'available_stock':item['stock_total']-item['reserved']-item['delivered']}


def order_view(order,eid=None):
    return {**order,'can_cancel':order['status']=='requested' and (eid is None or order['employee_id']==eid)}


def funding_for(s,eid,amount):
    buckets=defaultdict(int)
    for row in s['ledger'].values():
        if row['employee_id']==eid:
            for sid,value in row['allocations'].items():
                buckets[sid]+=value
    result={}
    for sid in sorted(buckets,key=lambda sid:s['seasons'][sid]['starts_at']):
        take=min(amount,buckets[sid])
        if take>0:
            result[sid]=take
            amount-=take
    require(amount==0,'INSUFFICIENT_COINS','Недостаточно CQ-монет')
    return result


def create_order(s,eid,body,now,entitlement_id=None):
    require(entitlement_id or not policy(s,'settings')['shop_paused'],'SHOP_PAUSED','Новые покупки временно приостановлены')
    item=s['items'].get(body['item_id'])
    require(item,'NOT_FOUND','Товар не найден',404)
    require(item['active'],'ITEM_UNAVAILABLE','Товар временно недоступен')
    require(item_view(item)['available_stock']>0,'OUT_OF_STOCK','Этот товар закончился')
    key=uid('order_')
    ent=None
    if entitlement_id:
        ent=own(s['entitlements'],entitlement_id,eid)
        season=s['seasons'][ent['season_id']]
        require(now<instant(season['claim_deadline']),'CLAIM_EXPIRED','Срок выбора подарка истёк')
        require(ent['status']=='available','REWARD_ALREADY_RESERVED','Подарок уже выбран или получен')
        pool=s['pools'][ent['pool_id']]
        require(item['id'] in pool['item_ids'] and item['unit_budget_kzt']<=ent['cap'],'INVALID_REWARD','Товар не входит в этот подарочный пул',422)
        price=0
        cap=ent['cap']
        funds={ent['season_id']:cap}
        ent['status']='reserved'
        ent['order_id']=key
    else:
        require(item['shop_visible'] and item['coin_price'] is not None,'ITEM_UNAVAILABLE','Этот подарок доступен только по пропуску')
        require(body.get('expected_item_version')==item['version'] and body.get('expected_coin_price')==item['coin_price'],
                'ITEM_PRICE_CHANGED','Условия товара изменились. Откройте карточку заново.')
        price=item['coin_price']
        require(wallet(s,eid)['balance']>=price,'INSUFFICIENT_COINS','Недостаточно CQ-монет',missing_coins=price-wallet(s,eid)['balance'])
        allocations=funding_for(s,eid,price)
        funds={sid:n*policy(s,'economy',s['seasons'][sid])['coin_backing'] for sid,n in allocations.items()}
        cap=sum(funds.values())
        require(cap>=item['unit_budget_kzt'],'INSUFFICIENT_BACKING','Обеспечения монет недостаточно для этого товара')
        coin(s,eid,next(iter(allocations)),'shop_order',key,-price,now,{sid:-n for sid,n in allocations.items()})
    item['reserved']+=1
    order=dict(id=key,employee_id=eid,payment_kind='pass_entitlement' if ent else 'coins',
               entitlement_id=entitlement_id,item_id=item['id'],item_snapshot=deepcopy(item_view(item)),
               coins_charged=price,budget_cap_kzt=cap,funding=funds,status='requested',requested_at=stamp(now),
               timeline=[{'status':'requested','at':stamp(now),'note':'Получение в HR-службе; тестовая выдача'}])
    if not ent: order['coin_allocations']=allocations
    s['orders'][key]=order
    return order_view(order,eid)


def transition_order(s,oid,target,note,actual_cost,now,eid=None):
    order=own(s['orders'],oid,eid) if eid else s['orders'].get(oid)
    require(order,'NOT_FOUND','Заявка не найдена',404)
    if order['status']==target:
        return order_view(order,eid)
    allowed={'requested':('cancelled',)} if eid else {'requested':('approved','rejected'), 'approved':('ready','cancelled'), 'ready':('delivered',)}
    require(target in allowed.get(order['status'],()),'ORDER_CANNOT_CANCEL' if target=='cancelled' else 'INVALID_TRANSITION','Этот переход заявки недоступен')
    if target in ('cancelled','rejected') and not eid:
        require(note.strip(),'REASON_REQUIRED','Укажите причину',422)
    item=s['items'][order['item_id']]
    if target=='delivered':
        require(note.strip(),'REASON_REQUIRED','Добавьте пометку тестовой выдачи',422)
        require(actual_cost is not None and 0<=actual_cost<=min(order['budget_cap_kzt'],order['item_snapshot']['unit_budget_kzt']),
                'INVALID_COST','Стоимость должна укладываться в лимит выбранного товара',422)
        item['reserved']-=1
        item['delivered']+=1
        order['actual_cost_kzt']=actual_cost
        order['fulfillment_note']='Тестовая выдача. '+note
        if order['entitlement_id']:
            s['entitlements'][order['entitlement_id']]['status']='fulfilled'
    if target in ('cancelled','rejected'):
        item['reserved']-=1
        if order['coins_charged']:
            allocations=order.get('coin_allocations') or {sid:amount//100 for sid,amount in order['funding'].items()}
            coin(s,order['employee_id'],next(iter(allocations)),'order_refund',oid,order['coins_charged'],now,allocations)
        elif order['entitlement_id']:
            ent=s['entitlements'][order['entitlement_id']]
            ent['status']='available' if now<instant(s['seasons'][ent['season_id']]['claim_deadline']) else 'expired'
            ent.pop('order_id',None)
    order['status']=target
    order[target+'_at']=stamp(now)
    order['timeline'].append({'status':target,'at':stamp(now),'note':note})
    return order_view(order,eid)


def economy(s,season):
    sid=season['id']
    backing=policy(s,'economy',season)['coin_backing']
    # All buckets partition the original commitment; orders move, never duplicate, liabilities.
    issued=sum(r['allocations'].get(sid,0)*backing for r in s['ledger'].values()
               if r['source_type'] in ('pass_level','pass_amendment','season_podium','admin_correction','nomination','result_amendment'))
    entitlements=[e for e in s['entitlements'].values() if e['season_id']==sid]
    earned=issued+sum(e['cap'] for e in entitlements)
    budget=season.get('committed_budget_kzt',pass_totals(season)['total_kzt'])
    # Finalization closes every XP source: unearned rewards and unused podium
    # reserves are released then; earned gifts remain claimable until closure.
    unearned=max(0,budget-earned) if season['status'] not in ('finalized','closed') else 0
    coins=sum(r['allocations'].get(sid,0)*backing for r in s['ledger'].values())
    liability=coins+sum(e['cap'] for e in entitlements if e['status']=='available')
    reserved=spent=0
    for order in s['orders'].values():
        amount=order['funding'].get(sid,0)
        if order['status'] in ('requested','approved','ready'):
            reserved+=amount
            if order['coins_charged']:
                lots=order.get('coin_allocations') or {k:v//100 for k,v in order['funding'].items()}
                reserved+=lots.get(sid,0)*backing-amount
        elif order['status']=='delivered':
            spent+=order['actual_cost_kzt']*amount/order['budget_cap_kzt']
    released=budget-unearned-liability-reserved-spent
    return dict(virtual_budget_kzt=season['virtual_budget_kzt'],committed_budget_kzt=budget,
                unearned_reserved=unearned,earned_liability=liability,order_reserved=reserved,spent=round(spent,2),released=round(released,2),
                wallet_liability_kzt=coins,max_per_member_kzt=pass_totals(season)['per_member_kzt'],
                pending_orders=sum(o['status'] in ('requested','approved','ready') and sid in o['funding'] for o in s['orders'].values()),
                coins_issued=issued//backing,
                pending_reviews=sum(r['season_id']==sid and r['status']=='pending' for r in s['reviews'].values()),
                confirmed_xp=sum(x['amount'] for x in list(s['xp'].values())+list(s.get('xp_adjustments',{}).values()) if x['season_id']==sid))


def finalize(s,season,now):
    sid=season['id']
    if sid in s['snapshots']:
        return
    for review in s['reviews'].values():
        if review['season_id']==sid and review['status']=='pending':
            review.update(status='rejected',decision_note='review_deadline_missed',decided_at=stamp(now))
    rows=leaderboard(s,season,page=1)['entries']
    # Fetch the full roster, not just the public first page.
    for page in range(2,(len(season['roster'])+19)//20+1):
        rows+=leaderboard(s,season,page=page)['entries']
    eligible=[r for r in rows if r['prize_eligible']]
    rules=policy(s,'leaderboards',season)
    for index,row in enumerate(eligible[:len(rules['prizes'])]):
        row['prize_rank']=index+1
        row['title']=rules['winner_title'] if index==0 else f'Призёр сезона: {index+1} место'
        coin(s,row['employee_id'],sid,'season_podium',f'{sid}:{index}',rules['prizes'][index],now)
    departments=Counter(r['department'] for r in rows if r['confirmed_xp']>0)
    for department,count in departments.items():
        winner=next((r for r in rows if r['department']==department and r['prize_eligible']),None)
        if count>=3 and winner:
            key=f'{sid}:{winner["employee_id"]}:department_leader'
            s['badges'][key]=dict(id=key,code='department_leader',name='Лидер подразделения',season_id=sid,
                employee_id=winner['employee_id'],xp_awarded=0,effective_at=season['ends_at'])
            winner['badges'].append('Лидер подразделения')
    for row in rows:
        row['overall_rank']=row['rank']
        row.pop('is_self',None)
    award_nominations(s,season,rows,now)
    s['snapshots'][sid]=deepcopy(rows)
    season['status']='finalized'
    season['finalized_at']=stamp(now)


def award_nominations(s,season,rows,now):
    sid=season['id']
    for rule in policy(s,'nominations',season)['items']:
        if not rule['active']:continue
        groups=sorted({r['department'] for r in rows}) if rule['per_department'] else ['*']
        for group in groups:
            candidates=[r for r in rows if r['prize_eligible'] and (group=='*' or r['department']==group)]
            def score(row):
                eid=row['employee_id']
                if rule['criterion']=='best_streak':return streak(s,season,eid,now)['best_streak']
                if rule['criterion']=='distinct_skills':
                    return len({k for rev in s['reviews'].values() if rev['employee_id']==eid and rev['season_id']==sid and rev['status']=='approved'
                                for k,v in s['completions'][rev['completion_id']]['gains'].items() if v>0})
                return row[rule['criterion']]
            if not candidates:continue
            winner=sorted(candidates,key=lambda r:(-score(r),r['employee_id']))[0]
            source=f'{sid}:{rule["id"]}:{group}';eid=winner['employee_id']
            coin(s,eid,sid,'nomination',source,rule['coins'],now)
            key=f'{eid}:nomination:{source}'
            s['badges'].setdefault(key,dict(id=key,code=rule['id'],name=rule['name'],season_id=sid,employee_id=eid,xp_awarded=0,effective_at=stamp(now)))
            if rule['name'] not in winner['badges']:winner['badges'].append(rule['name'])


def tick(s,now):
    changed=False
    for season in sorted(s['seasons'].values(),key=lambda x:x['starts_at']):
        before=season['status']
        if before=='draft':
            continue
        if season['status']=='scheduled' and now>=instant(season['starts_at']):
            season['status']='active'
        if season['status']=='active' and now>=instant(season['ends_at']):
            season['status']='settling'
        if season['status']=='settling' and now>=instant(season['review_deadline']):
            finalize(s,season,now)
        if season['status']=='finalized' and now>=instant(season['claim_deadline']):
            season['status']='closed'
            for ent in s['entitlements'].values():
                if ent['season_id']==season['id'] and ent['status']=='available':
                    ent['status']='expired'
        changed=changed or season['status']!=before
    for order in s['orders'].values():
        if order['status']=='requested' and now>=instant(order['requested_at'])+timedelta(days=policy(s,'economy')['order_expiry_days']):
            transition_order(s,order['id'],'cancelled','Срок обработки заявки истёк',None,now,order['employee_id'])
            changed=True
    if changed:
        s['audit'].append({'at':stamp(now),'actor':'system','action':'season_tick'})
    return changed
