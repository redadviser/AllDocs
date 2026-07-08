import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common/app_constants.dart';
import 'common/app_scaffold.dart';
import 'common/storage_permission_gate.dart';
import 'theme/app_theme.dart';

class AllDocsApp extends StatefulWidget {
  const AllDocsApp({super.key});

  @override
  State<AllDocsApp> createState() => _AllDocsAppState();
}

class _AllDocsAppState extends State<AllDocsApp> {
  @override
  void initState() {
    super.initState();
    AppTheme.loadSavedSettings();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppTheme.primaryColor,
        AppTheme.textScaleFactor,
        AppTheme.highContrastMode,
      ]),
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: AppTheme.highContrastMode.value
                ? Colors.black
                : AppTheme.background,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: MaterialApp(
            title: 'AllDocs',
            onGenerateTitle: (context) => AppConstants.appTitle.tr(),
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              final scaledChild = MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: TextScaler.linear(AppTheme.textScaleFactor.value),
                ),
                child: child ?? const SizedBox.shrink(),
              );

              if (!AppTheme.highContrastMode.value) return scaledChild;

              return ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  1.35,
                  0,
                  0,
                  0,
                  -44.625,
                  0,
                  1.35,
                  0,
                  0,
                  -44.625,
                  0,
                  0,
                  1.35,
                  0,
                  -44.625,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
                child: scaledChild,
              );
            },
            home: const StoragePermissionGate(child: MainNavScreen()),
          ),
        );
      },
    );
  }
}
