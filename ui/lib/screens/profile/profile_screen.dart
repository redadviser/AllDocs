import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/app_constants.dart';
import '../../common/app_sheet.dart';
import '../../common/backup_flow.dart';
import '../../common/language_picker.dart';
import '../../common/settings_grid.dart';
import '../../common/zip_preview_sheet.dart' show formatBytes;
import 'plans_screen.dart';
import '../../common/snapshot_builder.dart';
import '../../common/user_initials.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import '../auth/auth_gate.dart';
import '../albums/hidden_albums_screen.dart';
import '../auth/security_gate.dart';
import '../cloud/cloud_screen.dart';
import '../security/devices_screen.dart';
import '../support/faq_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.documentsService,
    this.showBackButton = false,
  });

  final DocumentsService documentsService;

  /// True when opened as its own page (from the gallery avatar).
  final bool showBackButton;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final PageController _settingsPageController;
  int _settingsPage = 0;

  @override
  void initState() {
    super.initState();
    _settingsPageController = PageController();
  }

  @override
  void dispose() {
    _settingsPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SnapshotBuilder(
      documentsService: widget.documentsService,
      builder: (context, snapshot) {
        final profile = snapshot.profile;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              _ProfileTitle(
                settingsOpen: _settingsPage == 1,
                onSettingsTap: _toggleSettingsPage,
                showBackButton: widget.showBackButton,
              ),
              const SizedBox(height: 18),
              Expanded(
                child: PageView(
                  controller: _settingsPageController,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (page) => setState(() => _settingsPage = page),
                  children: [
                    _ProfileOverviewPage(
                      profile: profile,
                      snapshot: snapshot,
                      documentsService: widget.documentsService,
                    ),
                    _ProfileSettingsPage(
                      profile: profile,
                      documentsService: widget.documentsService,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleSettingsPage() {
    final nextPage = _settingsPage == 0 ? 1 : 0;
    setState(() => _settingsPage = nextPage);
    _settingsPageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }
}

class _ProfileOverviewPage extends StatelessWidget {
  const _ProfileOverviewPage({
    required this.profile,
    required this.snapshot,
    required this.documentsService,
  });

  final UserProfile profile;
  final DocumentsSnapshot snapshot;
  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('profile_overview'),
      physics: const BouncingScrollPhysics(),
      children: [
        _ProfileHeader(
          profile: profile,
          onEditPhoto: () => _pickAndSaveAvatar(documentsService),
        ),
        const SizedBox(height: 12),
        _StatsGrid(profile: profile, tagsCount: snapshot.tags.length),
        const SizedBox(height: 12),
        _BackupSection(documentsService: documentsService),
        const SizedBox(height: 12),
        _StorageSection(summary: profile.storageSummary),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ProfileSettingsPage extends StatelessWidget {
  const _ProfileSettingsPage({
    required this.profile,
    required this.documentsService,
  });

  final UserProfile profile;
  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('profile_settings'),
      physics: const BouncingScrollPhysics(),
      children: [
        _ProfileHeader(
          profile: profile,
          onEditPhoto: () => _pickAndSaveAvatar(documentsService),
        ),
        const SizedBox(height: 12),
        const _CustomizationPanel(),
        const SizedBox(height: 12),
        _SecuritySection(profile: profile, documentsService: documentsService),
        const SizedBox(height: 12),
        const _LanguageSection(),
        const SizedBox(height: 12),
        const _HelpSection(),
        const SizedBox(height: 12),
        _AccountSection(documentsService: documentsService),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Profile page
// ---------------------------------------------------------------------------

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.profile, required this.tagsCount});

  final UserProfile profile;
  final int tagsCount;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        icon: Icons.description_outlined,
        value: _formatNumber(profile.documentsCount),
        label: AppConstants.profileDocuments.tr(),
      ),
      (
        icon: Icons.collections_bookmark_outlined,
        value: _formatNumber(profile.categoriesCount),
        label: AppConstants.profileAlbums.tr(),
      ),
      (
        icon: Icons.sell_outlined,
        value: _formatNumber(tagsCount),
        label: AppConstants.profileTags.tr(),
      ),
      (
        icon: Icons.star_outline_rounded,
        value: _formatNumber(profile.favoritesCount),
        label: AppConstants.profileFavorites.tr(),
      ),
    ];
    return SettingsGrid(
      spacing: 10,
      wideColumns: 4,
      children: [
        for (final stat in stats)
          SettingsCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              children: [
                Icon(stat.icon, size: 24, color: AppTheme.mutedText),
                const SizedBox(height: 8),
                Text(
                  stat.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Backup at one tap: shows when/where the last one went; "Back up now"
/// asks where to (phone or any cloud) and does it; "Options" opens the
/// connections page (destination, daily backup, restore).
class _BackupSection extends StatelessWidget {
  const _BackupSection({required this.documentsService});

  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppSettings.lastBackupAt,
        AppSettings.backupProvider,
      ]),
      builder: (context, _) {
        final last = AppSettings.lastBackupAt.value;
        final providerId = AppSettings.backupProvider.value;
        final destination = providerId == null
            ? AppConstants.backupThisDevice.tr()
            : documentsService.cloud.providerNamed(providerId)?.displayName ??
                  AppConstants.backupThisDevice.tr();
        return SettingsSection(
          icon: Icons.backup_outlined,
          title: AppConstants.backupTitle.tr(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                last == null
                    ? AppConstants.backupStatusNever.tr()
                    : AppConstants.backupStatus.tr(
                        namedArgs: {
                          'date': DateFormat.yMMMd().add_Hm().format(last),
                          'destination': destination,
                        },
                      ),
                style: const TextStyle(color: AppTheme.mutedText),
              ),
              const SizedBox(height: 10),
              SettingsGrid(
                children: [
                  SettingsGridAction(
                    icon: Icons.backup_outlined,
                    title: AppConstants.backupNow.tr(),
                    onTap: () => showBackupSheet(context, documentsService),
                  ),
                  SettingsGridAction(
                    icon: Icons.cloud_outlined,
                    title: AppConstants.connectionsTitle.tr(),
                    onTap: () => openConnectionsPage(context, documentsService),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Everything the app stores: the gallery (in albums or not), the archive
/// and the recycle bin, against the library's limit.
class _StorageSection extends StatelessWidget {
  const _StorageSection({required this.summary});

  final StorageSummary summary;

  @override
  Widget build(BuildContext context) {
    String count(int value) => AppConstants.profileStorageCount.tr(
      namedArgs: {'count': _formatNumber(value)},
    );

    return SettingsSection(
      icon: Icons.inventory_2_outlined,
      title: AppConstants.profileStorage.tr(),
      child: SettingsGrid(
        spacing: 10,
        square: true,
        children: [
          _StorageUsageTile(summary: summary),
          _StorageInfoTile(
            icon: Icons.collections_bookmark_outlined,
            title: AppConstants.profileStorageInAlbums.tr(),
            value: formatBytes(summary.inAlbums.bytes),
            subtitle: count(summary.inAlbums.count),
          ),
          _StorageInfoTile(
            icon: Icons.photo_library_outlined,
            title: AppConstants.profileStorageWithoutAlbum.tr(),
            value: formatBytes(summary.withoutAlbum.bytes),
            subtitle: count(summary.withoutAlbum.count),
          ),
          _StorageInfoTile(
            icon: Icons.inventory_outlined,
            title: AppConstants.profileStorageArchiveTrash.tr(),
            value: formatBytes(summary.archivedOrDeleted.bytes),
            subtitle: count(summary.archivedOrDeleted.count),
          ),
        ],
      ),
    );
  }
}

class _StorageUsageTile extends StatelessWidget {
  const _StorageUsageTile({required this.summary});

  final StorageSummary summary;

  @override
  Widget build(BuildContext context) {
    final color = summary.usedRatio > 0.85
        ? AppTheme.destructive
        : AppTheme.accent;
    return SettingsCard(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortest = constraints.biggest.shortestSide;
          final compact = shortest < 160;
          final circle = (shortest * (compact ? 0.42 : 0.5)).clamp(56.0, 90.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.folder_copy_outlined,
                    size: 16,
                    color: AppTheme.mutedText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      AppConstants.profileStorageInApp.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.text,
                        fontSize: compact ? 13 : 14,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 6 : 10),
              Expanded(
                child: Center(
                  child: SizedBox.square(
                    dimension: circle,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          // A sliver even when nearly empty, so it reads as
                          // a gauge rather than an empty ring.
                          value: summary.usedBytes == 0
                              ? 0
                              : summary.usedRatio.clamp(0.01, 1.0),
                          strokeWidth: compact ? 8 : 10,
                          backgroundColor: AppTheme.surfaceSoft,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                        Center(
                          child: Text(
                            '${summary.usedPercent}%',
                            style: TextStyle(
                              color: AppTheme.text,
                              fontSize: compact ? 15 : 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: compact ? 6 : 8),
              Text(
                '${formatBytes(summary.usedBytes)} / '
                '${formatBytes(summary.limitBytes)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: compact ? 11 : 12,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StorageInfoTile extends StatelessWidget {
  const _StorageInfoTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppTheme.mutedText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.text, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings page
// ---------------------------------------------------------------------------

/// App lock (biometrics, when it locks), hidden previews and the account's
/// sessions/devices.
class _SecuritySection extends StatefulWidget {
  const _SecuritySection({
    required this.profile,
    required this.documentsService,
  });

  final DocumentsService documentsService;

  /// Whose PIN it is (shown on the change-PIN screen).
  final UserProfile profile;

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  final SecurityLockService _securityLockService = SecurityLockService();
  bool _loading = true;
  bool _biometricEnabled = false;
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _securityLockService.isBiometricEnabled();
    final canUseBiometrics = await _securityLockService.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled && canUseBiometrics;
      _canUseBiometrics = canUseBiometrics;
      _loading = false;
    });
  }

  Future<void> _setBiometricEnabled(bool enabled) async {
    if (enabled && !_canUseBiometrics) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppConstants.securityBiometricUnavailable.tr())),
      );
      return;
    }
    await _securityLockService.setBiometricEnabled(enabled);
    if (!mounted) return;
    setState(() => _biometricEnabled = enabled);
  }

  Future<void> _changePin() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PinChangeScreen(
          userName: widget.profile.name,
          avatarUrl: widget.profile.avatarUrl,
        ),
      ),
    );
    if (changed != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppConstants.securityPinChanged.tr())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      icon: Icons.shield_outlined,
      title: AppConstants.profileSecurity.tr(),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          AppSettings.autoLockMinutes,
          AppSettings.hidePreviews,
        ]),
        builder: (context, _) => SettingsGrid(
          children: [
            SettingsGridAction(
              icon: Icons.pin_outlined,
              title: AppConstants.securityChangePin.tr(),
              onTap: _changePin,
            ),
            SettingsGridToggle(
              icon: Icons.fingerprint_rounded,
              title: AppConstants.profileBiometricLock.tr(),
              value: _biometricEnabled,
              onChanged: _loading ? null : _setBiometricEnabled,
            ),
            SettingsGridAction(
              icon: Icons.timer_outlined,
              title: AppConstants.settingsAutoLock.tr(),
              value: autoLockLabel(AppSettings.autoLockMinutes.value),
              onTap: () => _showAutoLockSheet(context),
            ),
            SettingsGridToggle(
              icon: Icons.visibility_off_outlined,
              title: AppConstants.settingsHidePreviews.tr(),
              value: AppSettings.hidePreviews.value,
              onChanged: AppSettings.setHidePreviews,
            ),
            SettingsGridAction(
              icon: Icons.visibility_off_outlined,
              title: AppConstants.hiddenTitle.tr(),
              onTap: () => openHiddenAlbums(context, widget.documentsService),
            ),
            SettingsGridAction(
              icon: Icons.devices_outlined,
              title: AppConstants.profileDevices.tr(),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const DevicesScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSection extends StatelessWidget {
  const _LanguageSection();

  static const _flags = {
    'pt': '🇵🇹',
    'en': '🇬🇧',
    'es': '🇪🇸',
    'fr': '🇫🇷',
  };

  @override
  Widget build(BuildContext context) {
    final options = [
      (locale: const Locale('pt'), label: AppConstants.profilePortuguese.tr()),
      (locale: const Locale('en'), label: AppConstants.profileEnglish.tr()),
      (locale: const Locale('es'), label: AppConstants.profileSpanish.tr()),
      (locale: const Locale('fr'), label: AppConstants.profileFrench.tr()),
    ];
    return SettingsSection(
      icon: Icons.language_outlined,
      title: AppConstants.profileLanguage.tr(),
      child: SettingsGrid(
        wideColumns: 4,
        children: [
          for (final option in options)
            _LanguageOption(
              flag: _flags[option.locale.languageCode]!,
              label: option.label,
              selected:
                  context.locale.languageCode == option.locale.languageCode,
              onTap: () => changeAppLanguage(context, option.locale),
            ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.flag,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String flag;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppTheme.accent.withValues(alpha: 0.16)
          : AppTheme.surfaceStrong.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppTheme.accent : AppTheme.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_rounded, size: 16, color: AppTheme.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Taking the documents out of the app, and signing out.
class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.documentsService});

  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      icon: Icons.manage_accounts_outlined,
      title: AppConstants.profileAccountTitle.tr(),
      child: SettingsGrid(
        children: [
          SettingsGridAction(
            icon: Icons.ios_share_rounded,
            title: AppConstants.profileExportDocuments.tr(),
            onTap: () => _exportDocuments(context),
          ),
          SettingsGridAction(
            icon: Icons.logout_rounded,
            title: AppConstants.profileLogout.tr(),
            destructive: true,
            onTap: () => _confirmAndLogout(context),
          ),
        ],
      ),
    );
  }

  Future<void> _exportDocuments(BuildContext context) async {
    final result = await documentsService.exportDocuments(
      dialogTitle: AppConstants.profileExportPickerTitle.tr(),
    );
    if (!context.mounted) return;

    final message = result.count == 0 || result.path == null
        ? AppConstants.profileExportEmpty.tr()
        : AppConstants.profileExportDone.tr(
            namedArgs: {'count': '${result.count}', 'path': result.path!},
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmAndLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(AppConstants.profileLogoutConfirmTitle.tr()),
        content: Text(AppConstants.profileLogoutConfirmMessage.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppConstants.commonCancel.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: Text(AppConstants.profileLogout.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await AuthService.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }
}

const _supportEmail = 'webmaster@eupasoft.com';
const _privacyPolicyUrl = 'https://redadviser.com/?page_id=316';
const _androidPackageName = 'com.alldocs.app';

class _HelpSection extends StatelessWidget {
  const _HelpSection();

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      icon: Icons.help_outline_rounded,
      title: AppConstants.profileHelpTitle.tr(),
      child: SettingsGrid(
        children: [
          SettingsGridAction(
            icon: Icons.quiz_outlined,
            title: AppConstants.profileFaq.tr(),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const FaqScreen())),
          ),
          SettingsGridAction(
            icon: Icons.support_agent_outlined,
            title: AppConstants.profileContactSupport.tr(),
            onTap: () => _contactSupport(context),
          ),
          SettingsGridAction(
            icon: Icons.star_rate_outlined,
            title: AppConstants.profileRateApp.tr(),
            onTap: () => _rateApp(context),
          ),
          SettingsGridAction(
            icon: Icons.privacy_tip_outlined,
            title: AppConstants.profilePrivacyPolicy.tr(),
            onTap: () => _launch(context, Uri.parse(_privacyPolicyUrl)),
          ),
        ],
      ),
    );
  }

  Future<void> _contactSupport(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': AppConstants.profileContactSupportSubject.tr(),
      },
    );
    await _launch(context, uri);
  }

  Future<void> _rateApp(BuildContext context) async {
    if (Platform.isAndroid) {
      final marketUri = Uri.parse('market://details?id=$_androidPackageName');
      if (await canLaunchUrl(marketUri)) {
        await launchUrl(marketUri);
        return;
      }
      if (!context.mounted) return;
      final webUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=$_androidPackageName',
      );
      await _launch(context, webUri);
      return;
    }

    // No published App Store id yet on iOS — collect feedback by email
    // instead of a broken review deep link.
    await _contactSupport(context);
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppConstants.profileLinkOpenError.tr())),
      );
    }
  }
}

class _ProfileTitle extends StatelessWidget {
  const _ProfileTitle({
    required this.settingsOpen,
    required this.onSettingsTap,
    this.showBackButton = false,
  });

  final bool settingsOpen;
  final VoidCallback onSettingsTap;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBackButton) ...[const BackButton(), const SizedBox(width: 4)],
        Expanded(
          child: Text(
            AppConstants.profileTitle.tr(),
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: AppConstants.profileSettings.tr(),
          onPressed: onSettingsTap,
          visualDensity: VisualDensity.compact,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) {
              return RotationTransition(
                turns: Tween<double>(begin: -0.12, end: 0).animate(animation),
                child: ScaleTransition(scale: animation, child: child),
              );
            },
            child: Icon(
              settingsOpen ? Icons.close_rounded : Icons.settings_outlined,
              key: ValueKey(settingsOpen),
              size: settingsOpen ? 24 : 26,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _pickAndSaveAvatar(DocumentsService documentsService) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 800,
    maxHeight: 800,
    imageQuality: 85,
  );
  if (picked == null) return;

  final avatarPath = await _saveAvatarPermanently(picked.path);
  await AuthService.setLocalAvatarPath(avatarPath);
  documentsService.refreshProfile();
}

// image_picker hands back a file in the app's cache dir, which Android can
// wipe via "Clear cache" alone (no uninstall needed) — copy it into the
// app's persistent documents directory so the photo actually survives that.
Future<String> _saveAvatarPermanently(String pickedPath) async {
  final documentsDir = await getApplicationDocumentsDirectory();
  final destination = File('${documentsDir.path}/profile_avatar');
  await File(pickedPath).copy(destination.path);

  // Same path every time, so without this a re-picked photo would keep
  // showing the previous one from Flutter's in-memory image cache.
  PaintingBinding.instance.imageCache.evict(FileImage(destination));
  return destination.path;
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.onEditPhoto});

  final UserProfile profile;
  final VoidCallback onEditPhoto;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile.avatarUrl;
    final isNetworkAvatar = avatarUrl != null && avatarUrl.startsWith('http');
    final isLocalAvatar = avatarUrl != null && !isNetworkAvatar;

    return SettingsCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: avatarUrl == null ? AppTheme.surfaceStrong : null,
                  image: isNetworkAvatar
                      ? DecorationImage(
                          image: NetworkImage(avatarUrl),
                          fit: BoxFit.cover,
                        )
                      : isLocalAvatar
                      ? DecorationImage(
                          image: FileImage(File(avatarUrl)),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: avatarUrl == null
                    ? Center(
                        child: Text(
                          initialsFromName(profile.name),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 2,
                child: GestureDetector(
                  onTap: onEditPhoto,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.photo_camera_rounded,
                      color: AppTheme.onAccent,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  profile.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                // The plan, as a button: the way into the plans page.
                _PlanButton(summary: profile.storageSummary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanButton extends StatelessWidget {
  const _PlanButton({required this.summary});

  final StorageSummary summary;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppPlan>(
      valueListenable: PlanService.current,
      builder: (context, plan, _) => Material(
        color: AppTheme.accent.withValues(alpha: 0.18),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openPlansScreen(context, summary: summary),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlanMedal(plan: plan, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${plan.name} · ${AppConstants.plansSeePlans.tr()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppTheme.mutedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomizationPanel extends StatelessWidget {
  const _CustomizationPanel();

  static const _colors = <Color?>[
    null,
    Color(0xFF16A3A9),
    Color(0xFFFF00FB),
    Color(0xFF7C5CFF),
    Color(0xFFFFB84D),
    Color(0xFFF8757D),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppTheme.primaryColor,
        AppTheme.textScaleFactor,
        AppTheme.highContrastMode,
      ]),
      builder: (context, child) {
        return SettingsSection(
          icon: Icons.tune_rounded,
          title: AppConstants.profileCustomization.tr(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppConstants.profilePrimaryColor.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final color in _colors) _ColorSwatch(color: color),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppConstants.profileFontSize.tr(),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${(AppTheme.textScaleFactor.value * 100).round()}%',
                    style: const TextStyle(color: AppTheme.primarySoft),
                  ),
                ],
              ),
              Slider(
                min: AppTheme.minTextScaleFactor,
                max: AppTheme.maxTextScaleFactor,
                divisions: AppTheme.textScaleDivisions,
                value: AppTheme.textScaleFactor.value,
                onChanged: (value) => AppTheme.setTextScaleFactor(value),
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.contrast_rounded,
                      color: AppTheme.primarySoft,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppConstants.profileContrastMode.tr(),
                          style: const TextStyle(
                            color: AppTheme.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          AppConstants.profileContrastDescription.tr(),
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: AppTheme.highContrastMode.value,
                    onChanged: AppTheme.setHighContrastMode,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final selected = AppTheme.primaryColor.value == color;
    final swatchColor = color ?? AppTheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () => AppTheme.setPrimaryColor(color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color == null ? AppTheme.surfaceStrong : swatchColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : AppTheme.border,
            width: selected ? 3 : 1,
          ),
        ),
        child: color == null
            ? const Icon(Icons.restart_alt_rounded, color: AppTheme.primarySoft)
            : selected
            ? const Icon(Icons.check_rounded, color: Colors.white)
            : null,
      ),
    );
  }
}

String autoLockLabel(int minutes) {
  if (minutes < 0) return AppConstants.settingsAutoLockNever.tr();
  if (minutes == 0) return AppConstants.settingsAutoLockImmediately.tr();
  return AppConstants.settingsAutoLockMinutes.tr(
    namedArgs: {'count': '$minutes'},
  );
}

void _showAutoLockSheet(BuildContext context) {
  showOptionsSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              AppConstants.settingsAutoLock.tr(),
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              AppConstants.settingsAutoLockHint.tr(),
              style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
            ),
          ),
          for (final minutes in AppSettings.autoLockChoices)
            ListTile(
              title: Text(autoLockLabel(minutes)),
              trailing: AppSettings.autoLockMinutes.value == minutes
                  ? Icon(Icons.check_rounded, color: AppTheme.accent)
                  : null,
              onTap: () {
                AppSettings.setAutoLockMinutes(minutes);
                Navigator.of(context).pop();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

String _formatNumber(int value) {
  final text = value.toString();
  final buffer = StringBuffer();

  for (var i = 0; i < text.length; i++) {
    final positionFromEnd = text.length - i;
    buffer.write(text[i]);
    if (positionFromEnd > 1 && positionFromEnd % 3 == 1) {
      buffer.write('.');
    }
  }

  return buffer.toString();
}
