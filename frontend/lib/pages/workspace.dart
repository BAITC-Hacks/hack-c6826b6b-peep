import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../core/api.dart';
import '../widgets/ui.dart';
import 'login.dart';

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
      'plan_full': 'В плане уже три шага',
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
      seasonTab = 'tasks';
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
  bool loading = false, busy = false;
  Set<String> simulationIds = {};
  Json? simulation;
  String? simulationRole, simulationGrade;
  Map<String, String> hrFilters = {};
  bool get hr => user?['role'] == 'hr';
  String get root => hr ? 'hr' : 'employee';
  String get title => titles[page.split('/').first] ?? 'Подробности';
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
          'home': 'Мой путь',
          'plan': 'Мой план',
          'season': 'Карьерный пропуск',
          'shop': 'Магазин наград',
          'catalog': 'Каталог',
          'history': 'История развития',
          'profile': 'Мой профиль',
          'goal': 'Карьерная цель',
          'skills': 'Навыки',
          'simulator': 'Что если',
          'passport': 'Паспорт развития',
          'wallet': 'Кошелёк',
          'rewards': 'Мои подарки',
          'activities': 'Активность',
          'assistant': 'Карьерный помощник',
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
    final version = ++generation;
    setState(() {
      loading = true;
      error = '';
    });
    try {
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
        return {};
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
      seasonTab = 'tasks';
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
        children: [if (title.isNotEmpty) heading(title, subtitle), child],
      ),
    ),
  );
  Widget actions(List<Widget> children) =>
      Wrap(spacing: 10, runSpacing: 10, children: children);
  Widget empty(String text) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(text, style: const TextStyle(color: muted, height: 1.7)),
  );
  Widget metric(String name, String val, {Color accent = pink}) => Container(
    width: 190,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: panelRaised,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return LoginPage(
        api: api,
        message: loginMessage.isEmpty ? null : loginMessage,
        onLogin: (u) {
          setState(() {
            user = u;
            loginMessage = '';
          });
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
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final links = titles.entries
        .where((e) => hr || !['goal', 'skills', 'activities'].contains(e.key))
        .toList();
    Widget navigation() => ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Brand(),
        const SizedBox(height: 24),
        for (final e in links)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              selected: page.split('/').first == e.key,
              selectedTileColor: panelRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(e.value, style: const TextStyle(fontSize: 13)),
              onTap: () {
                if (!wide) Navigator.pop(context);
                go(e.key);
              },
            ),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Выйти'),
          onTap: logout,
        ),
      ],
    );
    return Scaffold(
      drawer: wide
          ? null
          : Drawer(
              backgroundColor: night,
              child: SafeArea(child: navigation()),
            ),
      body: QuestBackdrop(
        child: SafeArea(
          child: Row(
            children: [
              if (wide) SizedBox(width: 238, child: navigation()),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
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
                          Expanded(
                            child: Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (!hr && home['gamification'] != null)
                            TextButton(
                              onPressed: () => go('wallet'),
                              child: Text(
                                '${home['gamification']['wallet_balance']} CQ',
                                style: const TextStyle(
                                  color: Color(0xFFF2D28C),
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Обновить',
                            onPressed: loading ? null : reload,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ),
                    if (loading) const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: SingleChildScrollView(
                        key: ValueKey(page),
                        padding: EdgeInsets.all(wide ? 28 : 16),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (reference['showcase'] == true)
                                  const Notice(
                                    'Витринный сценарий · синтетическая история игровых дней',
                                  ),
                                if (error.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
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
                                if (data.isNotEmpty || !loading)
                                  hr ? hrView() : careerView(),
                                const SizedBox(height: 30),
                              ],
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
          : NavigationBar(
              selectedIndex: bottomIndex(),
              onDestinationSelected: (i) {
                if (i == 4) {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: ListView(
                        children: [
                          for (final e in links)
                            ListTile(
                              title: Text(e.value),
                              onTap: () {
                                Navigator.pop(ctx);
                                go(e.key);
                              },
                            ),
                        ],
                      ),
                    ),
                  );
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
                            ('Сводка', Icons.dashboard_outlined),
                            ('Сезон', Icons.emoji_events_outlined),
                            ('Проверки', Icons.fact_check_outlined),
                            ('Награды', Icons.redeem),
                            ('Ещё', Icons.more_horiz),
                          ]
                        : [
                            ('Путь', Icons.explore_outlined),
                            ('План', Icons.route_outlined),
                            ('Сезон', Icons.emoji_events_outlined),
                            ('Магазин', Icons.shopping_bag_outlined),
                            ('Ещё', Icons.more_horiz),
                          ])
                  NavigationDestination(icon: Icon(entry.$2), label: entry.$1),
              ],
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
