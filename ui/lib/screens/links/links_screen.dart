import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/album_dialog.dart' show showConfirmDialog;
import '../../common/app_constants.dart';
import '../../common/app_sheet.dart';
import '../../common/document_actions.dart' show showSnack;
import '../../common/document_file_icon.dart';
import '../../common/secure_share_flow.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import '../requests/requests_screen.dart';

enum LinksTab { send, ask }

/// Links to and from other people (Vault): documents shared behind a
/// secure link ("Send") and requests for documents ("Ask").
Future<void> openLinks(
  BuildContext context,
  DocumentsService documentsService, {
  LinksTab tab = LinksTab.send,
  String? albumId,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LinksScreen(
        documentsService: documentsService,
        initialTab: tab,
        albumId: albumId,
      ),
    ),
  );
}

class LinksScreen extends StatelessWidget {
  const LinksScreen({
    super.key,
    required this.documentsService,
    this.initialTab = LinksTab.send,
    this.albumId,
  });

  final DocumentsService documentsService;
  final LinksTab initialTab;

  /// Album a new request files its documents in, when opened from one.
  final String? albumId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.index,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 12, 0),
                child: Row(
                  children: [
                    const BackButton(),
                    Expanded(
                      child: Text(
                        AppConstants.linksTitle.tr(),
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                dividerColor: AppTheme.surfaceStrong,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.outbox_outlined, size: 20),
                    text: AppConstants.linksTabSend.tr(),
                    iconMargin: const EdgeInsets.only(bottom: 4),
                  ),
                  Tab(
                    icon: const Icon(Icons.forward_to_inbox_outlined, size: 20),
                    text: AppConstants.linksTabAsk.tr(),
                    iconMargin: const EdgeInsets.only(bottom: 4),
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    SecureSharesTab(documentsService: documentsService),
                    DocumentRequestsTab(
                      documentsService: documentsService,
                      albumId: albumId,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The documents shared behind a link, and a new one.
class SecureSharesTab extends StatefulWidget {
  const SecureSharesTab({super.key, required this.documentsService});

  final DocumentsService documentsService;

  @override
  State<SecureSharesTab> createState() => _SecureSharesTabState();
}

class _SecureSharesTabState extends State<SecureSharesTab> {
  List<SecureShare>? _shares;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final shares = await SecureSharesService.list();
      if (mounted) {
        setState(() {
          _shares = shares;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _new() async {
    final snapshot = await widget.documentsService.loadSnapshot();
    if (!mounted) return;
    final document = await showOptionsSheet<DocumentFile>(
      context: context,
      builder: (_) => _DocumentPicker(
        documents: [
          for (final document in [
            ...snapshot.documents,
            ...snapshot.archivedDocuments,
          ])
            if (document.localPath != null) document,
        ],
      ),
    );
    if (document == null || !mounted) return;
    if (await shareWithSecureLink(context, widget.documentsService, document)) {
      await _refresh();
    }
  }

  Future<void> _menu(SecureShare share) async {
    final active = share.status == SecureShareStatus.active;
    final choice = await showOptionsSheet<String>(
      context: context,
      builder: (sheetContext) {
        Widget item(String id, IconData icon, String label, {Color? color}) {
          return ListTile(
            leading: Icon(icon, color: color ?? AppTheme.primarySoft),
            title: Text(label, style: TextStyle(color: color)),
            onTap: () => Navigator.of(sheetContext).pop(id),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active && share.url != null) ...[
                item(
                  'share',
                  Icons.ios_share_rounded,
                  AppConstants.sharesShareLink.tr(),
                ),
                item(
                  'copy',
                  Icons.copy_rounded,
                  AppConstants.sharesCopyLink.tr(),
                ),
              ],
              if (active)
                item(
                  'revoke',
                  Icons.link_off_rounded,
                  AppConstants.sharesRevoke.tr(),
                  color: AppTheme.destructive,
                ),
              item(
                'delete',
                Icons.delete_outline_rounded,
                AppConstants.sharesDelete.tr(),
                color: active ? null : AppTheme.destructive,
              ),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    try {
      switch (choice) {
        case 'share':
          await shareSecureLink(context, share);
        case 'copy':
          await Clipboard.setData(ClipboardData(text: share.url!));
          if (mounted) showSnack(context, AppConstants.sharesCopied.tr());
        case 'revoke':
          final confirmed = await showConfirmDialog(
            context,
            title: AppConstants.sharesRevoke.tr(),
            message: AppConstants.sharesRevokeMessage.tr(),
            actionLabel: AppConstants.sharesRevoke.tr(),
          );
          if (!confirmed) return;
          await SecureSharesService.revoke(share.id);
          if (mounted) showSnack(context, AppConstants.sharesRevoked.tr());
          await _refresh();
        case 'delete':
          if (active) {
            final confirmed = await showConfirmDialog(
              context,
              title: AppConstants.sharesDelete.tr(),
              message: AppConstants.sharesRevokeMessage.tr(),
              actionLabel: AppConstants.commonDelete.tr(),
            );
            if (!confirmed) return;
          }
          await SecureSharesService.delete(share.id);
          await _refresh();
      }
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.sharesFailed.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final shares = _shares;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'shares',
        onPressed: _new,
        icon: const Icon(Icons.add_link_rounded),
        label: Text(AppConstants.sharesNew.tr()),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: shares == null && !_failed
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  if (_failed)
                    LinksNote(text: AppConstants.requestsFailed.tr())
                  else if (shares!.isEmpty)
                    LinksNote(
                      icon: Icons.link_rounded,
                      text: AppConstants.sharesEmpty.tr(),
                    )
                  else
                    for (final share in shares) ...[
                      _ShareCard(share: share, onTap: () => _menu(share)),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.share, required this.onTap});

  final SecureShare share;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (share.status) {
      SecureShareStatus.active => (
        AppConstants.sharesStatusActive.tr(),
        AppTheme.success,
      ),
      SecureShareStatus.expired => (
        AppConstants.sharesStatusExpired.tr(),
        AppTheme.dimText,
      ),
      SecureShareStatus.revoked => (
        AppConstants.sharesStatusRevoked.tr(),
        AppTheme.dimText,
      ),
      SecureShareStatus.locked => (
        AppConstants.sharesStatusLocked.tr(),
        AppTheme.destructive,
      ),
      SecureShareStatus.used => (
        AppConstants.sharesStatusUsed.tr(),
        AppTheme.dimText,
      ),
    };
    final date = DateFormat.yMMMd(
      context.locale.toString(),
    ).format(share.expiresAt);
    final views = share.viewCount == 0
        ? AppConstants.sharesOpenedNever.tr()
        : AppConstants.sharesOpened.tr(
            namedArgs: {
              'count': share.maxViews == null
                  ? '${share.viewCount}'
                  : '${share.viewCount}/${share.maxViews}',
            },
          );

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      share.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  LinkStatusChip(label: label, color: color),
                  const Icon(Icons.more_vert_rounded, color: AppTheme.dimText),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  AppConstants.sharesUntil.tr(namedArgs: {'date': date}),
                  views,
                ].join(' · '),
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
              ),
              if (share.hasCode) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.pin_outlined,
                      size: 15,
                      color: AppTheme.mutedText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppConstants.sharesWithCode.tr(),
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks the document to share.
class _DocumentPicker extends StatefulWidget {
  const _DocumentPicker({required this.documents});

  final List<DocumentFile> documents;

  @override
  State<_DocumentPicker> createState() => _DocumentPickerState();
}

class _DocumentPickerState extends State<_DocumentPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = normalizeForSearch(_query);
    final shown = [
      for (final document in widget.documents)
        if (query.isEmpty || normalizeForSearch(document.title).contains(query))
          document,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                AppConstants.sharesPick.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: AppConstants.albumsSearchGallery.tr(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.only(
                  bottom: 12 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                itemCount: shown.length,
                itemBuilder: (context, index) {
                  final document = shown[index];
                  return ListTile(
                    onTap: () => Navigator.of(context).pop(document),
                    leading: DocumentFileIcon(type: document.type, size: 40),
                    title: Text(
                      document.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.text),
                    ),
                    subtitle: Text(
                      '${document.sizeLabel} · ${document.dateLabel}',
                      style: const TextStyle(color: AppTheme.mutedText),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An empty or failed list's message.
class LinksNote extends StatelessWidget {
  const LinksNote({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 0),
      child: Column(
        children: [
          if (icon != null) ...[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withValues(alpha: 0.14),
              ),
              child: Icon(icon, color: AppTheme.accent, size: 30),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.mutedText, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// A link's state, as a small coloured pill.
class LinkStatusChip extends StatelessWidget {
  const LinkStatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color == AppTheme.dimText ? AppTheme.mutedText : color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
