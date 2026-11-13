import 'dart:math' show min, sqrt;

import 'package:flutter/material.dart';

/// One responsive shortcut-cell rule shared by every control surface.
abstract final class ShortcutGridGeometry {
  static const double horizontalInset = 10;
  static const double spacing = 6;

  static int columnsForViewport(Size viewport, {required int keysPerPage}) {
    final landscape = viewport.width > viewport.height;
    if (viewport.shortestSide < 600) return landscape ? 5 : 3;
    return (sqrt(keysPerPage) * (landscape ? 1.25 : 0.8)).round();
  }

  static int pageSizeForViewport(Size viewport, int keysPerPage) =>
      viewport.shortestSide < 600 ? 15 : keysPerPage;

  static double contentWidthForViewport(
    Size viewport, {
    double safeAreaLeft = 0,
    double safeAreaRight = 0,
  }) {
    return surfaceWidthForViewport(
          viewport,
          safeAreaLeft: safeAreaLeft,
          safeAreaRight: safeAreaRight,
        ) -
        horizontalInset * 2;
  }

  static ({double left, double right}) horizontalPaddingForViewport(
    Size viewport, {
    double safeAreaLeft = 0,
    double safeAreaRight = 0,
  }) {
    final surfaceWidth = surfaceWidthForViewport(
      viewport,
      safeAreaLeft: safeAreaLeft,
      safeAreaRight: safeAreaRight,
    );
    final centerGap =
        (viewport.width - safeAreaLeft - safeAreaRight - surfaceWidth) / 2;
    return (
      left: centerGap + horizontalInset,
      right: centerGap + horizontalInset,
    );
  }

  static double surfaceWidthForViewport(
    Size viewport, {
    double safeAreaLeft = 0,
    double safeAreaRight = 0,
  }) {
    final usableWidth = viewport.width - safeAreaLeft - safeAreaRight;
    return viewport.shortestSide < 600 && viewport.width > viewport.height
        ? (usableWidth - 1) * 2 / 3
        : usableWidth;
  }

  static ({int columns, int rows, double width, double height}) forViewport({
    required Size viewport,
    required double gridContentWidth,
    required int keysPerPage,
    double safeAreaVertical = 0,
    int? columns,
    int? rows,
  }) {
    final pageSize = pageSizeForViewport(viewport, keysPerPage);
    final resolvedColumns =
        columns ?? columnsForViewport(viewport, keysPerPage: pageSize);
    final resolvedRows = rows ?? (pageSize / resolvedColumns).ceil();
    final width =
        (gridContentWidth - spacing * (resolvedColumns - 1)) / resolvedColumns;
    final landscape = viewport.width > viewport.height;
    final phoneLayout = viewport.shortestSide < 600;
    final homeGridHeight = phoneLayout
        ? landscape
              ? viewport.height - safeAreaVertical - 112
              : (viewport.height - safeAreaVertical - 102) * 0.62 - 16
        : viewport.height - safeAreaVertical - 108;
    final heightBudget =
        (homeGridHeight - spacing * (resolvedRows - 1)) / resolvedRows;
    return (
      columns: resolvedColumns,
      rows: resolvedRows,
      width: width,
      height: min(width, heightBudget),
    );
  }
}
