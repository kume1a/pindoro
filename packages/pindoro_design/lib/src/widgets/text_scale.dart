import 'package:flutter/widgets.dart';

/// The text scale (1 at 100 %).
double textScaleOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1);

/// Large text (160 % and up), where the layouts made for it take over.
bool isLargeText(BuildContext context) => textScaleOf(context) >= 1.6;
