import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../core/api.dart';
import '../widgets/ui.dart';
import '../widgets/career_pass.dart';
import 'login.dart';
import '../features/admin/admin_shell.dart';

part 'career_views.dart';
part 'game_views.dart';
part 'hr_views.dart';

String label(dynamic raw) =>
    const <String, String>{
      'planned': 'В плане',
      'in_progress': 'В работе',
      'completed': 'Завершено',
      'archived': 'В архиве',
      'pending': 'На проверке',
      'approved': 'Одобрено',
      'rejected': 'Отклонено',
      'requested': 'Заявка отправлена',
      'ready': 'Готово к выдаче',
      'delivered': 'Выдано',
      'cancelled': 'Отменено',
      'available': 'Доступно',
      'reserved': 'Зарезервировано',
      'fulfilled': 'Получено',
      'credited': 'Начислено',
      'expired': 'Срок истёк',
      'locked': 'Закрыто',
      'draft': 'Черновик',
      'scheduled': 'Запланирован',
      'active': 'Идёт сезон',
      'settling': 'Проверка итогов',
      'finalized': 'Итоги подведены',
      'closed': 'Закрыт',
      'online': 'Онлайн',
      'offline': 'Очно',
      'self_paced': 'Самостоятельно',
      'imported': 'Исходная история',
      'self_report': 'Самоотчёт',
      'no_goal': 'Выберите карьерную цель',
      'needs_assessment': 'Не хватает оценок для расчёта',
      'goal_covered': 'Расчётные требования цели покрыты',
      'plan_full': 'Достигнут лимит шагов плана',
      'plan_covers_goal': 'Текущего плана достаточно для расчётного покрытия',
      'no_time_fit': 'Нет шагов в вашем бюджете времени',
      'no_available_activities': 'Подходящих активностей пока нет',
      'all_candidates_hidden': 'Подходящие варианты скрыты',
      'ACTIVITY_UNAVAILABLE': 'Активность недоступна',
      'PREREQUISITE_NOT_MET': 'Не выполнены предварительные требования',
      'ALREADY_IMPORTED_COMPLETE': 'Уже завершено в исходной истории',
      'EXTERNAL_ACTIVITY_IN_PROGRESS': 'Уже начато вне платформы',
      'ALREADY_COMPLETED': 'Уже выполнено',
      'ACTIVITY_EXPIRED': 'Срок активности истёк',
      'pass_level': 'Награда пропуска',
      'season_podium': 'Приз сезона',
      'shop_order': 'Покупка',
      'order_refund': 'Возврат',
      'daily': 'Ежедневное задание',
      'activity': 'Карьерная практика',
      'achievement': 'Достижение',
    }[raw] ??
    value(raw);
String pct(dynamic v) =>
    v is num ? '${v.toStringAsFixed(1).replaceAll('.', ',')}%' : 'Нет данных';
Json map(dynamic v) => v is Map ? Json.from(v) : <String, dynamic>{};
String segment(String v) => Uri.encodeComponent(v);

