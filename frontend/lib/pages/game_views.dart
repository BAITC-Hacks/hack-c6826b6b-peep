// ignore_for_file: invalid_use_of_protected_member
part of 'workspace.dart';

extension _GameViews on _WorkspaceState {
  Widget seasonSummary(Json s) => card(
    'Твой сезон · уровень ${s['level']} / 100',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(value(s['season']?['name']), style: const TextStyle(color: muted)),
        const SizedBox(height: 18),
        LinearProgressIndicator(
          value: ((s['pass_progress'] ?? 0) as num).toDouble().clamp(0, 1),
          minHeight: 10,
          borderRadius: BorderRadius.circular(10),
        ),
        const SizedBox(height: 20),
        actions([
          metric(
            'Подтверждённый опыт',
            '${s['confirmed_xp']} XP',
            accent: blue,
          ),
          metric(
            'До следующего уровня',
            '${s['xp_to_next']} XP',
            accent: violet,
          ),
          metric(
            'CQ-монеты',
            '${s['wallet_balance']}',
            accent: const Color(0xFFF2D28C),
          ),
          metric('Серия активных дней', '${s['current_streak']}', accent: cyan),
        ]),
        const SizedBox(height: 18),
        Text(
          'Место: ${value(s['rank'], 'Ещё не начал')} · Ожидает проверки: ${s['pending_xp']} XP',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 16),
        actions([
          button('Открыть пропуск', () {
            seasonTab = 'pass';
            go('season');
          }, primary: true),
          button('Мои подарки', () => go('rewards')),
        ]),
      ],
    ),
  );
  Widget seasonView() {
    final content = map(data['content']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data['season'] != null) seasonSummary(data),
        if (data['season'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              '${label(data['season']['status'])} · до ${dateLabel(data['season']['ends_at'])} · Asia/Almaty',
              style: const TextStyle(color: muted),
            ),
          ),
        actions([
          for (final t in [
            ('tasks', 'Задания дня'),
            ('pass', '100 уровней'),
            ('streak', 'Календарь серии'),
            ('leaderboard', 'Рейтинг'),
            ('xp', 'Журнал XP'),
            ('hall', 'Зал славы'),
          ])
            ChoiceChip(
              label: Text(t.$2),
              selected: seasonTab == t.$1,
              onSelected: (_) {
                setState(() {
                  seasonTab = t.$1;
                  listPage = 1;
                  filter = '';
                });
                reload();
              },
            ),
        ]),
        const SizedBox(height: 24),
        if (seasonTab == 'tasks') ...[
          card(
            'Пять дней развития',
            Text(
              'Подтверждено ${content['weekly_days'] ?? 0} / 5 дней на неделе. Награда: 250 XP.\nЗадания обновятся ${value(content['resets_at'])}.',
              style: const TextStyle(height: 1.8),
            ),
          ),
          for (final task in records(content['items']))
            card(
              task['kind'] == 'main' ? 'Ежедневный шаг' : 'Кейс дня',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${task['xp']} XP · ${task['attempts_remaining']} попытки',
                    style: const TextStyle(color: cyan),
                  ),
                  const SizedBox(height: 12),
                  Text(task['instructions']),
                  taskPayload(map(task['public_payload'])),
                  const SizedBox(height: 16),
                  if (task['status'] == 'available')
                    button(
                      'Решить задание',
                      () => solveTask(task),
                      primary: true,
                    )
                  else
                    Text(
                      task['status'] == 'completed'
                          ? 'Задание принято. Опыт начислен.'
                          : 'Попытки закончились. Новое задание будет завтра.',
                      style: const TextStyle(color: pink),
                    ),
                  if (task['explanation'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        task['explanation'],
                        style: const TextStyle(color: muted),
                      ),
                    ),
                ],
              ),
            ),
          if (records(content['items']).isEmpty)
            empty('Задания доступны только в активном сезоне.'),
        ],
        if (seasonTab == 'pass') ...[
          const Text(
            'CQ начисляются автоматически. Подарки каждых пяти уровней выбираются отдельно и не списывают монеты. Выдача в этом приложении тестовая.',
            style: TextStyle(color: muted, height: 1.8),
          ),
          const SizedBox(height: 20),
          for (final level in records(content['items']))
            card(
              'Уровень ${level['level']} · ${level['required_total_xp']} XP',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final part in records(level['components']))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 16,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            part['name'],
                            style: TextStyle(
                              color: part['type'] == 'coins'
                                  ? const Color(0xFFF2D28C)
                                  : ink,
                            ),
                          ),
                          Text(
                            label(part['status']),
                            style: const TextStyle(color: muted),
                          ),
                          if (part['status'] == 'available')
                            button(
                              'Выбрать подарок',
                              () => chooseGift(part['entitlement_id']),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
        if (seasonTab == 'streak') ...[
          card(
            'Развитие входит в привычку',
            Text(
              'Текущая серия: ${content['current_streak']} · Лучшая: ${content['best_streak']}\nОсталось защит: ${content['freeze_remaining']} из 2. Защита сохраняет цепочку, но не даёт XP и не добавляет активный день.${content['preliminary'] == true ? '\nЕсть результаты, ожидающие HR: серия предварительная.' : ''}',
              style: const TextStyle(height: 1.8),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final day in records(content['days']))
                Tooltip(
                  message:
                      '${day['date']} · ${day['pending_hr'] == true ? 'Ожидает HR' : day['status']}',
                  child: Container(
                    width: 64,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: day['status'] == 'completed'
                          ? const Color(0xFF24585E)
                          : day['status'] == 'freeze'
                          ? const Color(0xFF3A355B)
                          : panel,
                      border: Border.all(
                        color: day['status'] == 'today' ? pink : line,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(day['date'].toString().substring(5)),
                        Icon(
                          day['status'] == 'completed'
                              ? Icons.check
                              : day['status'] == 'freeze'
                              ? Icons.ac_unit
                              : day['pending_hr'] == true
                              ? Icons.hourglass_top
                              : Icons.remove,
                          size: 17,
                          color: day['status'] == 'completed' ? cyan : muted,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (seasonTab == 'leaderboard') ...[
          select(
            'Рейтинг',
            filter.isEmpty ? 'overall' : filter,
            [
              ('overall', 'Общий'),
              ('department', 'Моё подразделение'),
              ('week', 'Неделя'),
            ],
            (v) {
              filter = v;
              listPage = 1;
              reload();
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'Рейтинг подтверждённого участия в программе. Не оценка профессиональной результативности.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          if (content['self'] != null)
            card('Ваша позиция', leaderRow(map(content['self']), self: true)),
          for (final row in records(content['entries']))
            card('', leaderRow(row)),
          pager(content),
        ],
        if (seasonTab == 'xp') ...[
          for (final row in records(content['items']))
            card(
              label(row['source_type']),
              Text('+${row['amount']} XP · ${dateLabel(row['effective_at'])}'),
            ),
          if (records(content['items']).isEmpty)
            empty(
              'Опыт появится после правильного ежедневного ответа или подтверждения практики HR.',
            ),
          pager(content),
        ],
        if (seasonTab == 'hall') ...[
          for (final season in records(content['items']))
            card(
              season['season']['name'],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final winner in records(season['winners']))
                    ListTile(
                      title: Text(
                        '${winner['prize_rank']}. ${winner['display_name']}',
                      ),
                      subtitle: Text(
                        '${winner['confirmed_xp']} XP · ${winner['title']}',
                      ),
                    ),
                  if (records(season['winners']).isEmpty)
                    const Text('Никто не прошёл призовой порог.'),
                  if (records(season['winners']).any(
                    (w) =>
                        w['prize_rank'] == 1 &&
                        w['employee_id'] == user?['employee_id'],
                  ))
                    button(
                      'Скачать сертификат',
                      () => download(
                        '/api/seasons/${segment(season['season']['id'])}/certificate',
                        'season-certificate.md',
                      ),
                    ),
                ],
              ),
            ),
          if (records(content['items']).isEmpty)
            empty('Итоги появятся после завершения сезона и периода проверки.'),
        ],
      ],
    );
  }

  Widget taskPayload(Json payload) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (payload['rows'] != null) ...[
          const Text('Клиент · Сумма'),
          for (final row in records(payload['rows']))
            Text('${row['customer_id']} · ${row['amount']}'),
        ],
        if (payload['before'] != null)
          Text(
            'До: ${(payload['before'] as List).join(' → ')}\nПосле: ${(payload['after'] as List).join(' → ')}',
            style: const TextStyle(height: 1.8),
          ),
      ],
    ),
  );
  Future<void> solveTask(Json task) async {
    final controllers = {
      for (final f in records(task['answer_fields']))
        f['key'] as String: TextEditingController(),
    };
    final answer = await showDialog<Json>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Твой ответ'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(task['instructions']),
                taskPayload(map(task['public_payload'])),
                for (final field in records(task['answer_fields']))
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TextField(
                      controller: controllers[field['key']],
                      keyboardType: field['type'] == 'text'
                          ? TextInputType.text
                          : const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                      decoration: InputDecoration(labelText: field['label']),
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
              for (final c in controllers.entries) c.key: c.value.text,
            }),
            child: const Text('Проверить'),
          ),
        ],
      ),
    );
    if (answer != null) {
      setState(() => busy = true);
      try {
        final result = await api.request(
          'POST',
          '/api/me/season/tasks/${segment(task['id'])}/attempt',
          {'answer': answer},
        );
        await reload();
        if (mounted) {
          await confirm(
            result['correct'] == true ? 'Верно!' : 'Пока не сходится',
            result['correct'] == true
                ? '${result['explanation']}\n\n+${result['award']?['awarded_xp'] ?? task['xp']} XP с учётом бонусов. Новых уровней: ${result['award']?['unlocked_levels']?.length ?? 0}, начислено ${result['award']?['credited_coins'] ?? 0} CQ. Всего ${result['gamification']['confirmed_xp']} XP · уровень ${result['gamification']['level']} · ${result['gamification']['wallet_balance']} CQ. Подарков к выбору: ${result['gamification']['unclaimed_gifts_count']}.'
                : result['explanation'] ??
                      'Осталось попыток: ${result['attempts_remaining']}. Попробуйте ещё раз.',
            action: 'Понятно',
          );
        }
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    Future.delayed(const Duration(milliseconds: 350), () {
      for (final c in controllers.values) {
        c.dispose();
      }
    });
  }

  Widget leaderRow(Json row, {bool self = false}) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: self ? pink : panelRaised,
      child: Text(
        value(row['rank'], '—'),
        style: TextStyle(color: self ? night : ink),
      ),
    ),
    title: Text(row['display_name']),
    subtitle: Text(
      '${row['department']}\n${row['confirmed_xp']} XP · ${row['active_days']} активных дней · уровень ${row['level']}',
    ),
    isThreeLine: true,
    onTap: () async {
      try {
        final detail = await api.get(
          '/api/seasons/${segment(data['season']['id'])}/participants/${segment(row['employee_id'])}',
        );
        if (mounted) {
          await confirm(
            detail['display_name'],
            '${detail['confirmed_xp']} XP\n${detail['active_days']} активных дней\n${(detail['badges'] as List).join('\n')}\n${detail['title'] ?? 'Участник сезона'}',
            action: 'Закрыть',
          );
        }
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      }
    },
  );
  IconData categoryIcon(String? name) => switch (name) {
    'Кухня' => Icons.kitchen_outlined,
    'Техника' => Icons.devices_outlined,
    'Гаджеты' => Icons.headphones_outlined,
    'Путешествия и впечатления' => Icons.flight_takeoff_rounded,
    _ => Icons.home_outlined,
  };
  Widget shopView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Развитие приносит больше',
        'Баланс: ${data['balance'] ?? 0} CQ. Монеты сохраняются между сезонами. Они не обмениваются на деньги.',
      ),
      select(
        'Категория',
        filter,
        [
          ('', 'Все награды'),
          for (final c in [
            'Техника',
            'Кухня',
            'Дом и уют',
            'Гаджеты',
            'Путешествия и впечатления',
          ])
            (c, c),
        ],
        (v) {
          filter = v;
          listPage = 1;
          reload();
        },
      ),
      const SizedBox(height: 14),
      actions([
        button(
          'Цена, наличие и сортировка',
          () => editListFilters(
            'Фильтры магазина',
            [
              (
                'affordable',
                'По балансу',
                [('', 'Любая цена'), ('true', 'Хватает монет')],
              ),
              (
                'in_stock',
                'Наличие',
                [('', 'Все товары'), ('true', 'Только в наличии')],
              ),
              (
                'sort',
                'Порядок',
                [
                  ('price_asc', 'Сначала дешевле'),
                  ('price_desc', 'Сначала дороже'),
                  ('name', 'По названию'),
                ],
              ),
            ],
            [('min_price', 'Цена от, CQ'), ('max_price', 'Цена до, CQ')],
          ),
        ),
      ]),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (ctx, box) {
          final width = box.maxWidth > 760
              ? (box.maxWidth - 18) / 2
              : box.maxWidth;
          return Wrap(
            spacing: 18,
            runSpacing: 0,
            children: [
              for (final item in records(data['items']))
                SizedBox(
                  width: width,
                  child: card(
                    item['name'],
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: violet.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(
                            categoryIcon(item['category']),
                            size: 44,
                            color: violet,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '${item['coin_price']} CQ',
                          style: const TextStyle(
                            fontSize: 26,
                            color: Color(0xFFF2D28C),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'В наличии: ${item['available_stock']} · лимит ${item['unit_budget_kzt']} ₸',
                          style: const TextStyle(color: muted),
                        ),
                        if ((data['balance'] ?? 0) < item['coin_price'])
                          Text(
                            'Не хватает ${item['coin_price'] - (data['balance'] ?? 0)} CQ',
                            style: const TextStyle(color: muted),
                          ),
                        const SizedBox(height: 16),
                        button(
                          'Посмотреть награду',
                          () => viewProduct(item),
                          primary: true,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      pager(data),
    ],
  );
  Future<void> viewProduct(Json item) async {
    final balance =
        (home['gamification']?['wallet_balance'] ?? data['balance'] ?? 0)
            as int;
    final enough = balance >= item['coin_price'] && item['available_stock'] > 0;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item['name']),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['description']),
                const SizedBox(height: 16),
                Text(item['delivery_terms']),
                const SizedBox(height: 18),
                Text(
                  'Цена: ${item['coin_price']} CQ\nБаланс: $balance CQ\n${enough ? 'После покупки: ${balance - item['coin_price']} CQ' : 'Недостаточно монет или товар закончился'}',
                  style: const TextStyle(height: 1.8),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Тестовая заявка. Реальная покупка у продавца не выполняется.',
                  style: TextStyle(color: muted),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Закрыть'),
          ),
          FilledButton(
            onPressed: enough ? () => Navigator.pop(ctx, true) : null,
            child: Text('Получить за ${item['coin_price']} CQ'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await act('POST', '/api/me/shop/orders', {
        'item_id': item['id'],
        'expected_item_version': item['version'],
        'expected_coin_price': item['coin_price'],
      });
    }
  }

  Widget walletView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      card(
        'Твой кошелёк',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${data['balance'] ?? 0} CQ',
              style: const TextStyle(fontSize: 42, color: Color(0xFFF2D28C)),
            ),
            const Text(
              'Внутренние монеты Career Quest. Не банковский счёт и не денежная выплата.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            button('В магазин', () => go('shop')),
          ],
        ),
      ),
      for (final row in records(data['items']))
        card(
          label(row['source_type']),
          Text(
            '${row['amount'] > 0 ? '+' : ''}${row['amount']} CQ · ${dateLabel(row['at'])}',
          ),
        ),
      if (records(data['items']).isEmpty)
        empty('Первые монеты появятся при открытии первого уровня пропуска.'),
      pager(data),
    ],
  );
  Widget rewardsView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Заработано твоими действиями',
        'Подарки пропуска и покупки за CQ — отдельные награды.',
      ),
      for (final e in records(data['entitlements']))
        card(
          'Уровень ${e['level']} · ${e['name']}',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${label(e['status'])} · лимит ${e['cap']} ₸'),
              if (e['status'] == 'available') ...[
                const SizedBox(height: 14),
                button(
                  'Выбрать подарок',
                  () => chooseGift(e['id']),
                  primary: true,
                ),
              ],
            ],
          ),
        ),
      heading('Мои заявки'),
      for (final order in records(data['orders'])) orderCard(order),
      if (records(data['orders']).isEmpty &&
          records(data['entitlements']).isEmpty)
        empty('Здесь появятся подарки пропуска и ваши заказы.'),
    ],
  );
  Future<void> chooseGift(String eid) async {
    try {
      final options = await api.get('/api/me/rewards/${segment(eid)}/options');
      if (!mounted) return;
      final item = await showDialog<Json>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(options['entitlement']['name']),
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Получение через HR. CQ не списываются. Неиспользованный остаток лимита не возвращается.',
              ),
            ),
            for (final item in records(options['items']))
              ListTile(
                enabled: item['available_stock'] > 0,
                title: Text(item['name']),
                subtitle: Text(
                  'Лимит ${item['unit_budget_kzt']} ₸ · доступно ${item['available_stock']}',
                ),
                onTap: () => Navigator.pop(ctx, item),
              ),
          ],
        ),
      );
      if (item != null &&
          await confirm(
            'Выбрать этот подарок?',
            '${item['name']}\n${item['description']}\n${item['delivery_terms']}\nСписание: 0 CQ.',
          )) {
        await act('POST', '/api/me/rewards/${segment(eid)}/claim', {
          'item_id': item['id'],
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Widget orderCard(Json order, {bool admin = false}) => card(
    order['item_snapshot']['name'],
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (admin)
          Text(
            value(order['employee_name']),
            style: const TextStyle(color: cyan),
          ),
        Text(
          '${label(order['status'])} · ${order['payment_kind'] == 'coins' ? '${order['coins_charged']} CQ' : 'Подарок пропуска, 0 CQ'}',
          style: const TextStyle(color: pink),
        ),
        ExpansionTile(
          title: const Text('История заявки'),
          children: [
            for (final event in records(order['timeline']))
              ListTile(
                title: Text(label(event['status'])),
                subtitle: Text(
                  '${dateLabel(event['at'])} · ${event['note'] ?? ''}',
                ),
              ),
          ],
        ),
        if (!admin && order['can_cancel'] == true)
          button('Отменить заявку', () async {
            if (await confirm(
              'Отменить заявку?',
              order['coins_charged'] > 0
                  ? '${order['coins_charged']} CQ вернутся в кошелёк.'
                  : 'Можно будет выбрать другой подарок, если срок выбора ещё не истёк.',
            )) {
              await act(
                'POST',
                '/api/me/reward-orders/${segment(order['id'])}/cancel',
              );
            }
          }),
        if (admin)
          actions([
            for (final target in switch (order['status']) {
              'requested' => ['approved', 'rejected'],
              'approved' => ['ready', 'cancelled'],
              'ready' => ['delivered'],
              _ => <String>[],
            })
              button(
                label(target),
                () => fulfillOrder(order, target),
                primary: target == 'approved' || target == 'delivered',
              ),
          ]),
      ],
    ),
  );
}
