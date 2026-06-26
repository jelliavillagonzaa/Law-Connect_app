import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:law_connect4/pages/client/client_landing_page.dart';

void main() {
  testWidgets('Landing page smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ClientLandingPage(),
      ),
    );
    await tester.pump();

    expect(find.text('Law Connect'), findsWidgets);
  });
}
