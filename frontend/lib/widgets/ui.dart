import 'package:flutter/material.dart';

import '../core/api.dart';

// Career Quest visual system. See docs/08-design-system.md before adding screens.
const night = Color(0xFF080D22);
const panel = Color(0xFF131D38);
const panelRaised = Color(0xFF1D284A);
const ink = Color(0xFFF5F3FF);
const muted = Color(0xFFABB7D5);
const line = Color(0xFF34436C);
const pink = Color(0xFFF392D5);
const blue = Color(0xFF719BFF);
const violet = Color(0xFFB29AFF);
const cyan = Color(0xFF6EDDE8);
const danger = Color(0xFFFFA2B8);
// Compatibility aliases for the existing page components.
const green = pink;
const paper = night;
const mint = Color(0xFF292847);
const lime = cyan;

typedef Json = Map<String, dynamic>;
List<Json> records(dynamic values) =>
    (values as List? ?? []).map((e) => Json.from(e as Map)).toList();
String value(dynamic item, [String fallback = '—']) =>
    item == null || item.toString().isEmpty ? fallback : item.toString();
String initials(String name) => name
    .split(' ')
    .where((e) => e.isNotEmpty)
    .take(2)
    .map((e) => e[0])
    .join()
    .toUpperCase();
String dateLabel(dynamic raw) {
  final date = DateTime.tryParse(value(raw));
  if (date == null) return value(raw);
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

/// Lightweight atmosphere: gradients instead of an expensive full-screen blur.
class QuestBackdrop extends StatelessWidget {
  const QuestBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: runtimeConfiguration,
        builder: (context, config, _) {
          final raw = config['branding']?['background'];
          final background =
              raw is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(raw)
              ? Color(int.parse('FF${raw.substring(1)}', radix: 16))
              : night;
          return ColoredBox(
            color: background,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(.95, -.95),
                          radius: 1.2,
                          colors: [
                            const Color(0xFF222655),
                            const Color(0xFF0D1530),
                            background,
                          ],
                          stops: [0, .5, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(1.1, 1.15),
                          radius: .9,
                          colors: [
                            Color(0x382B386B),
                            Color(0x226C386D),
                            Color(0x00080D22),
                          ],
                          stops: [0, .42, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Material(type: MaterialType.transparency, child: child),
              ],
            ),
          );
        },
      );
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.light = false, this.compact = false});
  final bool light;
  final bool compact;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: runtimeConfiguration,
        builder: (context, config, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((runtimeConfiguration.value['branding']?['logo_url'] ?? '')
                .toString()
                .isNotEmpty)
              Image.network(
                runtimeConfiguration.value['branding']['logo_url'],
                width: 38,
                height: 38,
                fit: BoxFit.contain,
                errorBuilder: (_, e, s) => const QuestMark(),
              )
            else
              const QuestMark(),
            if (!compact) ...[
              const SizedBox(width: 11),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    runtimeConfiguration.value['branding']?['app_name'] ??
                        'Career Quest',
                    style: const TextStyle(
                      color: ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.6,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}

/// Career Quest mark: a mountain route leading to a lit summit.
/// Kept as a vector painter so the logo stays crisp at every Flutter scale.
class QuestMark extends StatelessWidget {
  const QuestMark({super.key, this.size = 38});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * .15),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF315BB7), Color(0xFF6F3F91)],
      ),
      border: Border.all(color: blue.withValues(alpha: .58)),
      borderRadius: BorderRadius.circular(size * .32),
      boxShadow: [
        BoxShadow(
          color: violet.withValues(alpha: .2),
          blurRadius: size * .55,
          spreadRadius: -size * .2,
        ),
      ],
    ),
    child: const CustomPaint(painter: _QuestMarkPainter()),
  );
}

class _QuestMarkPainter extends CustomPainter {
  const _QuestMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final mountain = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final mountains = Path()
      ..moveTo(size.width * .08, size.height * .71)
      ..lineTo(size.width * .35, size.height * .39)
      ..lineTo(size.width * .51, size.height * .57)
      ..lineTo(size.width * .70, size.height * .25)
      ..lineTo(size.width * .92, size.height * .71);
    canvas.drawPath(mountains, mountain);

    final route = Paint()
      ..color = pink
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .1
      ..strokeCap = StrokeCap.round;
    final trail = Path()
      ..moveTo(size.width * .19, size.height * .84)
      ..cubicTo(
        size.width * .38,
        size.height * .68,
        size.width * .57,
        size.height * .85,
        size.width * .59,
        size.height * .63,
      )
      ..cubicTo(
        size.width * .60,
        size.height * .50,
        size.width * .67,
        size.height * .44,
        size.width * .70,
        size.height * .32,
      );
    canvas.drawPath(trail, route);
    canvas.drawCircle(
      Offset(size.width * .70, size.height * .25),
      size.width * .085,
      Paint()..color = pink,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: ink,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 7),
              Text(
                subtitle!,
                style: const TextStyle(color: muted, fontSize: 13, height: 1.6),
              ),
            ],
          ],
        ),
      ),
      if (action != null) ...[const SizedBox(width: 10), action!],
    ],
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = 24,
    this.color = panel,
  });
  final Widget child;
  final double padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.alphaBlend(blue.withValues(alpha: .065), color), color],
      ),
      border: Border.all(color: line.withValues(alpha: .9)),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .12),
          blurRadius: 24,
          offset: const Offset(0, 9),
        ),
        BoxShadow(color: blue.withValues(alpha: .035), blurRadius: 20),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class Tag extends StatelessWidget {
  const Tag(
    this.text, {
    super.key,
    this.color = violet,
    this.background = mint,
    this.icon,
  });
  final String text;
  final Color color;
  final Color background;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      border: Border.all(color: color.withValues(alpha: .2)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.error = false, this.action});
  final String text;
  final bool error;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error ? const Color(0xFF352039) : const Color(0xFF1D2A48),
      border: Border.all(color: (error ? danger : blue).withValues(alpha: .3)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline : Icons.info_outline,
          color: error ? danger : blue,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TextStyle(
                  color: error ? danger : ink,
                  height: 1.6,
                  fontSize: 13,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 8), action!],
            ],
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.title,
    this.subtitle, {
    super.key,
    this.icon = Icons.inbox_outlined,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
    child: Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: mint,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: line),
            ),
            child: Icon(icon, color: violet, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ink,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, height: 1.6),
          ),
        ],
      ),
    ),
  );
}
