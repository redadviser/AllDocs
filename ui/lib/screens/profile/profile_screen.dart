import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../common/app_constants.dart';
import '../../common/glass_panel.dart';
import '../../common/snapshot_builder.dart';
import '../../common/user_initials.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import '../security/devices_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.documentsService});

  final DocumentsService documentsService;

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
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            children: [
              _ProfileTitle(
                settingsOpen: _settingsPage == 1,
                onSettingsTap: _toggleSettingsPage,
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
                      documentsService: widget.documentsService,
                    ),
                    _ProfileSettingsPage(
                      profile: profile,
                      snapshot: snapshot,
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
    required this.documentsService,
  });

  final UserProfile profile;
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
        const SizedBox(height: 14),
        _StoragePanel(summary: profile.storageSummary),
        const SizedBox(height: 14),
        _StatsPanel(profile: profile),
      ],
    );
  }
}

class _ProfileSettingsPage extends StatelessWidget {
  const _ProfileSettingsPage({
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
      key: const PageStorageKey('profile_settings'),
      physics: const BouncingScrollPhysics(),
      children: [
        _ProfileHeader(
          profile: profile,
          onEditPhoto: () => _pickAndSaveAvatar(documentsService),
        ),
        const SizedBox(height: 14),
        const _CustomizationPanel(),
        const SizedBox(height: 14),
        _SettingsPanel(snapshot: snapshot, documentsService: documentsService),
        const SizedBox(height: 14),
        _ProfileWideAction(
          icon: Icons.shield_rounded,
          iconColor: const Color(0xFF37C66A),
          title: AppConstants.profileSecurity.tr(),
          subtitle: AppConstants.profileSecuritySubtitle.tr(),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DevicesScreen()),
          ),
        ),
        const SizedBox(height: 14),
        _PremiumPanel(profile: profile),
      ],
    );
  }
}

class _ProfileTitle extends StatelessWidget {
  const _ProfileTitle({
    required this.settingsOpen,
    required this.onSettingsTap,
  });

  final bool settingsOpen;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            AppConstants.profileTitle.tr(),
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        IconButton(
          tooltip: AppConstants.profileSettings.tr(),
          onPressed: onSettingsTap,
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
              size: settingsOpen ? 32 : 34,
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

  await AuthService.setLocalAvatarPath(picked.path);
  documentsService.refreshProfile();
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

    return GlassPanel(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: avatarUrl == null
                      ? const LinearGradient(
                          colors: [Color(0xFF3F8DFF), Color(0xFF102D63)],
                        )
                      : null,
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
                            fontWeight: FontWeight.w900,
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
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      color: Colors.white,
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
                    fontWeight: FontWeight.w900,
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        color: AppTheme.primarySoft,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        profile.planName,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 34),
        ],
      ),
    );
  }
}

class _StoragePanel extends StatelessWidget {
  const _StoragePanel({required this.summary});

  final StorageSummary summary;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(Icons.inventory_2_outlined, size: 32),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppConstants.profileStorage.tr(),
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      AppConstants.profileStorageUsedOf.tr(
                        namedArgs: {
                          'used': summary.usedGb.toStringAsFixed(1),
                          'total': summary.totalGb.toStringAsFixed(0),
                        },
                      ),
                      style: const TextStyle(color: AppTheme.mutedText),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  AppConstants.profileStoragePercent.tr(
                    namedArgs: {'percent': '${summary.usedPercent}'},
                  ),
                  style: const TextStyle(
                    color: AppTheme.primarySoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: summary.usedRatio,
                    minHeight: 9,
                    backgroundColor: AppTheme.surfaceSoft,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StorageLegend(
                      color: AppTheme.accent,
                      label: AppConstants.profileStorageUsed.tr(
                        namedArgs: {'used': summary.usedGb.toStringAsFixed(1)},
                      ),
                    ),
                    const SizedBox(width: 18),
                    _StorageLegend(
                      color: AppTheme.surfaceSoft,
                      label: AppConstants.profileStorageAvailable.tr(
                        namedArgs: {
                          'available': summary.availableGb.toStringAsFixed(1),
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageLegend extends StatelessWidget {
  const _StorageLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.mutedText),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.folder_rounded,
              value: _formatNumber(profile.documentsCount),
              label: AppConstants.profileDocuments.tr(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              icon: Icons.collections_bookmark,
              iconColor: AppTheme.premium,
              value: '${profile.categoriesCount}',
              label: AppConstants.profileAlbums.tr(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              icon: Icons.star_rounded,
              iconColor: AppTheme.warning,
              value: '${profile.favoritesCount}',
              label: AppConstants.profileFavorites.tr(),
            ),
          ),
        ],
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
        return GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                icon: Icons.tune_rounded,
                title: AppConstants.profileCustomization.tr(),
              ),
              const SizedBox(height: 16),
              Text(
                AppConstants.profilePrimaryColor.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontWeight: FontWeight.w800,
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
                        fontWeight: FontWeight.w800,
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceStrong.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor ?? AppTheme.accent, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 22,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.mutedText, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.snapshot,
    required this.documentsService,
  });

  final DocumentsSnapshot snapshot;
  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        children: [
          _SettingsTile(
            icon: Icons.cloud_outlined,
            title: AppConstants.profileCloudSync.tr(),
            value: AppConstants.profileActive.tr(),
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: Icons.settings_backup_restore_rounded,
            title: AppConstants.profileAutoBackup.tr(),
            value: AppConstants.profileDaily.tr(),
          ),
          const Divider(height: 1),
          const _BiometricSettingsTile(),
          const Divider(height: 1),
          _SettingsTile(
            icon: Icons.collections_bookmark_rounded,
            title: AppConstants.profileAlbums.tr(),
            onTap: () => _showAlbumsSheet(context, snapshot),
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: Icons.ios_share_rounded,
            title: AppConstants.profileExportDocuments.tr(),
            onTap: () => _exportDocuments(context),
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: Icons.language_rounded,
            title: AppConstants.profileLanguage.tr(),
            value: _languageName(context),
            onTap: () => _showLanguageSheet(context),
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
}

class _BiometricSettingsTile extends StatefulWidget {
  const _BiometricSettingsTile();

  @override
  State<_BiometricSettingsTile> createState() => _BiometricSettingsTileState();
}

class _BiometricSettingsTileState extends State<_BiometricSettingsTile> {
  final SecurityLockService _securityLockService = SecurityLockService();
  bool _loading = true;
  bool _enabled = false;
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: Icons.lock_outline_rounded,
      title: AppConstants.profileBiometricLock.tr(),
      trailingSwitch: true,
      switchValue: _enabled,
      onSwitchChanged: _loading ? null : _setEnabled,
    );
  }

  Future<void> _load() async {
    final enabled = await _securityLockService.isBiometricEnabled();
    final canUseBiometrics = await _securityLockService.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _enabled = enabled && canUseBiometrics;
      _canUseBiometrics = canUseBiometrics;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool enabled) async {
    if (enabled && !_canUseBiometrics) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppConstants.securityBiometricUnavailable.tr())),
      );
      return;
    }

    await _securityLockService.setBiometricEnabled(enabled);
    if (!mounted) return;
    setState(() => _enabled = enabled);
  }
}

