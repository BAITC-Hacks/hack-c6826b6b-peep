"""Deterministic career model: assessment != estimate != season experience."""
from collections import Counter, defaultdict
from copy import deepcopy
from datetime import timedelta
from functools import cmp_to_key
import math

from .engine import require, Problem, stamp, instant, uid, own
from .policies import policy

GRADES = ['Junior', 'Middle', 'Senior', 'Lead']
FORMATS = ['online', 'offline', 'self_paced']
TIMEZONES = ['Asia/Almaty', 'Asia/Qyzylorda', 'UTC']


def goal(s, eid):
    e = s['employees'][eid]
    effective = s['goals'].get(eid) or e['source_goal']
    suggestion = None
    if not effective:
        grades=[r['grade_id'] for r in sorted(s['roles'].values(),key=lambda r:r.get('rank',GRADES.index(r['grade_id']) if r['grade_id'] in GRADES else 99)) if r['role_id']==e['role'] and r.get('active',True)]
        for grade in grades[grades.index(e['grade'])+1:] if e['grade'] in grades else []:
            if e['role'] + '|' + grade in s['roles']:
                suggestion = dict(target_role=e['role'], target_grade=grade)
                break
    return {'goal': effective, 'suggested_goal': suggestion,
            'goal_source': 'personal' if eid in s['goals'] else 'dataset' if effective else 'suggested' if suggestion else 'none'}


def preferences(s, eid):
    return s['preferences'].get(eid, {'weekly_minutes': 120, 'preferred_formats': FORMATS, 'timezone': policy(s,'settings')['timezone']})


def target(s, g):
    role=deepcopy(s['roles'].get(g['target_role'] + '|' + g['target_grade'])) if g else None
    if role and policy(s,'recommendations')['strategy']=='unweighted_coverage':
        for r in role['requirements'].values(): r['weight']=1
    return role


def apply_gains(levels, gains):
    result = dict(levels)
    for sid, gain in gains.items():
        if result.get(sid) is not None:
            result[sid] = min(100, result[sid] + gain)
    return result


def readiness(levels, requirements):
    if not requirements or any(levels.get(k) is None for k in requirements):
        return None
    return 100 * sum(v['weight'] * min(levels[k], v['level']) / v['level'] for k, v in requirements.items()) / sum(v['weight'] for v in requirements.values())


def levels(s, eid):
    e = s['employees'][eid]
    result = dict(e['skills'])
    for c in sorted(s['completions'].values(), key=lambda c: (c['completed_at'], c['id'])):
        if c['employee_id'] == eid:
            gains={k:v for k,v in c['gains'].items() if instant(c['completed_at']) >
                   instant(e.get('skill_assessed_at',{}).get(k,e['assessment_at']))}
            result = apply_gains(result, gains)
    return result


def progress(s, eid, chosen_goal=None, extra_ids=(), extra_activities=()):
    g = chosen_goal if chosen_goal is not None else goal(s, eid)['goal']
    role = target(s, g)
    req = role['requirements'] if role else {}
    base = s['employees'][eid]['skills']
    estimated = levels(s, eid)
    for aid in extra_ids:
        estimated = apply_gains(estimated, s['activities'][aid]['gains'])
    for activity in extra_activities:
        estimated = apply_gains(estimated, activity['gains'])
    coverage = 100 * sum(base.get(k) is not None for k in req) / len(req) if req else None
    a, b = readiness(base, req), readiness(estimated, req)
    rows = []
    for sid in set(base) | set(req):
        r = req.get(sid)
        val = estimated.get(sid)
        contributions=[]
        running=base.get(sid)
        for c in sorted(s['completions'].values(),key=lambda c:(c['completed_at'],c['id'])):
            if c['employee_id']!=eid or not c['gains'].get(sid) or instant(c['completed_at'])<=instant(s['employees'][eid].get('skill_assessed_at',{}).get(sid,s['employees'][eid]['assessment_at'])):
                continue
            raw=c['gains'][sid]
            effective=min(raw,100-running) if running is not None else None
            if running is not None: running+=effective
            contributions.append(dict(activity_id=c['activity_id'],title=c.get('activity_snapshot',s['activities'][c['activity_id']])['title'],
                gain=raw,effective_gain=effective,completed_at=c['completed_at'],source='self_report'))
        rows.append(dict(skill_id=sid, name=s['skills'][sid]['name'], assessed_level=base.get(sid),
                         estimated_level=val, required_level=r['level'] if r else None,
                         weight=r['weight'] if r else None,
                         gap=max(0, r['level'] - val) if r and val is not None else None,
                         contributions=contributions))
    rows.sort(key=lambda r: (r['assessed_level'] is not None,
                            -(r['weight'] or 0) * (r['gap'] or 0) / (r['required_level'] or 1), r['skill_id']))
    return dict(goal=g, status='no_goal' if not req else 'needs_assessment' if coverage < 100 else 'ready',
                coverage=coverage, assessed_readiness=round(a, 4) if a is not None else None,
                estimated_readiness=round(b, 4) if b is not None else None, skills=rows,
                assessment_at=s['employees'][eid]['assessment_at'],
                missing_skill_ids=[k for k in req if base.get(k) is None])


