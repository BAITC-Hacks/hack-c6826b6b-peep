import 'dart:convert';

import 'package:flutter/material.dart';

import '../../widgets/ui.dart';

typedef AdminJson = Map<String, dynamic>;
AdminJson obj(dynamic value) => value is Map ? AdminJson.from(value) : {};
List<AdminJson> rows(dynamic value) =>
    value is List ? value.whereType<Map>().map(obj).toList() : [];
dynamic copyValue(dynamic value) => jsonDecode(jsonEncode(value));

String fieldTitle(String key) =>
    const {
      'id': 'ID',
      'skill_id': 'ID навыка',
      'name': 'Название',
      'title': 'Название',
      'full_name': 'ФИО',
      'display_name': 'Отображаемое имя',
      'username': 'Логин',
      'password': 'Начальный пароль (от 12 символов)',
      'temporary_password': 'Временный пароль (от 12 символов)',
      'employee_id': 'ID сотрудника',
      'role': 'Роль',
      'grade': 'Грейд',
      'role_id': 'Должность',
      'grade_id': 'Грейд',
      'department': 'Подразделение',
      'parent_id': 'ID родительского подразделения',
      'active': 'Активен',
      'reason': 'Основание изменения',
      'permissions': 'Дополнительные разрешения',
      'description': 'Описание',
      'category': 'Категория',
      'type': 'Тип',
      'rank': 'Порядок грейда',
      'requirements': 'Матрица требований по ID навыков',
      'level': 'Уровень',
      'weight': 'Вес',
      'duration_minutes': 'Продолжительность, мин',
      'gains': 'Прирост по ID навыков (0–20)',
      'prerequisites': 'Предварительные требования по ID навыков',
      'instructions': 'Инструкция',
      'outcome': 'Ожидаемый результат',
      'external_url': 'Ссылка на материал',
      'image_url': 'URL изображения',
      'format': 'Формат',
      'kind': 'Вид',
      'starts_at': 'Начало (ISO, с часовым поясом)',
      'ends_at': 'Окончание (ISO, с часовым поясом)',
      'available_from': 'Доступен с',
      'available_until': 'Доступен до',
      'reward_eligible': 'Участвует в начислении XP',
      'strategy': 'Стратегия расчёта',
      'max_steps': 'Максимум шагов в плане',
      'horizon_days': 'Горизонт подбора, дней',
      'budget_weeks': 'Бюджет времени, недель',
      'utility_weight': 'Вес пользы',
      'duration_weight': 'Вес длительности',
      'format_weight': 'Вес формата',
      'daily_xp': 'XP основного задания',
      'bonus_xp': 'XP дополнительного задания',
      'daily_count': 'Заданий в день',
      'attempts': 'Попыток на задание',
      'activity_min': 'Минимум XP за практику',
      'activity_max': 'Максимум XP за практику',
      'activity_multiplier': 'XP за минуту практики',
      'reviews_per_day': 'Заявок на проверку в день',
      'weekly_days': 'Активных дней для недельной награды',
      'weekly_xp': 'XP недельной награды',
      'coin_backing': 'Обеспечение одной CQ, ₸',
      'season_days': 'Длительность сезона, дней',
      'review_days': 'Срок проверки после сезона, дней',
      'claim_days': 'Срок выбора подарков, дней',
      'order_expiry_days': 'Автоотмена заявки, дней',
      'freezes': 'Защит серии',
      'milestones': 'Пороги серии',
      'days': 'Дней',
      'xp': 'XP',
      'min_xp': 'Призовой порог XP',
      'min_days': 'Призовой порог активных дней',
      'prizes': 'Призы по местам, CQ',
      'criteria': 'Критерии рейтинга по порядку',
      'winner_title': 'Титул победителя',
      'items': 'Записи',
      'code': 'Код',
      'condition': 'Условие',
      'threshold': 'Порог',
      'app_name': 'Название приложения',
      'primary': 'Основной цвет (#RRGGBB)',
      'background': 'Цвет фона (#RRGGBB)',
      'banner': 'Баннер',
      'logo_url': 'URL логотипа',
      'locale': 'Язык',
      'entries': 'Тексты',
      'key': 'Ключ',
      'value': 'Значение',
      'mode': 'Режим',
      'model': 'Модель',
      'timeout_seconds': 'Таймаут, секунд',
      'max_output_tokens': 'Лимит токенов ответа',
      'secret_alias': 'Серверный источник ключа',
      'organization': 'Организация',
      'timezone': 'Часовой пояс',
      'session_hours': 'Сессия, часов',
      'preview_minutes': 'Срок предпросмотра, минут',
      'maintenance': 'Режим обслуживания',
      'maintenance_message': 'Сообщение обслуживания',
      'shop_paused': 'Приостановить новые покупки',
      'quests_paused': 'Приостановить задания',
      'coin_price': 'Цена, CQ',
      'unit_budget_kzt': 'Стоимость обеспечения товара, ₸',
      'delivery_terms': 'Условия тестовой выдачи',
      'shop_visible': 'Показывать в магазине',
      'required_total_xp': 'Накопительный порог XP',
      'components': 'Компоненты награды',
      'coins': 'CQ',
      'budget_cap_kzt': 'Лимит подарка, ₸',
      'pool_code': 'Код подарочного пула',
      'cosmetic_code': 'Код оформления',
      'cap': 'Лимит, ₸',
      'item_ids': 'ID товаров',
      'fallback_item_id': 'ID запасного подарка',
      'season_id': 'ID сезона',
      'employee_ids': 'ID участников',
      'virtual_budget_kzt': 'Виртуальный бюджет, ₸',
      'assessed_at': 'Дата оценки (ISO)',
      'skills': 'Оценки по ID навыков',
      'source': 'Источник',
      'confirm_archive_plan': 'Подтвердить архивирование текущего плана',
      'item_id': 'ID товара',
      'delta': 'Изменение (+/−)',
      'amount_kzt': 'Дополнительное финансирование, ₸',
      'actions': 'Действия корректировки',
      'source_id': 'ID исходного события или задания',
      'status': 'Состояние',
      'version': 'Версия',
      'balance': 'Баланс CQ',
      'available_stock': 'Доступно на складе',
      'stock_total': 'Всего поступило',
      'reserved': 'Зарезервировано',
      'delivered': 'Выдано',
      'actor': 'Автор',
      'operation': 'Операция',
      'occurred_at': 'Время',
      'at': 'Время',
      'before_redacted': 'До изменения',
      'after_redacted': 'После изменения',
      'xp_delta': 'Изменение XP',
      'coin_delta': 'Изменение CQ',
      'budget_delta_kzt': 'Дополнительный резерв, ₸',
      'totals_before': 'Расчёт до',
      'totals_after': 'Расчёт после',
      'pass_totals': 'Стоимость пропуска',
      'per_member_kzt': 'Максимум на участника, ₸',
      'total_kzt': 'Максимум на всех, ₸',
      'max_xp': 'Максимальный XP',
      'gifts_kzt': 'Лимиты подарков, ₸',
      'roster': 'Участников',
      'levels': 'Уровней',
      'gifts': 'Подарков',
      'domain': 'Раздел',
      'target_id': 'Объект',
      'draft_version': 'Версия черновика',
      'created_at': 'Создано',
      'published_at': 'Опубликовано',
      'integrity': 'Целостность SQLite',
      'state_revision': 'Ревизия данных',
      'committed_budget_kzt': 'Зарезервированный бюджет, ₸',
      'earned_liability': 'Заработанные обязательства, ₸',
      'unearned_reserved': 'Резерв будущих наград, ₸',
      'order_reserved': 'Резерв заявок, ₸',
      'spent': 'Выдано, ₸',
      'released': 'Освобождено, ₸',
      'wallet_liability_kzt': 'Обеспечение кошельков, ₸',
      'pending_reviews': 'Ожидают проверки',
      'pending_orders': 'Ожидают выдачи',
      'employees': 'Сотрудники',
    }[key] ??
    key;

