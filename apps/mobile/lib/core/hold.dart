import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

extension HoldFuture on Ref {
  /// [provider]'s value, held while it loads: an auto-dispose provider that
  /// nothing watches would go away first.
  Future<T> hold<T>(ProviderListenable<Future<T>> provider) async {
    final sub = listen(provider, (_, _) {});
    try {
      return await sub.read();
    } finally {
      sub.close();
    }
  }
}
