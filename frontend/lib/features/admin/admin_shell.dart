import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/api.dart';
import '../../widgets/ui.dart';
import 'admin_forms.dart';
export 'admin_forms.dart' show PasswordChangePage;

class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
    this.initialRoute,
  });
  final CareerApi api;
  final AdminJson user;
  final Future<void> Function() onLogout;
  final String? initialRoute;
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> with WidgetsBindingObserver {
  AdminJson overview = {}, data = {}, forms = {};
  String page = 'overview', search = '', error = '', scope = 'global';
  int pageNumber = 1, loadVersion = 0;
  bool loading = true, busy = false;
  List<AdminJson> seasons = [];
  CareerApi get api => widget.api;
  List<AdminJson> get modules => rows(overview['modules']);
  AdminJson get module =>
      modules.where((m) => m['id'] == page).firstOrNull ?? {};
  bool can(String permission) =>
      (widget.user['capabilities'] as List? ?? []).contains(permission);
  String get path => '/api/admin/${module['path'] ?? page}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final route = widget.initialRoute ?? '';
    if (route.startsWith('/admin/')) page = route.substring(7).split('/').first;
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation information) async {
    if (information.uri.path.startsWith('/admin/')) {
      go(information.uri.path.substring(7).split('/').first, updateUrl: false);
      return true;
    }
    return false;
  }

  void go(String value, {bool updateUrl = true}) {
    setState(() {
      page = value;
      pageNumber = 1;
      search = '';
      scope = 'global';
      data = {};
    });
    if (updateUrl) {
      SystemNavigator.routeInformationUpdated(
        uri: Uri(path: '/admin/$page'),
        replace: false,
      );
    }
    load();
  }

  Future<void> load() async {
    final generation = ++loadVersion;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final info = await api.get('/api/admin/overview');
      final fs = await api.get('/api/admin/forms');
      await api.refreshConfiguration();
      if (!mounted || generation != loadVersion) return;
      overview = info;
      forms = fs;
      if (page != 'overview' && !modules.any((m) => m['id'] == page)) {
        page = 'overview';
      }
      if (can('seasons.manage')) {
        seasons = rows((await api.get('/api/admin/seasons'))['items']);
      }
      String url = path;
      if (page == 'inventory') url = '/api/admin/inventory/movements';
      if (page == 'system') url = '/api/admin/system/health';
      if ([
        'users',
        'employees',
        'departments',
        'skills',
        'career-roles',
        'activities',
        'shop',
        'reward-pools',
        'changes',
        'audit',
      ].contains(page)) {
        url +=
            '?${Uri(queryParameters: {'search': search, 'page': '$pageNumber', 'page_size': '25'}).query}';
      } else if ([
        'economy',
        'streaks',
        'achievements',
        'leaderboards',
        'quests',
        'nominations',
      ].contains(page)) {
        url += '?target_id=${Uri.encodeComponent(scope)}';
      }
      final result = page == 'overview' ? info : await api.get(url);
      if (mounted && generation == loadVersion) {
        setState(() {
          data = result;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && generation == loadVersion) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<AdminJson?> edit(AdminJson schema, AdminJson initial, String title) =>
      showDialog<AdminJson>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            SchemaEditor(schema: schema, initial: initial, title: title),
      );
  Future<void> detail(String title, dynamic value) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(child: AdminDetails(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> perform(Future<void> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<AdminJson?> commandForm(
    String schema,
    String title, [
    AdminJson initial = const {},
  ]) async {
    final definition = obj(forms[schema]);
    if (definition.isEmpty) {
      throw ApiException('Форма недоступна с текущими правами');
    }
    return edit(definition, initial, title);
  }

  Future<void> command(
    String schema,
    String title,
    String url, {
    AdminJson initial = const {},
    String method = 'POST',
  }) async {
    final body = await commandForm(schema, title, initial);
    if (body == null) return;
    await perform(() async {
      final result = await api.request(method, url, body);
      if (mounted) {
        if (result['domain'] != null) {
          await previewChange(result);
        } else {
          await detail('Действие выполнено', result);
        }
      }
      await load();
    });
  }

  Future<void> editResource([AdminJson? row]) async {
    final schema = obj(data['schema']);
    final props = obj(schema['properties']);
    final initial = obj(row ?? data['value']);
    final values = <String, dynamic>{
      for (final key in props.keys)
        if (initial.containsKey(key)) key: initial[key],
    };
    final withReason = {
      ...schema,
      'properties': {
        ...props,
        'reason': {'type': 'string', 'minLength': 3, 'maxLength': 2000},
      },
    };
    final result = await edit(
      withReason,
      values,
      row == null ? 'Новый черновик' : 'Редактировать',
    );
    if (result == null) return;
    final reason = result.remove('reason') ?? 'Изменение настроек';
    final target = page == 'career-roles'
        ? '${result['role_id']}|${result['grade_id']}'
        : (result['id'] ?? result['skill_id'] ?? scope).toString();
    await perform(() async {
      final change = await api.request('POST', path, {
        'target_id': target,
        'payload': result,
        'reason': reason,
      });
      if (mounted) await previewChange(change);
      await load();
    });
  }

  Future<void> previewChange(
    AdminJson change, {
    bool correction = false,
  }) async {
    final base =
        '/api/admin/${correction ? 'corrections' : 'changes'}/${Uri.encodeComponent(change['id'])}';
    final preview = await api.request('POST', '$base/preview', {});
    if (!mounted) return;
    final needsEconomy = [
      'pass',
      'economy',
      'achievements',
      'leaderboards',
      'nominations',
    ].contains(change['domain']);
    final mayPublish =
        preview['can_publish'] == true &&
        (!needsEconomy || can('economy.publish'));
    final reason = TextEditingController(
      text:
          change['reason'] ??
          obj(change['payload'])['reason'] ??
          'Публикация проверенного изменения',
    );
    final apply = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          correction ? 'Последствия корректировки' : 'Предпросмотр публикации',
        ),
        content: SizedBox(
          width: 800,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Условия уже оформленных заказов и выданных заданий сохраняются.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    metric('Изменение XP', preview['xp_delta']),
                    metric('Изменение CQ', preview['coin_delta']),
                    metric('Доп. резерв, ₸', preview['budget_delta_kzt']),
                  ],
                ),
                if (preview['pass_totals'] != null)
                  AdminDetails(preview['pass_totals']),
                for (final issue in rows(preview['blocking_errors']))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '${issue['code']}: ${issue['message']}',
                      style: const TextStyle(color: danger),
                    ),
                  ),
                if (needsEconomy && !can('economy.publish'))
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Для публикации экономики необходимо право economy.publish. Черновик сохранён.',
                    ),
                  ),
                ExpansionTile(
                  title: const Text('Что изменится'),
                  children: [
                    AdminDetails({
                      'До': preview['before'] ?? preview['totals_before'],
                      'После': preview['after'] ?? preview['totals_after'],
                      'Влияние на сотрудников': preview['comparisons'] ?? [],
                    }),
                  ],
                ),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Основание публикации',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Оставить черновик'),
          ),
          FilledButton(
            onPressed: mayPublish ? () => Navigator.pop(ctx, true) : null,
            child: Text(
              correction ? 'Применить корректировку' : 'Опубликовать',
            ),
          ),
        ],
      ),
    );
    final reasonText = reason.text;
    reason.dispose();
    if (apply == true) {
      await api.request('POST', '$base/${correction ? 'apply' : 'publish'}', {
        'preview_id': preview['preview_id'],
        'expected_revision': preview['base_revision'],
        'reason': reasonText,
      });
      await api.refreshConfiguration();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Изменение опубликовано и доступно сотрудникам'),
          ),
        );
      }
    }
  }

  Widget metric(String title, dynamic value) => Container(
    width: 190,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: panelRaised,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 8),
        Text(
          textValue(value),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: ink,
          ),
        ),
      ],
    ),
  );
  Widget action(
    String title,
    VoidCallback action, {
    IconData icon = Icons.edit_outlined,
  }) => OutlinedButton.icon(
    onPressed: busy ? null : action,
    icon: Icon(icon, size: 18),
    label: Text(title),
  );
  String name(AdminJson row) =>
      (row['name'] ??
              row['title'] ??
              row['full_name'] ??
              row['display_name'] ??
              row['username'] ??
              row['domain'] ??
              row['id'] ??
              row['operation'] ??
              'Запись')
          .toString();
  Future<void> passEditor(AdminJson season) async {
    final id = Uri.encodeComponent(season['id']);
    final result = await api.get('/api/admin/seasons/$id/pass');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PassEditor(
        api: api,
        season: season,
        data: result,
        onDraft: (change) => previewChange(change),
      ),
    );
    await load();
  }

  Future<void> userActions(AdminJson row) async {
    final id = Uri.encodeComponent(row['username']);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name(row)),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(child: AdminDetails(row)),
        ),
        actions: [
          if (can('users.manage'))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                command(
                  'user_edit',
                  'Изменить аккаунт',
                  '/api/admin/users/$id',
                  method: 'PATCH',
                  initial: {
                    'display_name': row['display_name'],
                    'employee_id': row['employee_id'],
                  },
                );
              },
              child: const Text('Профиль'),
            ),
          if (can('users.roles'))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                command(
                  'access',
                  'Права и блокировка',
                  '/api/admin/users/$id/access',
                  initial: {
                    'role': row['role'],
                    'active': row['active'],
                    'permissions': row['permissions'],
                  },
                );
              },
              child: const Text('Доступ'),
            ),
          if (can('users.manage'))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                command(
                  'password_reset',
                  'Сбросить пароль',
                  '/api/admin/users/$id/password-reset',
                );
              },
              child: const Text('Сброс пароля'),
            ),
          if (can('users.sessions'))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                command(
                  'reason',
                  'Завершить сессии',
                  '/api/admin/users/$id/revoke-sessions',
                );
              },
              child: const Text('Отозвать сессии'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> employeeActions(AdminJson row) async {
    final id = Uri.encodeComponent(row['id']);
    final profile = await api.get('/api/admin/employees/$id');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name(row)),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Chip(
                  label: Text('Просмотр администратором · только чтение'),
                ),
                AdminDetails(profile),
              ],
            ),
          ),
        ),
        actions: [
          if (can('employees.manage'))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                editResource(row);
              },
              child: const Text('Профиль'),
            ),
          if (can('employees.assessments'))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                command(
                  'assessment',
                  'Новая оценка',
                  '/api/admin/employees/$id/assessments',
                );
              },
              child: const Text('Оценка'),
            ),
          if (can('employees.goals'))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                command(
                  'goal',
                  'Изменить цель',
                  '/api/admin/employees/$id/goals',
                );
              },
              child: const Text('Цель'),
            ),
          if (can('employees.goals'))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                command(
                  'plan_action',
                  'Поддержка плана',
                  '/api/admin/employees/$id/plan-actions',
                );
              },
              child: const Text('План'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> orderActions(AdminJson row) async {
    final next =
        const {
          'requested': ['approved', 'rejected'],
          'approved': ['ready', 'cancelled'],
          'ready': ['delivered'],
        }[row['status']] ??
        <String>[];
    final schema = <String, dynamic>{
      'type': 'object',
      'properties': {
        'target_status': {'type': 'string', 'enum': next},
        'note': {'type': 'string', 'minLength': 3, 'maxLength': 2000},
        if (next.contains('delivered'))
          'actual_cost_kzt': {
            'type': 'integer',
            'minimum': 0,
            'maximum': row['budget_cap_kzt'],
          },
      },
    };
    if (next.isEmpty) {
      await detail('История заявки', row);
      return;
    }
    final result = await edit(schema, {}, 'Обработка заявки · тестовая выдача');
    if (result == null) return;
    await perform(() async {
      await api.request(
        'POST',
        '/api/admin/reward-orders/${Uri.encodeComponent(row['id'])}/transition',
        result,
      );
      await load();
    });
  }

  Future<void> reviewActions(AdminJson row) async {
    await detail('Результат сотрудника', row);
    if (!mounted || row['status'] != 'pending') return;
    final result = await edit(
      {
        'type': 'object',
        'properties': {
          'decision': {
            'type': 'string',
            'enum': ['approved', 'rejected'],
          },
          'comment': {'type': 'string', 'minLength': 3, 'maxLength': 2000},
        },
      },
      {},
      'Решение по результату',
    );
    if (result == null) return;
    await perform(() async {
      await api.request(
        'POST',
        '/api/admin/reviews/${Uri.encodeComponent(row['id'])}/decision',
        result,
      );
      await load();
    });
  }

  Future<void> openRow(AdminJson row) async {
    try {
      switch (page) {
        case 'users':
          await userActions(row);
        case 'employees':
          await employeeActions(row);
        case 'changes':
          await perform(() async {
            if (row['status'] == 'published') {
              final history = await api.get(
                '/api/admin/changes/${Uri.encodeComponent(row['id'])}',
              );
              if (!mounted) return;
              final restore = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Опубликованная версия'),
                  content: SizedBox(
                    width: 760,
                    child: SingleChildScrollView(child: AdminDetails(history)),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Закрыть'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Восстановить как черновик'),
                    ),
                  ],
                ),
              );
              if (restore == true) {
                final draft = await api.request(
                  'POST',
                  '/api/admin/changes/${Uri.encodeComponent(row['id'])}/restore-as-draft',
                  {'reason': 'Восстановление выбранной опубликованной версии'},
                );
                if (mounted) await previewChange(draft);
              }
            } else {
              await previewChange(row);
            }
            await load();
          });
        case 'corrections':
          await perform(() async {
            if (row['status'] == 'applied') {
              await detail('Корректировка', row);
            } else {
              await previewChange(row, correction: true);
            }
            await load();
          });
        case 'reward-orders':
          await orderActions(row);
        case 'reviews':
          await reviewActions(row);
        case 'wallets':
          await detail(
            'Журнал кошелька',
            await api.get(
              '/api/admin/wallets/${Uri.encodeComponent(row['id'])}/ledger',
            ),
          );
        case 'inventory':
          await command(
            'inventory',
            'Движение склада',
            '/api/admin/inventory/movements',
            initial: {'item_id': row['id']},
          );
        case 'budgets':
          await detail('Обеспечение сезона', row);
        default:
          if (data['schema'] != null) {
            await editResource(row);
          } else {
            await detail('Подробности', row);
          }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Widget toolbar() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (page == 'branding' && can('branding.manage'))
          action('Загрузить изображение', () async {
            final selection = await FilePicker.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
            );
            final file = selection.firstOrNull;
            if (file == null || !mounted) return;
            final bytes = await file.readAsBytes();
            if (!mounted) return;
            if (bytes.length > 5 * 1024 * 1024) {
              setState(() => error = 'Максимум 5 MiB');
              return;
            }
            final alt = TextEditingController();
            final accepted = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Предпросмотр изображения'),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.memory(
                          bytes,
                          height: 180,
                          errorBuilder: (_, e, s) =>
                              const Text('Изображение не читается'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: alt,
                          decoration: const InputDecoration(
                            labelText: 'Описание изображения',
                          ),
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
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Загрузить'),
                  ),
                ],
              ),
            );
            final description = alt.text;
            alt.dispose();
            if (accepted != true) return;
            await perform(() async {
              final media = await api.uploadImage(
                bytes,
                file.name,
                description,
              );
              if (mounted) {
                await detail('Изображение загружено · URL для формы', media);
              }
              await load();
            });
          }, icon: Icons.add_photo_alternate_outlined),
        if (page == 'recommendations')
          action(
            'Сравнить стратегии',
            () => command(
              'recommendation_test',
              'Проверка рекомендаций',
              '/api/admin/recommendation-policies/simulate',
              initial: {'payload': data['value']},
            ),
            icon: Icons.science_outlined,
          ),
        if (page == 'assistant')
          action(
            'Проверить помощника',
            () => command(
              'assistant_test',
              'Обезличенный тест помощника',
              '/api/admin/assistant-settings/test',
              initial: {'payload': data['value']},
            ),
            icon: Icons.science_outlined,
          ),
        if (page == 'quests')
          action(
            'Проверить 20 примеров',
            () => command(
              'quest_test',
              'Проверка шаблона',
              '/api/admin/quest-templates/test',
            ),
            icon: Icons.science_outlined,
          ),
        if (data['schema'] != null &&
            data['value'] == null &&
            !['corrections'].contains(page))
          action('Создать черновик', () => editResource(), icon: Icons.add),
        if (page == 'users' && can('users.manage'))
          action(
            'Создать аккаунт',
            () => command('user_create', 'Новый аккаунт', '/api/admin/users'),
            icon: Icons.person_add_outlined,
          ),
        if (page == 'seasons')
          action(
            'Создать сезон',
            () => command(
              'season',
              'Новый сезон',
              '/api/admin/seasons',
              initial: {
                'starts_at':
                    '${DateTime.now().add(const Duration(days: 91)).toIso8601String().substring(0, 10)}T00:00:00+05:00',
              },
            ),
            icon: Icons.add,
          ),
        if (page == 'budgets')
          action(
            'Добавить финансирование',
            () => command(
              'budget',
              'Виртуальное финансирование',
              '/api/admin/budget-movements',
            ),
            icon: Icons.add,
          ),
        if (page == 'corrections')
          action('Создать корректировку', () async {
            final result = await commandForm(
              'correction',
              'Основание и действия',
            );
            if (result == null) return;
            await perform(() async {
              final change = await api.request(
                'POST',
                '/api/admin/corrections',
                result,
              );
              if (mounted) await previewChange(change, correction: true);
              await load();
            });
          }, icon: Icons.add),
        if (page == 'system')
          action(
            'Создать резервную копию',
            () => command(
              'reason',
              'Копия в серверном runtime',
              '/api/admin/system/backups',
            ),
            icon: Icons.save_outlined,
          ),
        if (page == 'changes' && can('exports.create'))
          action('Экспорт конфигурации', () async {
            await perform(() async {
              final value = await api.get('/api/admin/config-exports');
              await FilePicker.saveFile(
                dialogTitle: 'Экспорт конфигурации',
                fileName: 'career-config.json',
                type: FileType.custom,
                allowedExtensions: ['json'],
                bytes: Uint8List.fromList(
                  utf8.encode(
                    const JsonEncoder.withIndent('  ').convert(value),
                  ),
                ),
              );
            });
          }, icon: Icons.download_outlined),
      ],
    );
  }

  Widget seasonCard(AdminJson row) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name(row), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '${textValue(row['status'])} · ${row['starts_at']} → ${row['ends_at']}',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            metric('Участников', obj(row['totals'])['roster']),
            metric('Стоимость, ₸', obj(row['totals'])['total_kzt']),
            metric('Уровней', obj(row['totals'])['levels']),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (can('pass.manage'))
              action(
                'Редактор пропуска',
                () => perform(() => passEditor(row)),
                icon: Icons.route_outlined,
              ),
            if (row['status'] == 'draft' && can('seasons.publish'))
              action('Проверить и опубликовать', () async {
                final result = await commandForm('reason', 'Публикация сезона');
                if (result == null) return;
                await perform(() async {
                  final change = await api.request(
                    'POST',
                    '/api/admin/seasons/${Uri.encodeComponent(row['id'])}/publication',
                    result,
                  );
                  if (mounted) await previewChange(change);
                  await load();
                });
              }, icon: Icons.publish),
            if (row['status'] == 'active')
              action(
                row['paused'] == true
                    ? 'Возобновить задания'
                    : 'Приостановить задания',
                () => command(
                  'reason',
                  'Изменить приём заданий',
                  '/api/admin/seasons/${Uri.encodeComponent(row['id'])}/pause',
                ),
                icon: Icons.pause_circle_outline,
              ),
            if (['draft', 'scheduled', 'active'].contains(row['status']))
              action(
                'Даты и название',
                () => command(
                  'season_edit',
                  'Изменение сезона',
                  '/api/admin/seasons/${Uri.encodeComponent(row['id'])}',
                  method: 'PATCH',
                  initial: {
                    'name': row['name'],
                    'starts_at': row['starts_at'],
                    'ends_at': row['ends_at'],
                  },
                ),
              ),
            if (['draft', 'scheduled', 'active'].contains(row['status']))
              action(
                'Участники',
                () => command(
                  'season_members',
                  'Участники сезона и резерв',
                  '/api/admin/seasons/${Uri.encodeComponent(row['id'])}/members',
                  initial: {'employee_ids': row['employee_ids']},
                ),
                icon: Icons.group_outlined,
              ),
          ],
        ),
      ],
    ),
  );
  Widget content() {
    if (page == 'overview') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Управление Career Quest',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Люди, развитие и награды — с проверкой последствий каждого изменения.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ...obj(overview['counts']).entries
                  .map((e) => metric(fieldTitle(e.key), e.value)),
              metric('Черновиков', overview['drafts']),
            ],
          ),
          const SizedBox(height: 24),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  obj(overview['current_season'])['name'] ?? 'Текущий сезон',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Начните с каталога или правил. Сохраните черновик, проверьте влияние и стоимость, затем опубликуйте.',
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (can('seasons.manage'))
                      action(
                        'Открыть сезон',
                        () => go('seasons'),
                        icon: Icons.route_outlined,
                      ),
                    action(
                      'Изменения',
                      () => go('changes'),
                      icon: Icons.history,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'DEMO · Все награды, бюджет и выдача виртуальные.',
            style: TextStyle(color: muted),
          ),
        ],
      );
    }
    if (data['value'] != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ([
            'economy',
            'streaks',
            'achievements',
            'leaderboards',
            'quests',
            'nominations',
          ].contains(page))
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: DropdownButtonFormField<String>(
                initialValue: scope,
                decoration: const InputDecoration(
                  labelText: 'Область применения',
                ),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: 'global',
                    child: Text('Начальные правила будущих сезонов'),
                  ),
                  ...seasons.map(
                    (s) => DropdownMenuItem(
                      value: s['id'].toString(),
                      child: Text(s['name'], overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) {
                  setState(() => scope = v!);
                  load();
                },
              ),
            ),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                action(
                  'Редактировать черновик',
                  () => editResource(obj(data['value'])),
                ),
                const SizedBox(height: 16),
                AdminDetails(data['value']),
              ],
            ),
          ),
        ],
      );
    }
    if (page == 'system') return Surface(child: AdminDetails(data));
    final all = rows(data['items']);
    if (all.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 50),
        child: Center(
          child: Text(
            'Записей пока нет. Здесь появятся результаты работы команды.',
          ),
        ),
      );
    }
    if (page == 'seasons') {
      return Column(
        children: all
            .map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: seasonCard(s),
              ),
            )
            .toList(),
      );
    }
    final wide = MediaQuery.sizeOf(context).width > 1100;
    final columns = page == 'users'
        ? ['role', 'active', 'sessions']
        : page == 'shop' || page == 'inventory'
        ? ['coin_price', 'available_stock', 'version']
        : page == 'wallets'
        ? ['balance']
        : page == 'changes'
        ? ['target_id', 'status', 'draft_version']
        : page == 'employees'
        ? ['department', 'role', 'grade']
        : page == 'audit'
        ? ['actor', 'operation', 'occurred_at']
        : ['status', 'version'];
    if (wide) {
      return Surface(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            headingTextStyle: const TextStyle(
              color: muted,
              fontWeight: FontWeight.bold,
            ),
            columns: [
              const DataColumn(label: Text('Запись')),
              ...columns.map((c) => DataColumn(label: Text(fieldTitle(c)))),
            ],
            rows: all
                .map(
                  (r) => DataRow(
                    onSelectChanged: (_) => openRow(r),
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 300,
                          child: Text(
                            name(r),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      ...columns.map((c) => DataCell(Text(textValue(r[c])))),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      );
    }
    return Column(
      children: all
          .map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => openRow(r),
                  child: Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name(r),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...columns
                            .where((c) => r[c] != null)
                            .map(
                              (c) => Text(
                                '${fieldTitle(c)}: ${textValue(r[c])}',
                                style: const TextStyle(color: muted),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget navigation() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      const Padding(padding: EdgeInsets.all(12), child: Brand()),
      ListTile(
        selected: page == 'overview',
        leading: const Icon(Icons.dashboard_outlined),
        title: const Text('Обзор'),
        onTap: () => navigate('overview'),
      ),
      for (final group in modules.map((m) => m['group']).toSet())
        ExpansionTile(
          initiallyExpanded: true,
          title: Text(
            group,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          children: [
            ...modules
                .where((m) => m['group'] == group)
                .map(
                  (m) => ListTile(
                    dense: true,
                    selected: page == m['id'],
                    selectedColor: pink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    title: Text(m['title']),
                    onTap: () => navigate(m['id']),
                  ),
                ),
          ],
        ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Выйти'),
        onTap: widget.onLogout,
      ),
    ],
  );
  void navigate(String target) {
    if (MediaQuery.sizeOf(context).width < 1000) Navigator.of(context).pop();
    go(target);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      backgroundColor: night,
      drawer: wide ? null : Drawer(backgroundColor: panel, child: navigation()),
      body: QuestBackdrop(
        child: SafeArea(
          child: Row(
            children: [
              if (wide)
                SizedBox(
                  width: 260,
                  child: Material(
                    color: panel.withValues(alpha: .8),
                    child: navigation(),
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: line)),
                      ),
                      child: Row(
                        children: [
                          if (!wide)
                            Builder(
                              builder: (ctx) => IconButton(
                                tooltip: 'Меню',
                                onPressed: () => Scaffold.of(ctx).openDrawer(),
                                icon: const Icon(Icons.menu),
                              ),
                            ),
                          const Chip(label: Text('DEMO')),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              module['title'] ?? 'Обзор',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (wide)
                            Text(
                              '${widget.user['display_name']} · ${textValue(widget.user['role'])}',
                              style: const TextStyle(color: muted),
                            ),
                          IconButton(
                            tooltip: 'Обновить',
                            onPressed: busy ? null : load,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ),
                    if (busy) const LinearProgressIndicator(value: 1),
                    Expanded(
                      child: SelectionArea(
                        child: ListView(
                          padding: EdgeInsets.all(wide ? 28 : 16),
                          children: [
                            if (error.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Surface(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        error,
                                        style: const TextStyle(color: danger),
                                      ),
                                      TextButton(
                                        onPressed: load,
                                        child: const Text(
                                          'Обновить и повторить',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (loading)
                              const Padding(
                                padding: EdgeInsets.all(60),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else ...[
                              if (page != 'overview') ...[
                                Text(
                                  module['title'] ?? page,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                toolbar(),
                                const SizedBox(height: 20),
                                if ([
                                  'users',
                                  'employees',
                                  'departments',
                                  'skills',
                                  'career-roles',
                                  'activities',
                                  'shop',
                                  'reward-pools',
                                  'changes',
                                  'audit',
                                ].contains(page))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: TextFormField(
                                      initialValue: search,
                                      key: ValueKey('search:$page'),
                                      decoration: const InputDecoration(
                                        labelText: 'Поиск · Enter',
                                        prefixIcon: Icon(Icons.search),
                                      ),
                                      onFieldSubmitted: (v) {
                                        setState(() {
                                          search = v;
                                          pageNumber = 1;
                                        });
                                        load();
                                      },
                                    ),
                                  ),
                              ],
                              content(),
                              if (data['total'] != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Найдено ${data['total']} · страница $pageNumber',
                                          style: const TextStyle(color: muted),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Назад',
                                        onPressed: pageNumber > 1
                                            ? () {
                                                pageNumber--;
                                                load();
                                              }
                                            : null,
                                        icon: const Icon(Icons.chevron_left),
                                      ),
                                      IconButton(
                                        tooltip: 'Далее',
                                        onPressed:
                                            pageNumber * 25 <
                                                (data['total'] as num)
                                            ? () {
                                                pageNumber++;
                                                load();
                                              }
                                            : null,
                                        icon: const Icon(Icons.chevron_right),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PassEditor extends StatefulWidget {
  const PassEditor({
    super.key,
    required this.api,
    required this.season,
    required this.data,
    required this.onDraft,
  });
  final CareerApi api;
  final AdminJson season, data;
  final Future<void> Function(AdminJson) onDraft;
  @override
  State<PassEditor> createState() => _PassEditorState();
}

class _PassEditorState extends State<PassEditor> {
  late List<AdminJson> rewards;
  int page = 0;
  bool busy = false, dirty = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    rewards = rows(copyValue(obj(widget.data['value'])['rewards']));
  }

  Future<void> editLevel(int index) async {
    final schema = obj(widget.data['schema']);
    final definition = obj(obj(schema[r'$defs'])['PassLevel']);
    final result = await showDialog<AdminJson>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SchemaEditor(
        schema: {...definition, r'$defs': schema[r'$defs']},
        initial: rewards[index],
        title: 'Уровень ${index + 1}',
      ),
    );
    if (result != null && mounted) {
      setState(() {
        rewards[index] = result;
        dirty = true;
      });
    }
  }

  Future<void> bulk() async {
    final result = await showDialog<AdminJson>(
      context: context,
      builder: (_) => SchemaEditor(
        schema: {
          'type': 'object',
          'properties': {
            'from': {
              'type': 'integer',
              'minimum': 1,
              'maximum': rewards.length,
            },
            'to': {'type': 'integer', 'minimum': 1, 'maximum': rewards.length},
            'xp_step': {'type': 'integer', 'minimum': 1, 'maximum': 100000},
            'coin_delta': {
              'type': 'integer',
              'minimum': -10000,
              'maximum': 10000,
            },
          },
        },
        initial: {
          'from': 1,
          'to': rewards.length,
          'xp_step': 200,
          'coin_delta': 0,
        },
        title: 'Заполнить диапазон (черновик)',
      ),
    );
    if (result != null && mounted) {
      setState(() {
        for (
          var i = (result['from'] as int) - 1;
          i < (result['to'] as int);
          i++
        ) {
          rewards[i]['required_total_xp'] = (i + 1) * result['xp_step'];
          final components = rewards[i]['components'] as List;
          for (final c in components) {
            if (c['type'] == 'coins') {
              c['coins'] = (c['coins'] as int) + result['coin_delta'];
            }
          }
        }
        dirty = true;
      });
    }
  }

  Future<void> close() async {
    if (dirty) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Закрыть несохранённый пропуск?'),
          content: const Text('Изменения уровней ещё не сохранены в черновик.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Остаться'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    var coins = 0, caps = 0;
    for (final r in rewards) {
      for (final c in rows(r['components'])) {
        coins += (c['coins'] as int? ?? 0);
        caps += (c['budget_cap_kzt'] as int? ?? 0);
      }
    }
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (p, r) {
        if (!p) close();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Пропуск · ${widget.season['name']}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${rewards.length} уровней · $coins CQ · подарки $caps ₸ · XP ${rewards.last['required_total_xp']}',
                ),
                const Text(
                  'Полная стоимость и влияние рассчитываются сервером в предпросмотре.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton(
                      onPressed: busy ? null : bulk,
                      child: const Text('Массовое заполнение'),
                    ),
                    OutlinedButton(
                      onPressed: busy || rewards.length >= 200
                          ? null
                          : () => setState(() {
                              rewards.add({
                                'level': rewards.length + 1,
                                'required_total_xp':
                                    (rewards.last['required_total_xp'] as int) +
                                    200,
                                'components': [
                                  {'type': 'coins', 'coins': 5, 'name': '5 CQ'},
                                ],
                              });
                              dirty = true;
                            }),
                      child: const Text('Добавить уровень'),
                    ),
                    OutlinedButton(
                      onPressed: busy || rewards.length <= 1
                          ? null
                          : () => setState(() {
                              rewards.removeLast();
                              page = page.clamp(0, (rewards.length - 1) ~/ 10);
                              dirty = true;
                            }),
                      child: const Text('Удалить последний'),
                    ),
                  ],
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(error, style: const TextStyle(color: danger)),
                  ),
                Expanded(
                  child: ListView(
                    children: List.generate(
                      (rewards.length - page * 10).clamp(0, 10),
                      (i) {
                        final index = page * 10 + i;
                        final r = rewards[index];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: panelRaised,
                              child: Text('${r['level']}'),
                            ),
                            title: Text('${r['required_total_xp']} XP'),
                            subtitle: Text(
                              rows(r['components'])
                                  .map(
                                    (c) => c['type'] == 'coins'
                                        ? '${c['coins']} CQ'
                                        : '${c['name']}${c['budget_cap_kzt'] != null ? ' · ${c['budget_cap_kzt']} ₸' : ''}',
                                  )
                                  .join(' + '),
                            ),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: busy ? null : () => editLevel(index),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Предыдущие уровни',
                      onPressed: page > 0 ? () => setState(() => page--) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('${page + 1} / ${(rewards.length / 10).ceil()}'),
                    IconButton(
                      tooltip: 'Следующие уровни',
                      onPressed: (page + 1) * 10 < rewards.length
                          ? () => setState(() => page++)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                    const Spacer(),
                    Flexible(
                      child: FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                setState(() => busy = true);
                                try {
                                  final change = await widget.api.request(
                                    'PATCH',
                                    '/api/admin/seasons/${Uri.encodeComponent(widget.season['id'])}/pass',
                                    {
                                      'payload': {'rewards': rewards},
                                      'reason':
                                          'Обновление карьерного пропуска',
                                    },
                                  );
                                  setState(() => dirty = false);
                                  await widget.onDraft(change);
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => error = e.toString());
                                  }
                                } finally {
                                  if (mounted) setState(() => busy = false);
                                }
                              },
                        child: const Text('Сохранить и проверить'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
