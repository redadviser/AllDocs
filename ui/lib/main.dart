import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'common/app_constants.dart';
import 'services/adapty_service.dart';
import 'services/app_settings.dart';
import 'services/cloud_keys.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Figtree',
    ], await rootBundle.loadString('assets/fonts/figtree/OFL.txt'));
  });
  await EasyLocalization.ensureInitialized();
  await AppSettings.load();
  await CloudKeys.load();
  // Store billing starts early, as Adapty recommends; never blocks startup.
  AdaptyService.initialize();

  runApp(
    EasyLocalization(
      supportedLocales: AppConstants.supportedLocales,
      path: AppConstants.translationsPath,
      fallbackLocale: AppConstants.fallbackLocale,
      child: const AllDocsApp(),
    ),
  );
}