String textValue(dynamic value) {
  if (value == null) return '—';
  if (value is bool) return value ? 'Да' : 'Нет';
  return const {
        'draft': 'Черновик',
        'previewed': 'Проверен',
        'published': 'Опубликован',
        'applied': 'Применено',
        'active': 'Идёт',
        'scheduled': 'Запланирован',
        'pending': 'На проверке',
        'approved': 'Одобрено',
        'rejected': 'Отклонено',
        'requested': 'Запрошено',
        'ready': 'Готово к выдаче',
        'delivered': 'Выдано',
        'cancelled': 'Отменено',
        'super_admin': 'Системный администратор',
        'admin': 'Администратор',
        'hr': 'HR',
        'employee': 'Сотрудник',
        'coins': 'Монеты',
        'gift': 'Выбор подарка',
        'mini': 'Фиксированный подарок',
        'cosmetic': 'Оформление',
        'weighted_coverage': 'Взвешенное покрытие',
        'unweighted_coverage': 'Равные веса навыков',
        'verified_activities': 'Подтверждённые практики',
        'distinct_skills': 'Разные навыки',
        'active_days': 'Активные дни',
        'confirmed_xp': 'Подтверждённый XP',
        'confirmed_activity_count': 'Проверенные активности',
        'template': 'Локальный шаблон',
        'environment': 'Настройка окружения',
        'llm': 'OpenAI с локальным fallback',
        'self_paced': 'Самостоятельно',
        'scheduled_activity': 'По расписанию',
        'online': 'Онлайн',
        'offline': 'Очно',
        'personal': 'Личная цель',
        'profile': 'Цель профиля',
        'restore_attempt': 'Восстановить попытку',
        'xp': 'Корректировка XP',
      }[value.toString()] ??
      value.toString();
}

