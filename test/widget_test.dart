import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/main.dart';

void main() {
  testWidgets('app starts and shows the title', (tester) async {
    await tester.pumpWidget(const NicoInTheBoxApp());
    expect(find.text('Nico in the Box'), findsOneWidget);
  });
}
