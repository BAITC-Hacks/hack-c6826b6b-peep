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
        if (data['gamification'] != null)
          seasonSummary(map(data['gamification'])),
        heading(
          'Привет, ${value(e['full_name']).split(' ').first}',
          '${value(e['role'])} · ${value(e['grade'])} · здесь только самое важное',
        ),
        journeyGuide(g, saved, rec),
        if (g.isNotEmpty) goalOverview(g, data['goal_source'] == 'personal'),
        progressSummary(p),
        heading(
          'Рекомендуемые шаги',
          'Показываем не больше трёх вариантов и объясняем пользу каждого.',
        ),
        if (records(rec['items']).isEmpty)
          card('', Text(label(rec['empty_reason']))),
        for (final r in records(rec['items']))
          activityCard(map(r['activity']), recommendation: r),
        actions([
          button('Все активности', () => go('catalog')),
          button('OpenAI-помощник', () => go('assistant')),
          if (rec['empty_reason'] == 'all_candidates_hidden')
            button(
              'Вернуть скрытые варианты',
              () => act(
                'DELETE',
                '/api/me/recommendation-exclusions?expected_revision=${api.stateRevision}',
              ),
            ),
        ]),
      ],
    );
  }

  Widget goalOverview(Json goal, bool personal) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          blue.withValues(alpha: .13),
          const Color(0xFF17213E),
          violet.withValues(alpha: .08),
        ],
      ),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: blue.withValues(alpha: .28)),
      boxShadow: [
        BoxShadow(
          color: blue.withValues(alpha: .06),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 680;
        final details = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: blue.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: blue.withValues(alpha: .25)),
              ),
              child: const Icon(Icons.explore_rounded, color: blue, size: 27),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ТВОЁ НАПРАВЛЕНИЕ',
                    style: TextStyle(
                      color: cyan,
                      fontSize: 9,
                      letterSpacing: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${goal['target_role']} · ${goal['target_grade']}',
                    style: const TextStyle(
                      color: ink,
                      fontSize: 21,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    personal
                        ? 'Направление выбрано тобой и его можно изменить.'
                        : 'Направление предложено на основе текущего профиля.',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
        final controls = actions([
          button('Изменить', () => go('goal')),
          button('Примерить другую цель', () => go('simulator')),
        ]);
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [details, const SizedBox(height: 20), controls],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: details),
            const SizedBox(width: 24),
            controls,
          ],
        );
      },
    ),
  );

  Widget journeyGuide(Json goal, Json saved, Json recommendations) {
    final planItems = records(saved['items']);
    final hasGoal = goal.isNotEmpty;
    final hasPlan = planItems.isNotEmpty;
    final hasAction = planItems.any(
      (item) => ['in_progress', 'completed'].contains(item['status']),
    );
    final step = !hasGoal
        ? 0
        : !hasPlan
        ? 1
        : 2;
    final title = switch (step) {
      0 => 'Сначала выбери направление',
      1 => 'Добавь первый шаг в маршрут',
      _ =>
        hasAction
            ? 'Продолжи начатый шаг'
            : 'Маршрут готов — начни с первого шага',
    };
    final description = switch (step) {
      0 => 'Это займёт минуту: выбери роль и уровень, к которым хочешь двигаться. Решение можно изменить позже.',
      1 =>
        records(recommendations['items']).isNotEmpty
            ? 'Мы уже подобрали варианты под твою цель и ритм. Выбери один — весь план сразу не нужен.'
            : 'Открой список активностей и выбери один реалистичный шаг на ближайшее время.',
      _ =>
        'В маршруте ${planItems.length} ${planItems.length == 1 ? 'шаг' : 'шага'}. Открой его и двигайся по порядку.',
    };
    final action = switch (step) {
      0 => ('Выбрать направление', 'goal'),
      1 => ('Выбрать первый шаг', 'catalog'),
      _ => ('Открыть маршрут', 'plan'),
    };
    final completed = [hasGoal, hasPlan, hasAction];
    const labels = ['Направление', 'Первый шаг', 'Действие'];
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C2C55), Color(0xFF241D43)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: violet.withValues(alpha: .38)),
        boxShadow: [
          BoxShadow(
            color: violet.withValues(alpha: .09),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ТВОЙ МАРШРУТ · ШАГ ${step + 1} ИЗ 3',
            style: const TextStyle(
              color: cyan,
              fontSize: 9,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: ink,
              fontSize: 24,
              height: 1.25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(
              description,
              style: const TextStyle(color: muted, height: 1.65),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => go(action.$2),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(action.$1),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (index, label) in labels.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: completed[index]
                        ? cyan.withValues(alpha: .1)
                        : index == step
                        ? pink.withValues(alpha: .11)
                        : night.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: completed[index]
                          ? cyan.withValues(alpha: .28)
                          : index == step
                          ? pink.withValues(alpha: .28)
                          : line.withValues(alpha: .55),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        completed[index]
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: completed[index]
                            ? cyan
                            : index == step
                            ? pink
                            : muted,
                        size: 15,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget progressSummary(Json p) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF172442), Color(0xFF161C35)],
      ),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: cyan.withValues(alpha: .2)),
      boxShadow: [
        BoxShadow(
          color: cyan.withValues(alpha: .045),
          blurRadius: 26,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cyan.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.insights_rounded, color: cyan, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: SectionTitle(
                'Прогресс к цели',
                subtitle: 'Три показателя отвечают на разные вопросы и не смешиваются между собой.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        actions([
          metric(
            'Последняя оценка',
            pct(p['assessed_readiness']),
            accent: blue,
          ),
          metric('Расчёт после шагов', pct(p['estimated_readiness'])),
          metric('Полнота данных', pct(p['coverage']), accent: cyan),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: night.withValues(alpha: .34),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: line.withValues(alpha: .52)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: muted, size: 18),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Оценка от ${dateLabel(p['assessment_at'])}. Расчёт после действий не заменяет аттестацию и не гарантирует повышение.',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (p['status'] != 'ready')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(label(p['status'])),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => go('skills'),
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          iconAlignment: IconAlignment.end,
          label: const Text('Разобрать навыки'),
        ),
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tag(label(a['format']), icon: Icons.widgets_outlined, color: cyan),
            Tag(
              '${a['duration_minutes']} мин.',
              icon: Icons.schedule_rounded,
              color: blue,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(value(a['description']), style: const TextStyle(height: 1.55)),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: violet.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: violet.withValues(alpha: .16)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.trending_up_rounded, color: violet, size: 18),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  map(a['gains']).entries
                      .map((g) => '${skillName(g.key)} +${g.value}')
                      .join(' · '),
                  style: const TextStyle(color: violet, height: 1.4),
                ),
              ),
            ],
          ),
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
  Widget planView(Json saved, {bool readOnly = false}) {
    final items = records(saved['items']);
    final totalMinutes = saved['total_minutes'] ?? 0;
    final estimatedWeeks = saved['estimated_weeks'] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'Шаги маршрута',
          'Двигайся по дороге последовательно: один реальный шаг за другим.',
        ),
        _planSummary(items.length, totalMinutes, estimatedWeeks),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: button(
            'Собрать маршрут с OpenAI',
            () => go('assistant'),
            primary: true,
          ),
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EmptyState(
                  'Дорога начинается с первой точки',
                  'Выбери одну активность, которую реально начать в ближайшее время.',
                  icon: Icons.add_road_rounded,
                ),
                if (!readOnly)
                  button(
                    'Проложить первый шаг',
                    () => go('catalog'),
                    primary: true,
                  ),
              ],
            ),
          )
        else
          _planRoad(items, readOnly),
        if (!readOnly && items.isNotEmpty) ...[
          const SizedBox(height: 18),
          if (items.length < 3)
            button('Проложить ещё один шаг', () => go('catalog'))
          else
            const Center(
              child: Tag(
                'Маршрут собран · 3 шага',
                color: cyan,
                icon: Icons.flag_rounded,
              ),
            ),
        ],
      ],
    );
  }

  Widget _planSummary(int count, dynamic minutes, dynamic weeks) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [blue.withValues(alpha: .12), violet.withValues(alpha: .07)],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: blue.withValues(alpha: .22)),
    ),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.alt_route_rounded, color: blue, size: 22),
        Text(
          count == 0
              ? 'Маршрут пока пуст'
              : 'Маршрут из $count ${count == 1 ? 'шага' : 'шагов'}',
          style: const TextStyle(
            color: ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        Tag('$count / 3', color: violet, icon: Icons.route_rounded),
        Tag('$minutes мин.', color: pink, icon: Icons.schedule_rounded),
        Tag('~$weeks нед.', color: cyan, icon: Icons.calendar_month_rounded),
      ],
    ),
  );

  Widget _planRoad(List<Json> items, bool readOnly) => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF111A34), Color(0xFF0B1128)],
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: line.withValues(alpha: .78)),
      boxShadow: [
        BoxShadow(
          color: blue.withValues(alpha: .055),
          blurRadius: 32,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 720;
        final rowHeight = compact ? 350.0 : 238.0;
        const topInset = 54.0;
        const bottomInset = 58.0;
        final height = topInset + rowHeight * items.length + bottomInset;
        double stopX(int i) =>
            compact ? 34 : box.maxWidth * (i.isEven ? .2 : .8);
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CareerRoadPainter(
                    stops: items.length,
                    compact: compact,
                    rowHeight: rowHeight,
                    topInset: topInset,
                    bottomInset: bottomInset,
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: box.maxWidth / 2 - 15,
                child: const _RoadTerminal(
                  icon: Icons.navigation_rounded,
                  color: blue,
                  semanticsLabel: 'Начало маршрута',
                ),
              ),
              for (final (i, item) in items.indexed) ...[
                Positioned(
                  top: topInset + i * rowHeight + 17,
                  left: compact ? 76 : (i.isEven ? box.maxWidth * .32 : 18),
                  right: compact ? 12 : (i.isEven ? 18 : box.maxWidth * .32),
                  child: _planStepCard(item, i, items, readOnly, compact),
                ),
                Positioned(
                  top: topInset + i * rowHeight + rowHeight / 2 - 28,
                  left: stopX(i) - 28,
                  child: _RoadStop(
                    number: i + 1,
                    status: value(item['status'], 'planned'),
                    title: value(item['activity']?['title']),
                  ),
                ),
              ],
              Positioned(
                bottom: 12,
                left: box.maxWidth / 2 - 15,
                child: const _RoadTerminal(
                  icon: Icons.flag_rounded,
                  color: pink,
                  semanticsLabel: 'Конец текущего маршрута',
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _planStepCard(
    Json item,
    int index,
    List<Json> items,
    bool readOnly,
    bool compact,
  ) {
    final activity = map(item['activity']);
    final status = value(item['status'], 'planned');
    final statusColor = _roadStatusColor(status);
    return Surface(
      padding: 18,
      color: const Color(0xFF182340),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            Wrap(
              spacing: 8,
              runSpacing: 7,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _roadStepLabel(index),
                Tag(
                  label(status),
                  color: statusColor,
                  background: statusColor.withValues(alpha: .09),
                ),
              ],
            )
          else
            Row(
              children: [
                _roadStepLabel(index),
                const Spacer(),
                Tag(
                  label(status),
                  color: statusColor,
                  background: statusColor.withValues(alpha: .09),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Text(
            value(activity['title']),
            style: const TextStyle(
              color: ink,
              fontSize: 19,
              height: 1.25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 12,
            runSpacing: 7,
            children: [
              if (activity['duration_minutes'] != null)
                _roadMeta(
                  Icons.schedule_rounded,
                  '${activity['duration_minutes']} мин.',
                ),
              if (activity['format'] != null)
                _roadMeta(Icons.widgets_outlined, label(activity['format'])),
            ],
          ),
          if (item['blocked_reason'] != null) ...[
            const SizedBox(height: 10),
            Text(
              label(item['blocked_reason']),
              style: const TextStyle(color: danger, fontSize: 12, height: 1.4),
            ),
          ],
          if (!readOnly) ...[
            const SizedBox(height: 16),
            Divider(color: line.withValues(alpha: .65), height: 1),
            const SizedBox(height: 14),
            actions([
              button(
                'Открыть материал',
                () => go('activities/${item['activity_id']}'),
              ),
              if (status == 'planned')
                button(
                  'Начать',
                  () => act(
                    'POST',
                    '/api/me/plan/items/${segment(item['id'])}/start',
                  ),
                  primary: true,
                ),
              if (status == 'in_progress')
                button('Завершить', () => completeStep(item), primary: true),
              button('Заменить', () => replaceStep(item)),
              button('Убрать', () async {
                if (await confirm('Убрать шаг?', activity['title'])) {
                  await act(
                    'POST',
                    '/api/me/plan/items/${segment(item['id'])}/archive',
                  );
                }
              }),
              if (index > 0)
                button('Поднять выше', () {
                  final ids = items.map((x) => x['id']).toList();
                  final previous = ids[index - 1];
                  ids[index - 1] = ids[index];
                  ids[index] = previous;
                  act('PUT', '/api/me/plan/order', {'item_ids': ids});
                }),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _roadMeta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: muted, size: 13),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: muted, fontSize: 10),
        ),
      ),
    ],
  );

  Widget _roadStepLabel(int index) => Text(
    'ЭТАП ${(index + 1).toString().padLeft(2, '0')}',
    style: const TextStyle(
      color: blue,
      fontSize: 9,
      letterSpacing: 1.35,
      fontWeight: FontWeight.w800,
    ),
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
              if ((a['image_url'] ?? '').toString().isNotEmpty)
                Image.network(
                  a['image_url'],
                  height: 180,
                  fit: BoxFit.contain,
                  semanticLabel: a['title'],
                  errorBuilder: (_, error, stack) => const SizedBox.shrink(),
                ),
              if ((a['external_url'] ?? '').toString().isNotEmpty)
                SelectableText('Материал: ${a['external_url']}'),
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
  Widget assistantView() {
    final answer = map(data['answer']);
    final draft = map(data['draft']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'OpenAI Career Copilot',
          'Объясняет расчёты и собирает черновик маршрута из реальных мероприятий.',
        ),
        _assistantHero(data['configured'] == true),
        card(
          'Разобраться в рекомендациях',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Выбери вопрос — помощник ответит по твоей цели, оценкам и сохранённому плану.',
                style: TextStyle(color: muted, height: 1.6),
              ),
              const SizedBox(height: 18),
              actions([
                for (final q in [
                  ('why', 'Почему эти шаги?'),
                  ('time', 'Как уложиться во время?'),
                  ('forecast', 'Что изменится после плана?'),
                  ('gaps', 'Каких навыков не хватает?'),
                ])
                  button(q.$2, () => _askOpenAI(q.$1)),
              ]),
            ],
          ),
        ),
        if (answer.isNotEmpty) _assistantAnswer(answer),
        card(
          'Собрать маршрут по мероприятиям',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'OpenAI выберет до трёх совместимых шагов из каталога. Сервер проверит время, конфликты и пользу для цели.',
                style: TextStyle(color: muted, height: 1.6),
              ),
              const SizedBox(height: 18),
              actions([
                button(
                  'Сбалансированный',
                  () => _composeOpenAIPlan('balanced'),
                  primary: true,
                  icon: Icons.route_rounded,
                ),
                button('Быстрый старт', () => _composeOpenAIPlan('quick')),
                button('Максимум эффекта', () => _composeOpenAIPlan('impact')),
              ]),
            ],
          ),
        ),
        if (busy) ...[
          const LinearProgressIndicator(color: pink),
          const SizedBox(height: 18),
        ],
        if (draft.isNotEmpty) _assistantDraft(draft),
      ],
    );
  }

  Widget _assistantHero(bool configured) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1D2E58), Color(0xFF241B43)],
      ),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: violet.withValues(alpha: .35)),
      boxShadow: [
        BoxShadow(color: violet.withValues(alpha: .08), blurRadius: 30),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, box) {
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tag(
              configured ? 'OPENAI ПОДКЛЮЧЁН' : 'ЛОКАЛЬНЫЙ РЕЖИМ',
              color: configured ? cyan : violet,
              icon: configured
                  ? Icons.auto_awesome_rounded
                  : Icons.shield_outlined,
            ),
            const SizedBox(height: 15),
            const Text(
              'Твой маршрут — с логикой, а не с магией',
              style: TextStyle(
                color: ink,
                fontSize: 24,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              configured
                  ? 'OpenAI формулирует понятный ответ, а Career Quest проверяет каждый факт и шаг.'
                  : 'Если OpenAI недоступен, безопасный локальный алгоритм продолжит работу без потери сценария.',
              style: const TextStyle(color: muted, height: 1.55),
            ),
          ],
        );
        final icon = Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: pink.withValues(alpha: .12),
            shape: BoxShape.circle,
            border: Border.all(color: pink.withValues(alpha: .35)),
          ),
          child: const Icon(Icons.hiking_rounded, color: pink, size: 38),
        );
        if (box.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [icon, const SizedBox(height: 18), copy],
          );
        }
        return Row(
          children: [
            Expanded(child: copy),
            const SizedBox(width: 24),
            icon,
          ],
        );
      },
    ),
  );

  Future<void> _askOpenAI(String question) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await api.request('POST', '/api/me/assistant/explain', {
        'question': question,
      });
      if (mounted) setState(() => data = {...data, 'answer': result});
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _composeOpenAIPlan(String focus) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await api.request('POST', '/api/me/assistant/plan', {
        'focus': focus,
      });
      if (mounted) setState(() => data = {...data, 'draft': result});
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _assistantAnswer(Json answer) => card(
    value(answer['title'], 'Ответ помощника'),
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _assistantMode(answer),
        const SizedBox(height: 16),
        Text(
          value(answer['text']),
          style: const TextStyle(color: ink, fontSize: 17, height: 1.65),
        ),
        if ((answer['bullets'] as List? ?? const []).isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final item in (answer['bullets'] as List? ?? const []))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(Icons.auto_awesome, color: cyan, size: 15),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      value(item),
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (records(answer['metrics']).isNotEmpty) ...[
          const SizedBox(height: 10),
          actions([
            for (final row in records(answer['metrics']))
              metric(value(row['label']), value(row['value']), accent: cyan),
          ]),
        ],
      ],
    ),
  );

  Widget _assistantMode(Json result) => Align(
    alignment: Alignment.centerLeft,
    child: Tag(
      result['mode'] == 'llm'
          ? 'OPENAI · ${value(result['model'], 'MODEL')}'
          : 'ПРОВЕРЕННЫЙ ЛОКАЛЬНЫЙ ОТВЕТ',
      color: result['mode'] == 'llm' ? cyan : violet,
      icon: result['mode'] == 'llm'
          ? Icons.auto_awesome_rounded
          : Icons.verified_user_outlined,
    ),
  );

  Widget _assistantDraft(Json draft) => card(
    value(draft['headline'], 'Черновик маршрута'),
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _assistantMode(draft),
        const SizedBox(height: 15),
        Text(
          value(draft['summary']),
          style: const TextStyle(color: ink, fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 16),
        actions([
          metric('Шагов', '${records(draft['items']).length}', accent: pink),
          metric(
            'Время',
            '${value(draft['total_minutes'], '0')} мин.',
            accent: cyan,
          ),
          metric(
            'Ориентир',
            '${value(draft['estimated_weeks'], '0')} нед.',
            accent: violet,
          ),
        ]),
        const SizedBox(height: 20),
        if (records(draft['items']).isEmpty)
          const Notice(
            'Подходящих свободных шагов сейчас нет. Проверь цель, оценки или текущий маршрут.',
          ),
        for (final item in records(draft['items'])) _assistantDraftItem(item),
        const SizedBox(height: 4),
        Text(
          value(draft['disclaimer']),
          style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );

  Widget _assistantDraftItem(Json item) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: night.withValues(alpha: .34),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: line.withValues(alpha: .75)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          value(item['title']),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          value(item['reason']),
          style: const TextStyle(color: muted, height: 1.5),
        ),
        const SizedBox(height: 12),
        actions([
          Tag('${value(item['duration_minutes'])} мин.', color: cyan),
          Tag(label(item['format']), color: violet),
          for (final skill in (item['focus_skills'] as List? ?? const []))
            Tag(value(skill), color: pink),
        ]),
        const SizedBox(height: 14),
        actions([
          button('Подробнее', () => go('activities/${item['id']}')),
          button('Добавить в маршрут', () async {
            await addActivity(value(item['id']));
            if (mounted) go('plan');
          }, primary: true),
        ]),
      ],
    ),
  );
}