class AdminDetails extends StatelessWidget {
  const AdminDetails(this.value, {super.key});
  final dynamic value;
  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: obj(value).entries.map((e) {
          if (e.value is Map || e.value is List) {
            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(fieldTitle(e.key)),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 12),
                  child: AdminDetails(e.value),
                ),
              ],
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: SelectableText(
              '${fieldTitle(e.key)}: ${textValue(e.value)}',
            ),
          );
        }).toList(),
      );
    }
    if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: (value as List).map((v) => AdminDetails(v)).toList(),
      );
    }
    return SelectableText(textValue(value));
  }
}

class SchemaEditor extends StatefulWidget {
  const SchemaEditor({
    super.key,
    required this.schema,
    required this.initial,
    required this.title,
  });
  final AdminJson schema, initial;
  final String title;
  @override
  State<SchemaEditor> createState() => _SchemaEditorState();
}

class _SchemaEditorState extends State<SchemaEditor> {
  final form = GlobalKey<FormState>();
  late AdminJson draft;
  bool dirty = false;
  @override
  void initState() {
    super.initState();
    draft = obj(copyValue(widget.initial));
  }

  AdminJson resolve(AdminJson schema) {
    if (schema.containsKey(r'$ref')) {
      return obj(
        obj(widget.schema[r'$defs'])[schema[r'$ref']
            .toString()
            .split('/')
            .last],
      );
    }
    if (schema['anyOf'] is List) {
      return resolve(
        rows(schema['anyOf'])
            .firstWhere((s) => s['type'] != 'null', orElse: () => {}),
      );
    }
    return schema;
  }

  dynamic defaults(AdminJson original) {
    if (original.containsKey('default')) return copyValue(original['default']);
    final s = resolve(original);
    if (s.containsKey('default')) return copyValue(s['default']);
    if (s.containsKey('const')) return s['const'];
    if (s['enum'] is List) return (s['enum'] as List).first;
    if (s['oneOf'] is List) return defaults(rows(s['oneOf']).first);
    if (s['type'] == 'object') {
      return <String, dynamic>{
        for (final e in obj(s['properties']).entries)
          e.key: defaults(obj(e.value)),
      };
    }
    if (s['type'] == 'array') return <dynamic>[];
    if (s['type'] == 'boolean') return false;
    if (s['type'] == 'integer' || s['type'] == 'number') {
      return s['minimum'] ?? 0;
    }
    return '';
  }

  void changed(VoidCallback action) {
    setState(() {
      action();
      dirty = true;
    });
  }

