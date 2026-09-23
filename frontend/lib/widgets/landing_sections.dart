import 'package:flutter/material.dart';

import 'ui.dart';

/// Public landing content. Describes only the scenarios available in the app.
class LandingSections extends StatelessWidget {
  const LandingSections({
    super.key,
    required this.benefitsKey,
    required this.stepsKey,
    required this.faqKey,
    required this.onStart,
    required this.onBenefits,
    required this.onSteps,
    required this.onFaq,
    required this.onTop,
  });

  final GlobalKey benefitsKey;
  final GlobalKey stepsKey;
  final GlobalKey faqKey;
  final VoidCallback onStart, onBenefits, onSteps, onFaq, onTop;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 850;
      final space = wide ? 88.0 : 56.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: space),
          _ScrollReveal(
            child: Column(
              key: benefitsKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Heading(
                  eyebrow: 'БОЛЬШЕ ЯСНОСТИ. БОЛЬШЕ ВОЗМОЖНОСТЕЙ.',
                  title: 'Карьера складывается\nв понятную картину',
                  description:
                      'Когда профиль, опыт и цель рядом, проще понять, '
                      'где ты сейчас и чему уделить внимание дальше.',
                ),
                const SizedBox(height: 30),
                _Columns(
                  columns: wide ? 2 : 1,
                  children: const [
                    _Benefit(
                      number: '01',
                      icon: Icons.person_outline_rounded,
                      accent: blue,
                      title: 'Твоя отправная точка',
                      description:
                          'Роль, грейд и последние оценки навыков — в одном '
                          'профиле. Начинай разговор о развитии с того, что уже умеешь.',
                      tag: 'ПРОФИЛЬ И НАВЫКИ',
                    ),
                    _Benefit(
                      number: '02',
                      icon: Icons.explore_outlined,
                      accent: pink,
                      title: 'Цель, которую выбираешь ты',
                      description:
                          'Сохрани желаемую роль и грейд. Сопоставь свои '
                          'навыки с требованиями цели и увидь, что ещё нужно развить.',
                      tag: 'ЛИЧНОЕ НАПРАВЛЕНИЕ',
                    ),
                    _Benefit(
                      number: '03',
                      icon: Icons.history_rounded,
                      accent: violet,
                      title: 'Опыт, который не теряется',
                      description:
                          'Обучение, аттестации и другие активности собраны '
                          'в истории. Возвращайся к результатам без поиска по уведомлениям.',
                      tag: 'ИСТОРИЯ РАЗВИТИЯ',
                    ),
                    _Benefit(
                      number: '04',
                      icon: Icons.groups_outlined,
                      accent: cyan,
                      title: 'Общий контекст для HR',
                      description:
                          'Каталог сотрудников, их цели и история помогают '
                          'подготовиться к разговору о карьере. HR видит дефициты навыков '
                          'и проверяет результаты выполненных заданий.',
                      tag: 'РАБОТА С КОМАНДОЙ',
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: space),
          _ScrollReveal(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Heading(
                  eyebrow: 'ПРИМЕР ПРОГРЕССА',
                  title: 'Видно не только цель,\nно и расстояние до неё',
                  description:
                      'Сравнение с требованиями роли показывает сильные стороны '
                      'и навыки, которым стоит уделить внимание.',
                ),
                const SizedBox(height: 30),
                _ProgressPreview(wide: wide),
              ],
            ),
          ),
          SizedBox(height: space),
          _ScrollReveal(
            child: Container(
              key: stepsKey,
              padding: EdgeInsets.all(wide ? 36 : 22),
              decoration: _decoration(tinted: true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Heading(
                    eyebrow: 'ОТ ЗНАКОМСТВА С СОБОЙ — К СЛЕДУЮЩЕМУ ШАГУ',
                    title: 'Большой путь начинается просто',
                    description: 'Три шага, чтобы сделать развитие осознанным.',
                  ),
                  const SizedBox(height: 32),
                  _Columns(
                    columns: wide ? 3 : 1,
                    children: const [
                      _Step(
                        number: '01',
                        title: 'Открой свой профиль',
                        description:
                            'Посмотри текущую роль, навыки и историю '
                            'активностей. Это твоя точка старта.',
                        accent: blue,
                      ),
                      _Step(
                        number: '02',
                        title: 'Выбери направление',
                        description:
                            'Укажи роль и грейд, к которым хочешь прийти. '
                            'Цель можно изменить в своём профиле.',
                        accent: violet,
                      ),
                      _Step(
                        number: '03',
                        title: 'Увидь, что развивать',
                        description:
                            'Сравни последние оценки с требованиями цели. '
                            'Обсуди следующий шаг с руководителем или HR.',
                        accent: pink,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: space),
          _ScrollReveal(
            child: KeyedSubtree(key: faqKey, child: _faq(wide)),
          ),
          SizedBox(height: space),
          _ScrollReveal(child: _footer(wide)),
        ],
      );
    },
  );

  Widget _faq(bool wide) {
    const intro = _Heading(
      eyebrow: 'FAQ',
      title: 'Есть вопросы?\nДавай разберёмся.',
      description: 'Всё основное о профиле, карьерной цели и работе с данными.',
    );
    const questions = Column(
      children: [
        _Question(
          question: 'Для кого создан Career Quest?',
          answer:
              'Для сотрудников, которым важно видеть свой опыт и карьерную '
              'цель в одном месте, и для HR, которые помогают команде развиваться. '
              'У каждой роли своё рабочее пространство.',
        ),
        _Question(
          question: 'Что делать, если у меня пока нет цели?',
          answer:
              'Если для твоей роли есть следующий грейд, он появится как '
              'возможное направление. Это только предложение: цель станет твоей '
              'после того, как ты её выберешь и сохранишь.',
        ),
        _Question(
          question: 'Выбор цели гарантирует повышение?',
          answer:
              'Нет. Цель помогает сопоставить навыки с требованиями роли '
              'и подготовиться к обсуждению развития. Решение о повышении '
              'принимается отдельно, вместе с руководителем и HR.',
        ),
        _Question(
          question: 'Как обновляются мои навыки?',
          answer:
              'В профиле показаны значения последней оценки из загруженных '
              'данных. Завершённое обучение отображается в истории, но само '
              'по себе не меняет оценку навыка.',
        ),
        _Question(
          question: 'Кто может видеть мой профиль?',
          answer:
              'Сотрудник видит свой профиль и историю. HR имеет доступ '
              'к каталогу сотрудников и их профилям. Сервер проверяет права '
              'доступа при каждом запросе.',
        ),
        _Question(
          question: 'Чем XP отличается от оценки навыка?',
          answer:
              'XP отражает участие в сезоне: ежедневные задания и результаты, '
              'подтверждённые HR. Он открывает уровни и награды, но не подменяет '
              'оценку компетенций. Прирост после самоотчёта показывается отдельно '
              'как расчётный и не гарантирует повышение.',
        ),
      ],
    );
    if (!wide) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [intro, SizedBox(height: 26), questions],
      );
    }
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 4, child: intro),
        SizedBox(width: 56),
        Expanded(flex: 6, child: questions),
      ],
    );
  }

  Widget _footer(bool wide) => Container(
    padding: EdgeInsets.all(wide ? 36 : 22),
    decoration: _decoration(tinted: true),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 28,
          runSpacing: 24,
          children: [
            const _Heading(
              eyebrow: 'ТВОЯ СЛЕДУЮЩАЯ ГЛАВА',
              title: 'Начни со своего пути.',
              description: 'Знакомство с возможностями начинается с тебя.',
            ),
            FilledButton.icon(
              key: const Key('landing-start'),
              onPressed: onStart,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Открыть свой профиль'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 28),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 48,
          runSpacing: 28,
          children: [
            const SizedBox(
              width: 270,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Brand(),
                  SizedBox(height: 16),
                  Text(
                    'Твой путь. Больше чем работа.',
                    style: TextStyle(color: ink),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Пространство, где опыт, навыки и карьерные цели '
                    'становятся одной историей.',
                    style: TextStyle(color: muted, height: 1.7, fontSize: 13),
                  ),
                ],
              ),
            ),
            _footerLinks('ПЛАТФОРМА', [
              ('Возможности', onBenefits),
              ('Как начать', onSteps),
              ('Вопросы и ответы', onFaq),
            ]),
            const SizedBox(
              width: 230,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Eyebrow('ДЛЯ ЛЮДЕЙ И КОМАНД'),
                  SizedBox(height: 18),
                  Text(
                    'Сотрудникам — видеть свою цель.\nHR — поддерживать развитие.',
                    style: TextStyle(color: muted, height: 1.9, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 20,
          runSpacing: 8,
          children: [
            Text(
              '© ${DateTime.now().year} Career Quest',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            TextButton.icon(
              onPressed: onTop,
              icon: const Icon(Icons.arrow_upward_rounded, size: 16),
              label: const Text('Наверх'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _footerLinks(String title, List<(String, VoidCallback)> links) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Eyebrow(title),
          const SizedBox(height: 10),
          for (final (label, action) in links)
            TextButton(onPressed: action, child: Text(label)),
        ],
      );
}

BoxDecoration _decoration({bool tinted = false}) => BoxDecoration(
  borderRadius: BorderRadius.circular(30),
  border: Border.all(color: line.withValues(alpha: .75)),
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      panelRaised.withValues(alpha: .8),
      tinted ? const Color(0xFF24203E) : panel,
    ],
  ),
);

class _ScrollReveal extends StatefulWidget {
  const _ScrollReveal({required this.child});

  final Widget child;

  @override
  State<_ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<_ScrollReveal> {
  ScrollPosition? _position;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextPosition = Scrollable.maybeOf(context)?.position;
    if (_position != nextPosition) {
      _position?.removeListener(_checkVisibility);
      _position = nextPosition;
      _position?.addListener(_checkVisibility);
    }
    if (MediaQuery.disableAnimationsOf(context) || _position == null) {
      _visible = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    }
  }

  void _checkVisibility() {
    if (!mounted || _visible) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final bottom = top + renderObject.size.height;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    if (top < viewportHeight * .92 && bottom > 0) {
      setState(() => _visible = true);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_checkVisibility);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, .055),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _HoverLift extends StatefulWidget {
  const _HoverLift({required this.child});

  final Widget child;

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = !MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedSlide(
        offset: enabled && _hovered ? const Offset(0, -.012) : Offset.zero,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedScale(
          scale: enabled && _hovered ? 1.012 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: cyan,
      fontSize: 10,
      height: 1.8,
      letterSpacing: 1.6,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.eyebrow,
    required this.title,
    required this.description,
  });
  final String eyebrow, title, description;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Eyebrow(eyebrow),
      const SizedBox(height: 14),
      Semantics(
        header: true,
        child: Text(
          title,
          style: TextStyle(
            fontSize: MediaQuery.sizeOf(context).width < 600 ? 27 : 36,
            height: 1.2,
            letterSpacing: -1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 16),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 590),
        child: Text(
          description,
          style: const TextStyle(color: muted, height: 1.8),
        ),
      ),
    ],
  );
}

class _Columns extends StatelessWidget {
  const _Columns({required this.columns, required this.children});
  final int columns;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        for (final child in children)
          SizedBox(
            width: (box.maxWidth - 18 * (columns - 1)) / columns,
            child: child,
          ),
      ],
    ),
  );
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.number,
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.tag,
  });
  final String number, title, description, tag;
  final IconData icon;
  final Color accent;
  @override
  Widget build(BuildContext context) => _HoverLift(
    child: Container(
      padding: const EdgeInsets.all(26),
      decoration: _decoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withValues(alpha: .25)),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const Spacer(),
              Text(
                number,
                style: TextStyle(
                  color: accent.withValues(alpha: .55),
                  fontSize: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              fontSize: 21,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(description, style: const TextStyle(color: muted, height: 1.8)),
          const SizedBox(height: 22),
          Text(
            tag,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              letterSpacing: 1.4,
              height: 1.7,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProgressPreview extends StatelessWidget {
  const _ProgressPreview({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(wide ? 34 : 20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: blue.withValues(alpha: .38)),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF182544), Color(0xFF171D37), Color(0xFF241B38)],
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .2),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _previewHeader(),
        const SizedBox(height: 26),
        Divider(color: line.withValues(alpha: .75)),
        const SizedBox(height: 28),
        if (wide)
          const IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 4, child: _ProgressSummary()),
                SizedBox(width: 32),
                VerticalDivider(width: 1),
                SizedBox(width: 32),
                Expanded(flex: 6, child: _SkillProgressPanel()),
              ],
            ),
          )
        else
          const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProgressSummary(),
              SizedBox(height: 28),
              _SkillProgressPanel(),
            ],
          ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: night.withValues(alpha: .38),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: line.withValues(alpha: .55)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 17, color: muted),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Пример на синтетическом профиле. Значения не относятся '
                  'к вошедшему пользователю.',
                  style: TextStyle(color: muted, fontSize: 11, height: 1.6),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _previewHeader() {
    const identity = Row(
      children: [
        _PreviewIcon(),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'КАРЬЕРНЫЙ МАРШРУТ',
                style: TextStyle(
                  color: muted,
                  fontSize: 9,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Персональный менеджер',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cyan.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cyan.withValues(alpha: .25)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: cyan),
          SizedBox(width: 7),
          Text(
            'ПРИМЕР ПРОФИЛЯ',
            style: TextStyle(
              color: cyan,
              fontSize: 9,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          identity,
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: badge),
        ],
      );
    }
    return Row(
      children: [
        const Expanded(child: identity),
        const SizedBox(width: 24),
        badge,
      ],
    );
  }
}