class Workspace extends StatefulWidget {
  const Workspace({super.key, this.api});
  final CareerApi? api;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> with WidgetsBindingObserver {
  late CareerApi api;
  Json? user;
  Json data = {}, home = {}, reference = {};
  String page = 'home',
      error = '',
      loginMessage = '',
      search = '',
      filter = '',
      seasonTab = 'pass';
  String? returnRoute;
  final Map<String, Json> viewFilters = {};
  final Map<String, Json> routeState = {};
  Timer? previewDebounce, countdownTimer;
  int previewGeneration = 0;
  Json get extraFilters =>
      viewFilters.putIfAbsent(page.split('/').first, () => {});
  Map<String, String> get reportFilters => Map.fromEntries(
    hrFilters.entries.where((e) => !['skill_id', 'has_gap'].contains(e.key)),
  );

  int listPage = 1, generation = 0;
  bool loading = false, busy = false, manageMode = false;
  Set<String> simulationIds = {};
  Json? simulation;
  String? simulationRole, simulationGrade;
  Map<String, String> hrFilters = {};
  bool get hr => user?['role'] == 'hr';
  bool hasPermission(String permission) =>
      (user?['capabilities'] as List? ?? []).contains(permission);
  bool get administrator =>
      ['admin', 'super_admin'].contains(user?['role']) || manageMode;
  String get root => hr ? 'hr' : 'employee';
  String get title => titles[page.split('/').first] ?? 'Подробности';
  String contentText(String key, String fallback) {
    final text =
        records(runtimeConfiguration.value['content']?['entries'])
            .where((e) => e['key'] == key)
            .firstOrNull?['value'] ??
        fallback;
    final season = data['gamification'] ?? data;
    return text
        .toString()
        .replaceAll('{level}', '${season['level'] ?? 0}')
        .replaceAll('{xp}', '${season['confirmed_xp'] ?? 0}')
        .replaceAll('{coins}', '${season['wallet_balance'] ?? 0}')
        .replaceAll('{season_name}', '${season['season']?['name'] ?? ''}');
  }

  Map<String, String> get titles => hr
      ? {
          'overview': 'Сводка',
          'skills': 'Дефициты навыков',
          'employees': 'Сотрудники',
          'gamification': 'Сезон и бюджет',
          'reviews': 'Проверка результатов',
          'rewards': 'Выдача наград',
          'shop': 'Управление магазином',
        }
      : {
          'home': contentText('home.title', 'Главная'),
          'plan': contentText('plan.title', 'Мой маршрут'),
          'season': contentText('season.title', 'Карьерный пропуск'),
          'shop': contentText('shop.title', 'Награды'),
          'catalog': contentText('catalog.title', 'Все активности'),
          'history': contentText('history.title', 'История'),
          'profile': contentText('profile.title', 'Профиль'),
          'goal': contentText('goal.title', 'Цель'),
          'skills': contentText('skills.title', 'Навыки'),
          'simulator': contentText('simulator.title', 'Примерить цель'),
          'passport': contentText('passport.title', 'Паспорт'),
          'wallet': contentText('wallet.title', 'CQ-баланс'),
          'rewards': 'Мои подарки',
          'activities': 'Активность',
          'assistant': 'OpenAI-помощник',
        };
  @override
  void initState() {
    super.initState();
    api = widget.api ?? CareerApi();
    countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && user != null && page == 'season' && seasonTab == 'tasks') {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addObserver(this);
    returnRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    api.onUnauthorized = () {
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      setState(() {
        user = null;
        data = {};
        home = {};
        reference = {};
        simulation = null;
        simulationIds = {};
        simulationRole = null;
        simulationGrade = null;
        viewFilters.clear();
        routeState.clear();
        hrFilters.clear();
        previewDebounce?.cancel();
        previewGeneration++;
        generation++;
        loginMessage = 'Сессия завершилась. Войдите снова.';
      });
    };
  }

  @override
  void dispose() {
    previewDebounce?.cancel();
    countdownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    api.onUnauthorized = null;
    if (widget.api == null) api.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && user != null && !administrator) {
      reload();
    }
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final route = routeInformation.uri.path;
    if (user == null) {
      returnRoute = route;
      return true;
    }
    if (route.startsWith('/$root/')) {
      go(route.substring(root.length + 2), updateUrl: false);
      return true;
    }
    return true;
  }

  void go(String target, {bool updateUrl = true}) {
    setState(() {
      routeState[page] = {'search': search, 'filter': filter, 'page': listPage};
      final old = routeState[target] ?? {};
      page = target;
      data = {};
      search = old['search'] ?? '';
      filter = old['filter'] ?? '';
      listPage = old['page'] ?? 1;
      error = '';
    });
    if (updateUrl) {
      SystemNavigator.routeInformationUpdated(
        uri: Uri(path: '/$root/$target'),
        replace: false,
      );
    }
    reload();
  }

