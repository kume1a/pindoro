import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pindoro/core/api_client.dart';

ApiClient _answering(Future<http.Response> Function(http.Request) reply) =>
    ApiClient('https://api.example', client: MockClient(reply));

Map<String, Object?> _body(Map<String, Object?> body) => body;

void main() {
  test('sends JSON with the token and reads the answer', () async {
    late http.Request sent;
    final api = _answering((request) async {
      sent = request;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final ok = await api.json(
      'POST',
      '/v1/x',
      token: 't0k',
      body: {'a': 1},
      (body) => body['ok']! as bool,
    );
    expect(ok, isTrue);
    expect(sent.url.toString(), 'https://api.example/v1/x');
    expect(sent.headers['authorization'], 'Bearer t0k');
    expect(sent.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(sent.body), {'a': 1});
  });

  test('uploads and downloads raw bytes', () async {
    late http.Request sent;
    final api = _answering((request) async {
      sent = request;
      return request.method == 'PUT'
          ? http.Response(jsonEncode({'n': request.bodyBytes.length}), 200)
          : http.Response.bytes([1, 2, 3], 200);
    });
    expect(
      await api.upload(
        '/v1/b',
        Uint8List.fromList([9, 9]),
        token: 't',
        (body) => body['n'],
      ),
      2,
    );
    expect(sent.headers['content-type'], 'application/octet-stream');
    expect(await api.download('/v1/b', token: 't'), [1, 2, 3]);
  });

  test('an answer that doesn\'t parse fails as a server error', () async {
    final api = _answering((_) async => http.Response('{"x": 1}', 200));
    await expectLater(
      api.json('GET', '/v1/x', (body) => body['y']! as String),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 200)
            .having((e) => e.offline, 'offline', false),
      ),
    );
  });

  test('a failed call carries its status, or none offline', () async {
    await expectLater(
      _answering(
        (_) async => http.Response('', 401),
      ).json('DELETE', '/v1/x', _body),
      throwsA(
        isA<ApiException>().having((e) => e.unknownToken, 'unknown', true),
      ),
    );
    await expectLater(
      _answering(
        (_) => throw http.ClientException('down'),
      ).json('GET', '/v1/x', _body),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', null)),
    );
  });
}
