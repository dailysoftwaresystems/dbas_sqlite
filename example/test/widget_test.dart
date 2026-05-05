import 'package:flutter_test/flutter_test.dart';

import 'package:dbas_sqlite_example/main.dart';

void main() {
  testWidgets('App renders with tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const DbasExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('CRUD'), findsOneWidget);
    expect(find.text('DB Ops'), findsOneWidget);
  });
}
