import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_caster/idle_screen.dart';
import 'package:nico_caster/main.dart';

void main() {
  test('default name uses the hostname, or a short code on Android', () {
    expect(
      defaultCasterName('abcd1234', hostname: 'LIVINGROOM-PC'),
      'LIVINGROOM-PC',
    );
    expect(defaultCasterName('abcd1234', hostname: 'tv.local'), 'tv');
    // Android reports "localhost" for every device.
    expect(defaultCasterName('abcd1234', hostname: 'localhost'), 'Caster abcd');
    expect(defaultCasterName('abcd1234', hostname: ''), 'Caster abcd');
    expect(defaultCasterName('abcd1234', hostname: 'a' * 40), hasLength(24));
  });

  testWidgets('shows the name and address, and renames', (tester) async {
    String? renamed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdleScreen(
            name: 'Living room TV',
            addresses: const ['192.168.0.160'],
            port: 47803,
            onRename: (name) => renamed = name,
          ),
        ),
      ),
    );
    expect(find.text('Waiting for a host'), findsOneWidget);
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('192.168.0.160'), findsOneWidget);

    await tester.tap(find.byTooltip('Rename this screen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Attic beamer ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(renamed, 'Attic beamer');
  });

  testWidgets('a non-default port is shown with the address', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdleScreen(
            name: 'TV',
            addresses: const ['10.0.0.5'],
            port: 47804,
            onRename: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('10.0.0.5:47804'), findsOneWidget);
  });
}
