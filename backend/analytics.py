"""Read-only HR aggregates. Missing assessments never count as failed skills."""
from collections import defaultdict
from datetime import datetime, time, timedelta
import csv
import io

from . import career
from .engine import instant, require
from .game_rules import ZONE, game_date


def report(s,filters,now):
    start=filters.get('date_from') or (game_date(now)-timedelta(days=29))
    end=filters.get('date_to') or game_date(now)
    require(start<=end and (end-start).days<=366,'INVALID_PERIOD','Проверьте период: начало не позже конца, максимум 366 дней',422)
    lo=datetime.combine(start,time.min,ZONE)
    hi=datetime.combine(end+timedelta(days=1),time.min,ZONE)
    reference=filters.get('reference','current_role')
    basis=filters.get('basis','assessed')
    people=[]
    cells={}
    events={}
    participants=set()
    completers=set()
    completions=set()
    no_goal=0
    for eid,e in s['employees'].items():
        if any(filters.get(k) and filters[k]!=e[field] for k,field in [('department','department'),('role_id','role'),('grade_id','grade')]):
            continue
        chosen=career.goal(s,eid)['goal']
        g=chosen if reference=='goal' else {'target_role':e['role'],'target_grade':e['grade']}
        p=career.progress(s,eid,g) if g else {'coverage':None,'assessed_readiness':None,'estimated_readiness':None,'skills':[]}
        hs=career.history(s,eid)
        person_events=[]
        for h in hs:
            a=h['activity']
            attendance_known=(a['kind']=='scheduled' and h.get('registered_at') and
                instant(h['registered_at'])<=instant(a['starts_at']) and
                lo<=instant(a['ends_at'])<hi and instant(a['ends_at'])<=now)
            included={field:bool(h.get(field) and lo<=instant(h[field])<hi) for field in ('started_at','attended_at','completed_at')}
            if any(included.values()):
                participants.add(eid)
                person_events.append(h)
            if included['completed_at']:
                completers.add(eid)
                completions.add((eid,h['activity_id']))
            if any(included.values()) or attendance_known:
                activity=events.setdefault(h['activity_id'],{'activity_id':h['activity_id'],'title':h['activity']['title'],
                    'started':set(),'attended':set(),'completed':set(),'participants':set(),'origins':set(),'attendance':None,
                    'registered_for_attendance':set(),'actually_attended':set()})
                for field,label in [('started_at','started'),('attended_at','attended'),('completed_at','completed')]:
                    if included[field]:
                        activity[label].add(eid)
                if any(included.values()): activity['participants'].add(eid)
                activity['origins'].update(src['origin'] for src in h['sources'])
                if attendance_known:
                    activity['registered_for_attendance'].add(eid)
                    if h.get('attended_at') and instant(a['starts_at'])<=instant(h['attended_at'])<=instant(a['ends_at']):
                        activity['actually_attended'].add(eid)
        if not chosen:
            no_goal+=1
        people.append(dict(employee_id=eid,full_name=e['full_name'],department=e['department'],role=e['role'],grade=e['grade'],
                           goal=chosen,coverage=p['coverage'],readiness=p[basis+'_readiness'],participated=bool(person_events)))
        for skill in p['skills']:
            if skill['required_level'] is None:
                continue
            key=(e['department'],skill['skill_id'])
            cell=cells.setdefault(key,dict(department=e['department'],skill_id=skill['skill_id'],name=skill['name'],
                required_count=0,assessed_count=0,missing_count=0,gap_count=0,relative=[],points=[],employee_ids=[]))
            cell['required_count']+=1
            value=skill[basis+'_level']
            if value is None:
                cell['missing_count']+=1
                continue
            gap=max(0,skill['required_level']-value)
            cell['assessed_count']+=1
            cell['gap_count']+=gap>0
            cell['relative'].append(gap/skill['required_level'])
            cell['points'].append(gap)
            if gap:
                cell['employee_ids'].append(eid)
    for cell in cells.values():
        n=cell['assessed_count']
        cell['gap_share']=cell['gap_count']/n if n else None
        cell['mean_relative_gap']=sum(cell.pop('relative'))/n if n else None
        cell['mean_points_gap']=sum(cell.pop('points'))/n if n else None
        cell.update(reference=reference,basis=basis)
    gaps=sorted(cells.values(),key=lambda c:(-c['gap_count'],-(c['mean_relative_gap'] or 0),c['skill_id'],c['department']))
    for a in events.values():
        denominator=len(a.pop('registered_for_attendance'))
        numerator=len(a.pop('actually_attended'))
        if denominator: a['attendance']=dict(numerator=numerator,denominator=denominator,value=numerator/denominator)
    activities=[{k:len(v) if isinstance(v,set) and k!='origins' else sorted(v) if isinstance(v,set) else v for k,v in a.items()} for a in events.values()]
    activities.sort(key=lambda a:(-a['participants'],a['activity_id']))
    n=len(people)
    full=[p['readiness'] for p in people if p['coverage']==100 and p['readiness'] is not None]
    ratio=lambda numerator,denominator:dict(numerator=numerator,denominator=denominator,value=numerator/denominator if denominator else None)
    covered={sid for a in s['activities'].values() if a['active'] and
        (not a['available_until'] or instant(a['available_until'])>now) and
        (not a['available_from'] or instant(a['available_from'])<=now+timedelta(days=28)) and
        (a['kind']!='scheduled' or now<instant(a['starts_at'])<=now+timedelta(days=28))
        for sid,g in a['gains'].items() if g>0}
    return dict(employees=people,skills=gaps,activities=activities,no_goal_count=no_goal,
        uncovered_skills=[g for g in gaps if g['gap_count'] and g['skill_id'] not in covered],
        kpis=dict(employees=n,goals=ratio(sum(p['goal'] is not None for p in people),n),
            participation=ratio(len(participants),n),completion=ratio(len(completers),len(participants)),
            completed_activities=len(completions),missing_assessments=sum(p['coverage'] is not None and p['coverage']<100 for p in people),
            mean_readiness=sum(full)/len(full) if full else None,readiness_count=len(full)),
        date_from=start.isoformat(),date_to=end.isoformat())