def active_plan(s, eid):
    return sorted([p for p in s['plan'].values() if p['employee_id'] == eid and p['status'] in ('planned', 'in_progress')],
                  key=lambda p: (p['position'], p['id']))


def blocked(s, eid, a, now, action='add', item=None):
    if not a['active']:
        return 'ACTIVITY_UNAVAILABLE'
    if any(s['employees'][eid]['skills'].get(k) is None or s['employees'][eid]['skills'][k] < v for k, v in a['prerequisites'].items()):
        return 'PREREQUISITE_NOT_MET'
    if action == 'add':
        external = [h['status'] for h in s['imported_history'] if h['employee_id'] == eid and h['activity_id'] == a['id']]
        if 'completed' in external:
            return 'ALREADY_IMPORTED_COMPLETE'
        if any(x in external for x in ('registered', 'in_progress', 'attended')):
            return 'EXTERNAL_ACTIVITY_IN_PROGRESS'
        if any(c['employee_id'] == eid and c['activity_id'] == a['id'] for c in s['completions'].values()):
            return 'ALREADY_COMPLETED'
        if a['available_from'] and instant(a['available_from']) > now:
            return 'ACTIVITY_UNAVAILABLE'
    if a['kind'] == 'scheduled':
        start, end = instant(a['starts_at']), instant(a['ends_at'])
        if action == 'add' and (start <= now or (a['available_until'] and instant(a['available_until']) <= now)):
            return 'ACTIVITY_UNAVAILABLE'
        if action == 'start' and not start <= now < end:
            return 'OUTSIDE_START_WINDOW'
        if action == 'complete' and not end <= now <= end + timedelta(days=7):
            return 'OUTSIDE_COMPLETION_WINDOW'
        if action == 'forecast' and (now > end + timedelta(days=7) or (now >= end and item and item['status'] == 'planned')):
            return 'ACTIVITY_EXPIRED'
    elif action in ('add', 'start') or (action == 'forecast' and item and item['status'] == 'planned'):
        if a['available_until'] and instant(a['available_until']) <= now:
            return 'ACTIVITY_EXPIRED'
    return None


def overlaps(a, b):
    return a['kind'] == b['kind'] == 'scheduled' and instant(a['starts_at']) < instant(b['ends_at']) and instant(b['starts_at']) < instant(a['ends_at'])


def plan(s, eid, now):
    items = active_plan(s, eid)
    rows = [{**p, 'activity': p.get('activity_snapshot',s['activities'][p['activity_id']]),
             'blocked_reason': blocked(s, eid, p.get('activity_snapshot',s['activities'][p['activity_id']]), now, 'forecast', p)} for p in items]
    minutes = sum(p['activity']['duration_minutes'] for p in rows)
    forecast_activities = [p['activity'] for p in rows if not p['blocked_reason']]
    return dict(items=rows, total_minutes=minutes, max_steps=policy(s,'recommendations')['max_steps'],
                estimated_weeks=math.ceil(minutes / preferences(s, eid)['weekly_minutes']),
                forecast=progress(s, eid, extra_activities=forecast_activities),
                archived_count=sum(p['employee_id'] == eid and p['status'] == 'archived' for p in s['plan'].values()))


