import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:all_docs/common/app_constants.dart';
import 'package:all_docs/screens/cloud/cloud_screen.dart';
import 'package:all_docs/services/services.dart';

void main() {
  testWidgets('connections lay out on a phone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    LocalDocumentsStore.debugDirectory = Directory.systemTemp.createTempSync(
      'alldocs_connections_smoke_',
    );
    await EasyLocalization.ensureInitialized();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: AppConstants.supportedLocales,
        path: AppConstants.translationsPath,
        fallbackLocale: AppConstants.fallbackLocale,
        startLocale: AppConstants.fallbackLocale,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(
              body: CloudScreen(documentsService: DocumentsService.local()),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Contas'), findsOneWidget);
    expect(find.text('Dropbox'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Restaurar'),
      find.byKey(const PageStorageKey('cloud')),
      const Offset(0, -300),
    );
    expect(find.text('Guardar em'), findsOneWidget);
  });
}
