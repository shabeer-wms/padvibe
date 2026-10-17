import 'package:flutter/widgets.dart';

/// Material 3 window size classes, by width in logical pixels.
enum WindowSize {
  compact, // < 600
  medium, //  600 - 839
  expanded; // >= 840

  static WindowSize ofWidth(double width) {
    if (width < 600) return WindowSize.compact;
    if (width < 840) return WindowSize.medium;
    return WindowSize.expanded;
  }

  static WindowSize of(BuildContext context) =>
      ofWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == WindowSize.compact;
  bool get isExpanded => this == WindowSize.expanded;
}

/// Number of pad columns that fit [width] without tiles getting too small.
/// [preferred] is the user's chosen column count; it is only ever reduced.
int responsiveGridColumns({
  required double width,
  required int preferred,
  double minTileWidth = 176,
  double spacing = 12,
  int minColumns = 2,
}) {
  final fit = ((width + spacing) / (minTileWidth + spacing)).floor();
  return fit.clamp(minColumns, preferred < minColumns ? minColumns : preferred);
}
