import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:sqlite3/sqlite3.dart';

/// A city's street photos (docs/pack-format.md, photo pack), opened
/// read-only: the images up front, each WebP when shown.
class PhotoPack {
  PhotoPack.open(String path)
    : _db = sqlite3.open(path, mode: OpenMode.readOnly);

  final Database _db;

  late final List<SceneImage> images = List.unmodifiable([
    for (final r in _db.select(
      'SELECT id, junction_node, approach_node, lat, lon, heading, distance_m, '
      'captured_at, source, licence, author, link FROM scene_image ORDER BY id',
    ))
      SceneImage.fromRow(r),
  ]);

  Uint8List? webp(String id) =>
      switch (_db.select('SELECT webp FROM scene_image WHERE id = ?', [id])) {
        final rows when rows.isNotEmpty => rows.first['webp'] as Uint8List,
        _ => null,
      };

  void close() => _db.close();
}

/// The open city's photo pack; null until Street photos downloads one.
final photoPackProvider = FutureProvider<PhotoPack?>((ref) async {
  final city = (await ref.watch(packRepositoryProvider.future)).city().id;
  final file = ref.watch(packStoreProvider).photos(city);
  if (file == null) return null;
  final photos = PhotoPack.open(file.path);
  ref.onDispose(photos.close);
  return photos;
});

/// The WebP of scene image [id], read once per showing.
final scenePhotoProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>(
      (ref, id) async => (await ref.watch(photoPackProvider.future))?.webp(id),
    );

/// How a Street photos download ended.
enum PhotosOutcome { installed, none, failed }

/// Street photos on (board V3-60): downloads the open city's photo pack,
/// its progress (0–1) as the state while it runs; off deletes it.
final photosDownloadProvider = NotifierProvider<PhotosDownload, double?>(
  PhotosDownload.new,
);

class PhotosDownload extends Notifier<double?> {
  @override
  double? build() => null;

  Future<PhotosOutcome> turnOn() async {
    state = 0;
    try {
      final city = (await ref.read(packRepositoryProvider.future)).city().id;
      final file = await ref
          .read(packStoreProvider)
          .refreshPhotos(
            city,
            onProgress: (p) => state = p.total == 0 ? 0 : p.received / p.total,
          );
      ref.invalidate(photoPackProvider);
      return file == null ? PhotosOutcome.none : PhotosOutcome.installed;
    } on Object catch (e) {
      if (kDebugMode) debugPrint('photo pack download failed: $e');
      return PhotosOutcome.failed;
    } finally {
      state = null;
    }
  }

  Future<void> turnOff() async {
    final city = (await ref.read(packRepositoryProvider.future)).city().id;
    ref.read(packStoreProvider).removePhotos(city);
    ref.invalidate(photoPackProvider);
  }
}
