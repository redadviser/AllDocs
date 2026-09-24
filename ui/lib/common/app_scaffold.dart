import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'app_constants.dart';
import 'document_import_flow.dart';
import '../screens/albums/albums_screen.dart';
import '../screens/archive/archive_screen.dart';
import '../screens/auth/security_gate.dart';
import '../screens/cloud/cloud_screen.dart';
import '../screens/gallery/gallery_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  final DocumentsService _documentsService = DocumentsService.local();
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _listenForSharedFiles();
    // A new account starts with a "Personal" shelf (Contracts, Invoices)
    // instead of an empty Albums tab.
    unawaited(
      _documentsService
          .ensureStarterShelf(AppConstants.albumsDefaultShelf.tr(), [
            (name: AppConstants.albumNameContract.tr(), iconName: 'work'),
            (name: AppConstants.albumNameInvoice.tr(), iconName: 'receipt'),
          ]),
    );
    // Daily cloud backup when enabled (silent, best-effort).
    unawaited(
      _documentsService.backup.runAutoBackupIfDue(
        _documentsService.cloud.providerNamed,
      ),
    );
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    _documentsService.dispose();
    super.dispose();
  }

  /// "Share to AllDocs" / "Open with AllDocs" from other apps, both on a
  /// cold start and while the app is running.
  void _listenForSharedFiles() {
    // Only the mobile plugins exist; elsewhere (tests, desktop) the channel
    // is missing and reports an error.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final intents = ReceiveSharingIntent.instance;
      _shareSubscription = intents.getMediaStream().listen(
        _handleSharedFiles,
        onError: (_) {},
      );
      intents.getInitialMedia().then((files) {
        _handleSharedFiles(files);
        intents.reset();
      }, onError: (_) {});
    } catch (_) {
      // Plugin unavailable (tests, desktop).
    }
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    // Only real files: a shared link or plain text arrives as a "path" that
    // isn't one, while a .txt/.csv opened with AllDocs is typed as text.
    final paths = [
      for (final file in files)
        if (file.path.isNotEmpty && File(file.path).existsSync()) file.path,
    ];
    if (paths.isEmpty) return;
    // "Open with AllDocs" while the app is locked: import only once the PIN
    // or biometrics succeed.
    await SecurityGate.whenUnlocked();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() => _selectedIndex = 0);
    await importIncomingFiles(context, _documentsService, paths);
  }

  @override
  Widget build(BuildContext context) {
    // Wrapping the whole scaffold (not just the nav bar) means a color/
    // contrast change re-runs this build and constructs fresh (non-const)
    // tab screens, so every tab picks up the new theme immediately instead
    // of only updating next time it happens to rebuild.
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppTheme.primaryColor,
        AppTheme.highContrastMode,
      ]),
      builder: (context, child) {
        final screens = [
          GalleryScreen(
            documentsService: _documentsService,
            onOpenArchive: _openArchive,
            onOpenCloud: _openCloud,
          ),
          AlbumsScreen(documentsService: _documentsService),
          ProfileScreen(documentsService: _documentsService),
        ];

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            bottom: false,
            child: IndexedStack(index: _selectedIndex, children: screens),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectPage,
            backgroundColor: AppTheme.surface,
            indicatorColor: AppTheme.accent.withValues(alpha: 0.16),
            surfaceTintColor: Colors.transparent,
            height: 66,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(
                  Icons.grid_view_rounded,
                  color: AppTheme.accent,
                ),
                label: AppConstants.navGallery.tr(),
              ),
              NavigationDestination(
                icon: const Icon(Icons.folder_outlined),
                selectedIcon: Icon(
                  Icons.folder_rounded,
                  color: AppTheme.accent,
                ),
                label: AppConstants.navAlbums.tr(),
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(
                  Icons.person_rounded,
                  color: AppTheme.accent,
                ),
                label: AppConstants.navProfile.tr(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _selectPage(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  void _openArchive() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: ArchiveScreen(
              documentsService: _documentsService,
              showBackButton: true,
            ),
          ),
        ),
      ),
    );
  }

  void _openCloud(CloudProviderId? provider) {
    openConnectionsPage(context, _documentsService, provider: provider);
  }
}