def skill_csv(rows):
    output=io.StringIO()
    fields=['department','skill_id','reference','basis','required_count','assessed_count','missing_count','gap_count','mean_relative_gap']
    writer=csv.writer(output)
    writer.writerow(fields)
    for row in rows:
        cells=[]
        for key in fields:
            val=row.get(key)
            if isinstance(val,str) and val.startswith(('=','+','-','@','\t','\r')):
                val="'"+val
            cells.append(val)
        writer.writerow(cells)
    return '\ufeff'+output.getvalue()


def passport(s,eid,now):
    from . import game
    e=s['employees'][eid]
    p=career.progress(s,eid)
    saved=career.plan(s,eid,now)
    badges=[b for b in s['badges'].values() if b['employee_id']==eid]
    summary=None
    try:
        summary=game.summary(s,game.choose_season(s,eid=eid),eid,now)
        summary.pop('wallet_balance',None)
    except Exception:
        pass
    return dict(employee=e,goal=career.goal(s,eid),progress=p,plan=saved,
                recent_completions=[{k:v for k,v in h.items() if k not in ('note','sources')} for h in career.history(s,eid) if h['status']=='completed'][:3],
                achievements=badges,season=summary,generated_at=now.isoformat())


def passport_markdown(data):
    e=data['employee']; g=data['goal']['goal']; p=data['progress']
    val=lambda n:'Нет данных' if n is None else str(n)
    lines=['# Паспорт развития',f'Сотрудник: {e["full_name"]}',f'Сформирован: {data["generated_at"]}',
        f'Цель: {g["target_role"]} {g["target_grade"]}' if g else 'Цель пока не выбрана.',
        f'Последняя оценка: {p["assessment_at"]}',f'Соответствие по оценке: {val(p["assessed_readiness"])}; по расчёту: {val(p["estimated_readiness"])}.',
        '', '| Навык | Оценка | Расчёт | Требование |','|---|---:|---:|---:|']
    for r in p['skills']:
        name=r['name'].replace('|','\\|').replace('\n',' ')
        lines.append(f'| {name} | {val(r["assessed_level"])} | {val(r["estimated_level"])} | {val(r["required_level"])} |')
    for heading,items in [('Последние завершения',[h['activity']['title'] for h in data['recent_completions']]),
                         ('Текущий план',[h['activity']['title'] for h in data['plan']['items']]),
                         ('Достижения',[b['name'] for b in data['achievements']])]:
        lines+=['',f'## {heading}']+['- '+x for x in items or ['Пока нет записей']]
    if data['season']:
        lines+=['',f'Сезон: {data["season"]["season"]["name"]}. Уровень {data["season"]["level"]}; XP {data["season"]["confirmed_xp"]}.']
    lines+=['','Расчётный прирост основан на самоотчётах, не меняет последнюю оценку и не гарантирует повышение. XP отражает участие в программе.']
    return '\n'.join(lines)
