import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../widgets/landing_sections.dart';
import '../widgets/ui.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.api,
    required this.onLogin,
    this.message,
  });
  final CareerApi api;
  final ValueChanged<Json> onLogin;
  final String? message;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool obscure = true;
  String? error;
  String selected = '';
  final _topKey = GlobalKey();
  final _loginKey = GlobalKey();
  final _benefitsKey = GlobalKey();
  final _stepsKey = GlobalKey();
  final _faqKey = GlobalKey();

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
      alignment: .04,
    );
  }

  void _selectDemo(String login) {
    if (busy) return;
    setState(() {
      selected = login;
      username.text = login;
      password.clear();
      error = null;
    });
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (username.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Выберите профиль и введите пароль.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final user = await widget.api.login(username.text.trim(), password.text);
      if (mounted) widget.onLogin(user);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: QuestBackdrop(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 1050;
            final inset = box.maxWidth < 500 ? 16.0 : 30.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(inset, 20, inset, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1380),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KeyedSubtree(key: _topKey, child: _header(wide)),
                      const SizedBox(height: 24),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 7, child: _hero(true)),
                            const SizedBox(width: 26),
                            Expanded(
                              flex: 5,
                              child: KeyedSubtree(
                                key: _loginKey,
                                child: _form(true),
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _hero(false),
                        const SizedBox(height: 20),
                        KeyedSubtree(key: _loginKey, child: _form(false)),
                      ],
                      LandingSections(
                        benefitsKey: _benefitsKey,
                        stepsKey: _stepsKey,
                        faqKey: _faqKey,
                        onStart: () => _scrollTo(_loginKey),
                        onBenefits: () => _scrollTo(_benefitsKey),
                        onSteps: () => _scrollTo(_stepsKey),
                        onFaq: () => _scrollTo(_faqKey),
                        onTop: () => _scrollTo(_topKey),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _header(bool wide) => Container(
    constraints: const BoxConstraints(minHeight: 68),
    padding: EdgeInsets.fromLTRB(wide ? 4 : 2, 8, wide ? 4 : 2, 14),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: line.withValues(alpha: .65))),
    ),
    child: Row(
      children: [
        const Expanded(child: Brand(light: true)),
        if (wide) ...[_navigation(), const SizedBox(width: 22)],
        FilledButton(
          onPressed: () => _scrollTo(_loginKey),
          style: FilledButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
            minimumSize: const Size(0, 42),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Вход'),
        ),
      ],
    ),
  );

  Widget _navigation() => Wrap(
    alignment: WrapAlignment.center,
    spacing: 2,
    children: [
      _navButton('Возможности', onPressed: () => _scrollTo(_benefitsKey)),
      _navButton('Как работает', onPressed: () => _scrollTo(_stepsKey)),
      _navButton('Вопросы', onPressed: () => _scrollTo(_faqKey)),
    ],
  );

  Widget _navButton(String label, {required VoidCallback onPressed}) =>
      TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: muted,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );

  Widget _hero(bool wide) => ClipRRect(
    borderRadius: BorderRadius.circular(30),
    child: SizedBox(
      height:
          (wide ? 718.0 : 360.0) *
          (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(
            1.0,
            double.infinity,
          ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF182757), Color(0xFF30204D), paper],
              ),
            ),
          ),
          Image.asset(
            'assets/images/career_landscape.png',
            fit: BoxFit.cover,
            alignment: wide ? Alignment.center : const Alignment(.2, -.25),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .5, 1],
                colors: [
                  paper.withValues(alpha: .55),
                  paper.withValues(alpha: .08),
                  paper.withValues(alpha: .94),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [paper.withValues(alpha: .58), Colors.transparent],
                stops: const [0, .85],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(wide ? 38 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Career ',
                        style: TextStyle(color: pink),
                      ),
                      const TextSpan(text: 'Quest'),
                    ],
                  ),
                  style: TextStyle(
                    color: ink,
                    fontSize: wide
                        ? 54
                        : (MediaQuery.sizeOf(context).width < 360 ? 30 : 36),
                    letterSpacing: wide ? -2 : -1.2,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 15),
                _TypewriterHeadline(
                  wide: wide,
                  animate: !busy && error == null,
                ),
                if (wide) ...[
                  const SizedBox(height: 23),
                  const SizedBox(
                    width: 350,
                    child: Text(
                      'Соедини навыки, опыт и карьерную цель. '
                      'У каждого большого пути есть свой первый шаг.',
                      style: TextStyle(
                        color: Color(0xFFD7DCF2),
                        fontSize: 15,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (wide)
                  _journey()
                else
                  const Text(
                    'Навыки, опыт и карьерная цель —\nв одном пространстве развития.',
                    style: TextStyle(color: ink, height: 1.6, fontSize: 12),
                  ),
              ],
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: blue.withValues(alpha: .45)),
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _form(bool wide) => Surface(
    padding: wide ? 32 : 22,
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuestMark(size: 52),
          const SizedBox(height: 23),
          const Text(
            'Рады видеть вас',
            style: TextStyle(
              fontSize: 28,
              color: ink,
              fontWeight: FontWeight.w800,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Войдите в своё пространство развития.',
            style: TextStyle(fontSize: 13, height: 1.6, color: muted),
          ),
          const SizedBox(height: 28),
          if (widget.message != null) ...[
            Notice(widget.message!),
            const SizedBox(height: 18),
          ],
          if (error != null) ...[
            Notice(error!, error: true),
            const SizedBox(height: 18),
          ],
          TextField(
            key: const Key('login-username'),
            controller: username,
            enabled: !busy,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(
              labelText: 'Логин',
              prefixIcon: Icon(Icons.person_outline, size: 20),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('login-password'),
            controller: password,
            enabled: !busy,
            obscureText: obscure,
            onSubmitted: (_) => submit(),
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Пароль',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              suffixIcon: IconButton(
                tooltip: obscure ? 'Показать пароль' : 'Скрыть пароль',
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: pink.withValues(alpha: .2),
                  blurRadius: 25,
                  spreadRadius: -3,
                ),
              ],
            ),
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : submit,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Text('Войти'),
                  const SizedBox(width: 12),
                  if (!busy) const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'ВЫБЕРИТЕ ПРОФИЛЬ',
                  style: TextStyle(
                    color: muted,
                    fontSize: 9,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _demo(
                  'Сотрудник',
                  'Мой профиль и цель',
                  Icons.person_outline,
                  'employee.demo',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _demo(
                  'HR',
                  'Команда и развитие',
                  Icons.groups_outlined,
                  'hr.demo',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: busy ? null : () => _selectDemo('colleague.demo'),
            child: const Text('Другой сотрудник · colleague.demo'),
          ),
          const SizedBox(height: 17),
          const Text(
            'Тестовые профили с синтетическими данными. Выбор заполнит логин. Введите пароль из настроек сервера.',
            style: TextStyle(color: muted, fontSize: 11, height: 1.7),
          ),
        ],
      ),
    ),
  );

  Widget _demo(
    String title,
    String subtitle,
    IconData icon,
    String login,
  ) => Material(
    color: selected == login
        ? const Color(0xFF312747)
        : const Color(0xFF17213B),
    shape: RoundedRectangleBorder(
      side: BorderSide(color: selected == login ? pink : line),
      borderRadius: BorderRadius.circular(18),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: busy ? null : () => _selectDemo(login),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected == login ? pink : blue, size: 23),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: muted, fontSize: 10, height: 1.5),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _journey() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xE619284A), Color(0xDD272043)],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: violet.withValues(alpha: .45)),
    ),
    child: Row(
      children: [
        Expanded(child: _node(Icons.fingerprint, 'Твой профиль', blue)),
        const Icon(
          Icons.arrow_forward_rounded,
          color: Color(0xFFD7DCF2),
          size: 30,
        ),
        Expanded(child: _node(Icons.auto_graph, 'Твои навыки', violet)),
        const Icon(
          Icons.arrow_forward_rounded,
          color: Color(0xFFD7DCF2),
          size: 30,
        ),
        Expanded(child: _node(Icons.flag_outlined, 'Твоя цель', pink)),
      ],
    ),
  );

  Widget _node(IconData icon, String label, Color accent) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: accent.withValues(alpha: .28)),
        ),
        child: Icon(icon, color: accent, size: 21),
      ),
      const SizedBox(height: 10),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: ink, fontSize: 11),
      ),
    ],
  );
}

