import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common/app_constants.dart';
import 'common/office_thumbnail_host.dart';
import 'screens/auth/auth_gate.dart';
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
            systemNavigationBarColor: AppTheme.background,
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
                child: Stack(
                  children: [
                    Positioned.fill(child: child ?? const SizedBox.shrink()),
                    // Draws Word/PowerPoint/Excel thumbnails for the
                    // document cards; 2 px, above every screen so it keeps
                    // working whichever page is open.
                    if (OfficeThumbnailHost.supported)
                      const Positioned(
                        left: 0,
                        bottom: 0,
                        width: 2,
                        height: 2,
                        child: OfficeThumbnailHost(),
                      ),
                  ],
                ),
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
            home: const AuthGate(),
          ),
        );
      },
    );
  }
}
