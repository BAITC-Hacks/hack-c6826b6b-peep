import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class UploadFile {
  const UploadFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class CareerApi {
  CareerApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment('API_BASE_URL', defaultValue: '');
  final http.Client _client;
  final String baseUrl;
  String? token;
  VoidCallback? onUnauthorized;

  Uri _uri(String path) {
    final origin = baseUrl.isNotEmpty
        ? baseUrl
        : (kIsWeb ? Uri.base.origin : 'http://127.0.0.1:8000');
    return Uri.parse('$origin$path');
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
    if (body != null) request.body = jsonEncode(body);
    return _send(request, isLogin: path == '/api/auth/login');
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final result = await request('POST', '/api/auth/login', {
      'username': username,
      'password': password,
    });
    token = result['token'] as String;
    return Map<String, dynamic>.from(result['user']);
  }

  Future<void> logout() async {
    // Capture the old Authorization header before removing local access.
    final revocation = request('POST', '/api/auth/logout');
    token = null;
    await revocation;
  }

  Future<Map<String, dynamic>> previewImport({
    UploadFile? employees,
    UploadFile? history,
    required String policy,
  }) {
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/hr/import/preview'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['conflict_policy'] = policy;
    if (employees != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'employees_file',
          employees.bytes,
          filename: employees.name,
        ),
      );
    }
    if (history != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'history_file',
          history.bytes,
          filename: history.name,
        ),
      );
    }
    return _send(request);
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
        final detail = data['detail'];
        throw ApiException(
          detail is String ? detail : 'Не удалось выполнить действие. Проверьте данные и попробуйте ещё раз.',
          response.statusCode,
        );
      }
      return data;
    } on TimeoutException {
      throw ApiException(
        'Ответ занял слишком много времени. Попробуйте ещё раз.',
      );
    } on http.ClientException {
      throw ApiException(
        'Не удалось соединиться. Проверьте подключение и повторите попытку.',
      );
    } on FormatException {
      throw ApiException('Не удалось прочитать ответ. Попробуйте ещё раз.');
    }
  }

  void dispose() => _client.close();
}

class ApiException implements Exception {
  ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
