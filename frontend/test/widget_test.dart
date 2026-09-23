import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:career_quest/core/api.dart';
import 'package:career_quest/main.dart';

Map<String, dynamic> profile({bool suggested = false}) => {
  'employee': {
    'employee_id': 'E0001',
    'full_name': 'Marat Yessenov',
    'department': 'Backend Development',
    'role': 'Backend Engineer',
    'grade': 'Junior',
    'hire_date': '2025-01-01',
    'work_format': 'hybrid',
    'last_review_date': '2026-09-01',
  },
  'goal': suggested
      ? null
      : {'target_role': 'Backend Engineer', 'target_grade': 'Middle'},
  'goal_source': suggested ? 'suggested' : 'dataset',
  'suggested_goal': suggested
      ? {'target_role': 'Backend Engineer', 'target_grade': 'Middle'}
      : null,
  'skills': [
    {
      'skill_id': 'SK_PYTHON',
      'name': 'Python',
      'assessed_level': 2,
      'required_level': 3,
      'critical': true,
    },
  ],
  'history': [
    {
      'record_id': 'R1',
      'title': 'Secure Coding Workshop',
      'date': '2026-09-02',
      'status': 'completed',
      'score': 80,
      'mandatory': true,
    },
  ],
  'stats': {
    'completed': 1,
    'in_progress': 0,
    'total': 1,
    'mandatory_pending': 0,
  },
};
http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<void> login(WidgetTester tester, String role) async {
  await tester.ensureVisible(find.text(role));
  await tester.tap(find.text(role));
  await tester.ensureVisible(find.text('Войти'));
  await tester.tap(find.text('Войти'));
  await tester.pumpAndSettle();
}

void size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'Narrow HR screen supports directory, profile and import without overflow',
    (tester) async {
      size(tester, const Size(320, 760));
      final api = CareerApi(
        baseUrl: 'http://test',
        client: MockClient((request) async {
          if (request.url.path == '/api/auth/login') {
            return response({
              'token': 'hr-token',
              'user': {'role': 'hr', 'display_name': 'HR Demo'},
            });
          }
          if (request.url.path == '/api/hr/employees') {
            return response({
              'employees': [
                {...profile()['employee'], 'has_goal': true},
              ],
              'total': 1,
            });
          }
          return response(profile());
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(CareerQuestApp(api: api));
      await login(tester, 'HR');
      await tester.ensureVisible(find.text('Marat Yessenov'));
      await tester.tap(find.text('Marat Yessenov'));
      await tester.pumpAndSettle();
      expect(find.text('Профиль сотрудника'), findsOneWidget);
      await tester.tap(find.text('Загрузка данных'));
      await tester.pumpAndSettle();
      expect(find.text('Какие данные добавить?'), findsOneWidget);
      await tester.ensureVisible(find.text('Проверить файлы'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Mobile employee uses token and sees suggestion, own profile and history',
    (tester) async {
      size(tester, const Size(390, 844));
      var authenticated = false;
      final api = CareerApi(
        baseUrl: 'http://test',
        client: MockClient((request) async {
          if (request.url.path == '/api/auth/login') {
            expect(jsonDecode(request.body)['username'], 'employee.demo');
            return response({
              'token': 'employee-token',
              'user': {
                'role': 'employee',
                'display_name': 'Marat Yessenov',
                'employee_id': 'E0001',
              },
            });
          }
          authenticated =
              request.headers['Authorization'] == 'Bearer employee-token';
          return response(profile(suggested: true));
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(CareerQuestApp(api: api));
      await login(tester, 'Сотрудник');
      expect(authenticated, isTrue);
      expect(find.text('Marat Yessenov'), findsOneWidget);
      expect(find.text('ВОЗМОЖНОЕ НАПРАВЛЕНИЕ'), findsOneWidget);
      expect(find.text('Загрузка данных'), findsNothing);
      expect(find.textContaining('FastAPI'), findsNothing);

      await tester.tap(find.text('История развития'));
      await tester.pumpAndSettle();
      expect(find.text('Secure Coding Workshop'), findsOneWidget);
    },
  );
  testWidgets('Expired session removes personal data and returns to login', (
    tester,
  ) async {
    var reads = 0;
    final api = CareerApi(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return response({
            'token': 'token',
            'user': {'role': 'employee', 'display_name': 'Marat Yessenov'},
          });
        }
        if (reads++ > 0) return response({'detail': 'Session expired'}, 401);
        return response(profile());
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(CareerQuestApp(api: api));
    await login(tester, 'Сотрудник');
    await tester.tap(find.byTooltip('Обновить профиль'));
    await tester.pumpAndSettle();
    expect(find.text('Рады видеть вас'), findsOneWidget);
    expect(find.text('Marat Yessenov'), findsNothing);
    expect(api.token, isNull);
  });
  testWidgets('Goal selection saves through API and replaces suggestion', (
    tester,
  ) async {
    size(tester, const Size(1280, 1000));
    var saved = false;
    final api = CareerApi(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return response({
            'token': 'token',
            'user': {'role': 'employee', 'display_name': 'Marat Yessenov'},
          });
        }
        if (request.url.path == '/api/meta') {
          return response({
            'roles': [
              {'role': 'Backend Engineer', 'grade': 'Middle'},
            ],
          });
        }
        if (request.method == 'PUT') {
          expect(request.url.path, '/api/me/goal');
          expect(jsonDecode(request.body), {
            'target_role': 'Backend Engineer',
            'target_grade': 'Middle',
          });
          saved = true;
          return response({...profile(), 'goal_source': 'personal'});
        }
        return response(profile(suggested: true));
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(CareerQuestApp(api: api));
    await login(tester, 'Сотрудник');
    await tester.tap(find.byTooltip('Изменить карьерную цель'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить цель'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(find.text('ВОЗМОЖНОЕ НАПРАВЛЕНИЕ'), findsNothing);
    expect(find.text('КАРЬЕРНАЯ ЦЕЛЬ'), findsOneWidget);
  });
  testWidgets('HR opens profile and import without employee goal controls', (
    tester,
  ) async {
    size(tester, const Size(1280, 1000));
    final api = CareerApi(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return response({
            'token': 'hr-token',
            'user': {'role': 'hr', 'display_name': 'HR Demo'},
          });
        }
        if (request.url.path == '/api/hr/employees') {
          return response({
            'employees': [
              {...profile()['employee'], 'has_goal': true},
            ],
            'total': 1,
          });
        }
        return response(profile());
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(CareerQuestApp(api: api));
    await login(tester, 'HR');
    expect(find.text('Люди и их направления'), findsOneWidget);
    await tester.tap(find.text('Marat Yessenov'));
    await tester.pumpAndSettle();
    expect(find.text('Профиль сотрудника'), findsOneWidget);
    expect(find.byTooltip('Изменить карьерную цель'), findsNothing);
    await tester.tap(find.text('Загрузка данных'));
    await tester.pumpAndSettle();
    expect(find.text('Какие данные добавить?'), findsOneWidget);
    expect(find.text('Проверить файлы'), findsOneWidget);
  });
  testWidgets('Invalid password cannot enter workspace', (tester) async {
    final api = CareerApi(
      baseUrl: 'http://test',
      client: MockClient(
        (request) async =>
            response({'detail': 'Неверный логин или пароль'}, 401),
      ),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(CareerQuestApp(api: api));
    await login(tester, 'Сотрудник');
    expect(find.text('Неверный логин или пароль'), findsOneWidget);
    expect(find.text('Рады видеть вас'), findsOneWidget);
    expect(api.token, isNull);
  });
}
