// ignore_for_file: invalid_use_of_protected_member
part of 'workspace.dart';

extension _HrViews on _WorkspaceState {
  Widget hrView() {
    switch (page.split('/').first) {
      case 'overview':
      case 'skills':
        return analyticsView();
      case 'employees':
        return page.contains('/')
            ? profileView(data, readOnly: true)
            : employeesView();
      case 'reviews':
        return reviewsView();
      case 'rewards':
        return hrRewardsView();
      case 'shop':
        return hrShopView();
      case 'gamification':
        return page.contains('/') ? hrLeaderboardView() : hrSeasonView();
      default:
        return card(
          'Страница не найдена',
          button('Открыть сводку', () => go('overview')),
        );
    }
  }

  Widget analyticsView() {
    final k = map(data['kpis']);
    String ratio(dynamic raw) {
      final x = map(raw);
      return x['value'] == null
          ? 'Нет данных'
          : '${((x['value'] as num) * 100).toStringAsFixed(1)}% (${x['numerator']}/${x['denominator']})';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'Развитие команды в контексте',
          'Навыки — текущий срез; участие — выбранный период. ${value(data['date_from'])} — ${value(data['date_to'])}',
        ),
        actions([
          button('Фильтры и период', editHrFilters),
          button(
            'Скачать CSV',
            () => download(
              '/api/hr/reports/skill-gaps.csv?${query(reportFilters)}',
              'skill-gaps.csv',
            ),
          ),
        ]),
        const SizedBox(height: 22),
        actions([
          metric('Сотрудники', '${k['employees'] ?? 0}', accent: blue),
          metric('С карьерной целью', ratio(k['goals'])),
          metric('Участники периода', ratio(k['participation']), accent: cyan),
          metric(
            'Завершили среди участников',
            ratio(k['completion']),
            accent: violet,
          ),
          metric('Не хватает оценок', '${k['missing_assessments'] ?? 0}'),
          metric(
            'Среднее соответствие',
            pct(k['mean_readiness']),
            accent: blue,
          ),
        ]),
        const SizedBox(height: 20),
        Text(
          'В среднем соответствии учтено ${k['readiness_count'] ?? 0} сотрудников с полными оценками. Пропущенная оценка не считается нулевой.',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 24),
        heading(
          'Где команде нужна поддержка',
          'Нажмите навык, чтобы открыть сотрудников с дефицитом.',
        ),
        for (final gap in records(data['skills']))
          card(
            gap['name'],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gap['department'], style: const TextStyle(color: cyan)),
                const SizedBox(height: 8),
                Text(
                  'Дефицит у ${gap['gap_count']} из ${gap['assessed_count']} оценённых · нет оценки у ${gap['missing_count']}',
                ),
                Text(
                  'Средний относительный дефицит: ${gap['mean_relative_gap'] == null ? 'Нет данных' : pct((gap['mean_relative_gap'] as num) * 100)}',
                ),
                const SizedBox(height: 14),
                button('Посмотреть сотрудников', () {
                  hrFilters['department'] = gap['department'];
                  hrFilters['skill_id'] = gap['skill_id'];
                  hrFilters['has_gap'] = 'true';
                  go('employees');
                }),
              ],
            ),
          ),
        if (records(data['skills']).isEmpty)
          empty('Для выбранной группы данных нет.'),
        card(
          'Пробелы каталога',
          Text(
            records(data['uncovered_skills']).isEmpty
                ? 'Для выявленных дефицитов есть активные материалы.'
                : records(data['uncovered_skills'])
                      .map((g) => '${g['name']} · ${g['department']}')
                      .join('\n'),
            style: const TextStyle(height: 1.7),
          ),
          subtitle: 'Без индивидуальных prerequisites и предпочтений, горизонт — 28 дней.',
        ),
        card(
          'Активности периода',
          Column(
            children: [
              for (final a in records(data['activities']))
                ListTile(
                  title: Text(a['title']),
                  subtitle: Text(
                    'Начали ${a['started']} · посетили ${a['attended']} · завершили ${a['completed']} · участников ${a['participants']}\n${a['attendance'] == null ? 'Явка не измеряется без регистрации и факта посещения.' : 'Явка: ${ratio(a['attendance'])}'}',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<Json?> fieldsDialog(
    String title,
    List<(String, String, String)> fields, {
    String? description,
  }) async {
    final controllers = {
      for (final f in fields) f.$1: TextEditingController(text: f.$3),
    };
    final result = await showDialog<Json>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (description != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(description),
                  ),
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextField(
                      controller: controllers[f.$1],
                      decoration: InputDecoration(labelText: f.$2),
                      maxLines: f.$1 == 'description' || f.$1 == 'note' ? 3 : 1,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {
              for (final c in controllers.entries) c.key: c.value.text.trim(),
            }),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(milliseconds: 350), () {
      for (final c in controllers.values) {
        c.dispose();
      }
    });
    return result;
  }

  Future<void> editHrFilters() async {
    final result = await fieldsDialog('Фильтры команды', [
      (
        'department',
        'Подразделение (пусто — все)',
        hrFilters['department'] ?? '',
      ),
      ('role_id', 'Роль (пусто — все)', hrFilters['role_id'] ?? ''),
      ('grade_id', 'Грейд (пусто — все)', hrFilters['grade_id'] ?? ''),
      ('date_from', 'С даты ГГГГ-ММ-ДД', hrFilters['date_from'] ?? ''),
      ('date_to', 'По дату ГГГГ-ММ-ДД', hrFilters['date_to'] ?? ''),
    ]);
    if (result == null) return;
    hrFilters = {
      for (final entry in result.entries)
        if (entry.value.toString().isNotEmpty)
          entry.key: entry.value.toString(),
    };
    if (!mounted) return;
    var reference = hrFilters['reference'] ?? 'current_role',
        basis = hrFilters['basis'] ?? 'assessed';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Основа сравнения'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                select('Требования', reference, [
                  ('current_role', 'Текущая роль'),
                  ('goal', 'Карьерная цель'),
                ], (v) => update(() => reference = v)),
                const SizedBox(height: 16),
                select('Уровни навыков', basis, [
                  ('assessed', 'Последняя оценка'),
                  ('estimated', 'Расчёт после действий'),
                ], (v) => update(() => basis = v)),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
    hrFilters['reference'] = reference;
    hrFilters['basis'] = basis;
    listPage = 1;
    reload();
  }

  Widget employeesView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Люди и их маршруты',
        '${data['total'] ?? 0} сотрудников по текущим фильтрам',
      ),
      actions([
        button('Фильтры', editHrFilters),
        button('Сбросить фильтры', () {
          hrFilters = {};
          search = '';
          listPage = 1;
          reload();
        }),
      ]),
      const SizedBox(height: 18),
      TextFormField(
        initialValue: search,
        decoration: const InputDecoration(
          labelText: 'Имя, роль или подразделение',
          prefixIcon: Icon(Icons.search),
        ),
        onFieldSubmitted: (v) {
          search = v;
          listPage = 1;
          reload();
        },
      ),
      const SizedBox(height: 22),
      for (final e in records(data['items']))
        card(
          e['full_name'],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${e['role']} · ${e['grade']}\n${e['department']}'),
              Text(
                e['goal'] == null
                    ? 'Цель пока не выбрана'
                    : 'Цель: ${e['goal']['target_role']} ${e['goal']['target_grade']}',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 14),
              button(
                'Открыть профиль',
                () => go('employees/${e['employee_id']}'),
              ),
            ],
          ),
        ),
      if (records(data['items']).isEmpty) empty('Сотрудники не найдены.'),
      pager(data),
    ],
  );
  Widget reviewsView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Подтверждай результат, а не клик',
        'XP начисляется только после одобрения. Отказ не изменяет последнюю оценку навыков.',
      ),
      select(
        'Статус',
        filter,
        [
          ('', 'Все результаты'),
          ('pending', 'Ожидают проверки'),
          ('approved', 'Одобрены'),
          ('rejected', 'Отклонены'),
        ],
        (v) {
          filter = v;
          reload();
        },
      ),
      const SizedBox(height: 20),
      for (final r in records(data['items']))
        card(
          r['activity']['title'],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${r['employee_name']} · ${dateLabel(r['effective_at'])}',
                style: const TextStyle(color: cyan),
              ),
              const SizedBox(height: 12),
              Text('Критерий: ${r['activity']['outcome']}'),
              const SizedBox(height: 14),
              Text(
                r['evidence_text'],
                style: const TextStyle(fontSize: 16, height: 1.8),
              ),
              const SizedBox(height: 16),
              Text(
                '${label(r['status'])} · ${r['xp_amount']} XP',
                style: const TextStyle(color: pink),
              ),
              if (r['decision_note'] != null) Text(r['decision_note']),
              const SizedBox(height: 16),
              if (r['status'] == 'pending')
                actions([
                  button('Подтвердить результат', () async {
                    if (await confirm(
                      'Одобрить результат?',
                      '${r['employee_name']} получит ${r['xp_amount']} XP и возможные награды достижений.',
                    )) {
                      await act(
                        'POST',
                        '/api/hr/reward-reviews/${segment(r['id'])}/decision',
                        {'decision': 'approved', 'comment': ''},
                      );
                    }
                  }, primary: true),
                  button('Отклонить', () async {
                    final comment = await prompt('Причина отказа');
                    if (comment != null) {
                      await act(
                        'POST',
                        '/api/hr/reward-reviews/${segment(r['id'])}/decision',
                        {'decision': 'rejected', 'comment': comment},
                      );
                    }
                  }),
                ]),
            ],
          ),
        ),
      if (records(data['items']).isEmpty)
        empty('Проверок с таким статусом пока нет.'),
    ],
  );
  Widget hrRewardsView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Награда должна дойти до человека',
        'Все выдачи здесь тестовые: без внешних покупок и платежей.',
      ),
      select(
        'Статус',
        filter,
        [
          ('', 'Все заявки'),
          for (final s in [
            'requested',
            'approved',
            'ready',
            'delivered',
            'cancelled',
            'rejected',
          ])
            (s, label(s)),
        ],
        (v) {
          filter = v;
          reload();
        },
      ),
      const SizedBox(height: 22),
      for (final o in records(data['items'])) orderCard(o, admin: true),
      if (records(data['items']).isEmpty) empty('Заявок с таким статусом нет.'),
    ],
  );
  Future<void> fulfillOrder(Json order, String target) async {
    Json payload = {
      'target_status': target,
      'note': '',
      'actual_cost_kzt': null,
    };
    if (target == 'delivered') {
      final result = await fieldsDialog(
        'Тестовая выдача',
        [
          ('note', 'Примечание о выдаче', 'Тестовая выдача в HR-службе'),
          (
            'cost',
            'Учётная стоимость, ₸',
            '${order['item_snapshot']['unit_budget_kzt']}',
          ),
        ],
        description:
            '${order['item_snapshot']['name']}. Лимит: ${order['item_snapshot']['unit_budget_kzt']} ₸.',
      );
      if (result == null) return;
      payload['note'] = result['note'];
      payload['actual_cost_kzt'] = int.tryParse(result['cost']);
    } else if (target == 'rejected' || target == 'cancelled') {
      final note = await prompt(
        'Причина ${target == 'rejected' ? 'отказа' : 'отмены'}',
      );
      if (note == null) return;
      payload['note'] = note;
    } else if (!await confirm(label(target), order['item_snapshot']['name'])) {
      return;
    }
    await act(
      'POST',
      '/api/hr/reward-orders/${segment(order['id'])}/transition',
      payload,
    );
  }

  Widget hrShopView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Каталог наград',
        'Изменения влияют на будущие заказы. Подтверждённые цены и комплектация сохраняются.',
      ),
      if (hasPermission('shop.manage') && hasPermission('stock.manage'))
        Align(
          alignment: Alignment.centerLeft,
          child: button(
            'Добавить награду',
            () => editProduct(null),
            primary: true,
          ),
        ),
      const SizedBox(height: 20),
      for (final item in records(data['items']))
        card(
          item['name'],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item['coin_price']} CQ · всего ${item['stock_total']} · резерв ${item['reserved']} · выдано ${item['delivered']}',
              ),
              Text(
                item['active'] == true
                    ? 'Витрина активна'
                    : 'Скрыто из витрины',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 16),
              actions([
                if (hasPermission('shop.manage') &&
                    hasPermission('stock.manage'))
                  button('Редактировать', () => editProduct(item)),
                if (hasPermission('shop.manage'))
                  button(
                    item['active'] == true ? 'Скрыть' : 'Показать',
                    () => act(
                      'PATCH',
                      '/api/hr/shop/items/${segment(item['id'])}',
                      {'active': item['active'] != true},
                    ),
                  ),
              ]),
            ],
          ),
        ),
    ],
  );
  Future<void> editProduct(Json? item) async {
    final result = await fieldsDialog(
      item == null ? 'Новая награда' : 'Условия награды',
      [
        if (item == null) ('id', 'Код награды (латиница)', ''),
        ('name', 'Название', item?['name'] ?? ''),
        if (item == null) ('category', 'Категория', 'Дом и уют'),
        ('description', 'Комплектация / описание', item?['description'] ?? ''),
        (
          'delivery_terms',
          'Условия получения',
          item?['delivery_terms'] ?? 'Тестовая выдача в HR-службе',
        ),
        ('coin_price', 'Цена CQ', '${item?['coin_price'] ?? 50}'),
        if (item == null) ('unit_budget_kzt', 'Лимит обеспечения, ₸', '5000'),
        ('stock_total', 'Всего единиц', '${item?['stock_total'] ?? 4}'),
      ],
    );
    if (result == null) return;
    for (final key in ['coin_price', 'unit_budget_kzt', 'stock_total']) {
      if (result.containsKey(key)) result[key] = int.tryParse(result[key]);
    }
    await act(
      item == null ? 'POST' : 'PATCH',
      '/api/hr/shop/items${item == null ? '' : '/${segment(item['id'])}'}',
      result,
    );
  }

  Widget hrSeasonView() {
    final selected = map(data['selected']), economy = map(data['economy']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'Сезон с понятными правилами',
          'Виртуальный бюджет учитывает монеты, права на подарки, заявки и выданные награды отдельно.',
        ),
        if (hasPermission('seasons.manage'))
          actions([button('Создать сезон', createSeason, primary: true)]),
        const SizedBox(height: 20),
        if (records(data['items']).isNotEmpty)
          select(
            'Сезон',
            value(selected['id'], ''),
            [
              for (final s in records(data['items']))
                (s['id'] as String, '${s['name']} · ${label(s['status'])}'),
            ],
            (v) {
              filter = v;
              reload();
            },
          ),
        const SizedBox(height: 22),
        if (selected.isNotEmpty) ...[
          card(
            selected['name'],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${label(selected['status'])} · ${dateLabel(selected['starts_at'])} — ${dateLabel(selected['ends_at'])}\nУчастников: ${(selected['employee_ids'] as List).length}',
                  style: const TextStyle(height: 1.8),
                ),
                const SizedBox(height: 18),
                actions([
                  button(
                    'Рейтинг и итоги',
                    () => go('gamification/${selected['id']}/leaderboard'),
                  ),
                  if (selected['status'] == 'draft' &&
                      hasPermission('seasons.manage'))
                    button('Изменить участников', () => editRoster(selected)),
                  if (selected['status'] == 'draft' &&
                      hasPermission('seasons.publish'))
                    button('Опубликовать сезон', () async {
                      if (await confirm(
                        'Зафиксировать правила сезона?',
                        'Участников: ${(selected['employee_ids'] as List).length}. Максимальное обязательство: ${economy['committed_budget_kzt']} ₸.\nПосле публикации нельзя уменьшить обещанные награды или исключить участников. Это виртуальный бюджет; платежей не будет.',
                      )) {
                        await act(
                          'POST',
                          '/api/hr/seasons/${segment(selected['id'])}/publish',
                        );
                      }
                    }, primary: true),
                  if ((selected['status'] == 'draft' ||
                          selected['status'] == 'scheduled') &&
                      hasPermission('seasons.manage'))
                    button('Изменить сезон', () => editSeason(selected)),
                ]),
              ],
            ),
          ),
          actions([
            for (final pair in [
              ('unearned_reserved', 'Будущие награды'),
              ('earned_liability', 'Заработанные обязательства'),
              ('order_reserved', 'Резерв заявок'),
              ('spent', 'Выдано'),
              ('released', 'Освобождено'),
            ])
              metric(
                pair.$2,
                '${economy[pair.$1] ?? 0} ₸',
                accent: pair.$1 == 'spent' ? pink : blue,
              ),
          ]),
          const SizedBox(height: 24),
          card(
            'Правила экономики',
            Text(
              'Максимум на участника — ${economy['max_per_member_kzt']} ₸ виртуального бюджета. Уровни и награды определяет опубликованная версия пропуска.\n\nМонеты не выводятся в деньги. Игровой рейтинг не заменяет оценку профессиональных результатов.',
              style: const TextStyle(height: 1.8),
            ),
          ),
          heading(
            'Подарочные пулы',
            'Запасной сертификат сохраняет возможность получить заработанную награду.',
          ),
          for (final pool in records(data['pools']?['items']))
            card(
              'Лимит ${pool['cap']} ₸',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(pool['item_ids'] as List).length} вариантов · ${pool['code']}',
                  ),
                  const SizedBox(height: 12),
                  if (hasPermission('shop.manage'))
                    button('Дополнить варианты', () => editPool(pool)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget hrLeaderboardView() {
    final content = map(data['content']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        actions([button('К сезонам', () => go('gamification'))]),
        const SizedBox(height: 20),
        heading(
          value(data['season']?['name']),
          content['is_final'] == true
              ? 'Итоги зафиксированы'
              : 'Текущий рейтинг участия',
        ),
        for (final row in records(content['entries']))
          card(row['title'] ?? 'Участник', leaderRow(row)),
        pager(content),
        if (content['is_final'] == true)
          button(
            'Сертификат победителя',
            () => download(
              '/api/seasons/${segment(data['season']['id'])}/certificate',
              'season-certificate.md',
            ),
          ),
      ],
    );
  }

  Future<void> editRoster(Json season) async {
    try {
      final people = <Json>[];
      for (var p = 1; ; p++) {
        final result = await api.get('/api/hr/employees?page=$p');
        people.addAll(records(result['items']));
        if (people.length >= result['total']) break;
      }
      if (!mounted) return;
      final ids = Set<String>.from(season['employee_ids']);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: const Text('Участники черновика'),
            content: SizedBox(
              width: 480,
              height: 380,
              child: ListView(
                children: [
                  for (final e in people)
                    CheckboxListTile(
                      title: Text(e['full_name']),
                      subtitle: Text(e['department']),
                      value: ids.contains(e['employee_id']),
                      onChanged: (v) => update(() {
                        if (v == true) {
                          ids.add(e['employee_id']);
                        } else {
                          ids.remove(e['employee_id']);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: ids.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text('Сохранить ${ids.length}'),
              ),
            ],
          ),
        ),
      );
      if (accepted == true) {
        await act('PATCH', '/api/hr/seasons/${segment(season['id'])}', {
          'employee_ids': ids.toList(),
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> createSeason() async {
    final roster = <Json>[];
    try {
      for (var p = 1; ; p++) {
        final result = await api.get('/api/hr/employees?page=$p');
        roster.addAll(records(result['items']));
        if (roster.length >= result['total']) break;
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
      return;
    }
    if (!mounted) return;
    final ids = <String>{};
    final chosen = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Участники нового сезона'),
          content: SizedBox(
            width: 500,
            height: 400,
            child: ListView(
              children: [
                for (final e in roster)
                  CheckboxListTile(
                    title: Text(e['full_name']),
                    subtitle: Text(e['department']),
                    value: ids.contains(e['employee_id']),
                    onChanged: (v) => update(() {
                      v == true
                          ? ids.add(e['employee_id'])
                          : ids.remove(e['employee_id']);
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: ids.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: Text('Выбрать ${ids.length}'),
            ),
          ],
        ),
      ),
    );
    if (chosen != true) return;
    final fields = await fieldsDialog('Условия сезона', [
      ('name', 'Название', 'Новый уровень'),
      ('date', 'Дата начала ГГГГ-ММ-ДД', ''),
      ('budget', 'Виртуальный бюджет, ₸', '${ids.length * 1200000 + 50000}'),
    ], description: '90 дней. Начало в полночь Asia/Almaty.');
    if (fields == null) return;
    final d = DateTime.tryParse(fields['date']);
    if (d == null) {
      setState(() => error = 'Укажите корректную дату начала');
      return;
    }
    await act('POST', '/api/hr/seasons', {
      'name': fields['name'],
      'starts_at': DateTime.utc(
        d.year,
        d.month,
        d.day,
      ).subtract(const Duration(hours: 5)).toIso8601String(),
      'employee_ids': ids.toList(),
      'virtual_budget_kzt': int.tryParse(fields['budget']),
      'economy_version': 'economy-v1',
    });
  }

  Future<void> editSeason(Json season) async {
    final result = await fieldsDialog('Изменить сезон', [
      if (season['status'] == 'draft') ('name', 'Название', season['name']),
      (
        'date',
        'Дата начала ГГГГ-ММ-ДД',
        DateTime.parse(season['starts_at'])
            .add(const Duration(hours: 5))
            .toIso8601String()
            .substring(0, 10),
      ),
      if (season['status'] == 'draft')
        ('budget', 'Виртуальный бюджет, ₸', '${season['virtual_budget_kzt']}'),
    ]);
    if (result == null) return;
    final d = DateTime.tryParse(result['date']);
    if (d == null) {
      setState(() => error = 'Укажите корректную дату');
      return;
    }
    await act('PATCH', '/api/hr/seasons/${segment(season['id'])}', {
      'starts_at': DateTime.utc(
        d.year,
        d.month,
        d.day,
      ).subtract(const Duration(hours: 5)).toIso8601String(),
      if (result['name'] != null) 'name': result['name'],
      if (result['budget'] != null)
        'virtual_budget_kzt': int.tryParse(result['budget']),
    });
  }

  Future<void> editPool(Json pool) async {
    final items = await api.get('/api/hr/shop/items');
    if (!mounted) return;
    final selected = Set<String>.from(pool['item_ids']);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text('Подарки до ${pool['cap']} ₸'),
          content: SizedBox(
            width: 500,
            height: 400,
            child: ListView(
              children: [
                for (final item in records(
                  items['items'],
                ).where((i) => i['unit_budget_kzt'] <= pool['cap']))
                  CheckboxListTile(
                    title: Text(item['name']),
                    value: selected.contains(item['id']),
                    onChanged: (pool['item_ids'] as List).contains(item['id'])
                        ? null
                        : (v) => update(() {
                            v == true
                                ? selected.add(item['id'])
                                : selected.remove(item['id']);
                          }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await act('PUT', '/api/hr/reward-pools/${segment(pool['id'])}', {
        'item_ids': selected.toList(),
        'fallback_item_id': pool['fallback_item_id'],
        'cap': pool['cap'],
      });
    }
  }
}
