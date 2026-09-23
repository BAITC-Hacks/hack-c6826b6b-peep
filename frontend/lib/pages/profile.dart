import 'package:flutter/material.dart';

import '../core/api.dart';
import '../widgets/ui.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.api,
    this.employeeId,
    this.historyOnly = false,
    this.onBack,
  });
  final CareerApi api;
  final String? employeeId;
  final bool historyOnly;
  final VoidCallback? onBack;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Json? profile;
  String? error;
  bool busy = true;
  bool showAllSkills = false;
  bool showAllHistory = false;
  String historyFilter = 'all';
  bool get isOwn => widget.employeeId == null;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.get(
        isOwn
            ? '/api/me/profile'
            : '/api/employees/${Uri.encodeComponent(widget.employeeId!)}',
      );
      if (mounted) setState(() => profile = data);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    if (busy && profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && profile == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Notice(
          error!,
          error: true,
          action: TextButton(onPressed: load, child: const Text('Повторить')),
        ),
      );
    }
    if (profile == null) return const SizedBox();
    final employee = Json.from(profile!['employee']);
    return SingleChildScrollView(
      padding: EdgeInsets.all(wide ? 36 : 20),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1250),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.onBack != null) ...[
                TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Все сотрудники'),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.historyOnly
                          ? 'История развития'
                          : isOwn
                          ? 'Мой профиль'
                          : 'Профиль сотрудника',
                      style: TextStyle(
                        fontSize: wide ? 32 : 27,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.9,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Обновить профиль',
                    onPressed: busy ? null : load,
                    icon: const Icon(Icons.refresh_rounded, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.historyOnly
                    ? 'Весь ваш опыт — от первого обучения до последней активности.'
                    : 'Где вы сейчас и куда хотите двигаться дальше.',
                style: const TextStyle(color: muted, fontSize: 14),
              ),
              const SizedBox(height: 28),
              if (error != null) ...[
                Notice(error!, error: true),
                const SizedBox(height: 18),
              ],
              if (!widget.historyOnly) ...[
                _identity(employee),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, box) {
                    if (box.maxWidth < 790) {
                      return Column(
                        children: [
                          _goal(employee),
                          const SizedBox(height: 20),
                          _details(employee),
                        ],
                      );
                    }
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 6, child: _goal(employee)),
                          const SizedBox(width: 20),
                          Expanded(flex: 4, child: _details(employee)),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 30),
                _skills(),
                const SizedBox(height: 30),
              ],
              _history(),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _identity(Json employee) => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF202C50), Color(0xFF18203D), Color(0xFF352341)],
      ),
      border: Border.all(color: const Color(0xFF4B4870)),
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color(0x2317194D),
          blurRadius: 28,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFB1DF), Color(0xFF7F73D8)],
                ),
                border: Border.all(color: const Color(0xFFC9B6FF)),
                borderRadius: BorderRadius.circular(23),
                boxShadow: const [
                  BoxShadow(color: Color(0x35B56BDC), blurRadius: 22),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                initials(value(employee['full_name'])),
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF231B47),
                ),
              ),
            ),
            const SizedBox(width: 19),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value(employee['full_name']),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: ink,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${value(employee['role'])} · ${value(employee['grade'])}',
                    style: const TextStyle(fontSize: 13, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            Tag(
              value(employee['department']),
              icon: Icons.business_outlined,
              color: muted,
              background: paper,
            ),
            Tag(
              _workFormat(employee['work_format']),
              icon: Icons.work_outline,
              color: muted,
              background: paper,
            ),
            Tag(
              'В команде с ${dateLabel(employee['hire_date'])}',
              icon: Icons.calendar_today_outlined,
              color: muted,
              background: paper,
            ),
          ],
        ),
      ],
    ),
  );

  String _workFormat(dynamic format) =>
      {'office': 'В офисе', 'remote': 'Удалённо', 'hybrid': 'Гибрид'}[format] ??
      value(format);

  Widget _goal(Json employee) {
    final suggested = profile!['goal_source'] == 'suggested';
    final rawGoal = profile!['goal'] ?? profile!['suggested_goal'];
    final goal = rawGoal == null ? null : Json.from(rawGoal);
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF19284D), Color(0xFF272048), Color(0xFF472C51)],
        ),
        border: Border.all(color: const Color(0xFF55528D)),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x192F63F0), blurRadius: 28)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: green, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  suggested ? 'ВОЗМОЖНОЕ НАПРАВЛЕНИЕ' : 'КАРЬЕРНАЯ ЦЕЛЬ',
                  style: const TextStyle(
                    color: Color(0xFFD4BBE9),
                    letterSpacing: 1.5,
                    fontSize: 10,
                  ),
                ),
              ),
              if (isOwn)
                IconButton(
                  tooltip: 'Изменить карьерную цель',
                  onPressed: _editGoal,
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 21),
          if (goal != null) ...[
            Text(
              value(goal['target_role']),
              style: const TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.w600,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 13),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 13,
              runSpacing: 8,
              children: [
                Text(
                  value(employee['grade']),
                  style: const TextStyle(
                    color: Color(0xFFB9BCD9),
                    fontSize: 15,
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: lime, size: 20),
                Tag(
                  value(goal['target_grade']),
                  color: const Color(0xFF231B47),
                  background: green,
                ),
              ],
            ),
          ] else
            const Text(
              'Куда вы хотите расти?',
              style: TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 24),
          Text(
            suggested
                ? 'Цель пока не выбрана. Следующий грейд — наше предложение; подтвердите его или выберите своё направление.'
                : goal == null
                ? 'Выберите роль и грейд, чтобы сравнить свои навыки с требованиями.'
                : profile!['goal_source'] == 'personal'
                ? 'Вы выбрали эту цель. Требования к роли помогут увидеть, на какие навыки обратить внимание.'
                : 'Цель из вашего профиля. Её можно изменить, если ваши планы поменялись.',
            style: const TextStyle(
              color: Color(0xFFCED0E9),
              fontSize: 12,
              height: 1.7,
            ),
          ),
          if (isOwn) ...[
            const SizedBox(height: 20),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: lime,
                padding: EdgeInsets.zero,
              ),
              onPressed: _editGoal,
              icon: const Icon(Icons.north_east, size: 17),
              label: Text(
                suggested || goal == null
                    ? 'Выбрать цель'
                    : 'Настроить направление',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _details(Json employee) {
    final stats = Json.from(profile!['stats']);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ваш опыт в цифрах',
            style: TextStyle(
              color: ink,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _stat(value(stats['completed'], '0'), 'Завершено', green),
              _stat(
                value(stats['in_progress'], '0'),
                'В процессе',
                const Color(0xFF78CCF1),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 14),
          _detail('Всего записей истории', value(stats['total'], '0')),
          const SizedBox(height: 12),
          _detail(
            'Обязательных не завершено',
            value(stats['mandatory_pending'], '0'),
          ),
          const SizedBox(height: 12),
          _detail('Последняя оценка', dateLabel(employee['last_review_date'])),
        ],
      ),
    );
  }

  Widget _stat(String count, String title, Color color) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count,
          style: TextStyle(
            color: color,
            fontSize: 35,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(title, style: const TextStyle(color: muted, fontSize: 12)),
      ],
    ),
  );
  Widget _detail(String label, String text) => Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      ),
      const SizedBox(width: 8),
      Text(
        text,
        style: const TextStyle(
          color: ink,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    ],
  );

  Widget _skills() {
    final all = records(profile!['skills']);
    final shown = showAllSkills ? all : all.take(6).toList();
    final isSuggested = profile!['goal_source'] == 'suggested';
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Карта навыков',
            subtitle: 'Уровни из последней оценки · шкала от 0 до 5',
            action: Tag(
              '${all.length} навыков',
              color: muted,
              background: paper,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              const _Legend('Оценённый уровень', green),
              _Legend(
                isSuggested
                    ? 'Требование предложенной роли'
                    : 'Требование целевой роли',
                const Color(0xFF59668F),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (all.isEmpty)
            const EmptyState(
              'Навыки пока не добавлены',
              'Они появятся после загрузки профиля.',
            ),
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 650 ? 2 : 1;
              final width = (box.maxWidth - (columns - 1) * 30) / columns;
              return Wrap(
                spacing: 30,
                runSpacing: 24,
                children: [
                  for (final skill in shown)
                    SizedBox(width: width, child: _skill(skill)),
                ],
              );
            },
          ),
          if (all.length > 6) ...[
            const SizedBox(height: 22),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => showAllSkills = !showAllSkills),
                icon: Icon(
                  showAllSkills ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(showAllSkills ? 'Свернуть' : 'Показать все навыки'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Завершение обучения само по себе не меняет эти оценки. Здесь показаны подтверждённые исходные уровни.',
            style: TextStyle(color: muted, height: 1.5, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _skill(Json skill) {
    final assessed = (skill['assessed_level'] as num? ?? 0).toInt();
    final required = (skill['required_level'] as num?)?.toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                value(skill['name']),
                style: const TextStyle(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (skill['critical'] == true)
              const Tooltip(
                message: 'Ключевой навык целевой роли',
                child: Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.star_outline,
                    color: Color(0xFFF0B6EA),
                    size: 15,
                  ),
                ),
              ),
            Text(
              '$assessed / 5',
              style: const TextStyle(
                color: green,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              Expanded(
                child: Container(
                  height: 7,
                  margin: EdgeInsets.only(right: i < 5 ? 5 : 0),
                  decoration: BoxDecoration(
                    color: i <= assessed
                        ? null
                        : (required != null && i <= required
                              ? const Color(0xFF59668F)
                              : paper),
                    gradient: i <= assessed
                        ? const LinearGradient(
                            colors: [Color(0xFF9B84FF), Color(0xFFF392D5)],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: i <= assessed
                        ? const [
                            BoxShadow(color: Color(0x229B84FF), blurRadius: 8),
                          ]
                        : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          required == null
              ? 'Не входит в требования выбранной роли'
              : 'Для роли требуется: $required / 5',
          style: const TextStyle(color: muted, fontSize: 10),
        ),
      ],
    );
  }

  Widget _history() {
    final all = records(profile!['history']);
    final filtered = all
        .where(
          (record) =>
              historyFilter == 'all' || record['status'] == historyFilter,
        )
        .toList();
    final shown = widget.historyOnly || showAllHistory
        ? filtered
        : filtered.take(5).toList();
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'История активностей',
            subtitle: 'Обучение, мероприятия и другие шаги развития',
            action: Tag(
              '${all.length} записей',
              color: muted,
              background: paper,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in {
                'all': 'Все',
                'completed': 'Завершены',
                'in_progress': 'В процессе',
                'overdue': 'Просрочены',
              }.entries)
                ChoiceChip(
                  label: Text(
                    option.value,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: historyFilter == option.key,
                  onSelected: (_) => setState(() => historyFilter = option.key),
                  showCheckmark: false,
                  side: const BorderSide(color: line),
                  selectedColor: mint,
                  backgroundColor: paper,
                  labelStyle: TextStyle(
                    color: historyFilter == option.key ? green : muted,
                    fontWeight: historyFilter == option.key
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (shown.isEmpty)
            const EmptyState(
              'Пока нет активностей',
              'Записи появятся здесь после загрузки истории.',
            ),
          for (var i = 0; i < shown.length; i++) ...[
            _activity(shown[i]),
            if (i < shown.length - 1) const Divider(height: 1),
          ],
          if (!widget.historyOnly && filtered.length > 5) ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () =>
                    setState(() => showAllHistory = !showAllHistory),
                child: Text(
                  showAllHistory ? 'Свернуть историю' : 'Показать всю историю',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _activity(Json entry) {
    final complete = entry['status'] == 'completed';
    final status =
        {
          'completed': 'Завершено',
          'in_progress': 'В процессе',
          'no_show': 'Не посетил(а)',
          'overdue': 'Просрочено',
          'assigned': 'Назначено',
          'declined': 'Отклонено',
          'dropped': 'Прервано',
          'not_started': 'Не начато',
        }[entry['status']] ??
        value(entry['status']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: complete ? mint : paper,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              complete ? Icons.check_rounded : Icons.school_outlined,
              color: complete ? green : muted,
              size: 19,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value(entry['title'], value(entry['event_id'])),
                  style: const TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      dateLabel(entry['date']),
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    Tag(
                      status,
                      background: complete ? mint : paper,
                      color: complete ? green : muted,
                    ),
                    if (entry['mandatory'] == true)
                      const Text(
                        'Обязательное',
                        style: TextStyle(
                          color: Color(0xFFD5BBF4),
                          fontSize: 11,
                        ),
                      ),
                    if (entry['score'] != null && value(entry['score']) != '—')
                      Text(
                        'Результат: ${entry['score']}',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editGoal() async {
    final result = await showDialog<Json>(
      context: context,
      builder: (context) => GoalDialog(api: widget.api, profile: profile!),
    );
    if (result != null && mounted) setState(() => profile = result);
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.title, this.color);
  final String title;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(title, style: const TextStyle(fontSize: 10, color: muted)),
      ),
    ],
  );
}

class GoalDialog extends StatefulWidget {
  const GoalDialog({super.key, required this.api, required this.profile});
  final CareerApi api;
  final Json profile;
  @override
  State<GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<GoalDialog> {
  List<Json>? roles;
  String? selected;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final meta = await widget.api.get('/api/meta');
      if (!mounted) return;
      final options = records(meta['roles']);
      const gradeOrder = {'Junior': 0, 'Middle': 1, 'Senior': 2, 'Lead': 3};
      options.sort((a, b) {
        final roleCompare = value(a['role']).compareTo(value(b['role']));
        if (roleCompare != 0) return roleCompare;
        return (gradeOrder[a['grade']] ?? 99).compareTo(
          gradeOrder[b['grade']] ?? 99,
        );
      });
      final goal = widget.profile['goal'] ?? widget.profile['suggested_goal'];
      final key = goal == null
          ? null
          : '${goal['target_role']}|${goal['target_grade']}';
      setState(() {
        roles = options;
        selected = options.any((e) => '${e['role']}|${e['grade']}' == key)
            ? key
            : null;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> save({bool reset = false}) async {
    if (!reset && selected == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final target = reset
          ? null
          : roles!.firstWhere((e) => '${e['role']}|${e['grade']}' == selected);
      final result = await widget.api.request(
        reset ? 'DELETE' : 'PUT',
        '/api/me/goal',
        reset
            ? null
            : {'target_role': target!['role'], 'target_grade': target['grade']},
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Ваше направление'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Выберите роль и грейд, к которым хотите прийти. Цель можно изменить в любой момент.',
            style: TextStyle(color: muted, height: 1.6, fontSize: 13),
          ),
          const SizedBox(height: 23),
          if (error != null) ...[
            Notice(error!, error: true),
            const SizedBox(height: 14),
          ],
          if (roles == null && error == null) const LinearProgressIndicator(),
          if (roles == null && error != null)
            TextButton(onPressed: load, child: const Text('Повторить')),
          if (roles != null)
            DropdownButtonFormField<String>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Целевая роль и грейд',
              ),
              items: roles!
                  .map(
                    (e) => DropdownMenuItem(
                      value: '${e['role']}|${e['grade']}',
                      child: Text(
                        '${e['role']} · ${e['grade']}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: busy ? null : (key) => setState(() => selected = key),
            ),
          if (widget.profile['goal_source'] == 'personal') ...[
            const SizedBox(height: 18),
            TextButton(
              onPressed: busy ? null : () => save(reset: true),
              child: const Text('Вернуть цель из исходного профиля'),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: busy || selected == null ? null : save,
        child: Text(busy ? 'Сохраняем…' : 'Сохранить цель'),
      ),
    ],
  );
}
