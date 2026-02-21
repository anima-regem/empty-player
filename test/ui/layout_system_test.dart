import 'package:empty_player/ui/layout_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LayoutMetrics.resolveMode', () {
    test('returns compact for narrow width', () {
      final mode = LayoutMetrics.resolveMode(360, textScale: 1.0);
      expect(mode, AppLayoutMode.compact);
    });

    test('returns medium for phone landscape width', () {
      final mode = LayoutMetrics.resolveMode(600, textScale: 1.0);
      expect(mode, AppLayoutMode.medium);
    });

    test('returns expanded for tablet width', () {
      final mode = LayoutMetrics.resolveMode(900, textScale: 1.0);
      expect(mode, AppLayoutMode.expanded);
    });

    test('increases compact tendency on high text scale', () {
      final mode = LayoutMetrics.resolveMode(430, textScale: 1.35);
      expect(mode, AppLayoutMode.compact);
    });
  });
}
