"""Administration calls the same career/game services inside the Engine transaction."""
from copy import deepcopy
from datetime import timedelta
import hashlib
import json

from . import career, game
from .database import encode
from .engine import require, Problem, stamp, instant, uid
from .policies import policy, pass_totals, level_for
from .permissions import PERMISSIONS

DOMAIN_PERMISSION = {
    'employees':'employees.manage', 'departments':'employees.manage', 'skills':'reference.manage',
    'career-roles':'reference.manage', 'activities':'learning.manage', 'recommendations':'recommendations.manage',
    'economy':'economy.manage', 'pass':'pass.manage', 'streaks':'streaks.manage',
    'achievements':'achievements.manage', 'leaderboards':'leaderboards.manage', 'shop':'shop.manage',
    'reward-pools':'shop.manage', 'branding':'branding.manage', 'content':'content.manage',
    'assistant':'ai.manage', 'settings':'settings.manage', 'season-publication':'seasons.publish',
    'quests':'quests.manage','nominations':'leaderboards.manage',
    'season-edit':'seasons.manage','season-members':'seasons.manage',
}
COLLECTIONS = {'employees':'employees','departments':'departments','skills':'skills','career-roles':'roles',
               'activities':'activities','shop':'items','reward-pools':'pools'}


def check(user, permission):
    require(permission in user.get('capabilities', []), 'FORBIDDEN', 'Недостаточно прав для этого раздела', 403)


def fresh_user(database, db, user, permission):
    row=db.execute('SELECT * FROM accounts WHERE username=? AND active=1', (user['username'],)).fetchone()
    require(row, 'UNAUTHORIZED', 'Аккаунт недоступен', 401)
    actual=database.public_user(row, db)
    check(actual, permission)
    return actual


def redact(value):
    if isinstance(value, dict):
        return {k:redact(v) for k,v in value.items() if not any(x in k.lower() for x in
                ('password','salt','token','secret','expected_answer','evidence_text','correct_answer'))}
    if isinstance(value, list): return [redact(v) for v in value]
    return value


def audit(db, user, operation, entity_id, before, after, reason, now, request_id=''):
    db.execute('INSERT INTO admin_audit VALUES (?,?,?,?,?,?,?,?,?,?)',
               (uid('audit_'),user['username'],user['role'],operation,entity_id,encode(redact(before)),
                encode(redact(after)),reason,stamp(now),request_id))


def current(s, domain, target='global'):
    if domain in COLLECTIONS:
        return deepcopy(s[COLLECTIONS[domain]].get(target, {}))
    if domain=='pass': return dict(rewards=deepcopy(game.choose_season(s,target)['rewards']))
    if domain=='season-publication': return game.season_summary(game.choose_season(s,target))
    if domain=='season-edit':return {k:game.choose_season(s,target)[k] for k in ('name','starts_at','ends_at')}
    if domain=='season-members':return dict(employee_ids=list(game.choose_season(s,target)['roster']))
    return deepcopy(policy(s,domain,s['seasons'].get(target)))


def require_budget(season):
    totals=pass_totals(season)
    require(totals['total_kzt']<=season['virtual_budget_kzt'], 'INSUFFICIENT_BUDGET',
            f"Нужен резерв {totals['total_kzt']:,} ₸; доступно {season['virtual_budget_kzt']:,} ₸",
            required_kzt=totals['total_kzt'], available_kzt=season['virtual_budget_kzt'])
    if season['status']!='draft':
        season['committed_budget_kzt']=max(season.get('committed_budget_kzt',0),totals['total_kzt'])


