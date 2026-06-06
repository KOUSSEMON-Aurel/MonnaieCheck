import 'package:flutter_test/flutter_test.dart';
import 'package:monnaie_check/main.dart';

void main() {
  testWidgets('App launches correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const MonnaieCheckApp());
    expect(find.text('MonnaieCheck'), findsOneWidget);
  });
}
