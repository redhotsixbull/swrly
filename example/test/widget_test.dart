import 'package:flutter/widgets.dart';
import 'package:swrly/swrly.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('ExampleApp builds', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('swrly'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    QueryClient.instance.clear();
  });
}
