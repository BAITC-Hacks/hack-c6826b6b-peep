"""Transactional seasons, rewards and inventory. Mutations run under Engine lock."""
from collections import Counter, defaultdict
from copy import deepcopy
from datetime import datetime, time, timedelta
import json
from pathlib import Path

from .engine import require, Problem, own, uid, instant, stamp
from .game_rules import ZONE, MINIS, STREAK_XP, game_date, pass_rewards, streak_calendar, task_variant, normalise_answer


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
    return sum(x['amount'] for x in s['xp'].values() if x['season_id'] == sid and x['employee_id'] == eid)


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
    end = start + timedelta(days=90)
    season = dict(id=key, name=name, status='draft', starts_at=stamp(start), ends_at=stamp(end),
                  review_deadline=stamp(end + timedelta(days=7)), claim_deadline=stamp(end + timedelta(days=14)),
                  timezone='Asia/Almaty', economy_version='economy-v1', virtual_budget_kzt=budget,
                  roster={eid: {'display_name': s['employees'][eid]['full_name'], 'department': s['employees'][eid]['department']} for eid in ids},
                  rewards=pass_rewards(), created_at=stamp(now))
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
        multiplier = 10 if code == 'gift10000' else 9 if code == 'gift30000' else 1
        name = 'Сертификат на подарки' if part['type'] == 'gift' else part['name']
        s['items'][key] = dict(id=key, name=name, category='Подарки пропуска', coin_price=None,
            unit_budget_kzt=cap, stock_total=n*multiplier, reserved=0, delivered=0, active=True, version=1,
            shop_visible=False, protected_pool=pid, description=f'{name}, лимит {cap} ₸. Тестовая выдача через HR.',
            delivery_terms='Получение в HR-службе. Без заказа у продавца и реальной оплаты.', image_asset='gift')
        options = [key]
        if part['type'] == 'gift':
            options += [i['id'] for i in s['items'].values() if i['shop_visible'] and i['unit_budget_kzt'] <= cap]
        s['pools'][pid] = dict(id=pid, season_id=season['id'], code=code, cap=cap, item_ids=options, fallback_item_id=key)


def publish(s, season, now):
    require(season['status'] == 'draft', 'SEASON_LOCKED', 'Этот сезон уже опубликован')
    required = len(season['roster']) * 1200000 + 50000
    require(season['virtual_budget_kzt'] >= required, 'INSUFFICIENT_BUDGET', f'Нужен виртуальный резерв {required} ₸', required_kzt=required)
    require(instant(season['ends_at']) > now, 'INVALID_START', 'Период сезона уже завершился', 422)
    for other in s['seasons'].values():
        if other['id'] != season['id'] and other['status'] != 'draft':
            require(not (instant(season['starts_at']) < instant(other['ends_at']) and instant(other['starts_at']) < instant(season['ends_at'])),
                    'SEASON_OVERLAP', 'Периоды заработка сезонов пересекаются')
    require([r['level'] for r in season['rewards']] == list(range(1, 101)), 'INVALID_REWARDS', 'Нужны все 100 уровней', 422)
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
    for item in json.loads((Path(__file__).resolve().parent.parent / 'data/gamification/shop.json').read_text()):
        s['items'][item['id']] = {**item, 'active': True, 'version': 1, 'stock_total': 4, 'reserved': 0, 'delivered': 0,
            'shop_visible': True, 'image_asset': item['category'],
            'description': item['name'] + '. Учебный SKU: сертификат на эту категорию в пределах указанного лимита. Конкретная модель не обещается.',
            'delivery_terms': 'Тестовая выдача сертификата в HR-службе. Монтаж, доставка, бронирование и платежи не выполняются.'}
    ids = sorted(s['employees'])[:4]
    start = datetime.combine(game_date(now), time.min, ZONE)
    season = make_season(s, 'Сезон 1. Новый уровень', stamp(start), ids, len(ids)*1200000+50000, now)
    publish(s, season, now)