def apply_payload(s, domain, target, payload, now, change_id):
    old=current(s,domain,target)
    value=deepcopy(payload)
    if domain in COLLECTIONS:
        collection=s[COLLECTIONS[domain]]
        identity=value.get('id',value.get('skill_id',value.get('role_id','')+'|'+value.get('grade_id','')))
        require(identity==target, 'INVALID_ID', 'ID формы и адреса должны совпадать', 422)
        if domain=='departments':
            parent=value['parent_id']; seen={target}
            while parent:
                require(parent in s['departments'] and parent not in seen, 'DEPARTMENT_CYCLE', 'Родитель не найден или образует цикл',422)
                seen.add(parent); parent=s['departments'][parent]['parent_id']
            if old and old['name']!=value['name']:
                for employee in s['employees'].values():
                    if employee['department']==old['name']: employee['department']=value['name']
        if domain=='employees':
            require(value['role']+'|'+value['grade'] in s['roles'], 'INVALID_ROLE','Выберите существующую роль и грейд',422)
            require(any(d['name']==value['department'] and d['active'] for d in s['departments'].values()),
                    'INVALID_DEPARTMENT','Выберите активное подразделение',422)
            value={**dict(employee_id=target, skills={}, source_goal=None, assessment_at=stamp(now),
                         source_skills={}, source_scale=[0,100]), **old, **value}
        if domain=='skills' and not value['active']:
            require(not any(target in r['requirements'] for r in s['roles'].values()),
                    'REFERENCED_ENTITY','Навык используется в требованиях; сначала измените матрицу',422)
        if domain=='career-roles':
            require(all(k in s['skills'] for k in value['requirements']), 'INVALID_SKILL','Неизвестный навык в матрице',422)
        if domain=='activities':
            require(all(k in s['skills'] for k in value['gains']|value['prerequisites']), 'INVALID_SKILL','Неизвестный навык активности',422)
        if domain=='shop':
            require(not value['shop_visible'] or value['coin_price'] is not None and
                    value['unit_budget_kzt']<=value['coin_price']*policy(s,'economy')['coin_backing'],
                    'INVALID_BUDGET','Цена CQ должна покрывать бюджет товара',422)
            value={**dict(stock_total=0,reserved=0,delivered=0,image_asset=value['category']),**old,**value}
            if old.get('protected_pool'):
                require(value['active'] and value['unit_budget_kzt']<=old['unit_budget_kzt'],
                        'GUARANTEED_REWARD','Нельзя ухудшить гарантированный запасной подарок')
        if domain=='reward-pools':
            require(value['season_id'] in s['seasons'], 'NOT_FOUND','Сезон не найден',404)
            require(value['fallback_item_id'] in value['item_ids'] and all(i in s['items'] and
                    s['items'][i]['unit_budget_kzt']<=value['cap'] for i in value['item_ids']),
                    'INVALID_POOL','Проверьте товары, запасной вариант и лимит',422)
            if old and s['seasons'][value['season_id']]['status']!='draft':
                require(set(old['item_ids'])<=set(value['item_ids']) and value['cap']>=old['cap'] and
                        value['fallback_item_id']==old['fallback_item_id'], 'PROMISED_REWARD','Обещанный выбор сохраняется')
        value['version']=old.get('version',0)+1
        value['updated_at']=stamp(now)
        collection[target]=value
        return value
    if domain=='season-publication':
        return game.publish(s,game.choose_season(s,target),now)
    if domain=='season-edit':
        se=game.choose_season(s,target);start,end=instant(value['starts_at']),instant(value['ends_at'])
        require(start.tzinfo and end.tzinfo and start<end,'INVALID_DATES','Проверьте даты с часовыми поясами',422)
        require(start.astimezone(game.ZONE).hour==0 and start.minute==0 and start.second==0,'INVALID_START','Начало сезона — полночь Asia/Almaty',422)
        require(se['status'] in ('draft','scheduled','active'),'SEASON_LOCKED','Сезон завершён')
        if se['status']=='active':require(stamp(start)==se['starts_at'] and end>=instant(se['ends_at']),'PROMISED_INTERVAL','Активный сезон можно только продлить')
        if se['status']=='scheduled':require(start>now,'INVALID_START','Новая дата должна быть в будущем',422)
        if se['status']!='draft':
            for other in s['seasons'].values():
                if other['id']!=target and other['status']!='draft':
                    require(not(start<instant(other['ends_at']) and instant(other['starts_at'])<end),'SEASON_OVERLAP','Периоды сезонов пересекаются')
        require(timedelta(days=1)<=end-start<=timedelta(days=366) and (end-start).seconds==0,'INVALID_DURATION','От 1 до 366 полных дней',422)
        rules=policy(s,'economy',se)
        se.update(name=value['name'],starts_at=stamp(start),ends_at=stamp(end),review_deadline=stamp(end+timedelta(days=rules['review_days'])),claim_deadline=stamp(end+timedelta(days=rules['claim_days'])))
        rules['season_days']=(end-start).days
        return value
    if domain=='season-members':
        se=game.choose_season(s,target);ids=set(value['employee_ids'])
        require(ids and len(ids)==len(value['employee_ids']) and ids<=set(s['employees']),'INVALID_ROSTER','Проверьте участников и повторы',422)
        require(se['status'] in ('draft','scheduled','active'),'SEASON_LOCKED','Сезон завершён')
        if se['status']!='draft':require(set(se['roster'])<=ids,'PROMISED_REWARD','Участники опубликованного сезона сохраняются')
        se['roster']={eid:se['roster'].get(eid,dict(display_name=s['employees'][eid]['full_name'],department=s['employees'][eid]['department'],joined_at=stamp(now))) for eid in sorted(ids)}
        require_budget(se);game.make_pools(s,se)
        return dict(employee_ids=sorted(ids),totals=pass_totals(se))
    if domain=='pass':
        season=game.choose_season(s,target)
        require(season['status'] not in ('settling','finalized','closed'),'SEASON_LOCKED','Сезон уже завершён')
        if season['status']!='draft':
            require(len(value['rewards'])>=len(season['rewards']), 'PROMISED_REWARD','Сокращение пропуска доступно следующему сезону')
            for before,after in zip(season['rewards'],value['rewards']):
                require(after['required_total_xp']<=before['required_total_xp'], 'PROMISED_REWARD','Порог XP текущего сезона нельзя повышать')
                require(len(after['components'])>=len(before['components']), 'PROMISED_REWARD','Компоненты обещанной награды сохраняются')
                for a,b in zip(before['components'],after['components']):
                    require(a['type']==b['type'] and b.get('coins',0)>=a.get('coins',0) and
                            b.get('budget_cap_kzt',0)>=a.get('budget_cap_kzt',0) and
                            a.get('pool_code')==b.get('pool_code') and a.get('cosmetic_code')==b.get('cosmetic_code'),
                            'PROMISED_REWARD','Ухудшение награды или замена её источника доступна следующему сезону')
        season['rewards']=value['rewards']
        require_budget(season)
        game.make_pools(s,season)
        season['policy_version']=season.get('policy_version',1)+1
        if season['status']!='draft':
            for eid in season['roster']: game.award_followups(s,season,eid,now)
        return value
    season=s['seasons'].get(target)
    if target!='global': require(season,'NOT_FOUND','Сезон не найден',404)
    if season:
        require(domain in ('economy','streaks','leaderboards','achievements','quests','nominations'), 'INVALID_SCOPE','Эта настройка глобальная',422)
        require(season['status'] not in ('settling','finalized','closed'),'SEASON_LOCKED','Для итогов нужна корректировка')
        if domain=='economy' and season['status']!='draft':
            for field in ('coin_backing','season_days','review_days','claim_days'):
                require(value[field]==old[field], 'FUTURE_SEASON_REQUIRED','Календарь и обеспечение меняются для будущего сезона')
        season.setdefault('policies',{})[domain]=value
        require_budget(season)
        season['policy_version']=season.get('policy_version',1)+1
        if domain=='economy' and season['status']=='draft':
            end=instant(season['starts_at'])+timedelta(days=value['season_days'])
            season.update(ends_at=stamp(end),review_deadline=stamp(end+timedelta(days=value['review_days'])),
                          claim_deadline=stamp(end+timedelta(days=value['claim_days'])))
    else:
        s['policies'][domain]=value
    return value


