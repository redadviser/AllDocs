import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../common/app_constants.dart';
import '../../common/document_actions.dart';
import '../../common/document_file_icon.dart';
import '../../common/document_import_flow.dart';
import '../../common/zip_preview_sheet.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';

/// Folder-by-folder browser for one cloud account: open folders, search,
/// tick files and import them (downloaded into AllDocs).
class CloudBrowserScreen extends StatefulWidget {
  const CloudBrowserScreen({
    super.key,
    required this.documentsService,
    required this.provider,
  });

  final DocumentsService documentsService;
  final CloudProvider provider;

  @override
  State<CloudBrowserScreen> createState() => _CloudBrowserScreenState();
}

class _CloudBrowserScreenState extends State<CloudBrowserScreen> {
  final List<CloudItem> _path = [];
  final Map<String, CloudItem> _selected = {};
  final TextEditingController _searchController = TextEditingController();
  List<CloudItem> _items = const [];
  bool _loading = true;
  String? _error;
  String? _searchQuery;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = _searchQuery;
      final items = query != null
          ? await widget.provider.search(query)
          : await widget.provider.listFolder(
              _path.isEmpty ? null : _path.last.id,
            );
      final visible = items.where(isImportableCloudItem).toList()
        ..sort((a, b) {
          if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      if (!mounted) return;
      setState(() {
        _items = visible;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppConstants.cloudRequestFailed.tr();
      });
    }
  }

  void _openFolder(CloudItem folder) {
    _path.add(folder);
    _searchQuery = null;
    _searchController.clear();
    _load();
  }

  bool _goUp() {
    if (_searchQuery != null) {
      _searchQuery = null;
      _searchController.clear();
      _load();
      return true;
    }
    if (_path.isEmpty) return false;
    _path.removeLast();
    _load();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final title = _searchQuery != null
        ? AppConstants.cloudSearchResults.tr(
            namedArgs: {'query': _searchQuery!},
          )
        : _path.isEmpty
        ? widget.provider.displayName
        : _path.last.name;

    return PopScope(
      canPop: _path.isEmpty && _searchQuery == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUp();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          surfaceTintColor: Colors.transparent,
          title: Text(title, style: const TextStyle(fontSize: 18)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (!_goUp()) Navigator.of(context).pop();
            },
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: AppConstants.cloudSearchHint.tr(
                    namedArgs: {'provider': widget.provider.displayName},
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                onSubmitted: (value) {
                  final query = value.trim();
                  _searchQuery = query.isEmpty ? null : query;
                  _load();
                },
              ),
            ),
            if (_path.isNotEmpty && _searchQuery == null)
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _Crumb(
                      label: widget.provider.displayName,
                      onTap: () {
                        _path.clear();
                        _load();
                      },
                    ),
                    for (var i = 0; i < _path.length; i++)
                      _Crumb(
                        label: _path[i].name,
                        onTap: i == _path.length - 1
                            ? null
                            : () {
                                _path.removeRange(i + 1, _path.length);
                                _load();
                              },
                      ),
                  ],
                ),
              ),
            Expanded(child: _buildList()),
            if (_selected.isNotEmpty)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        AppConstants.cloudImportCount.tr(
                          namedArgs: {'count': '${_selected.length}'},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppTheme.mutedText)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: Text(AppConstants.securityDevicesRetry.tr()),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          AppConstants.cloudEmptyFolder.tr(),
          style: const TextStyle(color: AppTheme.mutedText),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          if (item.isFolder) {
            return ListTile(
              leading: const Icon(Icons.folder_outlined, size: 30),
              title: Text(item.name),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openFolder(item),
            );
          }
          final selected = _selected.containsKey(item.id);
          final meta = [
            if (item.sizeBytes != null) formatBytes(item.sizeBytes!),
            if (item.modifiedAt != null)
              DateFormat.yMMMd().format(item.modifiedAt!.toLocal()),
          ].join(' · ');
          return ListTile(
            leading: DocumentFileIcon(type: item.documentType, size: 38),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: meta.isEmpty
                ? null
                : Text(
                    meta,
                    style: const TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 12,
                    ),
                  ),
            trailing: Checkbox(
              value: selected,
              onChanged: (_) => _toggle(item),
            ),
            onTap: () => _toggle(item),
          );
        },
      ),
    );
  }

  void _toggle(CloudItem item) {
    setState(() {
      _selected.containsKey(item.id)
          ? _selected.remove(item.id)
          : _selected[item.id] = item;
    });
  }

  Future<void> _import() async {
    final all = _selected.values.toList();
    final zips = all
        .where((item) => item.name.toLowerCase().endsWith('.zip'))
        .toList();
    final items = all.where((item) => !zips.contains(item)).toList();
    final progress = ValueNotifier<(int, int)>((0, items.length));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, value, _) => Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    AppConstants.cloudDownloading.tr(
                      namedArgs: {
                        'done': '${value.$1}',
                        'total': '${value.$2}',
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    ImportResult result = ImportResult.empty;
    Object? failure;
    try {
      result = await widget.documentsService.importFromCloud(
        widget.provider,
        items,
        onProgress: (done, total) => progress.value = (done, total),
      );
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    setState(_selected.clear);
    if (failure != null) {
      showSnack(context, AppConstants.cloudRequestFailed.tr());
      return;
    }
    // Zips go through the same "what's inside?" preview as local ones.
    for (final zip in zips) {
      try {
        final downloaded = await widget.provider.download(zip);
        final temp = await getTemporaryDirectory();
        final file = File(
          '${temp.path}/${DateTime.now().microsecondsSinceEpoch}.zip',
        );
        await file.writeAsBytes(downloaded.bytes);
        if (!mounted) return;
        result += await extractPreviewAndImportZipFromPath(
          context,
          widget.documentsService,
          path: file.path,
        );
        await file.delete();
      } catch (_) {
        if (mounted) showSnack(context, AppConstants.cloudRequestFailed.tr());
      }
    }
    if (!mounted) return;
    await reportImport(context, widget.documentsService, result);
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                color: onTap == null ? AppTheme.text : AppTheme.accent,
                fontSize: 13,
              ),
            ),
          ),
        ),
        if (onTap != null)
          const Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppTheme.dimText,
          ),
      ],
    );
  }
}
