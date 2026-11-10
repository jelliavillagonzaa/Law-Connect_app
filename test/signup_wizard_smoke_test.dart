import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:law_connect4/pages/auth/signup_page.dart';

void main() {
  testWidgets('Create account wizard shows the privacy step', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: SignupPage()));
    await tester.pump();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('I Agree'), findsOneWidget);
    expect(find.text('Your privacy comes first'), findsOneWidget);
  });

  testWidgets('Create account button opens the privacy step', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SignupPage(),
                    ),
                  );
                },
                child: const Text('Create account'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Your privacy comes first'), findsOneWidget);
    expect(find.text('I Agree'), findsOneWidget);
  });
}
