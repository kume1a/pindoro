import 'package:flutter/material.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Shared M0 layout: title, a line of copy, actions at the bottom.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.child,
  });

  final String title;
  final String body;
  final List<Widget> actions;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(PindoroTokens.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroTokens.spaceMd,
          children: [
            Text(body, style: Theme.of(context).textTheme.bodyLarge),
            Expanded(child: child ?? const SizedBox()),
            ...actions,
          ],
        ),
      ),
    ),
  );
}
