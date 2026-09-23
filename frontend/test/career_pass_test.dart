import 'package:career_quest/widgets/career_pass.dart';
import 'package:career_quest/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

List<Json> rewards(int xp, {String giftStatus = 'available'}) => [
  for (var level = 1; level <= 100; level++)
    {
      'level': level,
      'required_total_xp': level * 200,
      'unlocked': xp >= level * 200,
      'components': [
        if (level % 5 == 0)
          {
            'type': 'gift',
            'name': 'Подарок до 10 000 ₸',
            'budget_cap_kzt': 10000,
            'status': xp >= level * 200 ? giftStatus : 'locked',
            if (xp >= level * 200) 'entitlement_id': 'gift-$level',
          }
        else
          {
            'type': 'coins',
            'name': '10 CQ',
            'coins': 10,
            'status': xp >= level * 200 ? 'credited' : 'locked',
          },
        if (level == 2)
          {
            'type': 'mini',
            'name': 'Набор чая',
            'status': xp >= 400 ? giftStatus : 'locked',
            if (xp >= 400) 'entitlement_id': 'mini-2',
          },
        if (level % 25 == 0)
          {
            'type': 'cosmetic',
            'name': 'Рамка сезона',
            'status': xp >= level * 200 ? 'fulfilled' : 'locked',
          },
      ],
    },
];

Future<void> mount(
  WidgetTester t,
  Widget child, {
  double width = 1000,
  double scale = 1,
}) async {
  t.view.physicalSize = Size(width, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        splashFactory: InkRipple.splashFactory,
        fontFamily: 'Inter',
      ),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await loader.load();
  });
  for (final width in [320.0, 1000.0]) {
    testWidgets(
      'Road centers progress, navigates to finale and returns at $width',
      (t) async {
        final semantics = t.ensureSemantics();

        await mount(
          t,
          CareerPassRoad(
            levels: rewards(7650),
            confirmedXp: 7650,
            onChooseGift: (_) {},
          ),
          width: width,
        );
        expect(find.bySemanticsLabel('Уровень 38, текущий'), findsOneWidget);
        expect(find.text('ТЫ ЗДЕСЬ'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tap(find.byTooltip('Уровни 91–100'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('pass-reward-91')), findsOneWidget);
        await t.tap(find.text('К моему уровню'));
        await t.pumpAndSettle();
        expect(find.bySemanticsLabel('Уровень 38, текущий'), findsOneWidget);
        await t.tap(find.textContaining('Забрать награды ·'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('pass-reward-2')), findsOneWidget);
        expect(t.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets('Available gift opens details and dispatches exact entitlement', (
    t,
  ) async {
    String? selected;
    await mount(
      t,
      CareerPassRoad(
        levels: rewards(1100),
        confirmedXp: 1100,
        onChooseGift: (id) => selected = id,
      ),
    );
    await t.tap(find.byKey(const ValueKey('pass-reward-5')));
    await t.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('Можно забрать'), findsOneWidget);
    await t.tap(find.text('Выбрать подарок'));
    await t.pumpAndSettle();
    expect(selected, 'gift-5');
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final status in ['locked', 'reserved', 'fulfilled', 'expired']) {
    testWidgets('$status rewards never offer a claim', (t) async {
      final xp = status == 'locked' ? 800 : 1100;
      await mount(
        t,
        CareerPassRoad(
          levels: rewards(xp, giftStatus: status),
          confirmedXp: xp,
          onChooseGift: (_) => fail('Invalid reward claim'),
        ),
      );
      await t.tap(find.byKey(const ValueKey('pass-reward-5')));
      await t.pumpAndSettle();
      expect(find.text('Выбрать подарок'), findsNothing);
      if (status == 'locked') {
        expect(
          find.text('Ещё 200 XP, чтобы открыть этот уровень.'),
          findsOneWidget,
        );
      }
      expect(t.takeException(), isNull);
    });
  }

  for (final xp in [0, 199, 200, 19999, 20250]) {
    testWidgets('XP boundary $xp and enlarged text fit narrow screen', (
      t,
    ) async {
      final level = (xp ~/ 200).clamp(0, 100);
      await mount(
        t,
        Column(
          children: [
            SeasonProgressCard(
              summary: {
                'level': level,
                'confirmed_xp': xp,
                'xp_to_next': level == 100 ? 0 : 200 - xp % 200,
              },
              onRewards: () {},
            ),
            CareerPassRoad(
              levels: rewards(xp),
              confirmedXp: xp,
              onChooseGift: (_) {},
            ),
          ],
        ),
        width: 320,
        scale: 1.5,
      );
      expect(
        find.text(level == 100 ? 'ПРОПУСК ПРОЙДЕН' : '${xp % 200} / 200 XP'),
        findsOneWidget,
      );
      expect(find.textContaining('уровня 101'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('Published custom XP thresholds appear in progress', (t) async {
    await mount(
      t,
      SeasonProgressCard(
        summary: {
          'level': 1,
          'max_level': 7,
          'confirmed_xp': 225,
          'xp_to_next': 225,
          'level_start_xp': 150,
          'level_target_xp': 450,
        },
        onRewards: () {},
      ),
      width: 320,
    );
    expect(find.text('7 УРОВНЕЙ'), findsOneWidget);
    expect(find.text('75 / 300 XP'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
