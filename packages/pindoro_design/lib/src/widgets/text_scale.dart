import 'package:flutter/widgets.dart';

/// The text scale (1 at 100 %).
double textScaleOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1);

/// The text scale from which the layouts made for large text take over (160 %).
const double largeTextScale = 1.6;

/// Large text ([largeTextScale] and up).
bool isLargeText(BuildContext context) =>
    textScaleOf(context) >= largeTextScale;
