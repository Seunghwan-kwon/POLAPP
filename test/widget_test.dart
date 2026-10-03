import 'package:flutter_test/flutter_test.dart';
import 'package:pol_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('로그인 정보가 없으면 로그인 화면을 표시한다', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const PolApp());
    await tester.pumpAndSettle();

    expect(find.text('POL APP'), findsOneWidget);
    expect(find.text('접 속'), findsOneWidget);
  });
}