void _showAlbumsSheet(BuildContext context, DocumentsSnapshot snapshot) {
  final albums = [
    for (final shelf in snapshot.shelves)
      for (final album in shelf.albums) (shelf: shelf, album: album),
  ];

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppConstants.profileAlbums.tr(),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: AppConstants.commonClose.tr(),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (albums.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    AppConstants.docshelfCreateFirstShelfMessage.tr(),
                    style: const TextStyle(color: AppTheme.mutedText),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: albums.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = albums[index];
                      final count = snapshot
                          .documentsForAlbum(item.album.id)
                          .length;
                      return ListTile(
                        leading: Icon(
                          Icons.folder_rounded,
                          color: Color(item.album.colorValue),
                        ),
                        title: Text(item.album.name),
                        subtitle: Text(item.shelf.name),
                        trailing: Text(
                          AppConstants.docshelfDocumentCount.tr(
                            namedArgs: {'count': '$count'},
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.value,
    this.trailingSwitch = false,
    this.switchValue = false,
    this.onSwitchChanged,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? value;
  final bool trailingSwitch;
  final bool switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primarySoft, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: const TextStyle(
                  color: AppTheme.primarySoft,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (trailingSwitch)
              Switch(value: switchValue, onChanged: onSwitchChanged),
            if (!trailingSwitch && onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 28),
            ],
          ],
        ),
      ),
    );
  }
}

String _languageName(BuildContext context) {
  return switch (context.locale.languageCode) {
    'en' => AppConstants.profileEnglish.tr(),
    'es' => AppConstants.profileSpanish.tr(),
    'fr' => AppConstants.profileFrench.tr(),
    _ => AppConstants.profilePortuguese.tr(),
  };
}

void _showLanguageSheet(BuildContext context) {
  final options = [
    (locale: const Locale('pt'), label: AppConstants.profilePortuguese.tr()),
    (locale: const Locale('en'), label: AppConstants.profileEnglish.tr()),
    (locale: const Locale('es'), label: AppConstants.profileSpanish.tr()),
    (locale: const Locale('fr'), label: AppConstants.profileFrench.tr()),
  ];

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppConstants.profileLanguage.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              for (final option in options)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option.label),
                  trailing:
                      context.locale.languageCode == option.locale.languageCode
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: AppTheme.accent,
                        )
                      : null,
                  onTap: () async {
                    await context.setLocale(option.locale);
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _ProfileWideAction extends StatelessWidget {
  const _ProfileWideAction({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: GlassPanel(
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppTheme.mutedText),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: AppTheme.mutedText),
          ],
        ),
      ),
    );
  }
}

class _PremiumPanel extends StatelessWidget {
  const _PremiumPanel({required this.profile});

  final UserProfile profile;

  bool get _isFree => profile.planName.toLowerCase() == 'free';

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB66CFF), Color(0xFF6637D8)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.profilePlanTitle.tr(
                    namedArgs: {'plan': profile.planName},
                  ),
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isFree
                      ? AppConstants.profilePlanFreeSubtitle.tr()
                      : AppConstants.profilePlanActiveSubtitle.tr(),
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppConstants.profileBackendFeature.tr())),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB993FF),
              side: const BorderSide(color: AppTheme.premium),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            child: Text(AppConstants.profileManagePlan.tr()),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, size: 30),
        ],
      ),
    );
  }
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
