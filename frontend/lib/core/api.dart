import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final runtimeConfiguration = ValueNotifier<Map<String, dynamic>>({});

class CareerApi {
  CareerApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment('API_BASE_URL', defaultValue: '');
  final http.Client _client;
  final String baseUrl;
  String? token;
  int stateRevision = 0;
  final Map<String, String> _pendingKeys = {};
  VoidCallback? onUnauthorized;
  Future<void> refreshConfiguration() async {
    final value = await get('/api/runtime-config');
    if (value['config_version'] !=
        runtimeConfiguration.value['config_version']) {
      runtimeConfiguration.value = value;
    }
  }

  Uri _uri(String path) {
    final origin = baseUrl.isNotEmpty ? baseUrl : _defaultOrigin();
    return Uri.parse('$origin$path');
  }

  String _defaultOrigin() {
    if (!kIsWeb) return 'http://127.0.0.1:8000';
    // A release build is served by FastAPI and uses the same origin. During
    // `flutter run`, the web dev server is separate, so use the local API
    // without requiring an easy-to-forget --dart-define flag.
    if (kDebugMode) return 'http://127.0.0.1:8000';
    return Uri.base.origin;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> get(String path) => request('GET', path);
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final request = http.Request(method, _uri(path))..headers.addAll(_headers);
    final mutation =
        method != 'GET' &&
        !path.startsWith('/api/auth/') &&
        path != '/api/me/simulations' &&
        path != '/api/me/assistant/explain' &&
        !(path.startsWith('/api/admin/') &&
            (path.endsWith('/simulate') || path.endsWith('/test')));
    final payload = body == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(body);
    if (mutation && method != 'DELETE') {
      payload.putIfAbsent('expected_revision', () => stateRevision);
    }
    if (body != null || mutation && method != 'DELETE') {
      request.body = jsonEncode(payload);
    }
    final signature = '$method:$path:${request.body}';
    if (mutation) {
      request.headers['Idempotency-Key'] = _pendingKeys.putIfAbsent(
        signature,
        _uuid,
      );
    }
    try {
      final result = await _send(request, isLogin: path == '/api/auth/login');
      _pendingKeys.remove(signature);
      return result;
    } on ApiException catch (e) {
      if (e.statusCode != null) _pendingKeys.remove(signature);
      rethrow;
    }
  }

  String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<Uint8List> download(String path) async {
    final usedToken = token;
    final response = await _client
        .get(_uri(path), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 && token == usedToken) {
      token = null;
      onUnauthorized?.call();
    }
    if (response.statusCode != 200) {
      throw ApiException('Не удалось скачать файл', response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> uploadImage(
    Uint8List bytes,
    String name,
    String alt,
  ) async {
    final request = http.MultipartRequest('POST', _uri('/api/admin/media'));
    request.headers.addAll({
      if (token != null) 'Authorization': 'Bearer $token',
      'Idempotency-Key': _uuid(),
    });
    request.fields.addAll({'expected_revision': '$stateRevision', 'alt': alt});
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: name),
    );
    return _send(request);
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final result = await request('POST', '/api/auth/login', {
      'username': username,
      'password': password,
    });
    token = result['token'] as String;
    stateRevision = 0;
    _pendingKeys.clear();
    return Map<String, dynamic>.from(result['user']);
  }

  Future<void> logout() async {
    // Capture the old Authorization header before removing local access.
    final revocation = request('POST', '/api/auth/logout');
    token = null;
    stateRevision = 0;
    _pendingKeys.clear();
    await revocation;
  }

  Future<Map<String, dynamic>> _send(
    http.BaseRequest request, {
    bool isLogin = false,
  }) async {
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
      Map<String, dynamic> data = {};
      if (response.bodyBytes.isNotEmpty) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) data = decoded;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 &&
            !isLogin &&
            token != null &&
            request.headers['Authorization'] == 'Bearer $token') {
          token = null;
          onUnauthorized?.call();
        }
        final detail = data['error']?['message'] ?? data['detail'];
        throw ApiException(
          detail is String ? detail : 'Не удалось выполнить действие. Проверьте данные и попробуйте ещё раз.',
          response.statusCode,
          data['error']?['code'],
        );
      }
      final revision = data['meta']?['state_revision'];
      if (revision is int) stateRevision = max(stateRevision, revision);
      if (data['data'] is Map) return Map<String, dynamic>.from(data['data']);
      return data;
    } on TimeoutException {
      throw ApiException(
        'Ответ занял слишком много времени. Попробуйте ещё раз.',
      );
    } on http.ClientException {
      throw ApiException(
        'Сервис входа сейчас недоступен. Перезапустите приложение и попробуйте снова.',
      );
    } on FormatException {
      throw ApiException('Не удалось прочитать ответ. Попробуйте ещё раз.');
    }
  }

  void dispose() => _client.close();
}

class ApiException implements Exception {
  ApiException(this.message, [this.statusCode, this.code]);
  final String message;
  final int? statusCode;
  final String? code;
  @override
  String toString() => message;
}