def draft(db,s,user,domain,target,payload,reason,now,change_id=None):
    if change_id:
        row=db.execute('SELECT * FROM change_sets WHERE id=?',(change_id,)).fetchone()
        require(row and row['status']!='published','CHANGE_LOCKED','Изменение уже опубликовано или не найдено')
        require(row['domain']==domain and row['target_id']==target,'INVALID_TARGET','Область изменения закреплена',422)
        db.execute("UPDATE change_sets SET payload=?,draft_version=draft_version+1,status='draft',reason=?,actor=? WHERE id=?",
                   (encode(payload),reason,user['username'],change_id))
    else:
        change_id=uid('change_')
        db.execute('INSERT INTO change_sets VALUES (?,?,?,?,?,?,?,?,?)',
                   (change_id,domain,target,encode(payload),1,'draft',user['username'],reason,stamp(now)))
    return get_change(db,change_id)


def get_change(db,key):
    row=db.execute('SELECT * FROM change_sets WHERE id=?',(key,)).fetchone()
    require(row,'NOT_FOUND','Черновик не найден',404)
    result=dict(row); result['payload']=json.loads(result['payload'])
    return result


def totals(s):
    return dict(xp=sum(game.xp_total(s,sid,eid) for sid,se in s['seasons'].items() for eid in se['roster']),
                coins=sum(r['amount'] for r in s['ledger'].values()),
                budget_kzt=sum(se.get('committed_budget_kzt',pass_totals(se)['total_kzt']) for se in s['seasons'].values()),
                gifts=len(s['entitlements']))


