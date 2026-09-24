import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/scan_image_filter.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'app_sheet.dart';

/// After capturing pages: pick the look (original, grayscale, black and
/// white, high contrast), previewed on the first page. Null = cancelled.
Future<ScanFilter?> showScanFilterSheet(
  BuildContext context,
  List<String> pages,
) {
  if (pages.isEmpty || !context.mounted) {
    return Future.value(ScanFilter.original);
  }
  return showAppSheet<ScanFilter>(
    context: context,
    isDismissible: false,
    builder: (context) => _ScanFilterSheet(pages: pages),
  );
}

class _ScanFilterSheet extends StatefulWidget {
  const _ScanFilterSheet({required this.pages});

  final List<String> pages;

  @override
  State<_ScanFilterSheet> createState() => _ScanFilterSheetState();
}

class _ScanFilterSheetState extends State<_ScanFilterSheet> {
  ScanFilter _filter = ScanFilter.original;
  final Map<ScanFilter, Future<List<int>?>> _previews = {};

  Future<List<int>?> _preview(ScanFilter filter) {
    return _previews.putIfAbsent(
      filter,
      () => scanFilterPreview(widget.pages.first, filter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppConstants.scanFilterTitle.tr(),
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppConstants.scanFilterPages.tr(
              namedArgs: {'count': '${widget.pages.length}'},
            ),
            style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: height * 0.42,
            child: Center(child: _PreviewImage(future: _preview(_filter))),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 98,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final filter in ScanFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _filter = filter),
                      child: Column(
                        children: [
                          Container(
                            width: 58,
                            height: 70,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: filter == _filter
                                    ? AppTheme.accent
                                    : AppTheme.border,
                                width: filter == _filter ? 2 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: _PreviewImage(
                                future: _preview(filter),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _label(filter),
                            style: TextStyle(
                              color: filter == _filter
                                  ? AppTheme.text
                                  : AppTheme.mutedText,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(AppConstants.commonCancel.tr()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_filter),
                  child: Text(AppConstants.scanFilterSave.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _label(ScanFilter filter) {
    return switch (filter) {
      ScanFilter.original => AppConstants.scanFilterOriginal.tr(),
      ScanFilter.grayscale => AppConstants.scanFilterGrayscale.tr(),
      ScanFilter.blackAndWhite => AppConstants.scanFilterBlackWhite.tr(),
      ScanFilter.highContrast => AppConstants.scanFilterContrast.tr(),
    };
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.future, this.fit = BoxFit.contain});

  final Future<List<int>?> future;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>?>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.memory(
          Uint8List.fromList(bytes),
          fit: fit,
          gaplessPlayback: true,
        );
      },
    );
  }
}
