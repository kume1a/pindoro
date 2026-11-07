import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:pindoro/core/config.dart';

/// Whether the server answers at all (any status counts); false on network
/// errors or after 5 s.
Future<bool> isOnline() async {
  try {
    await http
        .head(Uri.parse('${AppConfig.apiBaseUrl}/health'))
        .timeout(const Duration(seconds: 5));
    return true;
  } on Object {
    return false;
  }
}
