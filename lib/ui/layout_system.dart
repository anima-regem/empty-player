import 'package:flutter/material.dart';

enum AppLayoutMode { compact, medium, expanded }

@immutable
class LayoutMetrics {
  final AppLayoutMode mode;
  final double horizontalPadding;
  final double sectionSpacing;
  final double cardSpacing;
  final double compactActionSpacing;
  final double controlIconSize;
  final int minGridColumns;

  const LayoutMetrics({
    required this.mode,
    required this.horizontalPadding,
    required this.sectionSpacing,
    required this.cardSpacing,
    required this.compactActionSpacing,
    required this.controlIconSize,
    required this.minGridColumns,
  });

  bool get isCompact => mode == AppLayoutMode.compact;
  bool get isMedium => mode == AppLayoutMode.medium;
  bool get isExpanded => mode == AppLayoutMode.expanded;

  static AppLayoutMode resolveMode(double width, {required double textScale}) {
    final effectiveWidth = width / textScale.clamp(1.0, 1.4);
    if (effectiveWidth < 420) return AppLayoutMode.compact;
    if (effectiveWidth < 760) return AppLayoutMode.medium;
    return AppLayoutMode.expanded;
  }

  static LayoutMetrics of(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final mode = resolveMode(
      mediaQuery.size.width,
      textScale: mediaQuery.textScaler.scale(1.0),
    );
    switch (mode) {
      case AppLayoutMode.compact:
        return const LayoutMetrics(
          mode: AppLayoutMode.compact,
          horizontalPadding: 16,
          sectionSpacing: 10,
          cardSpacing: 12,
          compactActionSpacing: 6,
          controlIconSize: 28,
          minGridColumns: 2,
        );
      case AppLayoutMode.medium:
        return const LayoutMetrics(
          mode: AppLayoutMode.medium,
          horizontalPadding: 20,
          sectionSpacing: 12,
          cardSpacing: 14,
          compactActionSpacing: 8,
          controlIconSize: 30,
          minGridColumns: 2,
        );
      case AppLayoutMode.expanded:
        return const LayoutMetrics(
          mode: AppLayoutMode.expanded,
          horizontalPadding: 24,
          sectionSpacing: 14,
          cardSpacing: 16,
          compactActionSpacing: 8,
          controlIconSize: 32,
          minGridColumns: 3,
        );
    }
  }
}

@immutable
class ResponsiveScaffoldInsets {
  final EdgeInsets contentPadding;
  final double reservedBottomInset;

  const ResponsiveScaffoldInsets({
    required this.contentPadding,
    required this.reservedBottomInset,
  });
}

ResponsiveScaffoldInsets resolveScaffoldInsets(
  BuildContext context, {
  required double miniPlayerInset,
}) {
  final metrics = LayoutMetrics.of(context);
  final mediaQuery = MediaQuery.of(context);
  return ResponsiveScaffoldInsets(
    contentPadding: EdgeInsets.fromLTRB(
      metrics.horizontalPadding,
      metrics.sectionSpacing,
      metrics.horizontalPadding,
      miniPlayerInset + mediaQuery.padding.bottom + metrics.sectionSpacing,
    ),
    reservedBottomInset: miniPlayerInset,
  );
}
