import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'choices.dart';
import 'tray_frame.dart';

/// A graded question: the index picked and the right one.
typedef AnswerResult = ({int picked, int right});

/// The question tray docked over the map (Answer choices): the [question]
/// and its [meta] ("6 names"), four to six [choices] in a grid of equal rows
/// (one column, numbered, when a name doesn't fit half the width), then
/// [confirmLabel]. A tap selects, Confirm grades ([onConfirm] with the
/// index). With [result] set the choices show the right one and a wrong
/// pick, and take no input; the app swaps in the reveal sheet after 600 ms.
/// The handle drags it down to a peek. Give each question its own key: the
/// selection lives here.
class AnswerTray extends StatefulWidget {
  const AnswerTray({
    super.key,
    required this.question,
    required this.meta,
    required this.choices,
    required this.confirmLabel,
    required this.onConfirm,
    this.confirmHint,
    this.result,
    this.skip,
  });

  final String question;
  final String meta;
  final List<AnswerChoiceData> choices;
  final String confirmLabel;
  final ValueChanged<int> onConfirm;

  /// What a screen reader hears on the disabled Confirm ("Pick a name
  /// first.").
  final String? confirmHint;

  /// [AnswerResult.picked] is -1 when the player skipped (only the right one shows).
  final AnswerResult? result;

  /// A way out under Confirm ("I don't know"), until the question is graded.
  final TraySkip? skip;

  @override
  State<AnswerTray> createState() => _AnswerTrayState();
}

class _AnswerTrayState extends State<AnswerTray> {
  int? _selected;

  @override
  void didUpdateWidget(AnswerTray old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.choices, widget.choices)) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final selected = _selected;
    return TrayFrame(
      question: widget.question,
      meta: widget.meta,
      list: ChoiceGrid(
        labels: [for (final c in widget.choices) c.label],
        builder: (i, numbered) {
          final state = switch (result) {
            (picked: _, right: final r) when r == i => ChoiceState.right,
            (picked: final p, right: _) when p == i => ChoiceState.wrong,
            _? => ChoiceState.off,
            null when selected == i => ChoiceState.selected,
            null => ChoiceState.idle,
          };
          return AnswerChoice(
            choice: widget.choices[i],
            state: state,
            lead: numbered ? ChoiceLead.number : ChoiceLead.radio,
            number: i + 1,
            onTap: result == null
                ? () {
                    unawaited(HapticFeedback.selectionClick());
                    setState(() => _selected = i);
                  }
                : null,
          );
        },
      ),
      confirm: TrayConfirm(
        label: widget.confirmLabel,
        hint: widget.confirmHint,
        skip: result == null ? widget.skip : null,
        onPressed: selected == null || result != null
            ? null
            : () {
                unawaited(HapticFeedback.mediumImpact());
                widget.onConfirm(selected);
              },
      ),
    );
  }
}
