import 'dart:io';
import 'dart:typed_data';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:sqlite3/sqlite3.dart';

/// Writes a photo pack (docs/pack-format.md) holding [images] into [dir];
/// each WebP is a few placeholder bytes.
File writePhotoPack(Directory dir, List<SceneImage> images) {
  final file = File('${dir.path}/photos.sqlite');
  final db = sqlite3.open(file.path);
  try {
    db
      ..execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
      ..execute("INSERT INTO meta VALUES ('format_version', '1')")
      ..execute('''
        CREATE TABLE scene_image (
          id TEXT PRIMARY KEY, junction_node INTEGER NOT NULL,
          approach_node INTEGER NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL,
          heading REAL NOT NULL, distance_m REAL NOT NULL, captured_at TEXT,
          source TEXT NOT NULL, licence TEXT NOT NULL, author TEXT NOT NULL,
          link TEXT, width INTEGER NOT NULL, height INTEGER NOT NULL,
          webp BLOB NOT NULL)''');
    final insert = db.prepare(
      'INSERT INTO scene_image VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
      '960, 540, ?)',
    );
    for (final i in images) {
      insert.execute([
        i.id,
        i.junctionNode,
        i.approachNode,
        i.at.lat,
        i.at.lon,
        i.heading,
        i.distanceM,
        i.capturedAt?.toIso8601String(),
        i.source,
        i.licence,
        i.author,
        i.link,
        Uint8List.fromList([0x52, 0x49, 0x46, 0x46]),
      ]);
    }
    insert.close();
  } finally {
    db.close();
  }
  return file;
}
