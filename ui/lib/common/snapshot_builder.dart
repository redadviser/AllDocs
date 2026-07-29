import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';

class SnapshotBuilder extends StatefulWidget {
  const SnapshotBuilder({
    super.key,
    required this.documentsService,
    required this.builder,
  });

  final DocumentsService documentsService;
  final Widget Function(BuildContext context, DocumentsSnapshot snapshot)
  builder;

  @override
  State<SnapshotBuilder> createState() => _SnapshotBuilderState();
}

class _SnapshotBuilderState extends State<SnapshotBuilder> {
  late Future<DocumentsSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = widget.documentsService.loadSnapshot();
    widget.documentsService.revision.addListener(_reload);
  }

  @override
  void didUpdateWidget(covariant SnapshotBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentsService == widget.documentsService) return;
    oldWidget.documentsService.revision.removeListener(_reload);
    widget.documentsService.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.documentsService.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    setState(() {
      _snapshotFuture = widget.documentsService.loadSnapshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentsSnapshot>(
      future: _snapshotFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return widget.builder(context, snapshot.data!);
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                AppConstants.errorLoadDocuments.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }

        return Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        );
      },
    );
  }
}
