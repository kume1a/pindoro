import 'package:flutter/material.dart';

import '../../app/placeholder_screen.dart';
import '../map/pindoro_map.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
    title: 'Settings',
    body:
        'Map and street data $osmAttribution (ODbL). '
        'Font FiraGO (SIL Open Font License).',
  );
}
