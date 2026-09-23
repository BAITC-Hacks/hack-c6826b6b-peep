import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'ui.dart';

const _gold = Color(0xFFF4D38D);
String _number(num n) => n.round().toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ' ',
);
int _int(dynamic n) => n is num ? n.toInt() : 0;

/// XP within the current level is distinct from total season completion.
class SeasonProgressCard extends StatelessWidget {
  const SeasonProgressCard({
    super.key,
    required this.summary,
    this.onOpenPass,
    required this.onRewards,
    this.compact = false,
    this.featured = false,
  });
  final Json summary;
  final VoidCallback? onOpenPass;
  final VoidCallback onRewards;
  final bool compact;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final level = _int(summary['level']).clamp(0, 100);
    final xp = _int(summary['confirmed_xp']);
    final remaining = _int(summary['xp_to_next']);
    final maxed = level == 100;
    final progress = maxed ? 1.0 : ((200 - remaining) / 200).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: EdgeInsets.all(featured ? 28 : 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: featured
              ? const [Color(0xFF2D3C70), Color(0xFF29214D), Color(0xFF17213B)]
              : const [Color(0xFF26345E), Color(0xFF211E42), panel],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: featured
              ? _gold.withValues(alpha: .34)
              : violet.withValues(alpha: .35),
        ),
        boxShadow: featured
            ? [
                BoxShadow(
                  color: violet.withValues(alpha: .14),
                  blurRadius: 34,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact) ...[
            Row(
              children: [
                Container(
                  width: featured ? 42 : 30,
                  height: featured ? 42 : 30,
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(featured ? 14 : 10),
                    border: Border.all(color: _gold.withValues(alpha: .22)),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 17,
                    color: _gold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        featured ? 'КАРЬЕРНЫЙ ПРОПУСК' : 'ТВОЙ СЕЗОН',
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 9,
                          letterSpacing: 1.35,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value(summary['season']?['name'], 'Твой сезон'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink,
                          fontSize: featured ? 16 : 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: night.withValues(alpha: .28),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: line.withValues(alpha: .65)),
                  ),
                  child: const Text(
                    '100 УРОВНЕЙ',
                    style: TextStyle(
                      color: muted,
                      fontSize: 9,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _LevelCrest(level: level),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      maxed ? 'Вершина достигнута!' : 'Твой следующий уровень',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      maxed
                          ? 'Все 100 уровней открыты. Забери свои награды.'
                          : 'Ещё ${_number(remaining)} XP до уровня ${level + 1}',
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      label: maxed
                          ? 'Пропуск завершён'
                          : 'Прогресс до уровня ${level + 1}',
                      value: maxed ? '100%' : '${200 - remaining} из 200 XP',
                      child: ExcludeSemantics(
                        child: _XpBar(
                          progress: progress,
                          text: maxed
                              ? 'ПРОПУСК ПРОЙДЕН'
                              : '${200 - remaining} / 200 XP',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoChip(
                  Icons.bolt_rounded,
                  '${_number(xp)} XP за сезон',
                  blue,
                ),
                _InfoChip(
                  Icons.toll_rounded,
                  '${_number(_int(summary['wallet_balance']))} CQ',
                  _gold,
                ),
                _InfoChip(
                  Icons.local_fire_department_rounded,
                  'Серия: ${_int(summary['current_streak'])} дн.',
                  pink,
                ),
                if (_int(summary['pending_xp']) > 0)
                  _InfoChip(
                    Icons.hourglass_top_rounded,
                    '${_number(_int(summary['pending_xp']))} XP на проверке',
                    muted,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (onOpenPass != null)
                  FilledButton.icon(
                    onPressed: onOpenPass,
                    icon: const Icon(Icons.route_rounded, size: 18),
                    label: const Text('Открыть пропуск'),
                  ),
                TextButton.icon(
                  onPressed: onRewards,
                  icon: const Icon(Icons.redeem_rounded, size: 18),
                  label: Text(
                    _int(summary['unclaimed_gifts_count']) > 0
                        ? 'Мои подарки · ${summary['unclaimed_gifts_count']} ждут'
                        : 'Мои подарки',
                  ),
                ),
                if (summary['rank'] != null)
                  Text(
                    '№ ${summary['rank']} в рейтинге',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LevelCrest extends StatelessWidget {
  const _LevelCrest({required this.level});
  final int level;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Текущий уровень $level из 100',
    child: ExcludeSemantics(
      child: SizedBox(
        width: 78,
        height: 94,
        child: CustomPaint(
          painter: const _CrestPainter(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star_rounded, size: 17, color: _gold),
              Text(
                '$level',
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  color: ink,
                ),
              ),
              const Text(
                'УРОВЕНЬ',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: violet,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CrestPainter extends CustomPainter {
  const _CrestPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .5, 1)
      ..lineTo(size.width - 2, size.height * .15)
      ..lineTo(size.width - 2, size.height * .7)
      ..quadraticBezierTo(
        size.width * .8,
        size.height * .87,
        size.width * .5,
        size.height - 2,
      )
      ..quadraticBezierTo(
        size.width * .2,
        size.height * .87,
        2,
        size.height * .7,
      )
      ..lineTo(2, size.height * .15)
      ..close();
    canvas.drawShadow(path, violet.withValues(alpha: .5), 9, true);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6553A6), Color(0xFF302E60), Color(0xFF23294C)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = violet
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CrestPainter oldDelegate) => false;
}

class _XpBar extends StatelessWidget {
  const _XpBar({required this.progress, required this.text});
  final double progress;
  final String text;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: progress),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 550),
    curve: Curves.easeOutCubic,
    builder: (context, fill, _) => Container(
      height: 30,
      decoration: BoxDecoration(
        color: night,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: violet.withValues(alpha: .3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          children: [
            FractionallySizedBox(
              widthFactor: fill,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6951AF), Color(0xFFC865AC)],
                  ),
                  border: Border(
                    top: BorderSide(
                      color: pink.withValues(alpha: .65),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Text(
                text,
                style: const TextStyle(
                  color: ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7,
                  shadows: [Shadow(color: night, blurRadius: 5)],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.text, this.color);
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: night.withValues(alpha: .45),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// One continuous, virtualized road. Its position is derived from server XP
/// thresholds; browsing or opening a card never grants a reward.
class CareerPassRoad extends StatefulWidget {
  const CareerPassRoad({
    super.key,
    required this.levels,
    required this.confirmedXp,
    required this.onChooseGift,
    this.busy = false,
  });
  final List<Json> levels;
  final int confirmedXp;
  final ValueChanged<String> onChooseGift;
  final bool busy;
  @override
  State<CareerPassRoad> createState() => _CareerPassRoadState();
}

class _CareerPassRoadState extends State<CareerPassRoad> {
  static const _extent = 190.0;
  late final ScrollController _scroll;
  int _chapter = 0;
  double _viewport = 0;
  bool _atStart = true, _atEnd = false;

  // A virtual start node makes partial progress toward level 1 visible too.
  int get _current => widget.levels
      .where((l) => _int(l['required_total_xp']) <= widget.confirmedXp)
      .length;
  double get _position {
    final done = _current;
    if (done == widget.levels.length) return done.toDouble();
    final before = done == 0
        ? 0
        : _int(widget.levels[done - 1]['required_total_xp']);
    final next = _int(widget.levels[done]['required_total_xp']);
    return done +
        ((widget.confirmedXp - before) / math.max(1, next - before)).clamp(
          0,
          1,
        );
  }

  List<Json> get _available => widget.levels
      .where(
        (l) => records(
          l['components'],
        ).any((c) => c['status'] == 'available' && c['entitlement_id'] != null),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _goTo(_current, animate: false),
    );
  }

  @override
  void didUpdateWidget(CareerPassRoad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.confirmedXp != widget.confirmedXp ||
        oldWidget.levels.length != widget.levels.length) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _goTo(_current, animate: false),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final center = ((_scroll.offset + _viewport / 2) / _extent).floor();
    final chapter = ((math.max(1, center) - 1) ~/ 10).clamp(0, 9);
    final start = _scroll.offset <= 1;
    final end = _scroll.offset >= _scroll.position.maxScrollExtent - 1;
    if (chapter != _chapter || start != _atStart || end != _atEnd) {
      setState(() {
        _chapter = chapter;
        _atStart = start;
        _atEnd = end;
      });
    }
  }

  void _goTo(int index, {bool animate = true}) {
    if (!mounted || !_scroll.hasClients) return;
    final offset = (index * _extent + _extent / 2 - _viewport / 2).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(offset);
    } else {
      _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
    _onScroll();
  }

  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final step = math.max(1, (_viewport / _extent).floor());
    final center = ((_scroll.offset + _viewport / 2) / _extent - .5).round();
    _goTo((center + direction * step).clamp(0, widget.levels.length));
  }

  void _details(Json level) {
    final parts = records(level['components']);
    final remaining = math.max(
      0,
      _int(level['required_total_xp']) - widget.confirmedXp,
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Награды · уровень ${level['level']}'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  remaining > 0
                      ? 'Ещё ${_number(remaining)} XP, чтобы открыть этот уровень.'
                      : 'Уровень открыт за ${_number(_int(level['required_total_xp']))} XP.',
                  style: const TextStyle(color: muted),
                ),
                for (final part in parts) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(
                        _rewardIcon(part),
                        color: _rewardColor(part),
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value(part['name']),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _status(part['status']),
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (part['status'] == 'available' &&
                      part['entitlement_id'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: FilledButton.icon(
                        onPressed: widget.busy
                            ? null
                            : () {
                                Navigator.pop(dialogContext);
                                widget.onChooseGift(
                                  part['entitlement_id'] as String,
                                );
                              },
                        icon: const Icon(Icons.redeem_rounded, size: 18),
                        label: const Text('Выбрать подарок'),
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'CQ начисляются автоматически. Выбор подарка не тратит монеты. Выдача наград тестовая.',
                  style: TextStyle(fontSize: 12, color: muted, height: 1.6),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.levels.isEmpty) {
      return const Surface(child: Text('Награды пропуска пока недоступны.'));
    }
    final complete = _current == widget.levels.length;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final cardHeight = 254.0 + math.max(0, scale - 1) * 160;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF172343), Color(0xFF10172F)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Дорога наград',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.7,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  complete
                      ? '100 уровней позади. Время забрать заслуженное.'
                      : 'Каждые 200 XP — новый уровень. Каждый шаг — награда.',
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _goTo(_current),
                      icon: const Icon(Icons.my_location_rounded, size: 17),
                      label: const Text('К моему уровню'),
                    ),
                    if (_available.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () =>
                            _goTo(widget.levels.indexOf(_available.first) + 1),
                        icon: const Icon(Icons.redeem_rounded, size: 17),
                        label: Text('Забрать награды · ${_available.length}'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 600 ? 5 : 10;
                return Wrap(
                  spacing: 5,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < 10; i++)
                      SizedBox(
                        width:
                            (constraints.maxWidth - (columns - 1) * 5) /
                            columns,
                        child: Tooltip(
                          message: 'Уровни ${i * 10 + 1}–${(i + 1) * 10}',
                          child: Semantics(
                            button: true,
                            excludeSemantics: true,
                            selected: _chapter == i,
                            onTap: () => _goTo(i == 0 ? 0 : i * 10 + 1),
                            label:
                                'Перейти к уровням ${i * 10 + 1}–${(i + 1) * 10}',
                            child: Material(
                              color: _chapter == i
                                  ? const Color(0xFF493C66)
                                  : night.withValues(alpha: .5),
                              borderRadius: BorderRadius.circular(9),
                              child: InkWell(
                                onTap: () => _goTo(i == 0 ? 0 : i * 10 + 1),
                                borderRadius: BorderRadius.circular(9),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 44,
                                  ),
                                  padding: const EdgeInsets.fromLTRB(
                                    5,
                                    7,
                                    5,
                                    6,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                      color: _chapter == i
                                          ? pink
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        '${(i + 1) * 10}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _chapter == i ? pink : muted,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(3),
                                        child: LinearProgressIndicator(
                                          value: ((_position - i * 10) / 10)
                                              .clamp(0.0, 1.0),
                                          minHeight: 3,
                                          color: _chapter == i ? pink : cyan,
                                          backgroundColor: line.withValues(
                                            alpha: .5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final resized = _viewport != constraints.maxWidth;
              _viewport = constraints.maxWidth;
              if (resized) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _scroll.hasClients) {
                    _goTo(_current, animate: false);
                  }
                });
              }
              return SizedBox(
                height: cardHeight + 154 + math.max(0, scale - 1) * 26,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.stylus,
                    },
                    scrollbars: false,
                  ),
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    thickness: 4,
                    radius: const Radius.circular(4),
                    child: ListView.builder(
                      key: const Key('career-pass-track'),
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      itemExtent: _extent,
                      itemCount: widget.levels.length + 1,
                      itemBuilder: (context, index) => _RoadStop(
                        index: index,
                        current: _current,
                        position: _position,
                        last: index == widget.levels.length,
                        level: index == 0 ? null : widget.levels[index - 1],
                        confirmedXp: widget.confirmedXp,
                        cardHeight: cardHeight,
                        onTap: index == 0
                            ? null
                            : () => _details(widget.levels[index - 1]),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
            child: Row(
              children: [
                IconButton.outlined(
                  tooltip: 'Предыдущие уровни',
                  onPressed: _atStart ? null : () => _page(-1),
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Уровни ${_chapter * 10 + 1}–${(_chapter + 1) * 10}\nЛистай дорогу наград',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Следующие уровни',
                  onPressed: _atEnd ? null : () => _page(1),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadStop extends StatelessWidget {
  const _RoadStop({
    required this.index,
    required this.current,
    required this.position,
    required this.last,
    required this.level,
    required this.confirmedXp,
    required this.cardHeight,
    required this.onTap,
  });
  final int index, current, confirmedXp;
  final double position, cardHeight;
  final bool last;
  final Json? level;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final here = index == current;
    final unlocked = index <= current;
    final milestone = index > 0 && index % 5 == 0;
    final color = here
        ? pink
        : unlocked
        ? cyan
        : milestone
        ? _gold
        : muted;
    final scaledTop =
        math.max(0.0, MediaQuery.textScalerOf(context).scale(12) - 12) * 2;
    return Column(
      children: [
        SizedBox(
          height: 134 + scaledTop,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 60 + scaledTop,
                child: SizedBox(
                  height: 16,
                  child: CustomPaint(
                    painter: _RailPainter(
                      fill: position - index + .5,
                      first: index == 0,
                      last: last,
                    ),
                  ),
                ),
              ),
              if (here)
                Positioned(
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: pink,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: pink.withValues(alpha: .25),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: const Text(
                      'ТЫ ЗДЕСЬ',
                      style: TextStyle(
                        color: night,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 40 + scaledTop,
                child: Semantics(
                  container: true,
                  label:
                      'Уровень $index${here
                          ? ', текущий'
                          : unlocked
                          ? ', открыт'
                          : ', закрыт'}',
                  child: ExcludeSemantics(
                    child: Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: here
                              ? [Color(0xFFD782CF), Color(0xFF805AB8)]
                              : unlocked
                              ? [Color(0xFF317280), Color(0xFF23425F)]
                              : [Color(0xFF2C3352), Color(0xFF171F37)],
                        ),
                        borderRadius: BorderRadius.circular(
                          milestone ? 17 : 28,
                        ),
                        border: Border.all(
                          color: color.withValues(alpha: unlocked ? 1 : .45),
                          width: here ? 3 : 2,
                        ),
                        boxShadow: here
                            ? [
                                BoxShadow(
                                  color: pink.withValues(alpha: .3),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ]
                            : [
                                const BoxShadow(
                                  color: night,
                                  blurRadius: 0,
                                  spreadRadius: 5,
                                ),
                              ],
                      ),
                      child: Text(
                        '$index',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: unlocked ? ink : color,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 105 + scaledTop,
                child: Text(
                  index == 0
                      ? 'СТАРТ'
                      : '${_number(_int(level!['required_total_xp']))} XP',
                  style: TextStyle(
                    color: here ? pink : muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: SizedBox(
            height: cardHeight,
            child: level == null
                ? _StartCard(current: current)
                : _RewardCard(
                    level: level!,
                    confirmedXp: confirmedXp,
                    onTap: onTap!,
                  ),
          ),
        ),
      ],
    );
  }
}

/// Each tile paints its portion of one rail, including a fractional XP endpoint.
class _RailPainter extends CustomPainter {
  const _RailPainter({
    required this.fill,
    required this.first,
    required this.last,
  });
  final double fill;
  final bool first, last;
  @override
  void paint(Canvas canvas, Size size) {
    final start = first ? size.width / 2 : 0.0;
    final end = last ? size.width / 2 : size.width;
    final track = Rect.fromLTRB(start, 1, end, size.height - 1);
    canvas.drawRect(track, Paint()..color = night);
    canvas.drawRect(
      Rect.fromLTRB(start, 4, end, size.height - 4),
      Paint()..color = line,
    );
    final filled = (fill * size.width).clamp(start, end);
    if (filled > start) {
      final rect = Rect.fromLTRB(start, 3, filled, size.height - 3);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFDCC9FF), violet, Color(0xFF8160C3)],
          ).createShader(rect),
      );
      if (fill > 0 && fill < 1) {
        canvas.drawCircle(
          Offset(filled, size.height / 2),
          9,
          Paint()..color = pink.withValues(alpha: .2),
        );
        canvas.drawCircle(
          Offset(filled, size.height / 2),
          4,
          Paint()..color = ink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      fill != old.fill || first != old.first || last != old.last;
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.current});
  final int current;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          current == 0 ? Icons.rocket_launch_rounded : Icons.flag_rounded,
          color: violet,
          size: 42,
        ),
        const SizedBox(height: 18),
        Text(
          current == 0 ? 'Твой первый шаг' : 'Путь начался здесь',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 10),
        const Text(
          'Выполняй задания и накапливай XP',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12, height: 1.6),
        ),
      ],
    ),
  );
}

IconData _rewardIcon(Json part) => switch (part['type']) {
  'coins' => Icons.toll_rounded,
  'cosmetic' => Icons.workspace_premium_rounded,
  'mini' => Icons.card_giftcard_rounded,
  _ => Icons.redeem_rounded,
};
Color _rewardColor(Json part) => switch (part['type']) {
  'coins' => _gold,
  'cosmetic' => cyan,
  'mini' => violet,
  _ => _int(part['budget_cap_kzt']) >= 30000 ? _gold : pink,
};
String _status(dynamic status) => switch (status) {
  'credited' => 'Начислено',
  'fulfilled' => 'Получено',
  'available' => 'Можно забрать',
  'reserved' => 'Зарезервировано',
  'expired' => 'Срок истёк',
  _ => 'Закрыто',
};

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.level,
    required this.confirmedXp,
    required this.onTap,
  });
  final Json level;
  final int confirmedXp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = records(level['components']);
    final primary = parts.firstWhere(
      (p) => p['type'] == 'gift' || p['type'] == 'mini',
      orElse: () => parts.first,
    );
    final extras = parts.where((p) => !identical(p, primary)).toList();
    final available = parts.any((p) => p['status'] == 'available');
    final locked = parts.every((p) => p['status'] == 'locked');
    final received = parts.every(
      (p) => ['credited', 'fulfilled'].contains(p['status']),
    );
    final reserved = parts.any((p) => p['status'] == 'reserved');
    final color = _rewardColor(primary);
    final remaining = math.max(
      0,
      _int(level['required_total_xp']) - confirmedXp,
    );
    final status = available
        ? 'Забрать'
        : received
        ? 'Получено'
        : reserved
        ? 'В процессе'
        : locked
        ? 'Ещё ${_number(remaining)} XP'
        : 'Срок истёк';
    final title = _int(level['level']) == 100
        ? 'ГЛАВНЫЙ ПРИЗ'
        : primary['type'] == 'gift'
        ? 'ПОДАРОК НА ВЫБОР'
        : primary['type'] == 'mini'
        ? 'ПРИЯТНЫЙ БОНУС'
        : 'CQ-МОНЕТЫ';
    return Semantics(
      key: ValueKey('pass-reward-${level['level']}'),
      excludeSemantics: true,
      onTap: onTap,
      button: true,
      label:
          'Награда уровня ${level['level']}: ${parts.map((p) => p['name']).join(', ')}. $status',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          hoverColor: color.withValues(alpha: .07),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(
                    alpha: available
                        ? .22
                        : locked
                        ? .08
                        : .13,
                  ),
                  const Color(0xFF151D37),
                ],
              ),
              borderRadius: BorderRadius.circular(19),
              border: Border.all(
                color: available ? color : color.withValues(alpha: .28),
                width: available ? 1.6 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: .65,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  color.withValues(alpha: .24),
                                  color.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                          Transform.rotate(
                            angle: -.12,
                            child: Container(
                              width: 59,
                              height: 59,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(17),
                                color: color.withValues(alpha: .06),
                                border: Border.all(
                                  color: color.withValues(alpha: .2),
                                ),
                              ),
                            ),
                          ),
                          Icon(
                            _rewardIcon(primary),
                            size: 43,
                            color: color.withValues(alpha: locked ? .7 : 1),
                          ),
                          if (received)
                            Positioned(
                              right: 2,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: cyan,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: night,
                                  size: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    value(primary['name']),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: locked ? const Color(0xFFCCD3E7) : ink,
                      fontSize: primary['type'] == 'coins' ? 23 : 14,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 7),
                  if (extras.isNotEmpty)
                    Text(
                      extras.map((p) => '+ ${p['name']}').join(' · '),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 11),
                    )
                  else
                    Text(
                      primary['type'] == 'coins'
                          ? 'В твой кошелёк'
                          : 'За твой прогресс',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 9,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: available ? color : night.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          available
                              ? Icons.redeem_rounded
                              : received
                              ? Icons.check_rounded
                              : locked
                              ? Icons.lock_outline_rounded
                              : Icons.schedule_rounded,
                          size: 13,
                          color: available
                              ? night
                              : received
                              ? cyan
                              : muted,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            status,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: available
                                  ? night
                                  : received
                                  ? cyan
                                  : muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
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
        ),
      ),
    );
  }
}
