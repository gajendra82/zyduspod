import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyduspod/screens/pod_details_screen.dart';

void main() {
  testWidgets('POD Details Screen displays correctly', (WidgetTester tester) async {
    // Build the POD details screen
    await tester.pumpWidget(
      MaterialApp(
        home: PodDetailsScreen(
          podId: 1,
          documentType: 'POD',
        ),
      ),
    );

    // Verify that the app bar is displayed
    expect(find.text('POD Details'), findsOneWidget);
    
    // Verify that the back button is present
    expect(find.byIcon(Icons.arrow_back_ios), findsOneWidget);
    
    // Verify that the refresh button is present
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
