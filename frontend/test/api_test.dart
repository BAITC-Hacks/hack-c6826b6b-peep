import 'dart:async';
import 'dart:convert';

import 'package:career_quest/core/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Slow logout cannot clear a newer session', () async {
    final pending = Completer<http.Response>();
    final api = CareerApi(
      baseUrl: 'http://test',
      client: MockClient((r) async => pending.future),
    );
    addTearDown(api.dispose);
    api.token = 'old';
    final logout = api.logout();
    expect(api.token, isNull);
    api.token = 'new';
    pending.complete(http.Response('{}', 200));
    await logout;
    expect(api.token, 'new');
  });
  test('Stale unauthorized response cannot clear another account', () async {
    final pending = Completer<http.Response>();
    var expired = false;
    final api = CareerApi(
      baseUrl: 'http://test',
      client: MockClient((r) async => pending.future),
    );
    addTearDown(api.dispose);
    api.token = 'old';
    api.onUnauthorized = () => expired = true;
    final request = api.get('/api/me/profile');
    api.token = 'new';
    final assertion = expectLater(request, throwsA(isA<ApiException>()));
    pending.complete(http.Response('{}', 401));
    await assertion;
    expect(api.token, 'new');
    expect(expired, isFalse);
  });
  test(
    'Mutations include revision and UUID, and consume response envelope',
    () async {
      var calls = 0;
      final api = CareerApi(
        baseUrl: 'http://test',
        client: MockClient((r) async {
          if (calls++ > 0) {
            expect(jsonDecode(r.body)['expected_revision'], 7);
            expect(
              r.headers['Idempotency-Key'],
              matches(RegExp(r'^[a-f0-9-]{36}$')),
            );
            expect(r.headers['Authorization'], 'Bearer session');
          }
          return http.Response(
            jsonEncode({
              'data': {'saved': true},
              'meta': {'state_revision': 7},
            }),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      api.token = 'session';
      await api.get('/api/me/profile');
      expect(api.stateRevision, 7);
      expect(
        await api.request('POST', '/api/me/plan/items', {'activity_id': 'sql'}),
        {'saved': true},
      );
    },
  );
  test('Business conflict has code and preserves session', () async {
    final api = CareerApi(
      baseUrl: 'http://test',
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'error': {'code': 'STALE_STATE', 'message': 'Обновите данные'},
          }),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(api.dispose);
    api.token = 'session';
    await expectLater(
      api.request('POST', '/api/me/plan/items', {'activity_id': 'sql'}),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'STALE_STATE')),
    );
    expect(api.token, 'session');
  });
  test(
    'Network retry preserves UUID and original body across refreshed revision',
    () async {
      var calls = 0;
      String? key;
      String? body;
      final api = CareerApi(
        baseUrl: 'http://test',
        client: MockClient((r) async {
          if (calls++ == 0) {
            key = r.headers['Idempotency-Key'];
            body = r.body;
            throw http.ClientException('offline');
          }
          expect(r.headers['Idempotency-Key'], key);
          expect(r.body, body);
          return http.Response(
            '{"data":{"ok":true},"meta":{"state_revision":8}}',
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      api.token = 'session';
      api.stateRevision = 7;
      await expectLater(
        api.request('POST', '/api/me/shop/orders', {'item_id': 'x'}),
        throwsA(isA<ApiException>()),
      );
      api.stateRevision = 9;
      await api.request('POST', '/api/me/shop/orders', {'item_id': 'x'});
      expect(api.stateRevision, 9);
    },
  );
}
