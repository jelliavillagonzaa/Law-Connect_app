// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:law_connect4/screens/client/splash_screen.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // SplashScreen shows the app title immediately.
    // It only checks Firebase auth inside a delayed navigation callback,
    // so we must not advance the clock by waiting in the test.
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(autoNavigate: false),
      ),
    );

    await tester.pump();

    // Splash screen shows the app title immediately.
    expect(find.text('Law Connect'), findsOneWidget);
  });
}
