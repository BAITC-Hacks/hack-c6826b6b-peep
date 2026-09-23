// Part of the workspace State; extensions group screen builders, not state owners.
// ignore_for_file: invalid_use_of_protected_member
part of 'workspace.dart';

extension _CareerViews on _WorkspaceState {
  Widget careerView() {
    switch (page.split('/').first) {
      case 'home':
        return homeView();
      case 'profile':
        return profileView(data);
      case 'goal':
        return goalView();
      case 'skills':
        return skillsView(map(data['progress']));
      case 'plan':
        return planView(data);
      case 'catalog':
        return catalogView();
      case 'activities':
        return activityView();
      case 'history':
        return historyView(records(data['items']));
      case 'simulator':
        return simulatorView();
      case 'passport':
        return passportView();
      case 'assistant':
        return assistantView();
      case 'season':
        return seasonView();
      case 'shop':
        return shopView();
      case 'wallet':
        return walletView();
      case 'rewards':
        return rewardsView();
      default:
        return card(
          'Страница не найдена',
          button('На главную', () => go('home')),
        );
    }
  }

  Widget homeView() {
    final e = map(data['employee']),
        g = map(data['goal']),
        p = map(data['progress']),
        saved = map(data['plan']);
    final rec = map(data['recommendations']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'Твой следующий шаг, ${value(e['full_name']).split(' ').first}',
          '${value(e['role'])} · ${value(e['grade'])}',
        ),
        card(
          g.isEmpty
              ? 'Куда ты хочешь прийти?'
              : 'Твоя цель: ${g['target_role']} · ${g['target_grade']}',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (g.isEmpty && data['suggested_goal'] != null)
                Text(
                  'Возможное направление: ${data['suggested_goal']['target_role']} ${data['suggested_goal']['target_grade']}. Предложение станет целью после сохранения.',
                ),
              if (g.isNotEmpty)
                Text(
                  data['goal_source'] == 'personal'
                      ? 'Личная цель'
                      : 'Цель из профиля',
                  style: const TextStyle(color: muted),
                ),
              const SizedBox(height: 18),
              actions([
                button(
                  g.isEmpty ? 'Выбрать цель' : 'Изменить цель',
                  () => go('goal'),
                  primary: true,
                ),
                button('Что если', () => go('simulator')),
              ]),
            ],
          ),
        ),
        progressSummary(p),
        if (data['gamification'] != null)
          seasonSummary(map(data['gamification'])),
        if (records(saved['items']).isNotEmpty)
          card(
            'Продолжи свой маршрут',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  saved['items'][0]['activity']['title'],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                button('Продолжить шаг', () => go('plan'), primary: true),
              ],
            ),
          ),
        heading(
          'Подобрано для твоей цели',
          'Проверяем требования, время и пользу каждого шага.',
        ),
        if (records(rec['items']).isEmpty)
          card('', Text(label(rec['empty_reason']))),
        for (final r in records(rec['items']))
          activityCard(map(r['activity']), recommendation: r),
        actions([
          button('Открыть каталог', () => go('catalog')),
          button(
            'Вернуть скрытые варианты',
            () => act(
              'DELETE',
              '/api/me/recommendation-exclusions?expected_revision=${api.stateRevision}',
            ),
          ),
          button('Объяснить рекомендации', () => go('assistant')),
          button('Паспорт развития', () => go('passport')),
        ]),
      ],
    );
  }

  Widget progressSummary(Json p) => card(
    'Соответствие цели',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        actions([
          metric(
            'По последней оценке',
            pct(p['assessed_readiness']),
            accent: blue,
          ),
          metric('Расчёт после действий', pct(p['estimated_readiness'])),
          metric('Покрытие оценок', pct(p['coverage']), accent: cyan),
        ]),
        const SizedBox(height: 16),
        Text(
          'Оценка от ${dateLabel(p['assessment_at'])}. Расчётные баллы не заменяют аттестацию и не гарантируют повышение.',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        if (p['status'] != 'ready')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(label(p['status'])),
          ),
        const SizedBox(height: 14),
        button('Посмотреть навыки', () => go('skills')),
      ],
    ),
  );
  Widget skillsView(Json p) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      progressSummary(p),
      for (final skill in records(p['skills']))
        card(
          value(skill['name']),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Оценка: ${value(skill['assessed_level'])} / 100    Расчёт: ${value(skill['estimated_level'])} / 100',
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value:
                    ((skill['estimated_level'] ?? 0) as num).toDouble() / 100,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 12),
              Text(
                'Требование: ${value(skill['required_level'])} · Дефицит: ${value(skill['gap'])} · Значимость: ${value(skill['weight'])}',
                style: const TextStyle(color: muted),
              ),
              ExpansionTile(
                title: const Text('Откуда этот расчёт'),
                children: [
                  Text(
                    'Исходная оценка по шкале 0–5 преобразована в 0–100. Граница начислений: ${dateLabel(p['assessment_at'])}.',
                    style: const TextStyle(color: muted),
                  ),
                  for (final c in records(skill['contributions']))
                    ListTile(
                      title: Text(c['title']),
                      subtitle: Text(
                        '+${value(c['effective_gain'])} учтено из ${c['gain']} условных баллов · ${dateLabel(c['completed_at'])}',
                      ),
                    ),
                  if (records(skill['contributions']).isEmpty)
                    empty(
                      'После оценки локальных начислений по этому навыку нет.',
                    ),
                ],
              ),
              if (!hr)
                button('Найти активности', () {
                  viewFilters['catalog'] = {'skill_id': skill['skill_id']};
                  routeState.remove('catalog');
                  go('catalog');
                }),
            ],
          ),
        ),
    ],
  );
  Widget profileView(Json profile, {bool readOnly = false}) {
    final e = map(profile['employee']);
    final prefs = map(profile['preferences']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card(
          value(e['full_name']),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${value(e['role'])} · ${value(e['grade'])}',
                style: const TextStyle(fontSize: 20, color: pink),
              ),
              const SizedBox(height: 12),
              Text(
                '${value(e['department'])}\nВ команде с ${dateLabel(e['hire_date'])}\nПоследняя оценка: ${dateLabel(e['assessment_at'])}',
              ),
              if (!readOnly) ...[
                const SizedBox(height: 18),
                actions([
                  button('Карьерная цель', () => go('goal')),
                  button('Навыки', () => go('skills')),
                  button('История', () => go('history')),
                  button('Паспорт', () => go('passport')),
                ]),
              ],
            ],
          ),
        ),
        if (!readOnly)
          card(
            'Твой ритм развития',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${prefs['weekly_minutes'] ?? 120} минут в неделю · ${value(prefs['timezone'])}',
                ),
                Text(
                  (prefs['preferred_formats'] as List? ?? [])
                      .map(label)
                      .join(' · '),
                ),
                const SizedBox(height: 16),
                button('Изменить предпочтения', () => editPreferences(prefs)),
              ],
            ),
          ),
        if (readOnly) ...[
          progressSummaryReadOnly(map(profile['progress'])),
          planView(map(profile['plan']), readOnly: true),
          historyView(records(profile['history']?['items']), readOnly: true),
        ],
      ],
    );
  }

  Widget progressSummaryReadOnly(Json p) => card(
    'Навыки сотрудника',
    Column(
      children: [
        Text(
          'Оценка: ${pct(p['assessed_readiness'])} · Расчёт: ${pct(p['estimated_readiness'])}',
        ),
        for (final r in records(p['skills']))
          ListTile(
            title: Text(r['name']),
            subtitle: Text(
              'Оценка ${value(r['assessed_level'])} → расчёт ${value(r['estimated_level'])}; требование ${value(r['required_level'])}',
            ),
          ),
      ],
    ),
  );
  Future<void> editPreferences(Json old) async {
    var minutes = (old['weekly_minutes'] ?? 120) as int;
    var zone = (old['timezone'] ?? 'Asia/Almaty') as String;
    final formats = Set<String>.from(
      old['preferred_formats'] ?? ['online', 'offline', 'self_paced'],
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Время и форматы'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$minutes минут в неделю'),
                  Slider(
                    value: minutes.toDouble(),
                    min: 30,
                    max: 600,
                    divisions: 19,
                    label: '$minutes',
                    onChanged: (v) => update(() => minutes = v.round()),
                  ),
                  for (final f in ['online', 'offline', 'self_paced'])
                    CheckboxListTile(
                      title: Text(label(f)),
                      value: formats.contains(f),
                      onChanged: (v) => update(() {
                        v == true ? formats.add(f) : formats.remove(f);
                      }),
                    ),
                  select('Часовой пояс', zone, [
                    for (final z in ['Asia/Almaty', 'Asia/Qyzylorda', 'UTC'])
                      (z, z),
                  ], (v) => update(() => zone = v)),
                ],
              ),
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
    if (result == true) {
      await act('PATCH', '/api/me/preferences', {
        'weekly_minutes': minutes,
        'preferred_formats': formats.toList(),
        'timezone': zone,
      });
    }
  }

  Widget goalView() {
    final roles = records(reference['roles']);
    final selected = map(data['goal']).isNotEmpty
        ? map(data['goal'])
        : map(data['suggested_goal']);
    simulationRole ??= selected['target_role'];
    simulationGrade ??= selected['target_grade'];
    final names = roles.map((r) => r['role_id'] as String).toSet().toList();
    final grades = roles
        .where((r) => r['role_id'] == simulationRole)
        .map((r) => r['grade_id'] as String)
        .toList();
    final req = roles
        .where(
          (r) =>
              r['role_id'] == simulationRole &&
              r['grade_id'] == simulationGrade,
        )
        .firstOrNull;
    return card(
      'Выбери своё направление',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Это цель развития. Выбор не меняет текущую должность.'),
          const SizedBox(height: 20),
          select(
            'Роль',
            simulationRole ?? '',
            [for (final n in names) (n, n)],
            (v) => setState(() {
              simulationRole = v;
              simulationGrade = null;
            }),
          ),
          const SizedBox(height: 16),
          select(
            'Грейд',
            grades.contains(simulationGrade) ? simulationGrade! : '',
            [for (final g in grades) (g, g)],
            (v) => setState(() => simulationGrade = v),
          ),
          if (req != null) ...[
            const SizedBox(height: 20),
            const Text('Требования цели'),
            for (final entry in map(req['requirements']).entries)
              ListTile(
                title: Text(skillName(entry.key)),
                trailing: Text('${entry.value['level']} / 100'),
              ),
          ],
          const SizedBox(height: 20),
          actions([
            button('Сохранить цель', () async {
              if (simulationRole == null || simulationGrade == null) {
                setState(() => error = 'Выберите роль и грейд');
                return;
              }
              final items = records(data['plan']?['items']);
              if (items.isNotEmpty &&
                  !await confirm(
                    'Изменить цель?',
                    'Если роль или грейд изменятся, эти шаги будут архивированы:\n${items.map((p) => p['activity']['title']).join('\n')}',
                  )) {
                return;
              }
              await act('PUT', '/api/me/goal', {
                'role_id': simulationRole,
                'grade_id': simulationGrade,
                'confirm_archive_plan': true,
              });
            }, primary: true),
            button('Сбросить личную цель', () async {
              if (await confirm(
                'Сбросить цель?',
                'Вернётся цель из профиля. При изменении направления активные шаги будут архивированы.',
              )) {
                await act(
                  'DELETE',
                  '/api/me/goal?expected_revision=${api.stateRevision}&confirm_archive_plan=true',
                );
              }
            }),
            button('Отмена', () => go('home')),
          ]),
        ],
      ),
    );
  }

  String skillName(String id) => value(
    records(reference['skills'])
        .where((s) => s['skill_id'] == id)
        .firstOrNull?['name'],
    id,
  );
  Widget activityCard(Json a, {Json? recommendation}) => card(
    value(a['title']),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${label(a['format'])} · ${a['duration_minutes']} мин.',
          style: const TextStyle(color: cyan),
        ),
        const SizedBox(height: 10),
        Text(value(a['description'])),
        const SizedBox(height: 12),
        Text(
          map(a['gains']).entries
              .map((g) => '${skillName(g.key)} +${g.value}')
              .join(' · '),
          style: const TextStyle(color: violet),
        ),
        if (a['blocked_reason'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              label(a['blocked_reason']),
              style: const TextStyle(color: muted),
            ),
          ),
        if (recommendation != null) ...[
          const SizedBox(height: 12),
          Text(
            'Если выполнить сейчас: +${(recommendation['standalone_delta_pp'] as num).toStringAsFixed(1)} п.п.',
            style: const TextStyle(color: pink),
          ),
          ExpansionTile(
            title: const Text('Почему этот шаг'),
            children: [
              for (final reason in recommendation['reasons'])
                Padding(padding: const EdgeInsets.all(8), child: Text(reason)),
            ],
          ),
        ],
        const SizedBox(height: 18),
        actions([
          button('Подробнее', () => go('activities/${a['id']}')),
          if (a['blocked_reason'] == null)
            button(
              'Добавить в план',
              () => addActivity(a['id']),
              primary: true,
            ),
          if (recommendation != null)
            button('Не подходит', () => excludeActivity(a['id'])),
        ]),
      ],
    ),
  );
  Future<void> excludeActivity(String aid) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Почему не подходит?'),
        children: [
          for (final reason in [
            ('time', 'Мало времени'),
            ('format', 'Неинтересный формат'),
            ('known', 'Уже знакомо'),
            ('other', 'Другое'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, reason.$1),
              child: Text(reason.$2),
            ),
        ],
      ),
    );
    if (choice != null) {
      await act('POST', '/api/me/recommendation-exclusions', {
        'activity_id': aid,
        'reason': choice,
      });
    }
  }

  Future<void> addActivity(String aid, {String? replace}) async {
    if (busy) return;
    var body = <String, dynamic>{'activity_id': aid};
    final path = replace == null
        ? '/api/me/plan/items'
        : '/api/me/plan/items/${segment(replace)}/replace';
    // Each opt-in is explicit and resolves only the corresponding server warning.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        setState(() => busy = true);
        await api.request('POST', path, body);
        await reload();
        return;
      } on ApiException catch (e) {
        if (e.code == 'NO_GOAL_GAIN' || e.code == 'OVER_BUDGET') {
          setState(() => busy = false);
          if (!await confirm('Добавить шаг?', e.message)) return;
          body[e.code == 'NO_GOAL_GAIN'
                  ? 'accept_no_goal_gain'
                  : 'accept_over_budget'] =
              true;
        } else {
          if (mounted) setState(() => error = e.message);
          return;
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
  }

  Widget catalogView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      card(
        'Найди следующий шаг',
        Column(
          children: [
            TextFormField(
              initialValue: search,
              decoration: const InputDecoration(
                labelText: 'Поиск по названию и описанию',
                prefixIcon: Icon(Icons.search),
              ),
              onFieldSubmitted: (v) {
                search = v;
                listPage = 1;
                reload();
              },
            ),
            const SizedBox(height: 14),
            select(
              'Формат',
              filter,
              [
                ('', 'Все форматы'),
                ('online', 'Онлайн'),
                ('offline', 'Очно'),
                ('self_paced', 'Самостоятельно'),
              ],
              (v) {
                filter = v;
                listPage = 1;
                reload();
              },
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: actions([
          button(
            'Навык, время и доступность',
            () => editListFilters(
              'Фильтры каталога',
              [
                (
                  'skill_id',
                  'Навык',
                  [
                    ('', 'Все навыки'),
                    for (final sk in records(reference['skills']))
                      (sk['skill_id'] as String, sk['name'] as String),
                  ],
                ),
                (
                  'available',
                  'Доступность',
                  [
                    ('', 'Все активности'),
                    ('true', 'Доступные мне'),
                    ('false', 'С ограничениями'),
                  ],
                ),
              ],
              [('max_minutes', 'Максимум минут')],
            ),
          ),
        ]),
      ),
      for (final a in records(data['items'])) activityCard(a),
      if (records(data['items']).isEmpty)
        empty('По этим условиям активностей нет.'),
      pager(data),
    ],
  );
  Widget planView(Json saved, {bool readOnly = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Твой план',
        '${saved['total_minutes'] ?? 0} мин. · ориентир ${saved['estimated_weeks'] ?? 0} нед. при выбранном ритме',
      ),
      if (records(saved['items']).isEmpty)
        empty(
          'В плане пока нет шагов. Выберите рекомендации или откройте каталог.',
        ),
      for (final (i, p) in records(saved['items']).indexed)
        card(
          '${i + 1}. ${p['activity']['title']}',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label(p['status']), style: const TextStyle(color: pink)),
              if (p['blocked_reason'] != null) Text(label(p['blocked_reason'])),
              const SizedBox(height: 16),
              if (!readOnly)
                actions([
                  button(
                    'Открыть материал',
                    () => go('activities/${p['activity_id']}'),
                  ),
                  if (p['status'] == 'planned')
                    button(
                      'Начать',
                      () => act(
                        'POST',
                        '/api/me/plan/items/${segment(p['id'])}/start',
                      ),
                      primary: true,
                    ),
                  if (p['status'] == 'in_progress')
                    button('Завершить', () => completeStep(p), primary: true),
                  button('Заменить', () => replaceStep(p)),
                  button('Убрать', () async {
                    if (await confirm('Убрать шаг?', p['activity']['title'])) {
                      await act(
                        'POST',
                        '/api/me/plan/items/${segment(p['id'])}/archive',
                      );
                    }
                  }),
                  if (i > 0)
                    button('Выше', () {
                      final ids = records(saved['items'])
                          .map((x) => x['id'])
                          .toList();
                      final previous = ids[i - 1];
                      ids[i - 1] = ids[i];
                      ids[i] = previous;
                      act('PUT', '/api/me/plan/order', {'item_ids': ids});
                    }),
                ]),
            ],
          ),
        ),
      if (!readOnly) button('Открыть каталог', () => go('catalog')),
    ],
  );
  Future<void> replaceStep(Json p) async {
    final items = <Json>[];
    try {
      for (var p = 1; ; p++) {
        final result = await api.get('/api/activities?available=true&page=$p');
        items.addAll(records(result['items']));
        if (items.length >= result['total']) break;
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
      return;
    }
    if (!mounted) return;
    final aid = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Заменить шаг'),
        children: [
          for (final a in items)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a['id']),
              child: Text('${a['title']} · ${a['duration_minutes']} мин.'),
            ),
        ],
      ),
    );
    if (aid != null) await addActivity(aid, replace: p['id']);
  }

  Future<void> completeStep(Json p) async {
    final note = TextEditingController();
    var checked = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            'Завершить «${p['activity']?['title'] ?? data['activity']?['title']}»',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    value: checked,
                    onChanged: (v) => update(() => checked = v ?? false),
                    title: const Text('Я выполнил(а) активность'),
                  ),
                  TextField(
                    controller: note,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Что удалось применить? (необязательно)',
                    ),
                  ),
                  const Text(
                    'Самоотчёт меняет расчётный прогресс. Для XP отправьте результат на проверку HR.',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Подтвердить выполнение'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        setState(() => busy = true);
        final result = await api.request(
          'POST',
          '/api/me/plan/items/${segment(p['id'])}/complete',
          {'confirmed': true, 'note': note.text},
        );
        await reload();
        if (mounted) {
          await confirm(
            'Результат сохранён',
            'Расчётное соответствие: ${pct(result['before']?['estimated_readiness'])} → ${pct(result['progress']?['estimated_readiness'])}.\nПоследняя оценка не изменена. Запись добавлена в историю.',
            action: 'Понятно',
          );
        }
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    Future.delayed(const Duration(milliseconds: 350), note.dispose);
  }

  Widget activityView() {
    final a = map(data['activity']);
    if (a.isEmpty) return empty('Активность не найдена.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: button('Назад к каталогу', () => go('catalog')),
        ),
        const SizedBox(height: 18),
        card(
          a['title'],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${label(a['format'])} · ${a['duration_minutes']} минут',
                style: const TextStyle(color: cyan),
              ),
              const SizedBox(height: 16),
              Text(a['description']),
              const SizedBox(height: 20),
              Text('Результат: ${a['outcome']}'),
              const SizedBox(height: 16),
              Text(
                map(a['gains']).entries
                    .map(
                      (g) => '${skillName(g.key)}: +${g.value} условных баллов',
                    )
                    .join('\n'),
              ),
              if (map(a['prerequisites']).isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Предварительные требования:\n${map(a['prerequisites']).entries.map((g) => '${skillName(g.key)}: ${g.value}').join('\n')}',
                ),
              ],
              const SizedBox(height: 22),
              Text(a['instructions'], style: const TextStyle(height: 1.8)),
              const SizedBox(height: 20),
              if (data['completion'] != null)
                button('Результат в истории', () => go('history'))
              else if (data['plan_item'] != null)
                actions([
                  if (data['plan_item']['status'] == 'planned')
                    button(
                      'Начать',
                      () => act(
                        'POST',
                        '/api/me/plan/items/${segment(data['plan_item']['id'])}/start',
                      ),
                      primary: true,
                    ),
                  if (data['plan_item']['status'] == 'in_progress')
                    button(
                      'Завершить',
                      () => completeStep(map(data['plan_item'])),
                      primary: true,
                    ),
                  button('Открыть план', () => go('plan')),
                ])
              else if (data['blocked_reason'] == null)
                button(
                  'Добавить в план',
                  () => addActivity(a['id']),
                  primary: true,
                )
              else
                Text(label(data['blocked_reason'])),
            ],
          ),
        ),
      ],
    );
  }

  Widget historyView(List<Json> rows, {bool readOnly = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'История развития',
        'Исходные записи и ваши действия объединены без повторного начисления навыков.',
      ),
      if (!readOnly)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: actions([
            button(
              'Статус, формат и даты',
              () => editListFilters(
                'Фильтры истории',
                [
                  (
                    'status',
                    'Статус',
                    [
                      ('', 'Все'),
                      ('completed', 'Завершено'),
                      ('in_progress', 'В работе'),
                      ('registered', 'Зарегистрировано'),
                    ],
                  ),
                  (
                    'format',
                    'Формат',
                    [
                      ('', 'Все'),
                      ('online', 'Онлайн'),
                      ('offline', 'Очно'),
                      ('self_paced', 'Самостоятельно'),
                    ],
                  ),
                ],
                [
                  ('date_from', 'С даты ГГГГ-ММ-ДД'),
                  ('date_to', 'По дату ГГГГ-ММ-ДД'),
                ],
              ),
            ),
          ]),
        ),
      if (!readOnly)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: select(
            'Источник',
            filter,
            [
              ('', 'Все'),
              ('imported', 'Исходные записи'),
              ('self_report', 'Самоотчёты'),
            ],
            (v) {
              filter = v;
              listPage = 1;
              reload();
            },
          ),
        ),
      for (final h in rows)
        card(
          h['activity']['title'],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${label(h['status'])} · ${dateLabel(h['completed_at'] ?? h['started_at'])}',
              ),
              Text(
                records(h['sources'])
                    .map((s) => label(s['origin']))
                    .toSet()
                    .join(' + '),
                style: const TextStyle(color: muted),
              ),
              if (h['note'] != null) Text(h['note']),
              if (h['completion_id'] != null && !readOnly) ...[
                const SizedBox(height: 16),
                reviewStatus(h),
              ],
            ],
          ),
        ),
      if (rows.isEmpty) empty('Здесь появятся ваши активности.'),
      if (!readOnly) pager(data),
    ],
  );
  Widget reviewStatus(Json history) {
    final review = records(data['reviews']?['items'])
        .where((r) => r['completion_id'] == history['completion_id'])
        .firstOrNull;
    if (review != null) {
      return Text(
        '${label(review['status'])} · ${review['xp_amount']} XP${review['decision_note'] == null ? '' : '\n${review['decision_note']}'}',
        style: const TextStyle(color: violet),
      );
    }
    return button('Отправить результат на проверку', () async {
      final evidence = await prompt(
        'Результат практики',
        hint: '80–2000 символов: что сделали, как проверили, какие выводы получили.',
      );
      if (evidence != null) {
        await act(
          'POST',
          '/api/me/completions/${segment(history['completion_id'])}/reward-review',
          {'evidence_text': evidence},
        );
      }
    });
  }

  void scheduleSimulation() {
    previewDebounce?.cancel();
    previewDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted &&
          page == 'simulator' &&
          simulationRole != null &&
          simulationGrade != null) {
        calculateSimulation();
      }
    });
  }

  Future<void> calculateSimulation() async {
    final request = ++previewGeneration;
    try {
      final result = await api.request('POST', '/api/me/simulations', {
        'role_id': simulationRole,
        'grade_id': simulationGrade,
        'activity_ids': simulationIds.toList(),
      });
      if (mounted && request == previewGeneration && page == 'simulator') {
        setState(() {
          simulation = result;
          error = '';
        });
      }
    } catch (e) {
      if (mounted && request == previewGeneration) {
        setState(() => error = e.toString());
      }
    }
  }

  Widget simulatorView() {
    final roles = records(reference['roles']);
    final goal = map(home['goal']);
    simulationRole ??= goal['target_role'];
    simulationGrade ??= goal['target_grade'];
    final names = roles.map((r) => r['role_id'] as String).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card(
          'Проверь возможный маршрут',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('До сохранения цель, план и навыки не меняются.'),
              const SizedBox(height: 18),
              select(
                'Роль',
                simulationRole ?? '',
                [for (final name in names) (name, name)],
                (v) => setState(() {
                  simulationRole = v;
                  simulationGrade = null;
                  simulation = null;
                  scheduleSimulation();
                }),
              ),
              const SizedBox(height: 14),
              select(
                'Грейд',
                simulationGrade ?? '',
                [
                  for (final r in roles.where(
                    (r) => r['role_id'] == simulationRole,
                  ))
                    (r['grade_id'] as String, r['grade_id'] as String),
                ],
                (v) => setState(() {
                  simulationGrade = v;
                  simulation = null;
                  scheduleSimulation();
                }),
              ),
              const SizedBox(height: 16),
              button('Включить текущий план', () {
                setState(() {
                  simulationIds = records(home['plan']?['items'])
                      .map((p) => p['activity_id'] as String)
                      .toSet();
                  simulation = null;
                  scheduleSimulation();
                });
              }),
              for (final a in records(data['items']))
                CheckboxListTile(
                  value: simulationIds.contains(a['id']),
                  title: Text(a['title']),
                  subtitle: Text('${a['duration_minutes']} мин.'),
                  onChanged: (v) {
                    setState(() {
                      if (v == true && simulationIds.length < 3) {
                        simulationIds.add(a['id']);
                      } else if (v != true) {
                        simulationIds.remove(a['id']);
                      }
                      simulation = null;
                      scheduleSimulation();
                    });
                  },
                ),
              pager(data),
              Text('Выбрано ${simulationIds.length} из 3'),
              const SizedBox(height: 16),
              button('Рассчитать маршрут', calculateSimulation, primary: true),
            ],
          ),
        ),
        if (simulation != null)
          card(
            'Результат симуляции',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${pct(simulation!['before']['estimated_readiness'])} → ${pct(simulation!['after']['estimated_readiness'])}',
                  style: const TextStyle(fontSize: 30, color: pink),
                ),
                Text(
                  '${simulation!['total_minutes']} минут · ${simulation!['estimated_weeks']} недель',
                ),
                if (simulation!['over_budget'] == true)
                  const Text('Превышен бюджет четырёх недель.'),
                const SizedBox(height: 18),
                button('Сохранить этот план', () async {
                  if (await confirm(
                    'Заменить цель и план?',
                    'Останутся выбранные шаги:\n${records(simulation!['items']).map((p) => p['activity_id']).join('\n')}\nТекущие шаги вне списка будут архивированы.${simulation!['over_budget'] == true ? '\nВы также подтверждаете превышение бюджета времени.' : ''}',
                  )) {
                    await act(
                      'POST',
                      '/api/me/simulations/${segment(simulation!['id'])}/apply',
                      {
                        'confirm_replace_plan': true,
                        'accept_over_budget': simulation!['over_budget'],
                        'expected_revision': simulation!['revision'],
                      },
                    );
                  }
                }, primary: true),
              ],
            ),
          ),
      ],
    );
  }

  Widget passportView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading('Паспорт развития', value(data['employee']?['full_name'])),
      button(
        'Скачать Markdown',
        () => download('/api/me/passport/download', 'career-passport.md'),
        primary: true,
      ),
      const SizedBox(height: 20),
      progressSummaryReadOnly(map(data['progress'])),
      planView(map(data['plan']), readOnly: true),
      card(
        'Достижения',
        Text(
          records(data['achievements']).map((b) => b['name']).join('\n').isEmpty
              ? 'Достижения появятся после подтверждённых действий.'
              : records(data['achievements']).map((b) => b['name']).join('\n'),
        ),
      ),
    ],
  );
  Widget assistantView() => card(
    'Разберём твой маршрут',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Помощник объясняет расчёты по вашему профилю. Он не принимает решения о повышении.',
        ),
        const SizedBox(height: 20),
        actions([
          for (final q in [
            ('why', 'Почему эти шаги?'),
            ('time', 'Как уложиться во время?'),
            ('forecast', 'Что изменится после плана?'),
            ('gaps', 'Каких навыков не хватает?'),
          ])
            button(q.$2, () async {
              setState(() => busy = true);
              try {
                final result = await api.request(
                  'POST',
                  '/api/me/assistant/explain',
                  {'question': q.$1},
                );
                if (mounted) setState(() => data = result);
              } catch (e) {
                if (mounted) setState(() => error = e.toString());
              } finally {
                if (mounted) setState(() => busy = false);
              }
            }),
        ]),
        const SizedBox(height: 24),
        if (busy) const LinearProgressIndicator(),
        if (data['text'] != null) ...[
          Text(data['text'], style: const TextStyle(fontSize: 17, height: 1.8)),
          const SizedBox(height: 14),
          Text(
            data['mode'] == 'llm'
                ? 'Объяснение OpenAI на основе расчётов'
                : 'Объяснение на основе данных профиля',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ],
    ),
  );
}
