import 'package:flutter/widgets.dart';

import 'package:pindoro/l10n/app_localizations.dart';

extension L10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

const Map<String, String> _georgianLatin = {
  'ა': 'a', 'ბ': 'b', 'გ': 'g', 'დ': 'd', 'ე': 'e', 'ვ': 'v', 'ზ': 'z', //
  'თ': 't', 'ი': 'i', 'კ': 'k', 'ლ': 'l', 'მ': 'm', 'ნ': 'n', 'ო': 'o', //
  'პ': 'p', 'ჟ': 'zh', 'რ': 'r', 'ს': 's', 'ტ': 't', 'უ': 'u', 'ფ': 'p', //
  'ქ': 'k', 'ღ': 'gh', 'ყ': 'q', 'შ': 'sh', 'ჩ': 'ch', 'ც': 'ts', 'ძ': 'dz', //
  'წ': 'ts', 'ჭ': 'ch', 'ხ': 'kh', 'ჯ': 'j', 'ჰ': 'h',
};

/// Georgian letters in the national romanisation ("ვაკე" → "vake"), so a
/// Latin keyboard finds Georgian names.
String latinGeorgian(String s) =>
    s.split('').map((ch) => _georgianLatin[ch] ?? ch).join();

/// Groups of three with a narrow no-break space: "3 555" (copy deck format).
String formatNumber(int n) {
  final digits = n.abs().toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    groups.insert(0, digits.substring(end - 3 < 0 ? 0 : end - 3, end));
  }
  return '${n < 0 ? '−' : ''}${groups.join(' ')}';
}

/// Whole metres below 100 m ("84 m"), then up to the next 10 m ("850 m"),
/// from 1 km km with one decimal ("1.2 km"); Georgian uses a decimal comma
/// and its own units ("1,2 კმ"). Rounding up keeps a distance on its tier's
/// side of the limits, which are all multiples of 10 m.
String formatDistance(double metres, Locale locale) {
  final ka = locale.languageCode == 'ka';
  final m = metres < 99.5 ? metres.round() : (metres / 10).ceil() * 10;
  if (m < 1000) return '$m ${ka ? 'მ' : 'm'}';
  final km = (metres / 1000).toStringAsFixed(1);
  return ka ? '${km.replaceFirst('.', ',')} კმ' : '$km km';
}

/// "500 m", "1.5 km", "3 km": an area dimension (one decimal, no ".0").
String formatSize(double metres, Locale locale) {
  final ka = locale.languageCode == 'ka';
  if (metres < 999.5) return '${metres.round()} ${ka ? 'მ' : 'm'}';
  return '${_km(metres, ka)} ${ka ? 'კმ' : 'km'}';
}

/// "2.6 × 3 km": a rectangle's sides.
String formatSides(double width, double height, Locale locale) {
  final ka = locale.languageCode == 'ka';
  return '${_km(width, ka)} × ${_km(height, ka)} ${ka ? 'კმ' : 'km'}';
}

/// "1.3 MB" (one decimal) for a download size.
String formatMegabytes(int bytes, Locale locale) {
  final ka = locale.languageCode == 'ka';
  final mb = (bytes / 1e6).toStringAsFixed(1);
  return ka ? '${mb.replaceFirst('.', ',')} მბ' : '$mb MB';
}

String _km(double metres, bool ka) {
  final km = (metres / 1000)
      .toStringAsFixed(1)
      .replaceFirst(RegExp(r'\.0$'), '');
  return ka ? km.replaceFirst('.', ',') : km;
}

/// "5 min", "2 h", "3 d" for how long ago something happened.
String formatAgo(Duration ago, AppLocalizations l10n) {
  if (ago.inMinutes < 60) return l10n.unitMinutes(ago.inMinutes.clamp(1, 59));
  if (ago.inHours < 24) return l10n.unitHours(ago.inHours);
  return l10n.unitDays(ago.inDays);
}