Color _roadStatusColor(String status) => switch (status) {
  'completed' => cyan,
  'in_progress' => pink,
  'planned' => violet,
  _ => muted,
};

class _CareerRoadPainter extends CustomPainter {
  const _CareerRoadPainter({
    required this.stops,
    required this.compact,
    required this.rowHeight,
    required this.topInset,
    required this.bottomInset,
  });

  final int stops;
  final bool compact;
  final double rowHeight;
  final double topInset;
  final double bottomInset;

  Offset _stop(Size size, int index) => Offset(
    compact ? 34 : size.width * (index.isEven ? .2 : .8),
    topInset + index * rowHeight + rowHeight / 2,
  );

  Path _road(Size size) {
    final points = <Offset>[
      Offset(size.width / 2, 27),
      for (var i = 0; i < stops; i++) _stop(size, i),
      Offset(size.width / 2, size.height - 27),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final from = points[i - 1];
      final to = points[i];
      final middle = (from.dy + to.dy) / 2;
      path.cubicTo(from.dx, middle, to.dx, middle, to.dx, to.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final road = _road(size);
    canvas.drawPath(
      road,
      Paint()
        ..color = blue.withValues(alpha: .08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 42
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawPath(
      road,
      Paint()
        ..color = const Color(0xFF536489)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      road,
      Paint()
        ..color = const Color(0xFF10182D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 19
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      road,
      Paint()
        ..color = blue.withValues(alpha: .16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    final divider = Paint()
      ..color = ink.withValues(alpha: .48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final metric in road.computeMetrics()) {
      var distance = 5.0;
      while (distance < metric.length) {
        final end = (distance + 11).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), divider);
        distance += 24;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CareerRoadPainter oldDelegate) =>
      oldDelegate.stops != stops ||
      oldDelegate.compact != compact ||
      oldDelegate.rowHeight != rowHeight ||
      oldDelegate.topInset != topInset ||
      oldDelegate.bottomInset != bottomInset;
}

class _RoadStop extends StatelessWidget {
  const _RoadStop({
    required this.number,
    required this.status,
    required this.title,
  });

  final int number;
  final String status;
  final String title;

  @override
  Widget build(BuildContext context) {
    final color = _roadStatusColor(status);
    final icon = switch (status) {
      'completed' => Icons.check_rounded,
      'in_progress' => Icons.play_arrow_rounded,
      _ => null,
    };
    return Semantics(
      label: 'Этап $number: $title, ${label(status)}',
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color,
              Color.alphaBlend(night.withValues(alpha: .38), color),
            ],
          ),
          border: Border.all(color: ink.withValues(alpha: .72), width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .38), blurRadius: 18),
            const BoxShadow(
              color: Color(0xAA080D22),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: icon == null
            ? Text(
                '$number',
                style: const TextStyle(
                  color: night,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              )
            : Icon(icon, color: night, size: 28),
      ),
    );
  }
}

class _RoadTerminal extends StatelessWidget {
  const _RoadTerminal({
    required this.icon,
    required this.color,
    required this.semanticsLabel,
  });

  final IconData icon;
  final Color color;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: panelRaised,
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: .72), width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .25), blurRadius: 12),
        ],
      ),
      child: Icon(icon, color: color, size: 16),
    ),
  );
}