def recommendations(s, eid, now):
    rules=policy(s,'recommendations')
    p = progress(s, eid)
    result = dict(items=[], empty_reason=None, diagnostics={}, progress=p)
    if p['status'] != 'ready':
        return {**result, 'empty_reason': p['status']}
    current = levels(s, eid)
    req = target(s, p['goal'])['requirements']
    if readiness(current, req) >= 100:
        return {**result, 'empty_reason': 'goal_covered'}
    items = active_plan(s, eid)
    if len(items) >= rules['max_steps']:
        return {**result, 'empty_reason': 'plan_full'}
    future = dict(current)
    for item in items:
        a = s['activities'][item['activity_id']]
        if not blocked(s, eid, a, now, 'forecast', item):
            future = apply_gains(future, a['gains'])
    if readiness(future, req) >= 100:
        return {**result, 'empty_reason': 'plan_covers_goal'}
    prefs = preferences(s, eid)
    budget = prefs['weekly_minutes'] * rules['budget_weeks'] - sum(s['activities'][i['activity_id']]['duration_minutes'] for i in items)
    reserved = [s['activities'][p['activity_id']] for p in items]
    hidden = s['exclusions'].get(eid, {}).get(p['goal']['target_role'] + '|' + p['goal']['target_grade'], {})
    diagnostics = Counter()
    chosen = []
    def compare(a, b):
        if abs(a['score'] - b['score']) > 1e-9:
            return -1 if a['score'] > b['score'] else 1
        left=(-a['sequence_delta_pp'], a['activity']['duration_minutes'], a['activity']['id'])
        right=(-b['sequence_delta_pp'], b['activity']['duration_minutes'], b['activity']['id'])
        return (left>right)-(left<right)
    while len(chosen) < rules['max_steps'] - len(items) and readiness(future, req) < 100:
        candidates = []
        for a in s['activities'].values():
            reason = blocked(s, eid, a, now)
            if a['id'] in [x['id'] for x in reserved]:
                reason = 'in_plan'
            if not reason and a['kind'] == 'scheduled' and instant(a['starts_at']) > now + timedelta(days=rules['horizon_days']):
                reason = 'outside_horizon'
            if not reason and any(overlaps(a, b) for b in reserved):
                reason = 'schedule_conflict'
            delta = readiness(apply_gains(future, a['gains']), req) - readiness(future, req)
            if not reason and delta <= 1e-9:
                reason = 'no_gain'
            if not reason and a['duration_minutes'] > budget:
                reason = 'no_time_fit'
            if not reason and a['id'] in hidden:
                reason = 'hidden'
            if reason:
                diagnostics[reason] += 1
                continue
            score = 100 * (rules['utility_weight'] * delta / (100 - readiness(future, req)) + rules['duration_weight'] * min(1, 60 / a['duration_minutes']) + rules['format_weight'] * (a['format'] in prefs['preferred_formats']))
            standalone = readiness(apply_gains(current, a['gains']), req) - readiness(current, req)
            candidates.append(dict(activity=a, score=score, standalone_delta_pp=standalone,
                                   sequence_delta_pp=delta, reasons=[f'Закрывает дефициты цели: {p["goal"]["target_role"]} {p["goal"]["target_grade"]}',
                                   f'Время: {a["duration_minutes"]} мин. В пределах бюджета {rules["budget_weeks"]} недель.']))
        if not candidates:
            break
        item = sorted(candidates, key=cmp_to_key(compare))[0]
        chosen.append(item)
        a = item['activity']
        future = apply_gains(future, a['gains'])
        budget -= a['duration_minutes']
        reserved.append(a)
    empty = None if chosen else 'no_time_fit' if diagnostics['no_time_fit'] else 'all_candidates_hidden' if diagnostics['hidden'] else 'no_available_activities'
    return {**result, 'items': chosen, 'empty_reason': empty, 'diagnostics': dict(diagnostics),
            'forecast_readiness': round(readiness(future, req), 4)}


def set_goal(s, eid, value, now, confirm=False):
    if value:
        require(target(s, value) and target(s, value)['requirements'], 'INVALID_GOAL', 'Выберите роль и грейд из справочника', 422)
    old = goal(s, eid)['goal']
    new = value or s['employees'][eid]['source_goal']
    active = active_plan(s, eid)
    if old != new and active:
        require(confirm, 'CONFIRMATION_REQUIRED', 'Смена цели архивирует текущий план', item_ids=[p['id'] for p in active])
        for p in active:
            p.update(status='archived', archive_reason='goal_changed', archived_at=stamp(now))
    if value:
        s['goals'][eid] = value
    else:
        s['goals'].pop(eid, None)
    return goal(s, eid)


