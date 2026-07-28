import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:all_docs/app.dart';
import 'package:all_docs/common/app_constants.dart';
import 'package:all_docs/services/services.dart';

void main() {
  testWidgets('shows the AllDocs app shell', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    LocalDocumentsStore.debugDirectory = Directory.systemTemp.createTempSync(
      'alldocs_widget_test_',
    );
    await EasyLocalization.ensureInitialized();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: AppConstants.supportedLocales,
        path: AppConstants.translationsPath,
        fallbackLocale: AppConstants.fallbackLocale,
        startLocale: AppConstants.fallbackLocale,
        child: const AllDocsApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Entrar'), findsOneWidget);
    await tester.tap(find.text('Entrar'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Cria o teu PIN'), findsOneWidget);
    await _tapPin(tester, '1234');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Confirmar PIN'), findsWidgets);
    await _tapPin(tester, '1234');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Estante'), findsOneWidget);
    expect(find.text('Arquivo'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
  });
}

Future<void> _tapPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump(const Duration(milliseconds: 80));
  }
}
