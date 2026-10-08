import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../common/album_dialog.dart' show showConfirmDialog;
import '../../common/app_constants.dart';
import '../../common/app_sheet.dart';
import '../../common/document_actions.dart' show showSnack;
import '../../common/plan_prompts.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import '../albums/hidden_albums_screen.dart' show shelfDisplayName;

Future<void> openDocumentRequests(
  BuildContext context,
  DocumentsService documentsService, {
  String? albumId,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DocumentRequestsScreen(
        documentsService: documentsService,
        albumId: albumId,
      ),
    ),
  );
}

/// Brings in what arrived through requests (on app start); says so when
/// something did.
Future<void> collectRequestedDocuments(
  BuildContext context,
  DocumentsService documentsService,
) async {
  try {
    final added = await DocumentRequestsService.collect(documentsService);
    if (added == 0 || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppConstants.requestsArrived.tr(namedArgs: {'count': '$added'}),
        ),
        action: SnackBarAction(
          label: AppConstants.requestsView.tr(),
          onPressed: () => openDocumentRequests(context, documentsService),
        ),
      ),
    );
  } on StorageFullException catch (error) {
    if (context.mounted) await showStorageFullDialog(context, error);
  } catch (_) {
    // Offline or signed out: they wait on the server for the next try.
  }
}

/// "Send me X" links: the ones made, what came in, and a new one.
class DocumentRequestsScreen extends StatefulWidget {
  const DocumentRequestsScreen({
    super.key,
    required this.documentsService,
    this.albumId,
  });

  final DocumentsService documentsService;

  /// Album a new request files its documents in, when opened from one.
  final String? albumId;

  @override
  State<DocumentRequestsScreen> createState() => _DocumentRequestsScreenState();
}