  Future<void> reload() async {
    if (administrator || user?['must_change_password'] == true) return;
    final version = ++generation;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      await api.refreshConfiguration();
      final ref = await api.get('/api/reference');
      final base = hr
          ? <String, dynamic>{}
          : await api.get('/api/me/dashboard');
      final loaded = await fetchPage();
      if (mounted && version == generation) {
        setState(() {
          reference = ref;
          home = base;
          data = loaded;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && version == generation) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  String query(Map<String, dynamic> values) =>
      Uri(queryParameters: values.map((k, v) => MapEntry(k, v.toString())))
          .query;
  Future<Json> fetchPage() async {
    final parts = page.split('/');
    final name = parts.first;
    if (hr) {
      final filters = query(reportFilters);
      if (name == 'overview' || name == 'skills') {
        return api.get('/api/hr/overview?$filters');
      }
      if (name == 'employees') {
        if (parts.length > 1) {
          final p = await api.get('/api/hr/employees/${segment(parts[1])}');
          p['history'] = await api.get(
            '/api/hr/employees/${segment(parts[1])}/history',
          );
          return p;
        }
        return api.get(
          '/api/hr/employees?${query({...hrFilters, 'search': search, 'page': listPage})}',
        );
      }
      if (name == 'gamification' && parts.length > 2) {
        return {
          'season': await api.get('/api/seasons/${segment(parts[1])}'),
          'content': await api.get(
            '/api/seasons/${segment(parts[1])}/leaderboard?page=$listPage',
          ),
        };
      }
      if (name == 'gamification') {
        final seasons = await api.get('/api/hr/seasons');
        final items = records(seasons['items']);
        final chosen =
            items.where((s) => s['id'] == filter).firstOrNull ??
            items.where((s) => s['status'] == 'active').firstOrNull ??
            items.firstOrNull;
        if (chosen != null) {
          seasons['selected'] = chosen;
          seasons['economy'] = await api.get(
            '/api/hr/seasons/${segment(chosen['id'])}/economy',
          );
          seasons['pools'] = await api.get(
            '/api/hr/reward-pools?${query({'season_id': chosen['id']})}',
          );
        }
        return seasons;
      }
      if (name == 'reviews') {
        return api.get(
          '/api/hr/reward-reviews${filter.isEmpty ? '' : '?${query({'status': filter})}'}',
        );
      }
      if (name == 'rewards') {
        return api.get(
          '/api/hr/reward-orders${filter.isEmpty ? '' : '?${query({'status': filter})}'}',
        );
      }
      if (name == 'shop') return api.get('/api/hr/shop/items');
      return {};
    }
    switch (name) {
      case 'home':
        return api.get('/api/me/dashboard');
      case 'goal':
      case 'profile':
      case 'skills':
        return api.get('/api/me/profile');
      case 'plan':
        return api.get('/api/me/plan');
      case 'catalog':
        return api.get(
          '/api/activities?${query({...extraFilters, 'search': search, 'page': listPage, if (filter.isNotEmpty) 'format': filter})}',
        );
      case 'activities':
        return api.get('/api/activities/${segment(parts.last)}');
      case 'history':
        final h = await api.get(
          '/api/me/history?${query({...extraFilters, 'page': listPage, if (filter.isNotEmpty) 'origin': filter})}',
        );
        h['reviews'] = await api.get('/api/me/reward-reviews');
        return h;
      case 'simulator':
        return api.get(
          '/api/activities?${query({'page': listPage, 'search': search})}',
        );
      case 'passport':
        return api.get('/api/me/passport');
      case 'assistant':
        return api.get('/api/me/assistant/status');
      case 'wallet':
        return api.get('/api/me/wallet?page=$listPage');
      case 'rewards':
        return api.get('/api/me/rewards');
      case 'shop':
        return api.get(
          '/api/shop/items?${query({...extraFilters, 'page': listPage, if (filter.isNotEmpty) 'category': filter})}',
        );
      case 'season':
        final s = await api.get('/api/me/season');
        if (seasonTab == 'leaderboard') {
          s['content'] = await api.get(
            '/api/seasons/${segment(s['season']['id'])}/leaderboard?${query({'page': listPage, 'scope': filter.isEmpty ? 'overall' : filter, if (filter == 'week' && extraFilters['week'] != null) 'week': extraFilters['week']})}',
          );
        } else if (seasonTab == 'hall') {
          s['content'] = await api.get('/api/seasons/hall-of-fame');
        } else {
          s['content'] = await api.get('/api/me/season/$seasonTab');
        }
        return s;
      default:
        return {};
    }
  }

  Future<void> logout() async {
    final revoke = api.logout();
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() {
      user = null;
      data = {};
      home = {};
      reference = {};
      page = 'home';
      generation++;
      simulation = null;
      simulationIds = {};
      simulationRole = null;
      simulationGrade = null;
      viewFilters.clear();
      routeState.clear();
      hrFilters.clear();
      previewDebounce?.cancel();
      previewGeneration++;
      returnRoute = null;
      search = '';
      filter = '';
      seasonTab = 'pass';
      listPage = 1;
    });
    SystemNavigator.routeInformationUpdated(
      uri: Uri(path: '/login'),
      replace: true,
    );
    try {
      await revoke;
    } catch (_) {}
  }

  Future<void> act(String method, String path, [Json? body]) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await api.request(method, path, body ?? {});
      await reload();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(
    String title,
    String message, {
    String action = 'Подтвердить',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<String?> prompt(
    String title, {
    String hint = '',
    int max = 2000,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 8,
            maxLength: max,
            decoration: InputDecoration(hintText: hint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    // Dialog closes on the next frame; dispose only after the animation.
    Future.delayed(const Duration(milliseconds: 350), controller.dispose);
    return result;
  }

  Future<void> download(String path, String name) async {
    try {
      final bytes = await api.download(path);
      await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        type: FileType.any,
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Widget button(
    String text,
    VoidCallback action, {
    bool primary = false,
    IconData? icon,
  }) => primary
      ? FilledButton(onPressed: busy ? null : action, child: Text(text))
      : OutlinedButton(onPressed: busy ? null : action, child: Text(text));
  Widget heading(String text, [String? subtitle]) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: SectionTitle(text, subtitle: subtitle),
  );
  Widget card(String title, Widget child, {String? subtitle}) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: subtitle == null ? 30 : 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [pink, violet],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: pink.withValues(alpha: .25),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: SectionTitle(title, subtitle: subtitle)),
                ],
              ),
            ),
          child,
        ],
      ),
    ),
  );
  Widget actions(List<Widget> children) =>
      Wrap(spacing: 10, runSpacing: 10, children: children);
  Widget empty(String text) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: panelRaised.withValues(alpha: .36),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line.withValues(alpha: .65)),
    ),
    child: EmptyState(
      'Пока здесь пусто',
      text,
      icon: Icons.auto_awesome_rounded,
    ),
  );
  Widget metric(String name, String val, {Color accent = pink}) => Container(
    width: 190,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent.withValues(alpha: .13), panelRaised],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: .24)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: .055),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 4,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          val,
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
        const SizedBox(height: 8),
        Text(name, style: const TextStyle(color: muted, fontSize: 12)),
      ],
    ),
  );
  Widget pager(Json source) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        onPressed: listPage > 1
            ? () {
                setState(() => listPage--);
                reload();
              }
            : null,
        icon: const Icon(Icons.chevron_left),
      ),
      Text(
        '$listPage / ${((source['total'] ?? 0) / 20).ceil().clamp(1, 9999)}',
      ),
      IconButton(
        onPressed: listPage * 20 < (source['total'] ?? 0)
            ? () {
                setState(() => listPage++);
                reload();
              }
            : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
  Future<void> editListFilters(
    String title,
    List<(String, String, List<(String, String)>)> choices,
    List<(String, String)> fields,
  ) async {
    final draft = Json.from(extraFilters);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in choices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: select(
                        c.$2,
                        value(draft[c.$1], ''),
                        c.$3,
                        (v) => update(() => draft[c.$1] = v),
                      ),
                    ),
                  for (final f in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextFormField(
                        initialValue: value(draft[f.$1], ''),
                        decoration: InputDecoration(labelText: f.$2),
                        onChanged: (v) => draft[f.$1] = v,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                draft.clear();
                Navigator.pop(ctx, true);
              },
              child: const Text('Сбросить'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      setState(() {
        extraFilters
          ..clear()
          ..addAll(
            draft
              ..removeWhere((k, v) => v == null || v.toString().trim().isEmpty),
          );
        listPage = 1;
      });
      await reload();
    }
  }

  Widget select(
    String title,
    String selected,
    List<(String, String)> entries,
    ValueChanged<String> change,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$title:$selected'),
    initialValue: entries.any((e) => e.$1 == selected) ? selected : null,
    decoration: InputDecoration(labelText: title),
    isExpanded: true,
    items: entries
        .map(
          (e) => DropdownMenuItem(
            value: e.$1,
            child: Text(e.$2, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: (v) {
      if (v != null) change(v);
    },
  );

  IconData navIcon(String key) =>
      const <String, IconData>{
        'home': Icons.explore_rounded,
        'plan': Icons.route_rounded,
        'season': Icons.emoji_events_rounded,
        'shop': Icons.shopping_bag_rounded,
        'catalog': Icons.auto_stories_rounded,
        'history': Icons.history_rounded,
        'profile': Icons.badge_rounded,
        'simulator': Icons.auto_graph_rounded,
        'passport': Icons.description_rounded,
        'wallet': Icons.account_balance_wallet_rounded,
        'rewards': Icons.redeem_rounded,
        'assistant': Icons.auto_awesome_rounded,
        'overview': Icons.dashboard_rounded,
        'skills': Icons.insights_rounded,
        'employees': Icons.groups_rounded,
        'gamification': Icons.workspace_premium_rounded,
        'reviews': Icons.fact_check_rounded,
      }[key] ??
      Icons.circle_outlined;

  List<(String, List<String>)> get navGroups => hr
      ? [
          ('КОМАНДА', ['overview', 'skills', 'employees']),
          ('МОТИВАЦИЯ', ['gamification', 'reviews', 'rewards', 'shop']),
        ]
      : [
          (
            'ОСНОВНОЕ',
            ['home', 'plan', 'assistant', 'season', 'shop', 'profile'],
          ),
        ];

  Widget navigation(bool wide) {
    final displayName = value(
      user?['display_name'],
      hr ? 'HR-команда' : 'Сотрудник',
    );
    final username = value(user?['username'], hr ? 'hr.demo' : 'employee.demo');
    final game = map(home['gamification']);
    return Container(
      margin: wide ? const EdgeInsets.fromLTRB(14, 14, 0, 14) : EdgeInsets.zero,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111B39), Color(0xFF0B122B)],
        ),
        borderRadius: BorderRadius.circular(wide ? 28 : 0),
        border: Border.all(color: line.withValues(alpha: .72)),
        boxShadow: wide
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .24),
                  blurRadius: 34,
                  offset: const Offset(8, 12),
                ),
                BoxShadow(color: blue.withValues(alpha: .05), blurRadius: 30),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(wide ? 28 : 0),
        child: Stack(
          children: [
            Positioned(
              top: -90,
              right: -80,
              child: IgnorePointer(
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        violet.withValues(alpha: .15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 21, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Brand(),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              blue.withValues(alpha: .13),
                              violet.withValues(alpha: .08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: blue.withValues(alpha: .2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [blue, Color(0xFF7650A4)],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                initials(displayName),
                                style: const TextStyle(
                                  color: ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: ink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    username,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: cyan,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(13, 2, 13, 12),
                    children: [
                      for (final group in navGroups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 13, 12, 7),
                          child: Text(
                            group.$1,
                            style: const TextStyle(
                              color: Color(0xFF7886AD),
                              fontSize: 9,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        for (final key in group.$2) navItem(key, wide),
                      ],
                    ],
                  ),
                ),
                if (!hr && game.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: InkWell(
                      onTap: () => go('season'),
                      borderRadius: BorderRadius.circular(17),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF222B54),
                              violet.withValues(alpha: .16),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(
                            color: violet.withValues(alpha: .25),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.bolt_rounded,
                              color: pink,
                              size: 20,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Уровень ${value(game['level'], '1')}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${value(game['wallet_balance'], '0')} CQ',
                              style: const TextStyle(
                                color: Color(0xFFF2D28C),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 0, 13, 16),
                  child: Column(
                    children: [
                      Divider(color: line.withValues(alpha: .65)),
                      const SizedBox(height: 5),
                      ListTile(
                        minTileHeight: 48,
                        leading: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: danger.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            color: danger,
                            size: 19,
                          ),
                        ),
                        title: const Text(
                          'Выйти',
                          style: TextStyle(
                            color: ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        onTap: logout,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget navItem(String key, bool wide) {
    final active = page.split('/').first == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: active
              ? LinearGradient(
                  colors: [
                    pink.withValues(alpha: .18),
                    violet.withValues(alpha: .11),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: active ? pink.withValues(alpha: .3) : Colors.transparent,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: pink.withValues(alpha: .08),
                    blurRadius: 18,
                    spreadRadius: -5,
                  ),
                ]
              : null,
        ),
        child: ListTile(
          dense: true,
          minTileHeight: 45,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          selected: active,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          leading: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 33,
            height: 33,
            decoration: BoxDecoration(
              color: active
                  ? pink.withValues(alpha: .14)
                  : blue.withValues(alpha: .065),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              navIcon(key),
              color: active ? pink : const Color(0xFF91A5D8),
              size: 18,
            ),
          ),
          title: Text(
            titles[key] ?? key,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? ink : const Color(0xFFD5DCF2),
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          trailing: active
              ? Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: pink,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
          onTap: () {
            if (!wide) Navigator.pop(context);
            go(key);
          },
        ),
      ),
    );
  }

  Widget topBar(bool wide) => Container(
    margin: EdgeInsets.fromLTRB(wide ? 16 : 10, wide ? 14 : 10, 14, 0),
    padding: EdgeInsets.symmetric(horizontal: wide ? 18 : 11, vertical: 10),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          panelRaised.withValues(alpha: .82),
          const Color(0xFF151A37).withValues(alpha: .88),
        ],
      ),
      borderRadius: BorderRadius.circular(21),
      border: Border.all(color: line.withValues(alpha: .72)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .15),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        if (hr && (user?['capabilities'] as List? ?? []).isNotEmpty)
          IconButton(
            tooltip: 'Администрирование',
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: () {
              setState(() => manageMode = true);
              SystemNavigator.routeInformationUpdated(
                uri: Uri(path: '/admin/overview'),
                replace: false,
              );
            },
          ),
        if (!wide) ...[
          Builder(
            builder: (ctx) => IconButton.filledTonal(
              tooltip: 'Меню',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          ),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hr ? 'HR · РАЗВИТИЕ КОМАНДЫ' : 'ЛИЧНОЕ ПРОСТРАНСТВО',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: cyan,
                  fontSize: 8,
                  letterSpacing: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontSize: wide ? 19 : 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.35,
                ),
              ),
            ],
          ),
        ),
        if (!hr && home['gamification'] != null) ...[
          InkWell(
            onTap: () => go('wallet'),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF2D28C).withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFF2D28C).withValues(alpha: .22),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.toll_rounded,
                    size: 16,
                    color: Color(0xFFF2D28C),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${home['gamification']['wallet_balance']} CQ',
                    style: const TextStyle(
                      color: Color(0xFFF2D28C),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        IconButton.filledTonal(
          tooltip: 'Обновить',
          onPressed: loading ? null : reload,
          icon: const Icon(Icons.refresh_rounded, size: 20),
        ),
      ],
    ),
  );

  Widget employeePageGuide() {
    final key = page.split('/').first;
    if (hr || key == 'home') return const SizedBox.shrink();
    const guides = <String, (IconData, String, String)>{
      'plan': (
        Icons.route_rounded,
        'Собери маршрут из конкретных шагов',
        'Здесь не нужно планировать всю карьеру: выбери до трёх ближайших действий и начни с первого.',
      ),
      'season': (
        Icons.emoji_events_rounded,
        'Поддерживай регулярность',
        'Задания, серии и XP показывают участие в программе, но не заменяют оценку навыков.',
      ),
      'shop': (
        Icons.redeem_rounded,
        'Выбирай награды за участие',
        'CQ-монеты и подарки относятся к демонстрационному сезону и не влияют на карьерные решения.',
      ),
      'catalog': (
        Icons.auto_stories_rounded,
        'Найди один подходящий шаг',
        'Используй поиск и фильтры, затем добавь подходящую активность в свой маршрут.',
      ),
      'history': (
        Icons.history_rounded,
        'Посмотри, что уже сделано',
        'Здесь собраны исходные записи, завершённые активности и результаты, отправленные на проверку.',
      ),
      'profile': (
        Icons.badge_rounded,
        'Проверь свою отправную точку',
        'Роль, опыт, ритм развития и связанные инструменты собраны в одном месте.',
      ),
      'goal': (
        Icons.explore_rounded,
        'Выбери направление развития',
        'Цель помогает сравнить навыки с требованиями, но не меняет должность и не гарантирует повышение.',
      ),
      'skills': (
        Icons.insights_rounded,
        'Разбери прогресс по навыкам',
        'Смотри отдельно последнюю оценку, расчёт после действий и требования выбранной цели.',
      ),
      'simulator': (
        Icons.auto_graph_rounded,
        'Примерь другой маршрут без риска',
        'Пока ты не сохранишь результат, текущая цель, план и показатели останутся без изменений.',
      ),
      'passport': (
        Icons.description_rounded,
        'Собери развитие в одном документе',
        'Паспорт объединяет цель, прогресс, маршрут и достижения для спокойного обсуждения с руководителем.',
      ),
      'wallet': (
        Icons.account_balance_wallet_rounded,
        'Проверь движение CQ-монет',
        'Баланс отражает только виртуальную экономику демонстрационного сезона.',
      ),
      'rewards': (
        Icons.card_giftcard_rounded,
        'Следи за своими подарками',
        'Здесь видно выбранные награды и их текущий статус выдачи.',
      ),
      'assistant': (
        Icons.auto_awesome_rounded,
        'OpenAI объяснит и соберёт черновик',
        'Помощник разбирает серверные расчёты и предлагает маршрут из реальных мероприятий. Итоговая проверка и решение остаются за человеком.',
      ),
      'activities': (
        Icons.playlist_add_check_circle_rounded,
        'Разбери шаг перед добавлением',
        'Проверь формат, длительность, ожидаемый результат и связь активности с навыками.',
      ),
    };
    final guide = guides[key];
    if (guide == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [blue.withValues(alpha: .12), violet.withValues(alpha: .07)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: blue.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: blue.withValues(alpha: .2)),
            ),
            child: Icon(guide.$1, color: blue, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ЗАЧЕМ ЭТОТ РАЗДЕЛ',
                  style: TextStyle(
                    color: cyan,
                    fontSize: 8,
                    letterSpacing: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  guide.$2,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  guide.$3,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'На главную',
            onPressed: () => go('home'),
            icon: const Icon(Icons.home_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  Future<void> showMore(List<MapEntry<String, String>> links) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * .82,
          ),
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
          decoration: BoxDecoration(
            color: const Color(0xFF101831),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 17, 10, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hr ? 'Все разделы' : 'Профиль и помощь',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in links)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color:
                                  (page.split('/').first == entry.key
                                          ? pink
                                          : blue)
                                      .withValues(alpha: .11),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              navIcon(entry.key),
                              color: page.split('/').first == entry.key
                                  ? pink
                                  : blue,
                              size: 20,
                            ),
                          ),
                          title: Text(entry.value),
                          selected: page.split('/').first == entry.key,
                          selectedTileColor: pink.withValues(alpha: .08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            go(entry.key);
                          },
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

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return LoginPage(
        api: api,
        message: loginMessage.isEmpty ? null : loginMessage,
        onLogin: (u) {
          setState(() {
            user = u;
            manageMode =
                (returnRoute ?? '').startsWith('/admin/') &&
                (u['capabilities'] as List? ?? []).isNotEmpty;
            loginMessage = '';
          });
          if (administrator || u['must_change_password'] == true) return;
          final route = returnRoute;
          returnRoute = null;
          go(
            route != null && route.startsWith('/$root/')
                ? route.substring(root.length + 2)
                : hr
                ? 'overview'
                : 'home',
          );
        },
      );
    }
    if (user?['must_change_password'] == true) {
      return PasswordChangePage(api: api, onDone: logout);
    }
    if (administrator) {
      return AdminShell(
        api: api,
        user: user!,
        onLogout: logout,
        initialRoute: returnRoute,
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final links = hr
        ? titles.entries.toList()
        : [
            'profile',
            'history',
            'assistant',
          ].map((key) => MapEntry(key, titles[key]!)).toList();
    return Scaffold(
      drawer: wide
          ? null
          : Drawer(
              width: 292,
              backgroundColor: night,
              child: SafeArea(child: navigation(false)),
            ),
      body: QuestBackdrop(
        child: SafeArea(
          child: Row(
            children: [
              if (wide) SizedBox(width: 286, child: navigation(true)),
              Expanded(
                child: Column(
                  children: [
                    topBar(wide),
                    SizedBox(
                      height: 3,
                      child: loading
                          ? const LinearProgressIndicator(minHeight: 3)
                          : null,
                    ),
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.fromLTRB(
                          wide ? 16 : 10,
                          7,
                          14,
                          wide ? 14 : 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xA6080D22),
                          borderRadius: BorderRadius.circular(27),
                          border: Border.all(
                            color: line.withValues(alpha: .42),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          key: ValueKey(page),
                          padding: EdgeInsets.all(wide ? 28 : 15),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1180),
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey('page-$page'),
                                tween: Tween(begin: 0, end: 1),
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                builder: (context, progress, child) => Opacity(
                                  opacity: progress,
                                  child: Transform.translate(
                                    offset: Offset(0, 12 * (1 - progress)),
                                    child: child,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (runtimeConfiguration
                                            .value['settings']?['maintenance'] ==
                                        true)
                                      Notice(
                                        runtimeConfiguration
                                                .value['settings']['maintenance_message'] ??
                                            'Техническое обслуживание',
                                      ),
                                    if (contentText(
                                      'rules.notice',
                                      '',
                                    ).isNotEmpty)
                                      Notice(contentText('rules.notice', '')),
                                    if ((runtimeConfiguration
                                                .value['branding']?['banner'] ??
                                            '')
                                        .toString()
                                        .isNotEmpty)
                                      Notice(
                                        runtimeConfiguration
                                            .value['branding']['banner'],
                                      ),
                                    if (reference['showcase'] == true)
                                      const Notice(
                                        'Витринный сценарий · синтетическая история игровых дней',
                                      ),
                                    if (error.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: Notice(error, error: true),
                                      ),
                                    if (error.isNotEmpty)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton(
                                          onPressed: reload,
                                          child: const Text('Обновить данные'),
                                        ),
                                      ),
                                    if (!hr) employeePageGuide(),
                                    if (data.isNotEmpty || !loading)
                                      hr ? hrView() : careerView(),
                                    const SizedBox(height: 30),
                                  ],
                                ),
                              ),
                            ),
                          ),
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
      bottomNavigationBar: wide
          ? null
          : Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D152D),
                border: Border(
                  top: BorderSide(color: line.withValues(alpha: .7)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .28),
                    blurRadius: 24,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: NavigationBar(
                height: 72,
                elevation: 0,
                backgroundColor: Colors.transparent,
                indicatorColor: pink.withValues(alpha: .13),
                selectedIndex: bottomIndex(),
                onDestinationSelected: (i) {
                  if (i == 4) {
                    showMore(links);
                  } else {
                    go(
                      (hr
                          ? ['overview', 'gamification', 'reviews', 'rewards']
                          : ['home', 'plan', 'season', 'shop'])[i],
                    );
                  }
                },
                destinations: [
                  for (final entry
                      in hr
                          ? [
                              ('Сводка', Icons.dashboard_rounded),
                              ('Сезон', Icons.emoji_events_rounded),
                              ('Проверки', Icons.fact_check_rounded),
                              ('Награды', Icons.redeem_rounded),
                              ('Ещё', Icons.grid_view_rounded),
                            ]
                          : [
                              ('Главная', Icons.explore_rounded),
                              ('Маршрут', Icons.route_rounded),
                              ('Карьерный пропуск', Icons.emoji_events_rounded),
                              ('Награды', Icons.shopping_bag_rounded),
                              ('Ещё', Icons.grid_view_rounded),
                            ])
                    NavigationDestination(
                      icon: Icon(entry.$2),
                      label: entry.$1,
                    ),
                ],
              ),
            ),
    );
  }

  int bottomIndex() {
    final i =
        (hr
                ? ['overview', 'gamification', 'reviews', 'rewards']
                : ['home', 'plan', 'season', 'shop'])
            .indexOf(page);
    return i < 0 ? 4 : i;
  }
}