def preview(db,s,user,key,now):
    change=get_change(db,key); check(user,DOMAIN_PERMISSION[change['domain']])
    require(change['status']!='published','CHANGE_LOCKED','Изменение уже опубликовано')
    trial=deepcopy(s); errors=[]; before=totals(s)
    try:
        apply_payload(trial,change['domain'],change['target_id'],change['payload'],now,key)
    except Problem as exc:
        errors.append(dict(code=exc.code,message=exc.message,details=exc.details))
    after=totals(trial) if not errors else before
    comparisons=[]
    if change['domain'] in ('career-roles','recommendations','skills') and not errors:
        for eid in s['employees']:
            old=career.progress(s,eid); new=career.progress(trial,eid)
            if old!=new: comparisons.append(dict(employee_id=eid,before=old['estimated_readiness'],after=new['estimated_readiness']))
    result=dict(preview_id=uid('preview_'),change_id=key,draft_version=change['draft_version'],
                base_revision=s['revision']+1,expires_at=stamp(now+timedelta(minutes=policy(s,'settings')['preview_minutes'])),
                totals_before=before,totals_after=after,budget_delta_kzt=after['budget_kzt']-before['budget_kzt'],
                coin_delta=after['coins']-before['coins'],xp_delta=after['xp']-before['xp'],
                affected=dict(employees=len(comparisons),orders=0,assignments=0),
                comparisons=comparisons,blocking_errors=errors,warnings=[],can_publish=not errors,
                before=redact(current(s,change['domain'],change['target_id'])),after=redact(change['payload']))
    if change['domain'] in ('pass','season-members','season-publication'): result['pass_totals']=pass_totals(trial['seasons'][change['target_id']])
    digest=hashlib.sha256(encode(change['payload']).encode()).hexdigest()
    db.execute('INSERT INTO change_previews VALUES (?,?,?,?,?,?,?,?)',
               (result['preview_id'],key,user['username'],change['draft_version'],digest,result['base_revision'],result['expires_at'],encode(result)))
    db.execute("UPDATE change_sets SET status='previewed' WHERE id=?",(key,))
    return result