class _TypewriterHeadline extends StatefulWidget {
  const _TypewriterHeadline({required this.wide, required this.animate});
  final bool wide;
  final bool animate;

  @override
  State<_TypewriterHeadline> createState() => _TypewriterHeadlineState();
}

class _TypewriterHeadlineState extends State<_TypewriterHeadline> {
  static const phrases = [
    'больше, чем работа.',
    'рост в своём ритме.',
    'маршрут к новой роли.',
    'цель, к которой идёшь.',
  ];

  Timer? timer;
  int phrase = 0;
  int characters = 0;
  bool deleting = false;
  bool reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (disabled == reduceMotion && timer != null) return;
    reduceMotion = disabled;
    timer?.cancel();
    if (reduceMotion || !widget.animate) {
      characters = phrases[phrase].length;
    } else {
      timer = Timer(const Duration(milliseconds: 420), tick);
    }
  }

  @override
  void didUpdateWidget(covariant _TypewriterHeadline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate == widget.animate || reduceMotion) return;
    timer?.cancel();
    if (widget.animate) {
      timer = Timer(const Duration(milliseconds: 420), tick);
    } else {
      characters = phrases[phrase].length;
      deleting = false;
    }
  }

  void tick() {
    if (!mounted || reduceMotion || !widget.animate) return;
    final current = phrases[phrase];
    var delay = 72;

    setState(() {
      if (!deleting && characters < current.length) {
        characters += 1;
      } else if (!deleting) {
        deleting = true;
        delay = 1450;
      } else if (deleting && characters > 0) {
        characters -= 1;
        delay = 34;
      } else if (deleting) {
        deleting = false;
        phrase = (phrase + 1) % phrases.length;
        delay = 260;
      }
    });
    timer = Timer(Duration(milliseconds: delay), tick);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = phrases[phrase];
    final visible = current.substring(0, characters.clamp(0, current.length));
    final style = TextStyle(
      color: ink,
      fontSize: widget.wide ? 32 : 24,
      letterSpacing: -.7,
      height: 1.25,
      fontWeight: FontWeight.w700,
    );

    return Semantics(
      label: 'Твой путь — это $current',
      child: ExcludeSemantics(
        child: SizedBox(
          height: widget.wide ? 82 : 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Твой путь — это', style: style),
              Row(
                children: [
                  Flexible(child: Text(visible, style: style)),
                  if (!reduceMotion && widget.animate) ...[
                    const SizedBox(width: 3),
                    Text('▍', style: style.copyWith(color: pink)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
