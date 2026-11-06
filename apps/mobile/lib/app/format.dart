import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

extension L10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Groups of three with a narrow no-break space: "3 555" (copy deck format).
String formatNumber(int n) {
  final digits = n.abs().toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    groups.insert(0, digits.substring(end - 3 < 0 ? 0 : end - 3, end));
  }
  return '${n < 0 ? '−' : ''}${groups.join(' ')}';
}

/// Metres below 1 km ("84 m"), else km with one decimal ("1.2 km"); Georgian
/// uses a decimal comma and its own units ("1,2 კმ").
String formatDistance(double metres, Locale locale) {
  final ka = locale.languageCode == 'ka';
  if (metres < 999.5) return '${metres.round()} ${ka ? 'მ' : 'm'}';
  final km = (metres / 1000).toStringAsFixed(1);
  return ka ? '${km.replaceFirst('.', ',')} კმ' : '$km km';
}