  Future<void> close() async {
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Отменить изменения формы?'),
          content: const Text('Изменения ещё не сохранены в черновик.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Продолжить редактирование'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Отменить изменения'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Widget field(String name, AdminJson original, Map parent, String path) {
    var s = resolve(original);
    if (s['oneOf'] is List) {
      final variants = rows(s['oneOf']).map(resolve).toList();
      final current = obj(parent[name]);
      s = variants.firstWhere(
        (v) => obj(obj(v['properties'])['type'])['const'] == current['type'],
        orElse: () => variants.first,
      );
      parent[name] = current.isEmpty ? defaults(s) : current;
      return Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: obj(parent[name])['type'],
            decoration: const InputDecoration(labelText: 'Тип компонента'),
            items: variants.map((v) {
              final type = obj(
                obj(v['properties'])['type'],
              )['const'].toString();
              return DropdownMenuItem(
                value: type,
                child: Text(textValue(type)),
              );
            }).toList(),
            onChanged: (v) => changed(
              () => parent[name] = defaults(
                variants.firstWhere(
                  (s) => obj(obj(s['properties'])['type'])['const'] == v,
                ),
              ),
            ),
          ),
          field(name, s, parent, '$path.${obj(parent[name])['type']}'),
        ],
      );
    }
    parent.putIfAbsent(name, () => defaults(original));
    final value = parent[name];
    final title = fieldTitle(name);
    final type = s['type'];
    if (type == 'object') {
      parent[name] = obj(value);
      final nested = parent[name] as Map;
      final props = obj(s['properties']);
      if (props.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...props.entries
                  .where(
                    (e) =>
                        !['expected_revision', 'type'].contains(e.key) ||
                        !obj(e.value).containsKey('const'),
                  )
                  .map(
                    (e) => field(e.key, obj(e.value), nested, '$path.${e.key}'),
                  ),
            ],
          ),
        );
      }
      final itemSchema = obj(s['additionalProperties']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          ...nested.keys.toList().map(
            (k) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: field(k.toString(), itemSchema, nested, '$path.$k'),
                ),
                IconButton(
                  tooltip: 'Удалить строку',
                  onPressed: () => changed(() => nested.remove(k)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Добавить ID'),
            onPressed: () async {
              final controller = TextEditingController();
              final key = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('ID записи / навыка'),
                  content: TextField(controller: controller, autofocus: true),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(ctx, controller.text.trim()),
                      child: const Text('Добавить'),
                    ),
                  ],
                ),
              );
              controller.dispose();
              if (key != null && key.isNotEmpty && mounted) {
                changed(
                  () => nested.putIfAbsent(key, () => defaults(itemSchema)),
                );
              }
            },
          ),
          const SizedBox(height: 12),
        ],
      );
    }
    if (type == 'array') {
      parent[name] = value is List ? value : <dynamic>[];
      final list = parent[name] as List;
      final itemSchema = obj(s['items']);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title (${list.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ...List.generate(
              list.length,
              (i) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i + 1}. ${list[i] is Map ? (obj(list[i])['name'] ?? obj(list[i])['code'] ?? obj(list[i])['key'] ?? obj(list[i])['days'] ?? textValue(obj(list[i])['type'])) : textValue(list[i])}',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Выше',
                        onPressed: i == 0
                            ? null
                            : () => changed(() {
                                final x = list.removeAt(i);
                                list.insert(i - 1, x);
                              }),
                        icon: const Icon(Icons.arrow_upward, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Редактировать',
                        onPressed: () async {
                          final item = await showDialog<AdminJson>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => SchemaEditor(
                              schema: {
                                'type': 'object',
                                r'$defs': widget.schema[r'$defs'],
                                'properties': {'value': itemSchema},
                              },
                              initial: {'value': list[i]},
                              title: '$title · ${i + 1}',
                            ),
                          );
                          if (item != null && mounted) {
                            changed(() => list[i] = item['value']);
                          }
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Удалить',
                        onPressed: () => changed(() => list.removeAt(i)),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
              onPressed: () => changed(() => list.add(defaults(itemSchema))),
            ),
          ],
        ),
      );
    }
    if (type == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        value: value == true,
        onChanged: (v) => changed(() => parent[name] = v),
      );
    }
    if (s['enum'] is List || s.containsKey('const')) {
      final choices = s['enum'] as List? ?? [s['const']];
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$path:$value'),
          initialValue:
              choices.map((v) => v.toString()).contains(value.toString())
              ? value.toString()
              : choices.first.toString(),
          decoration: InputDecoration(labelText: title),
          isExpanded: true,
          items: choices
              .map(
                (v) => DropdownMenuItem(
                  value: v.toString(),
                  child: Text(textValue(v)),
                ),
              )
              .toList(),
          onChanged: s.containsKey('const')
              ? null
              : (v) => changed(() => parent[name] = v),
        ),
      );
    }
    final number = type == 'integer' || type == 'number';
    final nullable = rows(original['anyOf']).any((s) => s['type'] == 'null');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: ValueKey(path),
        initialValue: value?.toString() ?? '',
        decoration: InputDecoration(
          labelText: title,
          helperText: s['minimum'] != null || s['maximum'] != null
              ? 'Диапазон: ${s['minimum'] ?? '…'} — ${s['maximum'] ?? '…'}'
              : null,
        ),
        obscureText: name.contains('password'),
        maxLines:
            [
                  'description',
                  'instructions',
                  'reason',
                  'value',
                  'banner',
                  'delivery_terms',
                ].contains(name) &&
                !number
            ? 3
            : 1,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        onChanged: (v) {
          dirty = true;
          parent[name] = number
              ? (type == 'integer'
                    ? int.tryParse(v)
                    : double.tryParse(v.replaceAll(',', '.')))
              : (nullable && v.isEmpty ? null : v);
        },
        validator: (v) {
          if (nullable && (v ?? '').isEmpty) return null;
          if (number) {
            final n = num.tryParse((v ?? '').replaceAll(',', '.'));
            if (n == null || !n.isFinite) return 'Введите число';
            if (type == 'integer' && n != n.roundToDouble()) {
              return 'Введите целое число';
            }
            if (s['minimum'] != null && n < s['minimum'] ||
                s['maximum'] != null && n > s['maximum']) {
              return 'Значение вне диапазона';
            }
          }
          if ((v ?? '').length < (s['minLength'] ?? 0)) {
            return 'Минимум ${s['minLength']} символов';
          }
          if (s['maxLength'] != null && (v ?? '').length > s['maxLength']) {
            return 'Максимум ${s['maxLength']} символов';
          }
          if (s['pattern'] != null && !RegExp(s['pattern']).hasMatch(v ?? '')) {
            return 'Проверьте формат значения';
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) close();
    },
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: obj(widget.schema['properties']).entries
                  .where((e) => e.key != 'expected_revision')
                  .map((e) => field(e.key, obj(e.value), draft, e.key))
                  .toList(),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: close, child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              setState(() => dirty = false);
              Navigator.pop(context, draft);
            }
          },
          child: const Text('Продолжить'),
        ),
      ],
    ),
  );
}

