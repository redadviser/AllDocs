import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
    await tester.enterText(find.byType(EditableText).at(0), '1234');
    await tester.enterText(find.byType(EditableText).at(1), '1234');
    await tester.tap(find.text('Guardar PIN'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Estante'), findsOneWidget);
    expect(find.text('Arquivo'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
  });
}
