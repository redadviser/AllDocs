import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'common/app_constants.dart';
import 'services/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await AppSettings.load();

  runApp(
    EasyLocalization(
      supportedLocales: AppConstants.supportedLocales,
      path: AppConstants.translationsPath,
      fallbackLocale: AppConstants.fallbackLocale,
      child: const AllDocsApp(),
    ),
  );
}
