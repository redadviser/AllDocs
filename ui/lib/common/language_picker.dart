import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_constants.dart';

/// The app's languages, each named in itself so anyone can find their own
/// whatever language the app is showing.
const appLanguages = [
  (locale: Locale('pt'), name: 'Português', flag: '🇵🇹'),
  (locale: Locale('en'), name: 'English', flag: '🇬🇧'),
  (locale: Locale('es'), name: 'Español', flag: '🇪🇸'),
  (locale: Locale('fr'), name: 'Français', flag: '🇫🇷'),
];

/// Switches the app to [locale] and repaints it at once.
Future<void> changeAppLanguage(BuildContext context, Locale locale) async {
  await context.setLocale(locale);
  await rebuildWholeApp();
}

/// Most text uses `.tr()` without a context, so nothing depends on the
/// locale and a language change only showed up as screens happened to
/// rebuild (e.g. switching tabs). Marking every element dirty repaints the
/// whole app in the new language at once while keeping all state (open
/// tab, routes, unlocked session).
Future<void> rebuildWholeApp() async {
  // The new translations are applied when MaterialApp's Localizations
  // updates, which happens on the next frame.
  await WidgetsBinding.instance.endOfFrame;
  void markDirty(Element element) {
    element.markNeedsBuild();
    element.visitChildren(markDirty);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(markDirty);
}

Future<void> showLanguageSheet(BuildContext context) {
  // Read before the sheet opens: the sheet outlives nothing it depends on
  // if it never looks [context] up again.
  final current = context.locale.languageCode;
  final localization = EasyLocalization.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.language_rounded, color: AppTheme.accent),
                    const SizedBox(width: 10),
                    Text(
                      AppConstants.authLanguage.tr(),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              for (final language in appLanguages)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  selected: language.locale.languageCode == current,
                  selectedTileColor: AppTheme.accent.withValues(alpha: 0.12),
                  leading: Text(
                    language.flag,
                    style: const TextStyle(fontSize: 22),
                  ),
                  title: Text(
                    language.name,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: language.locale.languageCode == current
                      ? Icon(Icons.check_rounded, color: AppTheme.accent)
                      : null,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    if (language.locale.languageCode != current) {
                      await localization.setLocale(language.locale);
                      await rebuildWholeApp();
                    }
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// A compact "🇵🇹 PT" chip that opens [showLanguageSheet] — for screens
/// shown before the settings are reachable, like sign-in.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final code = context.locale.languageCode;
    final language = appLanguages.firstWhere(
      (language) => language.locale.languageCode == code,
      orElse: () => appLanguages.first,
    );
    return Tooltip(
      message: AppConstants.authLanguage.tr(),
      child: Material(
        color: Colors.black.withValues(alpha: 0.32),
        shape: StadiumBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showLanguageSheet(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(language.flag, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Text(
                  code.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(
                  Icons.expand_more_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
