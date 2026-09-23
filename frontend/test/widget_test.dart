import 'dart:convert';
import 'dart:io';

import 'package:career_quest/core/api.dart';
import 'package:career_quest/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final fixtures = jsonDecode(
  File('test/fixtures/api.json').readAsStringSync(),
) as Map<String, dynamic>;
http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void size(WidgetTester t, Size s) {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

CareerApi client({
  String role = 'employee',
  bool Function()? expired,
  Map<String, Object>? overrides,
}) => CareerApi(
  baseUrl: 'http://test',
  client: MockClient((r) async {
    if (r.url.path == '/api/auth/login') {
      return response({
        'token': 'session',
        'user': {
          'role': role,
          'employee_id': role == 'employee' ? 'E1' : null,
          'display_name': 'Test Person',
        },
      });
    }
    if (expired?.call() == true) {
      return response({
        'error': {'code': 'UNAUTHORIZED', 'message': 'Войдите снова'},
      }, 401);
    }
    if (r.url.path == '/api/auth/logout') return response({});
    expect(r.headers['Authorization'], 'Bearer session');
    return response(
      overrides?[r.url.path] ??
          fixtures[r.url.path] ??
          {
            'data': {},
            'meta': {'state_revision': 0},
          },
    );
  }),
);
Future<void> login(WidgetTester t, String role) async {
  await t.ensureVisible(find.text(role));
  await t.tap(find.text(role));
  final fields = find.byType(TextField);
  await t.enterText(fields.at(1), 'FixtureOnly!');
  await t.ensureVisible(find.text('Войти'));
  await t.tap(find.text('Войти'));
  await t.pumpAndSettle();
}

Future<void> nav(WidgetTester t, String text) async {
  if (find.byTooltip('Меню').evaluate().isNotEmpty) {
    await t.tap(find.byTooltip('Меню'));
    await t.pumpAndSettle();
  }
  final item = find
      .ancestor(of: find.text(text), matching: find.byType(ListTile))
      .first;
  await t.ensureVisible(item);
  await t.tap(item);
  await t.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 1280.0]) {
    testWidgets('Employee navigation and daily at width $width', (t) async {
      size(t, Size(width, 900));
      final api = client();
      addTearDown(api.dispose);
      await t.pumpWidget(CareerQuestApp(api: api));
      await login(t, 'Сотрудник');
      expect(find.textContaining('Привет'), findsOneWidget);
      expect(find.text('Загрузка данных'), findsNothing);
      await nav(t, 'Мой маршрут');
      expect(find.text('Шаги маршрута'), findsWidgets);
      await nav(t, 'Карьерный пропуск');
      await t.ensureVisible(find.text('Задания дня'));
      await t.tap(find.text('Задания дня'));
      await t.pumpAndSettle();
      expect(find.text('Задания дня'), findsOneWidget);
      expect(find.text('Ежедневный шаг'), findsOneWidget);
      expect(find.text('Кейс дня'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  for (final width in [360.0, 1280.0]) {
    testWidgets('Road plan fits and shows ordered stops at width $width', (
      t,
    ) async {
      size(t, Size(width, 900));
      final api = client(
        overrides: {
          '/api/me/plan': {
            'data': {
              'items': [
                {
                  'id': 'P1',
                  'activity_id': 'A1',
                  'status': 'in_progress',
                  'activity': {
                    'title': 'Accessible Interfaces',
                    'duration_minutes': 120,
                    'format': 'online',
                  },
                },
                {
                  'id': 'P2',
                  'activity_id': 'A2',
                  'status': 'planned',
                  'activity': {
                    'title': 'Практика с дизайн-системой',
                    'duration_minutes': 90,
                    'format': 'self_paced',
                  },
                },
              ],
              'total_minutes': 210,
              'estimated_weeks': 2,
            },
            'meta': {'state_revision': 0},
          },
        },
      );
      addTearDown(api.dispose);
      await t.pumpWidget(CareerQuestApp(api: api));
      await login(t, 'Сотрудник');
      await nav(t, 'Мой маршрут');
      expect(find.text('Маршрут из 2 шагов'), findsOneWidget);
      expect(find.text('ЭТАП 01'), findsOneWidget);
      expect(find.text('ЭТАП 02'), findsOneWidget);
      expect(find.text('Accessible Interfaces'), findsOneWidget);
      expect(find.text('Проложить ещё один шаг'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('OpenAI assistant explains and renders a plan draft', (t) async {
    size(t, const Size(1280, 1000));
    Map<String, Object> envelope(Object data) => {
      'data': data,
      'meta': {'state_revision': 3},
    };
    final api = client(
      overrides: {
        '/api/me/assistant/status': envelope({
          'configured': true,
          'provider': 'OpenAI',
          'model': 'gpt-4o-mini',
        }),
        '/api/me/assistant/explain': envelope({
          'title': 'Маршрут связан с целью',
          'text': 'Каждый шаг развивает нужные навыки.',
          'bullets': ['Сначала ближайшая практика'],
          'metrics': [
            {'label': 'Шагов в плане', 'value': '1'},
          ],
          'mode': 'llm',
          'model': 'gpt-4o-mini',
        }),
        '/api/me/assistant/plan': envelope({
          'headline': 'Маршрут готов к проверке',
          'summary': 'Выбран совместимый шаг.',
          'items': [
            {
              'id': 'A1',
              'title': 'Accessible Interfaces',
              'duration_minutes': 120,
              'format': 'online',
              'reason': 'Практика связана с целью.',
              'focus_skills': ['Accessibility'],
            },
          ],
          'total_minutes': 120,
          'estimated_weeks': 1,
          'mode': 'llm',
          'model': 'gpt-4o-mini',
          'disclaimer': 'Черновик ничего не меняет.',
        }),
      },
    );
    addTearDown(api.dispose);
    await t.pumpWidget(CareerQuestApp(api: api));
    await login(t, 'Сотрудник');
    await nav(t, 'OpenAI-помощник');
    expect(find.text('OpenAI Career Copilot'), findsOneWidget);
    expect(find.text('OPENAI ПОДКЛЮЧЁН'), findsOneWidget);

    await t.ensureVisible(find.text('Почему эти шаги?'));
    await t.tap(find.text('Почему эти шаги?'));
    await t.pumpAndSettle();
    expect(find.text('Маршрут связан с целью'), findsOneWidget);

    await t.ensureVisible(find.text('Сбалансированный'));
    await t.tap(find.text('Сбалансированный'));
    await t.pumpAndSettle();
    expect(find.text('Маршрут готов к проверке'), findsOneWidget);
    expect(find.text('Accessible Interfaces'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('Narrow HR overview and directory have no import', (t) async {
    size(t, const Size(360, 900));
    final api = client(role: 'hr');
    addTearDown(api.dispose);
    await t.pumpWidget(CareerQuestApp(api: api));
    await login(t, 'HR');
    expect(find.text('Развитие команды в контексте'), findsOneWidget);
    await nav(t, 'Сотрудники');
    expect(find.text('Synthetic Person E1'), findsOneWidget);
    expect(find.text('Загрузка данных'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('Expired session removes personal content', (t) async {
    size(t, const Size(1280, 900));
    var expired = false;
    final api = client(expired: () => expired);
    addTearDown(api.dispose);
    await t.pumpWidget(CareerQuestApp(api: api));
    await login(t, 'Сотрудник');
    expired = true;
    await t.tap(find.byTooltip('Обновить'));
    await t.pumpAndSettle();
    expect(find.text('Рады видеть вас'), findsOneWidget);
    expect(find.textContaining('Твой следующий шаг'), findsNothing);
    expect(api.token, isNull);
  });
  testWidgets('Landing contains FAQ and fills the selected demo account', (
    t,
  ) async {
    size(t, const Size(360, 900));
    final api = client();
    addTearDown(api.dispose);
    await t.pumpWidget(CareerQuestApp(api: api));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Сотрудник'));
    await t.tap(find.text('Сотрудник'));
    await t.pumpAndSettle();
    expect(
      (t.widgetList<TextField>(find.byType(TextField)).last).controller!.text,
      'Employee123!',
    );
    expect(find.textContaining('Чем XP отличается'), findsOneWidget);
    expect(find.text('Демо'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
