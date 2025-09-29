// This is a basic Flutter widget test for the Zydus POD app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zyduspod/main.dart';

void main() {
  testWidgets('Splash screen displays correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the splash screen displays the app title
    expect(find.text('Zydus POD'), findsOneWidget);
    expect(find.text('Proof of Delivery Management'), findsOneWidget);
    
    // Verify that the logo is displayed
    expect(find.byType(Image), findsOneWidget);
    
    // Verify that the loading indicator is shown
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    
    // Clean up any pending timers
    await tester.pumpAndSettle();
  });
}
