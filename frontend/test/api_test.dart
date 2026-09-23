import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:career_quest/core/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Slow logout clears old access immediately without clearing a newer session', () async {
    final pending = Completer<http.Response>();
    final api = CareerApi(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer old-token');
        return pending.future;
      }),
    );
    addTearDown(api.dispose);
    api.token = 'old-token';
    final logout = api.logout();
    expect(api.token, isNull);
    api.token = 'new-token';
    pending.complete(http.Response('{}', 200));
    await logout;
    expect(api.token, 'new-token');
  });

  test('A stale 401 cannot clear a newly authenticated session', () async {
    final pending = Completer<http.Response>();
    var unauthorized = false;
    final api = CareerApi(
      baseUrl: 'http://test',
      client: MockClient((request) async => pending.future),
    );
    addTearDown(api.dispose);
    api.token = 'old-token';
    api.onUnauthorized = () => unauthorized = true;
    final previous = api.get('/api/me/profile');
    api.token = 'new-token';
    final assertion = expectLater(previous, throwsA(isA<ApiException>()));
    pending.complete(http.Response('{"detail":"expired"}', 401));
    await assertion;
    expect(api.token, 'new-token');
    expect(unauthorized, isFalse);
  });

  test(
    'Import sends original file bytes, field names, conflict policy and token',
    () async {
      final api = CareerApi(
        baseUrl: 'http://test',
        client: MockClient((request) async {
          expect(request.url.path, '/api/hr/import/preview');
          expect(request.headers['Authorization'], 'Bearer hr-token');
          expect(
            request.headers['content-type'],
            contains('multipart/form-data'),
          );
          expect(
            request.body,
            contains('name="employees_file"; filename="judge.json"'),
          );
          expect(
            request.body,
            contains('name="history_file"; filename="history.csv"'),
          );
          expect(request.body, contains('name="conflict_policy"'));
          expect(request.body, contains('replace'));
          expect(request.body, contains('{"employees":[]}'));
          return http.Response('{"preview_id":"p1"}', 200);
        }),
      );
      api.token = 'hr-token';
      addTearDown(api.dispose);
      final result = await api.previewImport(
        employees: UploadFile(
          'judge.json',
          Uint8List.fromList(utf8.encode('{"employees":[]}')),
        ),
        history: UploadFile(
          'history.csv',
          Uint8List.fromList(utf8.encode('record_id,employee_id')),
        ),
        policy: 'replace',
      );
      expect(result['preview_id'], 'p1');
    },
  );
  test('Conflict preserves session and returns validation message', () async {
    var unauthorized = false;
    final api = CareerApi(
      baseUrl: 'http://test',
      client: MockClient(
        (request) async =>
            http.Response(jsonEncode({'detail': 'ID conflict: E0001'}), 409),
      ),
    );
    api.token = 'hr-token';
    api.onUnauthorized = () => unauthorized = true;
    addTearDown(api.dispose);
    await expectLater(
      api.request('POST', '/api/hr/import/commit', {'preview_id': 'stale'}),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
    );
    expect(unauthorized, isFalse);
    expect(api.token, 'hr-token');
  });
}