class _PreviewIcon extends StatelessWidget {
  const _PreviewIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: blue.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: blue.withValues(alpha: .3)),
    ),
    child: const Icon(Icons.route_rounded, color: blue, size: 24),
  );
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'КАРЬЕРНЫЙ ПЕРЕХОД',
        style: TextStyle(
          color: muted,
          fontSize: 9,
          letterSpacing: 1.3,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      const Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          _RolePill(label: 'Консультант', active: false),
          Icon(Icons.arrow_forward_rounded, color: muted, size: 20),
          _RolePill(label: 'Персональный менеджер', active: true),
        ],
      ),
      const SizedBox(height: 28),
      Row(
        children: [
          SizedBox(
            width: 116,
            height: 116,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: .6,
                  strokeWidth: 9,
                  strokeCap: StrokeCap.round,
                  backgroundColor: line.withValues(alpha: .45),
                  valueColor: const AlwaysStoppedAnimation(pink),
                ),
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '3 / 5',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.8,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'требований',
                        style: TextStyle(color: muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Три компетенции уже соответствуют цели',
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 9),
                Text(
                  'По двум компетенциям виден разрыв в один уровень.',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    decoration: BoxDecoration(
      color: active ? pink.withValues(alpha: .14) : night.withValues(alpha: .4),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(
        color: active ? pink.withValues(alpha: .4) : line.withValues(alpha: .7),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: active ? pink : muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SkillProgressPanel extends StatelessWidget {
  const _SkillProgressPanel();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: night.withValues(alpha: .3),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line.withValues(alpha: .55)),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Компетенции для цели',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              'ПОСЛЕДНЯЯ ОЦЕНКА',
              style: TextStyle(color: muted, fontSize: 8, letterSpacing: 1.1),
            ),
          ],
        ),
        SizedBox(height: 20),
        _SkillRow(name: 'Клиентский сервис', current: 4, target: 4),
        SizedBox(height: 17),
        _SkillRow(name: 'Деловая коммуникация', current: 3, target: 3),
        SizedBox(height: 17),
        _SkillRow(name: 'Продукты банка', current: 3, target: 3),
        SizedBox(height: 17),
        _SkillRow(name: 'Работа с возражениями', current: 2, target: 3),
        SizedBox(height: 17),
        _SkillRow(name: 'Финансовая грамотность', current: 2, target: 3),
        SizedBox(height: 20),
        _FocusCard(),
      ],
    ),
  );
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({
    required this.name,
    required this.current,
    required this.target,
  });
  final String name;
  final int current, target;

  @override
  Widget build(BuildContext context) {
    final complete = current >= target;
    final accent = complete ? cyan : pink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              complete ? 'Соответствует' : 'Нужно +${target - current}',
              style: TextStyle(
                color: accent,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$current / $target',
              style: const TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: current / target,
            minHeight: 5,
            backgroundColor: line.withValues(alpha: .42),
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
      ],
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: violet.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: violet.withValues(alpha: .22)),
    ),
    child: const Row(
      children: [
        Icon(Icons.center_focus_strong_rounded, color: violet, size: 22),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Фокус развития',
                style: TextStyle(color: violet, fontSize: 10),
              ),
              SizedBox(height: 4),
              Text(
                'Работа с возражениями · до требования цели 1 уровень',
                style: TextStyle(fontSize: 12, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.description,
    required this.accent,
  });
  final String number, title, description;
  final Color accent;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              number,
              style: TextStyle(
                color: accent,
                fontSize: 34,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(child: Divider(color: accent.withValues(alpha: .3))),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(description, style: const TextStyle(color: muted, height: 1.8)),
      ],
    ),
  );
}

class _Question extends StatelessWidget {
  const _Question({required this.question, required this.answer});
  final String question, answer;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: line.withValues(alpha: .7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
        childrenPadding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
        iconColor: pink,
        collapsedIconColor: violet,
        textColor: ink,
        collapsedTextColor: ink,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          question,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: const TextStyle(color: muted, height: 1.85),
            ),
          ),
        ],
      ),
    ),
  );
}
