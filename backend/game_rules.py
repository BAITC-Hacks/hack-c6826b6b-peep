"""Pure game rules; no UI clock, random browser seed or mutable wallet counter."""
from datetime import timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import hashlib
import hmac
import random
from zoneinfo import ZoneInfo

from .engine import require, Problem, instant

ZONE = ZoneInfo('Asia/Almaty')
STREAK_XP = {3: 30, 7: 70, 14: 140, 30: 300, 60: 600, 90: 900}
MINIS = {2: ('Набор чая', 1000), 8: ('Кофейный мини-набор', 1500),
         18: ('Набор полезных перекусов', 2000), 28: ('Блокнот для идей', 2500),
         38: ('Ароматическая свеча', 3000), 48: ('Кружка сезона', 4000),
         58: ('Настольное растение', 5000), 68: ('Набор для кофе и чая', 6000),
         78: ('Органайзер для поездок', 7000), 88: ('Подставка для ноутбука', 8000),
         98: ('Компактный внешний аккумулятор', 10000)}


def game_date(now):
    return now.astimezone(ZONE).date()


def pass_rewards():
    result = []
    for level in range(1, 101):
        parts = []
        if level % 5:
            coins = 5 * ((level - 1) // 5 + 1 + (level - 1) % 5)
            parts.append(dict(type='coins', coins=coins, name=f'{coins} CQ'))
        else:
            cap = 300000 if level == 100 else 30000 if level % 10 == 0 else 10000
            parts.append(dict(type='gift', budget_cap_kzt=cap, pool_code=f'gift{cap}', name=f'Подарок до {cap:,} ₸'.replace(',', ' ')))
        if level in MINIS:
            name, cap = MINIS[level]
            parts.append(dict(type='mini', budget_cap_kzt=cap, pool_code=f'mini{level}', name=name))
        if level % 25 == 0:
            parts.append(dict(type='cosmetic', name=['Бронза', 'Серебро', 'Золото', 'Платина'][level // 25 - 1], cosmetic_code=f'frame{level}'))
        result.append(dict(level=level, required_total_xp=200 * level, components=parts))
    return result


def streak_calendar(season, active_dates, pending_dates, now):
    first = game_date(instant(season['starts_at']))
    today = game_date(now)
    end = game_date(instant(season['ends_at']))
    count = best = freezes = 0
    started = False
    entries, milestones = [], {}
    for i in range(90):
        d = first + timedelta(days=i)
        key = d.isoformat()
        state = 'future'
        if d < min(today, end) or key in active_dates:
            if key in active_dates:
                started = True
                count += 1
                state = 'completed'
                best = max(best, count)
                if count in STREAK_XP:
                    milestones.setdefault(count, key)
            elif started and freezes < 2:
                freezes += 1
                state = 'freeze'
            else:
                count = 0
                state = 'missed'
        elif d == today:
            state = 'today'
        entries.append(dict(date=key, status=state, pending_hr=key in pending_dates))
    return dict(days=entries, current_streak=count, best_streak=best, freeze_remaining=2-freezes,
                milestones=milestones, active_days=len(active_dates), preliminary=bool(pending_dates))


def rounded(value):
    try:
        result = Decimal(str(value).replace(',', '.')).quantize(Decimal('.1'), rounding=ROUND_HALF_UP)
    except (InvalidOperation, ValueError, TypeError):
        raise Problem('INVALID_ANSWER', 'Введите конечное число', 422)
    require(result.is_finite(), 'INVALID_ANSWER', 'Введите конечное число', 422)
    return str(result)


def task_variant(secret, season, eid, date, kind):
    key = f'{season["id"]}:{eid}:{date}:{kind}:v1'
    seed = hmac.new(secret.encode(), key.encode(), hashlib.sha256).digest()
    rng = random.Random(int.from_bytes(seed, 'big'))
    day = (date - game_date(instant(season['starts_at']))).days
    answer = {}
    if kind == 'main':
        template = ['conversion', 'metric_change', 'weighted_average'][day % 3]
        if template == 'conversion':
            total, done = rng.randint(30, 150) * 10, rng.randint(10, 200)
            text = f'Из {total} визитов получено {done} заявок. Укажите конверсию в процентах с одним знаком после запятой.'
            number = Decimal(done) * 100 / total
            explanation = f'Конверсия = {done} / {total} × 100 = {rounded(number)}%.'
        elif template == 'metric_change':
            before = rng.randint(100, 900)
            after = before + rng.randint(20, 250)
            text = f'Показатель вырос с {before} до {after}. Укажите относительный прирост в процентах, один знак после запятой.'
            number = Decimal(after - before) * 100 / before
            explanation = f'Прирост = ({after} − {before}) / {before} × 100 = {rounded(number)}%.'
        else:
            n, m, a, b = rng.randint(10, 50), rng.randint(10, 50), rng.randint(50, 250), rng.randint(260, 500)
            text = f'В первой группе {n} клиентов со средним {a}, во второй {m} клиентов со средним {b}. Найдите общее среднее, один знак после запятой.'
            number = Decimal(n*a + m*b) / (n+m)
            explanation = f'Взвешенное среднее = ({n} × {a} + {m} × {b}) / ({n} + {m}) = {rounded(number)}.'
        fields = [{'key': 'value', 'label': 'Ответ', 'type': 'decimal'}]
        answer['value'] = rounded(number)
        payload = {}
    elif day % 2 == 0:
        template = 'transaction_case'
        rows = [{'customer_id': f'C{i % 3 + 1}', 'amount': rng.randint(5, 90) * 100} for i in range(6)]
        totals = {f'C{i}': sum(r['amount'] for r in rows if r['customer_id'] == f'C{i}') for i in range(1, 4)}
        winner = sorted(totals, key=lambda k: (-totals[k], k))[0]
        answer = {'total': rounded(sum(totals.values())), 'customer_id': winner}
        payload = {'rows': rows}
        text = 'Найдите сумму всех шести операций и ID клиента с наибольшей суммой. При равенстве выберите меньший ID.'
        fields = [{'key': 'total', 'label': 'Общая сумма', 'type': 'decimal'}, {'key': 'customer_id', 'label': 'ID клиента (C1, C2, C3)', 'type': 'text'}]
        explanation = f'Сумма {answer["total"]}. По клиентам: {totals}. Максимум у {winner}.'
    else:
        template = 'funnel_case'
        # Exact percentages yield unambiguous comparison of transition drops.
        base = rng.randint(5, 20) * 1000
        r1, r2 = rng.randint(50, 85), rng.randint(40, 85)
        d1, d2 = rng.sample(range(5, 25), 2)
        before = [base, base*r1//100, base*r1*r2//10000]
        after = [base, base*(r1-d1)//100, base*(r1-d1)*(r2-d2)//10000]
        drops = [Decimal(before[i+1])*100/before[i] - Decimal(after[i+1])*100/after[i] for i in range(2)]
        index = max(range(2), key=lambda i: drops[i])
        answer = {'transition_index': str(index+1), 'drop_pp': rounded(drops[index])}
        payload = {'before': before, 'after': after}
        text = 'Три этапа воронки до и после изменения. Найдите переход с наибольшим падением конверсии (1 или 2) и падение в процентных пунктах.'
        fields = [{'key': 'transition_index', 'label': 'Переход (1 или 2)', 'type': 'integer'}, {'key': 'drop_pp', 'label': 'Падение, п.п.', 'type': 'decimal'}]
        explanation = f'Конверсия перехода — следующий этап / предыдущий × 100. Падения: {rounded(drops[0])} и {rounded(drops[1])} п.п. Ответ: {index+1}.'
    return dict(template=template, template_version=1, instructions=text, public_payload=payload,
                answer_fields=fields, expected_answer=answer, explanation=explanation)


def normalise_answer(task, answer):
    require(isinstance(answer, dict) and set(answer) == {f['key'] for f in task['answer_fields']},
            'INVALID_ANSWER', 'Заполните все поля ответа', 422)
    result = {}
    for f in task['answer_fields']:
        value = answer[f['key']]
        require(not isinstance(value, (bool, list, dict)) and value is not None and len(str(value)) <= 50,
                'INVALID_ANSWER', 'Некорректный формат ответа', 422)
        if f['type'] == 'decimal':
            result[f['key']] = rounded(value)
        else:
            result[f['key']] = str(value).strip().upper()
            if f['type'] == 'integer':
                require(result[f['key']] in ('1', '2'), 'INVALID_ANSWER', 'Номер перехода: 1 или 2', 422)
            else:
                require(result[f['key']] in ('C1', 'C2', 'C3'), 'INVALID_ANSWER', 'ID клиента: C1, C2 или C3', 422)
    return result
