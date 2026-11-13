import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pindoro/core/config.dart';

/// The one client every API feature calls through; tests override it with a
/// `MockClient`.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(AppConfig.apiBaseUrl),
);

/// A failed API call: [status] is null when the server wasn't reached, and
/// a 2xx one when its answer didn't parse.
class ApiException implements Exception {
  const ApiException([this.status]);

  final int? status;

  bool get offline => status == null;

  /// The token is unknown: gone on the server, or signed in elsewhere.
  bool get unknownToken => status == 401;

  @override
  String toString() => 'ApiException($status)';
}

typedef ReadJson<T> = T Function(Map<String, Object?> body);

/// Calls to the Pindoro API (docs: `shared/openapi/openapi.json`), with an
/// optional bearer token. Every failure is an [ApiException].
class ApiClient {
  ApiClient(this._baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 10);

  /// Backups are bigger than any JSON call.
  static const Duration _bytesTimeout = Duration(seconds: 60);

  /// Sends [body] as JSON and [read]s the JSON answer.
  Future<T> json<T>(
    String method,
    String path,
    ReadJson<T> read, {
    String? token,
    Map<String, Object?>? body,
  }) async {
    final request = _request(method, path, token);
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _readJson(await _send(request, _timeout), read);
  }

  /// PUTs raw [bytes] and [read]s the JSON answer.
  Future<T> upload<T>(
    String path,
    Uint8List bytes,
    ReadJson<T> read, {
    required String token,
  }) async {
    final request = _request('PUT', path, token)
      ..headers['content-type'] = 'application/octet-stream'
      ..bodyBytes = bytes;
    return _readJson(await _send(request, _bytesTimeout), read);
  }

  /// The raw answer to a GET.
  Future<Uint8List> download(String path, {required String token}) async =>
      (await _send(_request('GET', path, token), _bytesTimeout)).bodyBytes;

  http.Request _request(String method, String path, String? token) {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'));
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    return request;
  }

  Future<http.Response> _send(http.Request request, Duration limit) async {
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _client.send(request).timeout(limit),
      ).timeout(limit);
    } on Exception {
      throw const ApiException();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode);
    }
    return res;
  }

  /// Any answer [read] can't parse fails like a server error.
  T _readJson<T>(http.Response res, ReadJson<T> read) {
    try {
      return read(
        res.body.isEmpty
            ? const {}
            : jsonDecode(res.body) as Map<String, Object?>,
      );
    } on Object {
      throw ApiException(res.statusCode);
    }
  }
}
