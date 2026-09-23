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

CareerApi client({String role = 'employee', bool Function()? expired}) =>
    CareerApi(
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
      expect(find.textContaining('Твой следующий шаг'), findsOneWidget);
      expect(find.text('Загрузка данных'), findsNothing);
      await nav(t, 'Мой план');
      expect(find.text('Твой план'), findsWidgets);
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
  testWidgets(
    'Landing contains FAQ, advantages, footer and no saved password',
    (t) async {
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
        isEmpty,
      );
      expect(find.textContaining('Чем XP отличается'), findsOneWidget);
      expect(find.text('Демо'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