def confirmed_days(s, sid, eid):
    return {game_date(instant(x['effective_at'])).isoformat() for x in s['xp'].values()
            if x['season_id'] == sid and x['employee_id'] == eid and x['source_type'] in ('daily', 'activity')}


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
    if reviews:
        badge('first_step', 100, reviews[0]['effective_at'], 'Первый шаг сделан')
    if len(reviews) >= 3:
        badge('three_steps', 200, reviews[2]['effective_at'], 'Устойчивое движение')
    covered = set()
    for review in reviews:
        covered |= {k for k, v in s['completions'][review['completion_id']]['gains'].items() if v > 0}
        if len(covered) >= 3:
            badge('skill_explorer', 300, review['effective_at'], 'Разностороннее развитие')
            break
    calendar = streak(s, season, eid, now)
    for count, day in calendar['milestones'].items():
        at = stamp(datetime.combine(datetime.fromisoformat(day).date(), time(12), ZONE))
        badge(f'streak_{count}', STREAK_XP[count], at, f'Серия: {count} активных дней')
    first = game_date(instant(season['starts_at']))
    for week in range(13):
        days = sorted(d for d in confirmed_days(s, sid, eid) if week*7 <= (datetime.fromisoformat(d).date()-first).days < (week+1)*7)
        if len(days) >= 5:
            at = stamp(datetime.combine(datetime.fromisoformat(days[4]).date(), time(12), ZONE))
            badge(f'week_{week}', 250, at, 'Пять дней развития')
    level = min(100, xp_total(s, sid, eid) // 200)
    for reward in season['rewards'][:level]:
        for index, part in enumerate(reward['components']):
            source = f'{sid}:{reward["level"]}:{index}'
            if part['type'] == 'coins':
                coin(s, eid, sid, 'pass_level', source, part['coins'], now)
            elif part['type'] in ('mini', 'gift'):
                key = f'{eid}:{source}'
                s['entitlements'].setdefault(key, dict(id=key, employee_id=eid, season_id=sid,
                    level=reward['level'], component=index, name=part['name'], cap=part['budget_cap_kzt'],
                    pool_id=f'{sid}:{part["pool_code"]}', status='available', opened_at=stamp(now)))
            else:
                badge(part['cosmetic_code'], 0, stamp(now), part['name'])
    if level == 100:
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
            points = sum(x['amount'] for x in events)
            days = {game_date(instant(x['effective_at'])).isoformat() for x in events if x['source_type'] in ('daily', 'activity')}
            count = sum(x['source_type'] == 'activity' for x in events)
            rows.append(dict(employee_id=person, **snap, confirmed_xp=points, level=min(100, xp_total(s, sid, person)//200),
                             active_days=len(days), confirmed_activity_count=count,
                             badges=[b['name'] for b in s['badges'].values() if b['season_id'] == sid and b['employee_id'] == person],
                             title=None, prize_eligible=points >= 1000 and len(days) >= 5, prize_rank=None))
        rows.sort(key=lambda r: (-r['confirmed_xp'], -r['confirmed_activity_count'], -r['active_days'], r['employee_id']))
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
    level = min(100, xp//200)
    return dict(season=season_summary(season, eid), confirmed_xp=xp, level=level,
                xp_to_next=200-xp % 200 if level < 100 else 0, wallet_balance=wallet(s,eid)['balance'],
                pass_progress=min(1,xp/20000), rank=(leaderboard(s,season,eid)['self'] or {}).get('rank'),
                pending_xp=sum(r['xp_amount'] for r in s['reviews'].values() if r['season_id'] == season['id'] and r['employee_id'] == eid and r['status'] == 'pending'),
                current_streak=calendar['current_streak'], best_streak=calendar['best_streak'],
                freeze_remaining=calendar['freeze_remaining'], active_days=calendar['active_days'],
                next_reward=season['rewards'][level] if level < 100 else None,
                unclaimed_gifts_count=sum(e['employee_id'] == eid and e['status'] == 'available' for e in s['entitlements'].values()))


def daily_tasks(s, season, eid, now):
    participant(season, eid)
    date = game_date(now)
    if season['status'] != 'active':
        return dict(items=[], status=season['status'])
    rows = []
    for kind in ('main','bonus'):
        key = f'{season["id"]}:{eid}:{date}:{kind}'
        if key not in s['tasks']:
            variant = task_variant(s['task_secret'], season, eid, date, kind)
            s['tasks'][key] = dict(id=key, season_id=season['id'], employee_id=eid, kind=kind,
                title='Ежедневный шаг' if kind=='main' else 'Кейс дня',game_date=date.isoformat(), xp=100 if kind == 'main' else 150, attempts=0, status='available', **variant)
        task = s['tasks'][key]
        rows.append({k:v for k,v in task.items() if k not in ('expected_answer','explanation','employee_id')}
                    | {'attempts_remaining':3-task['attempts'], 'explanation':task['explanation'] if task['status'] != 'available' else None})
    week = (date-game_date(instant(season['starts_at']))).days//7
    start = game_date(instant(season['starts_at']))+timedelta(days=week*7)
    count = sum(start.isoformat() <= d < (start+timedelta(days=7)).isoformat() for d in confirmed_days(s,season['id'],eid))
    return dict(items=rows, weekly_days=count, weekly_required=5, weekly_xp=250,
                resets_at=stamp(datetime.combine(date+timedelta(days=1),time.min,ZONE)))


def award_result(s, season, eid, before_xp, before_coins, before_events, before_gifts, before_badges, now):
    total=xp_total(s,season['id'],eid)
    return dict(accepted=True,awarded_xp=total-before_xp,
        new_xp_events=[x for key,x in s['xp'].items() if key not in before_events],
        unlocked_levels=list(range(min(100,before_xp//200)+1,min(100,total//200)+1)),
        credited_coins=wallet(s,eid)['balance']-before_coins,
        new_entitlements=[key for key in s['entitlements'] if key not in before_gifts],
        badges=[b for key,b in s['badges'].items() if key not in before_badges],
        gamification=summary(s,season,eid,now))


def award_before(s,season,eid):
    return (xp_total(s,season['id'],eid),wallet(s,eid)['balance'],set(s['xp']),set(s['entitlements']),set(s['badges']))


def attempt(s, eid, tid, answer, now):
    task = own(s['tasks'],tid,eid)
    season = choose_season(s, task['season_id'], eid)
    require(task['game_date'] == game_date(now).isoformat() and season['status'] == 'active', 'TASK_EXPIRED','Это задание уже завершило свой игровой день')
    if task['status'] == 'completed':
        return dict(correct=True, attempts_remaining=3-task['attempts'], explanation=task['explanation'], already_completed=True, gamification=summary(s,season,eid,now))
    require(task['attempts'] < 3,'ATTEMPTS_EXHAUSTED','Все попытки использованы')
    before=award_before(s,season,eid)
    normalised = normalise_answer(task,answer)
    task['attempts'] += 1
    correct = normalised == task['expected_answer']
    if correct:
        task['status'] = 'completed'
        emit_xp(s,season,eid,'daily',tid,task['xp'],stamp(now),now)
        award_followups(s,season,eid,now)
    elif task['attempts'] == 3:
        task['status'] = 'failed'
    return dict(correct=correct, attempts_remaining=3-task['attempts'],
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
    require(count<2,'DAILY_REVIEW_LIMIT','Можно подать на награду не более двух активностей за день выполнения')
    key=uid('review_')
    s['reviews'][key] = dict(id=key,completion_id=cid,employee_id=eid,season_id=season['id'],status='pending',evidence_text=evidence,
        xp_amount=min(300,max(100,2*s['activities'][c['activity_id']]['duration_minutes'])),effective_at=c['completed_at'],submitted_at=stamp(now),decision_note=None)
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
        funds={sid:n*100 for sid,n in allocations.items()}
        cap=price*100
        coin(s,eid,next(iter(allocations)),'shop_order',key,-price,now,{sid:-n for sid,n in allocations.items()})
    item['reserved']+=1
    order=dict(id=key,employee_id=eid,payment_kind='pass_entitlement' if ent else 'coins',
               entitlement_id=entitlement_id,item_id=item['id'],item_snapshot=deepcopy(item_view(item)),
               coins_charged=price,budget_cap_kzt=cap,funding=funds,status='requested',requested_at=stamp(now),
               timeline=[{'status':'requested','at':stamp(now),'note':'Получение в HR-службе; тестовая выдача'}])
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
            allocations={sid:amount//100 for sid,amount in order['funding'].items()}
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
    # All buckets partition the original commitment; orders move, never duplicate, liabilities.
    issued=sum(sum(r['allocations'].values())*100 for r in s['ledger'].values()
               if r['season_id']==sid and r['source_type'] in ('pass_level','season_podium'))
    entitlements=[e for e in s['entitlements'].values() if e['season_id']==sid]
    earned=issued+sum(e['cap'] for e in entitlements)
    budget=season.get('committed_budget_kzt',len(season['roster'])*1200000+50000)
    # Finalization closes every XP source: unearned rewards and unused podium
    # reserves are released then; earned gifts remain claimable until closure.
    unearned=max(0,budget-earned) if season['status'] not in ('finalized','closed') else 0
    coins=sum(r['allocations'].get(sid,0)*100 for r in s['ledger'].values())
    liability=coins+sum(e['cap'] for e in entitlements if e['status']=='available')
    reserved=spent=0
    for order in s['orders'].values():
        amount=order['funding'].get(sid,0)
        if order['status'] in ('requested','approved','ready'):
            reserved+=amount
        elif order['status']=='delivered':
            spent+=order['actual_cost_kzt']*amount/order['budget_cap_kzt']
    released=budget-unearned-liability-reserved-spent
    return dict(virtual_budget_kzt=season['virtual_budget_kzt'],committed_budget_kzt=budget,
                unearned_reserved=unearned,earned_liability=liability,order_reserved=reserved,spent=round(spent,2),released=round(released,2),
                wallet_liability_kzt=coins,max_per_member_kzt=1200000,
                pending_orders=sum(o['status'] in ('requested','approved','ready') and sid in o['funding'] for o in s['orders'].values()),
                coins_issued=issued//100,
                pending_reviews=sum(r['season_id']==sid and r['status']=='pending' for r in s['reviews'].values()),
                confirmed_xp=sum(x['amount'] for x in s['xp'].values() if x['season_id']==sid))


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
    for index,row in enumerate(eligible[:3]):
        row['prize_rank']=index+1
        row['title']='Сотрудник сезона' if index==0 else ['','Серебряный призёр','Бронзовый призёр'][index]
        coin(s,row['employee_id'],sid,'season_podium',f'{sid}:{index}',[250,150,100][index],now)
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
    s['snapshots'][sid]=deepcopy(rows)
    season['status']='finalized'
    season['finalized_at']=stamp(now)


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
        if order['status']=='requested' and now>=instant(order['requested_at'])+timedelta(days=7):
            transition_order(s,order['id'],'cancelled','Срок обработки заявки истёк',None,now,order['employee_id'])
            changed=True
    if changed:
        s['audit'].append({'at':stamp(now),'actor':'system','action':'season_tick'})
    return changed
