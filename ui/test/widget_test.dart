import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:all_docs/app.dart';
import 'package:all_docs/common/app_constants.dart';
import 'package:all_docs/services/services.dart';

/// In-memory stand-in for the real flutter_secure_storage-backed token
/// store, so this test can simulate an already-signed-in session without
/// exercising AllID's real network login (LocalModeConfig.isLocalOnly is
/// false, so AuthService talks to the real backend outside of tests).
class _FakeAuthTokenStore implements AuthTokenStore {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> delete() async => _token = null;
}

void main() {
  testWidgets('shows the AllDocs app shell', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'auth.display_name.v1': 'Test User',
    });
    LocalDocumentsStore.debugDirectory = Directory.systemTemp.createTempSync(
      'alldocs_widget_test_',
    );
    AuthService.tokenStore = _FakeAuthTokenStore()..write('test-token');
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
    // SecurityGate mounts almost immediately (AuthGate skips AllID), so its
    // internal 2s biometric-availability timeout needs to be pumped past
    // here rather than after a tap, unlike before.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 800));
    }

    // Already "signed in" via the fake token store, so AuthGate skips AllID
    // and goes straight into SecurityGate's PIN setup.
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
