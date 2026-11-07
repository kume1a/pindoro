import 'package:pindoro/features/home/data/home_data.dart';

/// When each part of Home's intro after a round starts (canvas M-43).
abstract final class HomeIntroAt {
  static const Duration xp = Duration(milliseconds: 300);
  static const Duration bar = Duration(milliseconds: 450);
  static const Duration streets = Duration(milliseconds: 950);
  static const Duration settle = Duration(milliseconds: 2600);
}

/// Where the intro's numbers start, and whether its ring and tip still show.
typedef HomeIntro = ({
  int xpBefore,
  int roundXp,
  HomeCounts before,
  bool settled,
});
