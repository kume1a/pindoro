import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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

/// Calls to the Pindoro API (docs: `shared/openapi/openapi.json`), with an
/// optional bearer token. Every failure is an [ApiException].
class ApiClient {
  ApiClient(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const Duration timeout = Duration(seconds: 10);

  /// Backups are bigger than any JSON call.
  static const Duration bytesTimeout = Duration(seconds: 60);

  /// Sends [body] as JSON (or raw [bytes]) and [read]s the JSON answer; any
  /// answer [read] can't parse fails like a server error.
  Future<T> json<T>(
    String method,
    String path,
    T Function(Map<String, Object?> body) read, {
    String? token,
    Map<String, Object?>? body,
    Uint8List? bytes,
  }) async {
    final request = _request(method, path, token);
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (bytes != null) {
      request.headers['content-type'] = 'application/octet-stream';
      request.bodyBytes = bytes;
    }
    final res = await _send(request, bytes == null ? timeout : bytesTimeout);
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

  /// The raw answer to a GET.
  Future<Uint8List> download(String path, {required String token}) async =>
      (await _send(_request('GET', path, token), bytesTimeout)).bodyBytes;

  http.Request _request(String method, String path, String? token) {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
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
}
