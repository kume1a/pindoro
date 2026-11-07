import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:pindoro/l10n/app_localizations.dart';

extension L10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Whether the UI is in Georgian.
  bool get georgian => Localizations.localeOf(this).languageCode == 'ka';

  /// A name kept in both scripts (cities), in the UI's language.
  String localName({required String ka, required String en}) =>
      georgian ? ka : en;
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
/// from 1 km in km with one decimal ("1.2 km"), in the locale's units and
/// decimal separator. Rounding up keeps a distance on its tier's side of the
/// limits, which are all multiples of 10 m.
String formatDistance(double metres, AppLocalizations l10n) {
  final m = metres < 99.5 ? metres.round() : (metres / 10).ceil() * 10;
  if (m < 1000) return l10n.unitMetres('$m');
  return l10n.unitKilometres(_decimal('0.0', metres / 1000, l10n));
}

/// "500 m", "1.5 km", "3 km": an area dimension (one decimal, no ".0").
String formatSize(double metres, AppLocalizations l10n) {
  if (metres < 999.5) return l10n.unitMetres('${metres.round()}');
  return l10n.unitKilometres(_km(metres, l10n));
}

/// "2.6 × 3 km": a rectangle's sides.
String formatSides(double width, double height, AppLocalizations l10n) =>
    l10n.unitKilometres('${_km(width, l10n)} × ${_km(height, l10n)}');

/// "1.3 MB" (one decimal) for a download size.
String formatMegabytes(int bytes, AppLocalizations l10n) =>
    l10n.unitMegabytes(_decimal('0.0', bytes / 1e6, l10n));

String _km(double metres, AppLocalizations l10n) =>
    _decimal('0.#', metres / 1000, l10n);

String _decimal(String pattern, double value, AppLocalizations l10n) =>
    NumberFormat(pattern, l10n.localeName).format(value);

/// "5 min", "2 h", "3 d" for how long ago something happened.
String formatAgo(Duration ago, AppLocalizations l10n) {
  if (ago.inMinutes < 60) return l10n.unitMinutes(ago.inMinutes.clamp(1, 59));
  if (ago.inHours < 24) return l10n.unitHours(ago.inHours);
  return l10n.unitDays(ago.inDays);
}