def check_add(s, eid, aid, now, body, ignore_id=None, existing=None):
    a = s['activities'].get(aid)
    require(a, 'NOT_FOUND', 'Активность не найдена', 404)
    reason = blocked(s, eid, a, now, 'forecast' if existing else 'add', existing)
    require(not reason, reason or '', 'Активность сейчас недоступна: ' + (reason or ''))
    others = [p for p in active_plan(s, eid) if p['id'] != ignore_id]
    require(len(others) < policy(s,'recommendations')['max_steps'], 'PLAN_LIMIT_REACHED', 'Достигнут лимит активных шагов плана')
    require(not any(p['activity_id'] == aid for p in others), 'DUPLICATE_PLAN_ITEM', 'Активность уже в плане')
    require(not any(overlaps(a, s['activities'][p['activity_id']]) for p in others), 'SCHEDULE_CONFLICT', 'Время пересекается с другим шагом')
    total = a['duration_minutes'] + sum(s['activities'][p['activity_id']]['duration_minutes'] for p in others)
    require(total <= preferences(s, eid)['weekly_minutes'] * policy(s,'recommendations')['budget_weeks'] or body.get('accept_over_budget'), 'OVER_BUDGET', 'План превышает бюджет времени. Подтвердите увеличение нагрузки.')
    req = (target(s, goal(s, eid)['goal']) or {}).get('requirements', {})
    before, after = readiness(levels(s, eid), req), readiness(apply_gains(levels(s, eid), a['gains']), req)
    require((before is not None and after > before) or body.get('accept_no_goal_gain'), 'NO_GOAL_GAIN', 'Шаг не даёт измеримого вклада в текущую цель. Добавить осознанно?')
    return a


def add_plan(s, eid, body, now, replace_id=None):
    old = own(s['plan'], replace_id, eid) if replace_id else None
    if old:
        require(old['status'] in ('planned', 'in_progress'), 'INVALID_TRANSITION', 'Этот шаг уже закрыт')
    a = check_add(s, eid, body['activity_id'], now, body, ignore_id=replace_id)
    position = old['position'] if old else max([p['position'] for p in active_plan(s, eid)], default=0) + 1
    if old:
        old.update(status='archived', archive_reason='replaced', archived_at=stamp(now))
    key = uid('plan_')
    s['plan'][key] = dict(id=key, employee_id=eid, activity_id=a['id'], position=position,
                          status='planned', goal=goal(s, eid)['goal'], created_at=stamp(now), started_at=None,
                          activity_snapshot=deepcopy(a),activity_version=a.get('version',1),formula_version=s.get('config_version',1))
    return plan(s, eid, now)


def transition(s, eid, pid, action, body, now):
    p = own(s['plan'], pid, eid)
    if action == 'complete':
        prior = next((c for c in s['completions'].values() if c['employee_id'] == eid and c['activity_id'] == p['activity_id']), None)
        if prior:
            return {'completion': prior, 'already_completed': True, 'progress': progress(s, eid)}
    if action == 'archive':
        require(p['status'] in ('planned', 'in_progress'), 'INVALID_TRANSITION', 'Шаг уже закрыт')
        p.update(status='archived', archive_reason='removed', archived_at=stamp(now))
        return plan(s, eid, now)
    if action == 'start' and p['status'] == 'in_progress':
        return p
    require(p['status'] == ('planned' if action == 'start' else 'in_progress'), 'INVALID_TRANSITION', 'Недопустимый переход статуса')
    a = p.get('activity_snapshot',s['activities'][p['activity_id']])
    reason = blocked(s, eid, a, now, action, p)
    require(not reason, reason or '', 'Действие недоступно: ' + (reason or ''))
    if action == 'start':
        p.update(status='in_progress', started_at=stamp(now))
        return p
    require(body.get('confirmed') is True, 'CONFIRMATION_REQUIRED', 'Подтвердите выполнение', 422)
    before = progress(s, eid)
    key = uid('completion_')
    c = dict(id=key, employee_id=eid, activity_id=a['id'], completed_at=stamp(now),
             started_at=p['started_at'], gains=deepcopy(a['gains']), note=body.get('note'), source='self_report',
             activity_snapshot=deepcopy(a),activity_version=p.get('activity_version',1))
    s['completions'][key] = c
    p.update(status='completed', completion_id=key)
    return dict(completion=c, before=before, progress=progress(s, eid), already_completed=False,
                reward_status='not_submitted', pending_xp=0)


