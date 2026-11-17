import 'package:pindoro_core/pindoro_core.dart';

import 'names.dart';

/// Lower-case word stems of [street]'s names in either script (SPEC §16.18): a place whose
/// name contains one would give the street away (a metro station named after its avenue), so
/// a question about the street leaves that place unnamed.
Set<String> nameStems(NamedStreet street) => {
  for (final name in nameForms(street))
    for (final word in name.split(' '))
      if (word.length >= _stemLength) word.substring(0, _stemLength),
};

/// Long enough to skip short words ("შოთა"), short enough that "რუსთაველი" and "რუსთაველის"
/// meet.
const int _stemLength = 5;
