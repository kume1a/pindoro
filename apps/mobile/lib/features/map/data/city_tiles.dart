import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// Zooms kept offline: the city whole down to the tiles' own maximum (maps
/// zoomed in further draw from zoom 15).
const double _minZoom = 10;
const double _maxZoom = 15;

/// Cities whose tiles are downloading or downloaded this session.
final _kept = <String>{};

/// Keeps [city]'s map tiles on the phone as a MapLibre offline region, so
/// maps work offline once it has downloaded. Runs in the background; an
/// interrupted download starts over next launch.
Future<void> keepCityTilesOffline(City city) async {
  if (!_kept.add(city.id)) return;
  HttpServer? style;
  try {
    final regions = [
      for (final r in await ml.getListOfRegions())
        if (r.metadata['city'] == city.id) r,
    ];
    if (regions.any((r) => r.metadata['complete'] == true)) return;
    for (final r in regions) {
      await ml.deleteOfflineRegion(r.id);
    }
    // MapLibre fetches a region's style over HTTP only (file:// fails), so
    // the bundled style is served on loopback while the download runs. Both
    // themes share the tiles.
    style = await _serve(await loadMapStyle(Brightness.light));
    final done = Completer<void>();
    final b = city.bbox;
    final region = await ml.downloadOfflineRegion(
      ml.OfflineRegionDefinition(
        bounds: ml.LatLngBounds(
          southwest: ml.LatLng(b.minLat, b.minLon),
          northeast: ml.LatLng(b.maxLat, b.maxLon),
        ),
        mapStyleUrl: 'http://127.0.0.1:${style.port}/style.json',
        minZoom: _minZoom,
        maxZoom: _maxZoom,
      ),
      metadata: {'city': city.id},
      onEvent: (event) => switch (event) {
        ml.Success() => done.complete(),
        ml.Error(:final cause) => done.completeError(cause),
        _ => null,
      },
    );
    await done.future;
    await ml.updateOfflineRegionMetadata(region.id, {
      'city': city.id,
      'complete': true,
    });
  } catch (e) {
    _kept.remove(city.id);
    if (kDebugMode) debugPrint('city tiles for ${city.id} failed: $e');
  } finally {
    await style?.close(force: true);
  }
}

/// A loopback server answering every request with [json].
Future<HttpServer> _serve(String json) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(
    (request) => request.response
      ..headers.contentType = ContentType.json
      ..write(json)
      ..close(),
  );
  return server;
}

/// Starts [keepCityTilesOffline] whenever a downloaded city pack opens,
/// without opening one itself.
final class CityTilesObserver extends ProviderObserver {
  @override
  void didAddProvider(ProviderObserverContext context, Object? value) =>
      _onPack(context, value);

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) => _onPack(context, newValue);

  void _onPack(ProviderObserverContext context, Object? value) {
    if (context.provider != packRepositoryProvider) return;
    if (value case AsyncData(
      value: final PackRepository pack,
    ) when !isFixturePack(pack)) {
      unawaited(keepCityTilesOffline(pack.city()));
    }
  }
}