def history(s, eid):
    merged = {}
    for h in s['imported_history']:
        if h['employee_id'] != eid:
            continue
        aid = h['activity_id']
        row = merged.setdefault(aid, {'activity_id': aid, 'sources': [], 'status': h['status']})
        row['sources'].append(h)
        for field in ('completed_at', 'started_at', 'registered_at', 'attended_at'):
            if h.get(field):
                row[field] = max(h[field], row.get(field) or h[field])
        if h['status'] == 'completed':
            row['status'] = 'completed'
    for c in s['completions'].values():
        if c['employee_id'] != eid:
            continue
        row = merged.setdefault(c['activity_id'], {'activity_id': c['activity_id'], 'sources': []})
        row['sources'].append({**c, 'origin': 'self_report'})
        row['status'] = 'completed'
        row['completion_id'] = c['id']
        row['note'] = c['note']
        for field in ('completed_at', 'started_at'):
            if not row.get(field):
                row[field] = c.get(field)
    for p in active_plan(s, eid):
        if p['status'] == 'in_progress' and p['activity_id'] not in merged:
            merged[p['activity_id']] = {'activity_id': p['activity_id'], 'status': 'in_progress',
                'started_at': p['started_at'], 'sources': [{**p, 'origin': 'self_report'}]}
    return sorted([{**h, 'activity': s['activities'][aid]} for aid, h in merged.items()],
                  key=lambda h: (h.get('completed_at') or h.get('started_at') or '', h['activity_id']), reverse=True)


def simulate(s, eid, body, now):
    ids = body['activity_ids']
    require(len(ids) <= policy(s,'recommendations')['max_steps'] and len(ids) == len(set(ids)), 'INVALID_SELECTION', 'Превышен лимит шагов или есть повторения', 422)
    chosen = {'target_role': body['role_id'], 'target_grade': body['grade_id']}
    require(target(s, chosen), 'INVALID_GOAL', 'Цель не найдена', 422)
    # Validate the candidate plan independently; retain the statuses of selected current items.
    temp = deepcopy(s)
    existing = {p['activity_id']: deepcopy(p) for p in active_plan(s, eid)}
    for p in active_plan(temp, eid):
        p['status'] = 'archived'
    temp['goals'][eid] = chosen
    for i, aid in enumerate(ids):
        check_add(temp, eid, aid, now, {'accept_over_budget': True, 'accept_no_goal_gain': True}, existing=existing.get(aid))
        p = existing.get(aid) or dict(id=uid('plan_'), employee_id=eid, activity_id=aid, status='planned', started_at=None, created_at=stamp(now))
        temp['plan'][p['id']] = {**p, 'goal': chosen, 'position': i}
    total = sum(s['activities'][aid]['duration_minutes'] for aid in ids)
    result = dict(id=uid('sim_'), employee_id=eid, goal=chosen, activity_ids=ids,
                  before=progress(s, eid, chosen), after=progress(s, eid, chosen, ids),
                  total_minutes=total, estimated_weeks=math.ceil(total / preferences(s, eid)['weekly_minutes']),
                  over_budget=total > policy(s,'recommendations')['budget_weeks'] * preferences(s, eid)['weekly_minutes'],
                  revision=s['revision']+1, expires_at=stamp(now + timedelta(minutes=15)),
                  items=active_plan(temp, eid))
    s['simulations'] = {k: v for k, v in s['simulations'].items() if instant(v['expires_at']) > now}
    s['simulations'][result['id']] = result
    return result


def apply_simulation(s, eid, sid, body, now):
    sim = own(s['simulations'], sid, eid)
    require(instant(sim['expires_at']) > now, 'PREVIEW_EXPIRED', 'Расчёт устарел. Запустите симуляцию снова.', 410)
    require(sim['revision'] == s['revision'], 'STALE_STATE', 'Данные изменились. Рассчитайте план снова.')
    require(body.get('confirm_replace_plan'), 'CONFIRMATION_REQUIRED', 'Подтвердите замену текущего плана')
    require(not sim['over_budget'] or body.get('accept_over_budget'), 'OVER_BUDGET', 'Подтвердите превышение бюджета времени')
    checked = simulate(s, eid, {'role_id': sim['goal']['target_role'], 'grade_id': sim['goal']['target_grade'], 'activity_ids': sim['activity_ids']}, now)
    selected = {p['id'] for p in checked['items']}
    for p in active_plan(s, eid):
        if p['id'] not in selected:
            p.update(status='archived', archive_reason='simulation_replaced', archived_at=stamp(now))
    for p in checked['items']:
        s['plan'][p['id']] = p
    s['goals'][eid] = sim['goal']
    return {'goal': goal(s, eid), 'plan': plan(s, eid, now)}