class _DocumentRequestsScreenState extends State<DocumentRequestsScreen> {
  List<DocumentRequest>? _requests;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      await DocumentRequestsService.collect(widget.documentsService);
    } on StorageFullException catch (error) {
      if (mounted) await showStorageFullDialog(context, error);
    } catch (_) {}
    try {
      final requests = await DocumentRequestsService.list();
      if (mounted) {
        setState(() {
          _requests = requests;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _new() async {
    if (!PlanService.current.value.has(PlanFeature.documentRequests)) {
      await showPlansPrompt(
        context,
        title: AppConstants.requestsTitle.tr(),
        message: AppConstants.requestsLocked.tr(),
      );
      return;
    }
    final snapshot = await widget.documentsService.loadSnapshot();
    if (!mounted) return;
    final created = await showOptionsSheet<DocumentRequest>(
      context: context,
      builder: (_) =>
          _NewRequestSheet(snapshot: snapshot, initialAlbumId: widget.albumId),
    );
    if (created == null || !mounted) return;
    await _share(created);
    await _refresh();
  }

  Future<void> _share(DocumentRequest request) async {
    final url = request.url;
    if (url == null) {
      showSnack(context, AppConstants.requestsLinkUnknown.tr());
      return;
    }
    final date = DateFormat.yMMMd(
      context.locale.toString(),
    ).format(request.expiresAt);
    await SecurityLockService.withoutAutoLock(
      () => SharePlus.instance.share(
        ShareParams(
          text: AppConstants.requestsShareText.tr(
            namedArgs: {'title': request.title, 'date': date, 'url': url},
          ),
        ),
      ),
    );
  }

  Future<void> _menu(DocumentRequest request) async {
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

        final open = request.status == DocumentRequestStatus.open;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (open && request.url != null) ...[
                item(
                  'share',
                  Icons.ios_share_rounded,
                  AppConstants.requestsShare.tr(),
                ),
                item(
                  'copy',
                  Icons.copy_rounded,
                  AppConstants.requestsCopy.tr(),
                ),
              ],
              if (open)
                item(
                  'close',
                  Icons.block_rounded,
                  AppConstants.requestsClose.tr(),
                ),
              item(
                'delete',
                Icons.delete_outline_rounded,
                AppConstants.requestsDelete.tr(),
                color: AppTheme.destructive,
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
          await _share(request);
        case 'copy':
          await Clipboard.setData(ClipboardData(text: request.url!));
          if (mounted) showSnack(context, AppConstants.requestsCopied.tr());
        case 'close':
          await DocumentRequestsService.close(request.id);
          await _refresh();
        case 'delete':
          final confirmed = await showConfirmDialog(
            context,
            title: AppConstants.requestsDelete.tr(),
            message: AppConstants.requestsDeleteMessage.tr(),
            actionLabel: AppConstants.commonDelete.tr(),
          );
          if (!confirmed) return;
          await DocumentRequestsService.delete(request.id);
          await _refresh();
      }
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.requestsFailed.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = _requests;
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add_rounded),
        label: Text(AppConstants.requestsNew.tr()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
              child: Row(
                children: [
                  const BackButton(),
                  Expanded(
                    child: Text(
                      AppConstants.requestsTitle.tr(),
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
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: requests == null && !_failed
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        children: [
                          if (_failed)
                            _Note(text: AppConstants.requestsFailed.tr())
                          else if (requests!.isEmpty)
                            _Note(
                              icon: Icons.forward_to_inbox_outlined,
                              text: AppConstants.requestsEmpty.tr(),
                            )
                          else
                            for (final request in requests) ...[
                              _RequestCard(
                                request: request,
                                onTap: () => _menu(request),
                              ),
                              const SizedBox(height: 10),
                            ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.icon});

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

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onTap});

  final DocumentRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final received = request.files.length;
    final (label, color) = switch (request.status) {
      _ when received > 0 => (
        AppConstants.requestsReceived.tr(namedArgs: {'count': '$received'}),
        AppTheme.success,
      ),
      DocumentRequestStatus.open => (
        AppConstants.requestsStatusOpen.tr(),
        AppTheme.warning,
      ),
      DocumentRequestStatus.expired => (
        AppConstants.requestsStatusExpired.tr(),
        AppTheme.dimText,
      ),
      DocumentRequestStatus.closed => (
        AppConstants.requestsStatusClosed.tr(),
        AppTheme.dimText,
      ),
    };
    final date = DateFormat.yMMMd(
      context.locale.toString(),
    ).format(request.expiresAt);

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
                      request.title,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color == AppTheme.dimText
                            ? AppTheme.mutedText
                            : color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.more_vert_rounded, color: AppTheme.dimText),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                AppConstants.requestsUntil.tr(namedArgs: {'date': date}),
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
              ),
              for (final file in request.files)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(
                        file.receivedAt == null
                            ? Icons.cloud_download_outlined
                            : Icons.check_circle_rounded,
                        size: 16,
                        color: file.receivedAt == null
                            ? AppTheme.mutedText
                            : AppTheme.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.text),
                        ),
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

class _NewRequestSheet extends StatefulWidget {
  const _NewRequestSheet({required this.snapshot, this.initialAlbumId});

  final DocumentsSnapshot snapshot;
  final String? initialAlbumId;

  @override
  State<_NewRequestSheet> createState() => _NewRequestSheetState();
}

class _NewRequestSheetState extends State<_NewRequestSheet> {
  static const _dayChoices = [3, 7, 14, 30];

  final _title = TextEditingController();
  final _message = TextEditingController();
  int _days = 7;
  late String? _albumId = widget.initialAlbumId;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    try {
      final request = await DocumentRequestsService.create(
        title: _title.text.trim(),
        message: _message.text.trim().isEmpty ? null : _message.text.trim(),
        days: _days,
        albumId: _albumId,
        language: context.locale.languageCode,
      );
      if (mounted) Navigator.of(context).pop(request);
    } on DocumentRequestsException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(
        context,
        (error.notIncluded
                ? AppConstants.requestsLocked
                : AppConstants.requestsFailed)
            .tr(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Every album, the hidden ones too (they're only listed here, to the
    // account's owner), named with their shelf.
    final albums = [
      for (final shelf in [
        ...widget.snapshot.shelves,
        ...widget.snapshot.hiddenShelves,
      ])
        for (final album in shelf.albums)
          (id: album.id, label: '${shelfDisplayName(shelf)} › ${album.name}'),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppConstants.requestsNew.tr(),
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: AppConstants.requestsWhat.tr(),
                hintText: AppConstants.requestsWhatHint.tr(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: AppConstants.requestsMessage.tr(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppConstants.requestsValidFor.tr(),
              style: const TextStyle(color: AppTheme.mutedText),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final days in _dayChoices)
                  ChoiceChip(
                    label: Text(
                      AppConstants.requestsDays.tr(
                        namedArgs: {'count': '$days'},
                      ),
                    ),
                    selected: _days == days,
                    onSelected: (_) => setState(() => _days = days),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: albums.any((a) => a.id == _albumId)
                  ? _albumId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: AppConstants.requestsSaveTo.tr(),
              ),
              dropdownColor: AppTheme.surfaceStrong,
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(AppConstants.requestsGallery.tr()),
                ),
                for (final album in albums)
                  DropdownMenuItem<String?>(
                    value: album.id,
                    child: Text(album.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _albumId = value),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _title.text.trim().isEmpty || _saving ? null : _create,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_rounded),
              label: Text(AppConstants.requestsCreate.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
