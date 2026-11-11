import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';

/// This install's version and build number, from `pubspec.yaml`.
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// Where to download a newer sideload build than this one, when the catalog
/// lists one; null when this is the newest build. Sideloaded installs never
/// update themselves, so this is how friends hear about a new one.
final appUpdateProvider = FutureProvider<Uri?>((ref) async {
  // The catalog's build is the Android APK; SideStore offers iOS updates.
  if (defaultTargetPlatform == TargetPlatform.iOS) return null;
  final info = await ref.watch(packageInfoProvider.future);
  final latest = await ref.watch(packStoreProvider).latestApp();
  final build = int.tryParse(info.buildNumber) ?? 0;
  return latest != null && latest.build > build ? latest.url : null;
}, retry: (_, _) => null);