class PasswordChangePage extends StatefulWidget {
  const PasswordChangePage({
    super.key,
    required this.api,
    required this.onDone,
  });
  final dynamic api;
  final Future<void> Function() onDone;
  @override
  State<PasswordChangePage> createState() => _PasswordChangePageState();
}

class _PasswordChangePageState extends State<PasswordChangePage> {
  final oldPassword = TextEditingController(),
      newPassword = TextEditingController();
  String error = '';
  bool busy = false;
  @override
  void dispose() {
    oldPassword.dispose();
    newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: QuestBackdrop(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Surface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Смените временный пароль',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: oldPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Текущий пароль',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Новый пароль (от 12 символов)',
                    ),
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(error, style: const TextStyle(color: danger)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (newPassword.text.length < 12) {
                              setState(
                                () => error = 'Нужно не менее 12 символов',
                              );
                              return;
                            }
                            setState(() => busy = true);
                            try {
                              await widget.api.request(
                                'POST',
                                '/api/auth/password',
                                {
                                  'current_password': oldPassword.text,
                                  'new_password': newPassword.text,
                                },
                              );
                              await widget.onDone();
                            } catch (e) {
                              if (mounted) setState(() => error = e.toString());
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: const Text('Сменить и войти заново'),
                  ),
                  TextButton(
                    onPressed: widget.onDone,
                    child: const Text('Выйти'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
