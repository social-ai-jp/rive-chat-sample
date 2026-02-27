import 'package:flutter_test/flutter_test.dart';
import 'package:vtuber_chat/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VTuberChatApp());
    expect(find.byType(VTuberChatApp), findsOneWidget);
  });
}
