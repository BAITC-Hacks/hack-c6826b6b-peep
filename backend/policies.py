"""Initial policy values and explicit per-season rule contexts."""
from copy import deepcopy

DEFAULTS = {
    'recommendations': dict(strategy='weighted_coverage', max_steps=3, horizon_days=28,
                            budget_weeks=4, utility_weight=.75, duration_weight=.15, format_weight=.10),
    'economy': dict(daily_xp=100, bonus_xp=150, daily_count=2, attempts=3,
                    activity_min=100, activity_max=300, activity_multiplier=2,
                    reviews_per_day=2, weekly_days=5, weekly_xp=250, coin_backing=100,
                    season_days=90, review_days=7, claim_days=14, order_expiry_days=7),
    'streaks': dict(freezes=2, milestones=[dict(days=d, xp=x) for d, x in
                                       [(3,30),(7,70),(14,140),(30,300),(60,600),(90,900)]]),
    'leaderboards': dict(min_xp=1000, min_days=5, prizes=[250,150,100],
                         criteria=['confirmed_xp','confirmed_activity_count','active_days'],
                         winner_title='Сотрудник сезона'),
    'achievements': dict(items=[
        dict(code='first_step', name='Первый шаг сделан', condition='verified_activities', threshold=1, xp=100, active=True),
        dict(code='three_steps', name='Устойчивое движение', condition='verified_activities', threshold=3, xp=200, active=True),
        dict(code='skill_explorer', name='Разностороннее развитие', condition='distinct_skills', threshold=3, xp=300, active=True)]),
    'quests': dict(items=[]),
    'nominations': dict(items=[]),
    'branding': dict(app_name='Career Quest', primary='#F392D5', background='#080D22',
                     banner='', logo_url=''),
    'content': dict(locale='ru', entries=[dict(key='season.title', value='Карьерный пропуск'),
                                         dict(key='shop.title', value='Магазин наград')]),
    'assistant': dict(mode='environment', model='gpt-4o-mini', timeout_seconds=8,
                      max_output_tokens=900, secret_alias='OPENAI_API_KEY'),
    'settings': dict(organization='Career Quest', timezone='Asia/Almaty', locale='ru',
                     session_hours=8, preview_minutes=15, maintenance=False,
                     maintenance_message='Техническое обслуживание', shop_paused=False, quests_paused=False),
}


def policy(s, domain, season=None):
    if season is not None and domain in season.get('policies', {}):
        return season['policies'][domain]
    return s.get('policies', {}).get(domain, DEFAULTS[domain])


def initialize(s):
    changed = 'policies' not in s
    s.setdefault('policies', deepcopy(DEFAULTS))
    for key, value in DEFAULTS.items():
        s['policies'].setdefault(key, deepcopy(value))
    for season in s['seasons'].values():
        season.setdefault('policies', {k: deepcopy(s['policies'][k]) for k in
                                      ('economy','streaks','leaderboards','achievements','quests','nominations')})
        for domain in ('quests','nominations'):
            season['policies'].setdefault(domain,deepcopy(DEFAULTS[domain]))
        season.setdefault('policy_version', 1)
    for name, default in [('xp_adjustments', {}), ('inventory_movements', []),
                          ('assessment_revisions', []), ('admin_history', []), ('departments', {}),
                          ('result_revisions', []), ('budget_movements', [])]:
        s.setdefault(name, default)
    for employee in s['employees'].values():
        name = employee['department']
        if not any(d['name'] == name for d in s['departments'].values()):
            import hashlib
            key = 'dep_' + hashlib.sha256(name.encode()).hexdigest()[:12]
            s['departments'][key] = dict(id=key, name=name, parent_id=None, active=True)
        employee.setdefault('active', True)
    grades=['Junior','Middle','Senior','Lead']
    for role in s['roles'].values():
        role.setdefault('rank',grades.index(role['grade_id']) if role['grade_id'] in grades else 99)
        role.setdefault('active',True)
    for entry in list(s['plan'].values())+list(s['completions'].values()):
        if entry['activity_id'] in s['activities']:
            entry.setdefault('activity_snapshot',deepcopy(s['activities'][entry['activity_id']]))
    return changed


def level_for(season, xp):
    return sum(r['required_total_xp'] <= xp for r in season['rewards'])


def pass_totals(season):
    components = [c for r in season['rewards'] for c in r['components']]
    coins = sum(c.get('coins', 0) for c in components)
    gifts = sum(c.get('budget_cap_kzt', 0) for c in components)
    backing = season.get('policies', {}).get('economy', DEFAULTS['economy'])['coin_backing']
    podium = sum(season.get('policies', {}).get('leaderboards', DEFAULTS['leaderboards'])['prizes']) * backing
    nominations=season.get('policies',{}).get('nominations',DEFAULTS['nominations'])['items']
    departments=len({r['department'] for r in season['roster'].values()})
    podium+=sum(n['coins']*(departments if n['per_department'] else 1)*backing for n in nominations if n['active'])
    return dict(levels=len(season['rewards']), max_xp=season['rewards'][-1]['required_total_xp'],
                coins=coins, gifts_kzt=gifts, per_member_kzt=coins*backing+gifts,
                gifts=sum(c['type'] in ('gift','mini') for c in components),
                roster=len(season['roster']), total_kzt=(coins*backing+gifts)*len(season['roster'])+podium)
