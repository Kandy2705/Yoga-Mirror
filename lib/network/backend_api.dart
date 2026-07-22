import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class BackendApiException implements Exception {
  const BackendApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() {
    return statusCode == null
        ? 'BackendApiException: $message'
        : 'BackendApiException($statusCode): $message';
  }
}

class BackendApi {
  BackendApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String? _accessToken;
  String? _refreshToken; // ignore: unused_field

  String? get accessToken => _accessToken;

  bool get isLoggedIn => _accessToken != null;

  Future<String> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('${ApiConfig.restBaseUrl}${ApiConfig.loginPath}');

    final response = await _client.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final body = _decodeResponse(response);

    if (body is! Map<String, dynamic>) {
      throw const BackendApiException(
          'Response dang nhap khong phai JSON object.');
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw BackendApiException(
        'Khong tim thay field data trong response: $body',
        statusCode: response.statusCode,
      );
    }

    final token = data['access_token'] ?? data['token'];
    if (token is! String || token.isEmpty) {
      throw BackendApiException(
        'Khong tim thay access_token. Response: $body',
        statusCode: response.statusCode,
      );
    }

    _accessToken = token;
    _refreshToken = data['refresh_token'] as String?;
    return token;
  }

  Future<List<Map<String, dynamic>>> getAssignedExercises(String date) async {
    final response = await _client.get(
      Uri.parse('${ApiConfig.restBaseUrl}/user-exercises/patient/$date'),
      headers: _authorizedHeaders(),
    );

    final body = _decodeResponse(response);
    final data = body is Map<String, dynamic> ? body['data'] : null;

    if (data is Map<String, dynamic>) {
      final items = data['items'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }

    return [];
  }

  Future<List<Map<String, dynamic>>> getExercises({int limit = 3}) async {
    final response = await _client.get(
      Uri.parse('${ApiConfig.restBaseUrl}/exercises?limit=$limit'),
      headers: _authorizedHeaders(),
    );

    final body = _decodeResponse(response);
    final data = body is Map<String, dynamic> ? body['data'] : null;

    if (data is Map<String, dynamic>) {
      final items = data['items'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }

    return [];
  }

  Map<String, String> _authorizedHeaders() {
    final token = _accessToken;
    if (token == null) {
      throw const BackendApiException('Chua dang nhap.');
    }
    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  dynamic _decodeResponse(http.Response response) {
    dynamic body;
    try {
      body = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      body = response.body;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendApiException(
        'Request that bai: $body',
        statusCode: response.statusCode,
      );
    }

    return body;
  }

  Future<Map<String, dynamic>> downloadJson(String url) async {
    final response = await _client.get(Uri.parse(url));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendApiException(
        'Tai JSON that bai: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const BackendApiException('JSON tu S3 khong phai object.');
    }
    return body;
  }

  void close() {
    _client.close();
  }
}
