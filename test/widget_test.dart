import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:empty_player/frame.dart';

void main() {
  testWidgets('App starts and builds Frame widget', (
    WidgetTester tester,
  ) async {
    // Build our app
    await tester.pumpWidget(const Frame());

    // Verify that the Frame widget builds
    expect(find.byType(Frame), findsOneWidget);
  });

  testWidgets('Frame widget builds MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(const Frame());

    // Verify MaterialApp is present
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
