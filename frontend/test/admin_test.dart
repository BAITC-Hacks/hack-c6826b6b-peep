import 'dart:convert';

import 'package:career_quest/core/api.dart';
import 'package:career_quest/features/admin/admin_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final width in [360.0, 1440.0]) {
    testWidgets('Admin overview and pass publication at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rewards = List.generate(
        100,
        (i) => <String, dynamic>{
          'level': i + 1,
          'required_total_xp': 200 * (i + 1),
          'components': [
            {'type': 'coins', 'coins': 5, 'name': '5 CQ'},
          ],
        },
      );
      final calls = <String>[];
      Map<String, dynamic>? saved;
      final season = {
        'id': 's1',
        'name': 'Тестовый сезон',
        'status': 'active',
        'starts_at': '2026-09-01',
        'ends_at': '2026-12-01',
        'totals': {'roster': 2, 'levels': 100, 'total_kzt': 1200000},
      };
      final api = CareerApi(
        baseUrl: 'http://test',
        client: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          dynamic data = {};
          switch (request.url.path) {
            case '/api/admin/overview':
              data = {
                'modules': [
                  {
                    'id': 'seasons',
                    'title': 'Сезоны и пропуск',
                    'group': 'Геймификация',
                    'path': 'seasons',
                  },
                ],
                'counts': {'employees': 2},
                'drafts': 0,
                'current_season': season,
              };
            case '/api/admin/seasons':
              data = {
                'items': [season],
              };
            case '/api/admin/seasons/s1/pass':
              if (request.method == 'GET') {
                data = {
                  'value': {'rewards': rewards},
                  'schema': {
                    r'$defs': {
                      'PassLevel': {
                        'type': 'object',
                        'properties': {
                          'level': {'type': 'integer', 'minimum': 1},
                          'required_total_xp': {
                            'type': 'integer',
                            'minimum': 1,
                          },
                          'components': {
                            'type': 'array',
                            'items': {
                              'type': 'object',
                              'properties': {
                                'type': {'const': 'coins'},
                                'coins': {'type': 'integer', 'minimum': 1},
                                'name': {'type': 'string'},
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                };
              } else {
                saved = jsonDecode(request.body);
                data = {
                  'id': 'c1',
                  'domain': 'pass',
                  'reason': 'Тест публикации',
                };
              }
            case '/api/admin/changes/c1/preview':
              data = {
                'preview_id': 'p1',
                'base_revision': 4,
                'can_publish': true,
                'xp_delta': 0,
                'coin_delta': 0,
                'budget_delta_kzt': 0,
                'blocking_errors': [],
              };
            case '/api/admin/changes/c1/publish':
              data = {'status': 'applied'};
          }
          return http.Response(
            jsonEncode({
              'data': data,
              'meta': {'state_revision': request.method == 'GET' ? 1 : 4},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..token = 'test-token';
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            splashFactory: InkRipple.splashFactory,
          ),
          home: AdminShell(
            api: api,
            user: {
              'display_name': 'Admin',
              'role': 'super_admin',
              'capabilities': [
                'seasons.manage',
                'pass.manage',
                'economy.publish',
              ],
            },
            initialRoute: '/admin/seasons',
            onLogout: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Редактор пропуска'));
      await tester.tap(find.text('Редактор пропуска'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('200 XP'));
      await tester.pumpAndSettle();
      final threshold = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Накопительный порог XP',
      );
      await tester.enterText(threshold, '150');
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Сохранить и проверить'));
      await tester.tap(find.text('Сохранить и проверить'));
      await tester.pumpAndSettle();
      expect(find.text('Предпросмотр публикации'), findsOneWidget);
      await tester.ensureVisible(find.text('Опубликовать'));
      await tester.tap(find.text('Опубликовать'));
      await tester.pumpAndSettle();
      expect(saved?['payload']['rewards'][0]['required_total_xp'], 150);
      expect(calls, contains('POST /api/admin/changes/c1/publish'));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('SKU form saves a server draft before publication', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? saved;
    bool published = false;
    final api = CareerApi(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        dynamic data = {};
        if (request.url.path == '/api/admin/overview') {
          data = {
            'modules': [
              {
                'id': 'shop',
                'title': 'Каталог наград',
                'group': 'Награды',
                'path': 'shop/items',
              },
            ],
            'counts': {},
            'current_season': {},
            'drafts': 0,
          };
        }
        if (request.url.path == '/api/admin/shop/items') {
          if (request.method == 'GET') {
            data = {
              'schema': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'string'},
                  'name': {'type': 'string', 'minLength': 1},
                  'coin_price': {'type': 'integer', 'minimum': 1},
                },
              },
              'items': [
                {'id': 'phone', 'name': 'Телефон', 'coin_price': 500},
              ],
              'total': 1,
            };
          } else {
            saved = jsonDecode(request.body);
            data = {'id': 'c2', 'domain': 'shop', 'reason': 'Тест цены'};
          }
        }
        if (request.url.path.endsWith('/preview')) {
          data = {
            'preview_id': 'p2',
            'base_revision': 3,
            'can_publish': true,
            'xp_delta': 0,
            'coin_delta': 0,
            'budget_delta_kzt': 0,
            'blocking_errors': [],
          };
        }
        if (request.url.path.endsWith('/publish')) {
          published = true;
          data = {'status': 'applied'};
        }
        return http.Response(
          jsonEncode({
            'data': data,
            'meta': {'state_revision': 3},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..token = 'test-token';
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          splashFactory: InkRipple.splashFactory,
        ),
        home: AdminShell(
          api: api,
          user: {
            'role': 'admin',
            'display_name': 'Admin',
            'capabilities': ['shop.manage'],
          },
          initialRoute: '/admin/shop',
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Телефон'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Цена, CQ',
      ),
      '750',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.labelText == 'Основание изменения',
      ),
      'Обновление цены на будущие заказы',
    );
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(saved?['payload']['coin_price'], 750);
    expect(published, isFalse);
    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();
    expect(published, isTrue);
    expect(tester.takeException(), isNull);
  });
}
