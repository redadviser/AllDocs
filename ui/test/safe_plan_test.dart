import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:all_docs/common/app_constants.dart';
import 'package:all_docs/models/models.dart';
import 'package:all_docs/screens/albums/albums_screen.dart';
import 'package:all_docs/screens/albums/hidden_albums_screen.dart';
import 'package:all_docs/services/services.dart';

// The safe ("Cofre") follows the plan: on Pocket an empty one stays locked,
// one with albums in it (the plan was dropped) opens read-only, and it
// works fully again as soon as the plan includes it. One test: the
// localization widget doesn't come back in a second test of the same file.
void main() {
  testWidgets('the safe follows the plan', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('alldocs_safe_plan_');
    LocalDocumentsStore.debugDirectory = tempDir;
    addTearDown(() {
      PlanService.current.value = PlanCatalog.builtIn.byId(AppPlan.free);
      LocalDocumentsStore.debugDirectory = null;
      tempDir.deleteSync(recursive: true);
    });
    PlanService.current.value = PlanCatalog.builtIn.byId(AppPlan.free);
    const store = LocalDocumentsStore();
    final service = DocumentsService.local();
    addTearDown(service.dispose);

    // Real file I/O (the library) only runs outside the fake clock.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await EasyLocalization.ensureInitialized();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: AppConstants.supportedLocales,
        path: AppConstants.translationsPath,
        fallbackLocale: AppConstants.fallbackLocale,
        startLocale: const Locale('pt'),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () => openHiddenAlbums(context, service),
                      child: const Text('open safe'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            body: AlbumsScreen(
                              documentsService: service,
                              hidden: true,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('safe shelves'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle();

    // Pocket, nothing in the safe: locked, the plans are offered.
    await tester.tap(find.text('open safe'));
    await settle();
    expect(
      find.text('O cofre está incluído no Folio e no Vault.'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10));
    await settle();

    // Pocket, with an album left in the safe: read-only.
    await tester.runAsync(() async {
      await store.createShelf('Casa');
      final shelf = (await store.loadSnapshot()).shelves.single.id;
      final album = (await store.createAlbum(shelf, 'Médico'))!;
      await store.hideAlbum(album);
    });
    // Changed behind the service's back: have it reload.
    service.refreshProfile();
    await tester.tap(find.text('safe shelves'));
    await settle();
    expect(find.textContaining('já não inclui o cofre'), findsOneWidget);
    expect(find.byTooltip('Nova estante'), findsNothing);
    expect(
      find.textContaining(RegExp('médico', caseSensitive: false)),
      findsWidgets,
    );

    // Folio again: everything back, right away.
    PlanService.current.value = PlanCatalog.builtIn.byId(AppPlan.premium);
    await settle();
    expect(find.textContaining('já não inclui o cofre'), findsNothing);
    expect(find.byTooltip('Nova estante'), findsOneWidget);
  });
}
