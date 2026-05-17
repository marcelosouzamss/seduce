import 'package:flutter_test/flutter_test.dart';

import 'package:seduce_mobile/main.dart';

void main() {
  testWidgets('Carrega tela inicial com filtros', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Seduce'), findsWidgets);
  });
}