def publish_change(db,s,user,key,body,now,request_id):
    change=get_change(db,key); check(user,DOMAIN_PERMISSION[change['domain']])
    if change['domain'] in ('pass','economy','leaderboards','achievements','nominations'): check(user,'economy.publish')
    row=db.execute('SELECT * FROM change_previews WHERE id=? AND change_id=?',(body['preview_id'],key)).fetchone()
    require(row and row['actor']==user['username'], 'INVALID_PREVIEW','Создайте собственный предпросмотр')
    require(change['status']=='previewed' and row['draft_version']==change['draft_version'] and
            row['payload_hash']==hashlib.sha256(encode(change['payload']).encode()).hexdigest() and
            row['base_revision']==s['revision'] and instant(row['expires_at'])>now,
            'STALE_PREVIEW','Данные изменились или срок истёк. Пересчитайте последствия.')
    require(json.loads(row['result'])['can_publish'], 'INVALID_CHANGE','Исправьте ошибки предпросмотра')
    before=current(s,change['domain'],change['target_id'])
    result=apply_payload(s,change['domain'],change['target_id'],change['payload'],now,key)
    if change['domain'] in ('season-members','season-publication'):
        for row in db.execute("SELECT employee_id FROM accounts WHERE role!='employee' AND employee_id IS NOT NULL"):
            if row[0] in s['seasons'][change['target_id']]['roster']:
                s['seasons'][change['target_id']]['roster'][row[0]]['prize_eligible']=False
    version=db.execute('SELECT COALESCE(MAX(version),0)+1 FROM config_versions WHERE domain=? AND target_id=?',
                       (change['domain'],change['target_id'])).fetchone()[0]
    db.execute('INSERT INTO config_versions VALUES (?,?,?,?,?,?,?,?)',
               (uid('config_'),change['domain'],change['target_id'],version,encode(change['payload']),row['payload_hash'],user['username'],stamp(now)))
    db.execute("UPDATE change_sets SET status='published' WHERE id=?",(key,))
    s['config_version']=s.get('config_version',1)+1
    if change['domain']=='employees':
        db.execute('INSERT OR IGNORE INTO employee_identities VALUES (?)',(change['target_id'],))
    audit(db,user,'publish:'+change['domain'],change['target_id'],before,result,body['reason'],now,request_id)
    return dict(status='applied',published_version=version,config_version=s['config_version'],entity=result)


