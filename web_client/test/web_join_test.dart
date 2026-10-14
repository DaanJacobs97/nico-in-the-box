import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_web_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'nickname': 'Kim'}));

  testWidgets('join asks for a nickname, pre-filled from last time', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: WebJoinScreen(host: '127.0.0.1', port: 1)),
    );
    expect(find.text('Playing in your browser'), findsOneWidget);

    await tester.tap(find.text('Join the room'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a nickname'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Kim'), findsOneWidget);
  });

  testWidgets('an unreachable room shows the error and offers a retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      // Port 1 on loopback refuses connections immediately.
      const MaterialApp(home: WebJoinScreen(host: '127.0.0.1', port: 1)),
    );
    await tester.tap(find.text('Join the room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join'));
    // The connection attempt uses real sockets, outside the fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('Could not reach a room'), findsOneWidget);
  });
}
