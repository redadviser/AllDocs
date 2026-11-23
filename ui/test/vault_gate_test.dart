import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:all_docs/common/app_constants.dart';
import 'package:all_docs/screens/vault/vault_gate.dart';
import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/vault/vault_migration.dart';
import 'package:all_docs/services/vault/vault_unlocker.dart';

class ScriptedUnlocker extends VaultUnlocker {
  ScriptedUnlocker(this.states)
    : super(store: const LocalDocumentsStore(), localOnly: false);

  final List<VaultState> states;
  int calls = 0;
  bool setAside = false;

  @override
  Future<VaultState> unlock() async =>
      states[(calls++).clamp(0, states.length - 1)];

  @override
  Future<void> setAsideLockedLibrary() async => setAside = true;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Translations load from assets (real I/O) and the progress bar never
  // settles, so frames are pumped a few times instead of pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(WidgetTester tester, Widget gate) async {
    await EasyLocalization.ensureInitialized();
    await tester.runAsync(() async {
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
              home: gate,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
  }

  const app = Text('biblioteca');

  testWidgets('unlocked: the app shows straight away', (tester) async {
    await pump(
      tester,
      VaultGate(unlocker: ScriptedUnlocker([VaultState.open]), child: app),
    );
    expect(find.text('biblioteca'), findsOneWidget);
  });

  testWidgets('needs encrypting: progress, then the app', (tester) async {
    final finish = Completer<MigrationResult>();
    late void Function(MigrationProgress) report;
    await pump(
      tester,
      VaultGate(
        unlocker: ScriptedUnlocker([VaultState.needsMigration]),
        migrate: (onProgress) {
          report = onProgress;
          return finish.future;
        },
        child: app,
      ),
    );
    expect(find.text('A proteger os teus documentos'), findsOneWidget);
    report(
      const MigrationProgress(
        done: 712,
        total: 1240,
        bytesDone: 2254857830,
        bytesTotal: 3865470566,
      ),
    );
    await tester.pump();
    // pt-PT only groups from 10 000 up ("1240", "12 400").
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            RegExp(r'^712 de 1\s?240 documentos$').hasMatch(w.data ?? ''),
      ),
      findsOneWidget,
    );
    expect(find.text('2,1 GB de 3,6 GB'), findsOneWidget);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    finish.complete(const MigrationResult(MigrationOutcome.done));
    await settle(tester);
    expect(find.text('biblioteca'), findsOneWidget);
  });

  testWidgets('key on the account but offline: asks for internet, retries', (
    tester,
  ) async {
    final unlocker = ScriptedUnlocker([
      VaultState.needsNetwork,
      VaultState.open,
    ]);
    await pump(tester, VaultGate(unlocker: unlocker, child: app));
    expect(
      find.text('Precisas de internet para abrir a biblioteca'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tentar de novo'));
    await settle(tester);
    expect(find.text('biblioteca'), findsOneWidget);
  });

  testWidgets('no key anywhere: explains, new library only after confirming', (
    tester,
  ) async {
    final unlocker = ScriptedUnlocker([
      VaultState.unrecoverable,
      VaultState.needsMigration,
    ]);
    await pump(
      tester,
      VaultGate(
        unlocker: unlocker,
        migrate: (_) async => const MigrationResult(MigrationOutcome.done),
        child: app,
      ),
    );
    expect(find.text('Não é possível abrir estes documentos'), findsOneWidget);
    await tester.tap(find.text('Começar uma biblioteca nova'));
    await settle(tester);
    expect(unlocker.setAside, isFalse);
    await tester.tap(find.text('Começar'));
    await settle(tester);
    expect(unlocker.setAside, isTrue);
    expect(find.text('biblioteca'), findsOneWidget);
  });

  testWidgets('no space: says how much, can go on without encrypting', (
    tester,
  ) async {
    await pump(
      tester,
      VaultGate(
        unlocker: ScriptedUnlocker([VaultState.needsMigration]),
        migrate: (_) async => const MigrationResult(
          MigrationOutcome.noSpace,
          missingBytes: 640 * 1024 * 1024,
        ),
        child: app,
      ),
    );
    expect(find.textContaining('640 MB'), findsOneWidget);
    await tester.tap(find.text('Continuar sem encriptar'));
    await settle(tester);
    expect(find.text('biblioteca'), findsOneWidget);
  });
}