def correction_actions(s,case,now,key):
    for index,action in enumerate(case['actions']):
        source=f'{key}:{index}'
        if action['type']=='revalue':
            sid=action['season_id'];season=game.choose_season(s,sid)
            old=policy(s,'economy',season)['coin_backing'];new=action['coin_backing']
            outstanding=sum(r['allocations'].get(sid,0) for r in s['ledger'].values())
            refundable=sum((o.get('coin_allocations') or {k:v//100 for k,v in o['funding'].items()}).get(sid,0)
                           for o in s['orders'].values() if o['coins_charged'] and o['status'] in ('requested','approved','ready'))
            before=game.economy(s,season)
            # Revalue existing obligations exactly; future issuance is checked separately by the new maximum.
            extra=(outstanding+refundable)*(new-old)
            season['policies']['economy']['coin_backing']=new
            future_delta=max(0,pass_totals(season)['total_kzt']-season.get('committed_budget_kzt',0)) if season['status'] not in ('finalized','closed') else 0
            reserve=max(extra,future_delta,0)
            require(season.get('committed_budget_kzt',0)+reserve<=season['virtual_budget_kzt'],
                    'INSUFFICIENT_BUDGET','Недостаточно финансирования переоценки',outstanding_coins=outstanding,refundable_coins=refundable,additional_kzt=reserve)
            season['committed_budget_kzt']=season.get('committed_budget_kzt',0)+reserve
            s.setdefault('coin_funding_adjustments',[]).append(dict(id=source,season_id=sid,old=old,new=new,
                outstanding_coins=outstanding,refundable_coins=refundable,delta_kzt=extra,future_reserve_kzt=reserve,at=stamp(now),reason=case['reason']))
            continue
        if action['type']=='assessment':
            eid=action['employee_id'];employee=s['employees'].get(eid)
            require(employee,'NOT_FOUND','Сотрудник не найден',404)
            date=instant(action['assessed_at']);require(date.tzinfo and date<=now,'INVALID_DATE','Дата оценки недопустима',422)
            require(set(action['skills'])<=set(s['skills']),'INVALID_SKILL','Неизвестный навык',422)
            s['assessment_revisions'].append(dict(id=source,employee_id=eid,before=deepcopy(employee['skills']),
                after=action['skills'],previous_at=employee['assessment_at'],assessed_at=stamp(date),reason=case['reason'],correction_id=key))
            dates=employee.setdefault('skill_assessed_at',{k:employee['assessment_at'] for k in employee['skills']})
            dates.update({k:stamp(date) for k in action['skills']})
            employee.update(skills={**employee['skills'],**action['skills']},assessment_at=stamp(date))
            continue
        if action['type']=='review':
            review=s['reviews'].get(action['source_id']);require(review,'NOT_FOUND','Проверка не найдена',404)
            require(review['status'] in ('approved','rejected'),'REVIEW_PENDING','Для ожидающей проверки используйте обычное решение')
            eid,sid=review['employee_id'],review['season_id'];season=game.choose_season(s,sid)
            require(season['status'] not in ('finalized','closed') or any(a['type']=='recalculate_results' and a['season_id']==sid for a in case['actions']),
                    'SEASON_LOCKED','Добавьте пересчёт итогов закрытого сезона')
            require(review['status']!=action['decision'],'UNCHANGED','Решение не меняется')
            difference=review['xp_amount']*(1 if action['decision']=='approved' else -1)
            require(game.xp_total(s,sid,eid)+difference>=0,'NEGATIVE_XP','XP станет отрицательным')
            s.setdefault('review_revisions',[]).append(dict(id=source,before=deepcopy(review),decision=action['decision'],reason=case['reason'],at=stamp(now)))
            review['status']=action['decision'];review['correction_id']=key
            s['xp_adjustments'][source]=dict(id=source,season_id=sid,employee_id=eid,amount=difference,
                source_type='admin_correction',source_id=review['id'],effective_at=review['effective_at'],created_at=stamp(now),reason=case['reason'])
            if season['status'] not in ('finalized','closed'):game.award_followups(s,season,eid,now)
            continue
        if action['type']=='gift':
            season=game.choose_season(s,action['season_id'],action['employee_id']);pool=s['pools'].get(action['pool_id'])
            require(pool and pool['season_id']==season['id'],'INVALID_POOL','Пул отсутствует в сезоне',422)
            require(now<instant(season['claim_deadline']),'CLAIM_EXPIRED','Срок выбора подарков истёк')
            cap=pool['cap'];required=season.get('committed_budget_kzt',0)+cap
            require(required<=season['virtual_budget_kzt'],'INSUFFICIENT_BUDGET','Нужно профинансировать компенсационный подарок',required_kzt=cap)
            fallback=s['items'][pool['fallback_item_id']]
            require(game.item_view(fallback)['available_stock']>0,'OUT_OF_STOCK','Нет запасного подарка')
            season['committed_budget_kzt']=required
            s['entitlements'][source]=dict(id=source,employee_id=action['employee_id'],season_id=season['id'],level=None,
                source='correction',source_id=source,component=None,name=action['name'],cap=cap,pool_id=pool['id'],status='available',opened_at=stamp(now))
            continue
        if action['type']=='reverse_delivery':
            order=s['orders'].get(action['source_id']);require(order and order['status']=='delivered','INVALID_ORDER','Нужна выданная заявка')
            item=s['items'][order['item_id']];require(item['delivered']>0,'INVALID_STOCK','Складская выдача отсутствует')
            # The asserted physical return is preserved as an immutable fact, then normal cancellation refunds once.
            s.setdefault('delivery_revisions',[]).append(dict(id=source,order_id=order['id'],before=deepcopy(order),
                returned_to_stock=True,reason=case['reason'],at=stamp(now)))
            item['delivered']-=1;item['reserved']+=1
            order.update(status='approved');order['timeline'].append(dict(status='return_registered',at=stamp(now),note=case['reason'],correction_id=key))
            game.transition_order(s,order['id'],'cancelled',case['reason'],None,now)
            continue
        if action['type']=='recalculate_results':
            season=game.choose_season(s,action['season_id']);sid=season['id'];old=s['snapshots'].get(sid)
            require(old,'NO_FINAL_RESULTS','Сезон ещё не финализирован')
            s['snapshots'].pop(sid)
            result=[]
            for page in range(1,(len(season['roster'])+19)//20+1):result+=game.leaderboard(s,season,page=page)['entries']
            rules=policy(s,'leaderboards',season);eligible=[r for r in result if r['prize_eligible']]
            delta_total=0
            for rank,row in enumerate(eligible[:len(rules['prizes'])]):
                eid=row['employee_id'];due=rules['prizes'][rank]
                paid=sum(r['amount'] for r in s['ledger'].values() if r['season_id']==sid and r['employee_id']==eid and r['source_type'] in ('season_podium','result_amendment'))
                delta=max(0,due-paid);delta_total+=delta*policy(s,'economy',season)['coin_backing']
                if delta:game.coin(s,eid,sid,'result_amendment',source+':'+eid,delta,now)
                row.update(prize_rank=rank+1,title=rules['winner_title'] if rank==0 else f'Призёр сезона: {rank+1} место')
            require(season.get('committed_budget_kzt',0)+delta_total<=season['virtual_budget_kzt'],'INSUFFICIENT_BUDGET','Доплаты новым призёрам требуют финансирования',required_kzt=delta_total)
            season['committed_budget_kzt']+=delta_total
            s['result_revisions'].append(dict(id=source,season_id=sid,previous=deepcopy(old),current=deepcopy(result),
                reason=case['reason'],retained_prior_prizes=True,at=stamp(now)))
            s['snapshots'][sid]=result
            continue
        eid,sid=action['employee_id'],action['season_id']; delta=action['delta']
        season=game.choose_season(s,sid,eid)
        if action['type']=='xp':
            require(season['status'] not in ('finalized','closed') or any(a['type']=='recalculate_results' and a['season_id']==sid for a in case['actions']),
                    'SEASON_LOCKED','Добавьте к case пересчёт итогов закрытого сезона')
            require(game.xp_total(s,sid,eid)+delta>=0,'NEGATIVE_XP','Итоговый XP не может быть отрицательным')
            original=s['xp'].get(action['source_id'])
            require(not action['source_id'] or original and original['employee_id']==eid and original['season_id']==sid,
                    'INVALID_SOURCE','Исходное XP-событие не найдено у этого сотрудника в сезоне',422)
            s['xp_adjustments'][source]=dict(id=source,season_id=sid,employee_id=eid,amount=delta,
                source_type='admin_correction',source_id=action['source_id'],effective_at=original['effective_at'] if original else stamp(now),created_at=stamp(now),reason=case['reason'])
            if season['status'] not in ('finalized','closed'):game.award_followups(s,season,eid,now)
        elif action['type']=='coins':
            if delta>0:
                required=delta*policy(s,'economy',season)['coin_backing']
                committed=season.get('committed_budget_kzt',pass_totals(season)['total_kzt'])
                require(committed+required<=season['virtual_budget_kzt'],'INSUFFICIENT_BUDGET','Сначала внесите дополнительное финансирование',required_kzt=required)
                season['committed_budget_kzt']=committed+required
                allocations={sid:delta}
            else:
                allocations={k:-v for k,v in game.funding_for(s,eid,-delta).items()}
            game.coin(s,eid,sid,'admin_correction',source,delta,now,allocations)
        elif action['type']=='restore_attempt':
            task=s['tasks'].get(action['source_id'])
            require(task and task['employee_id']==eid and task['season_id']==sid,'INVALID_SOURCE','Задание не найдено',422)
            require(task['status']!='completed','TASK_COMPLETED','Выполненное задание не переназначается')
            require(0<delta<=task['attempts'],'INVALID_DELTA','Укажите число использованных попыток для восстановления',422)
            task['attempts']-=delta; task['status']='available'
    for season in s['seasons'].values():
        require(game.economy(s,season)['released']>=-.01,'INSUFFICIENT_BUDGET','Недостаточно обеспечения обязательств')
    return totals(s)
