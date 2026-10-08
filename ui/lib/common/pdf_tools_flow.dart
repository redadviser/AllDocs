import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pdf_tools.dart';
import '../services/services.dart';
import '../services/watermark_overlay.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'app_sheet.dart';
import 'document_actions.dart' show showSnack;
import 'plan_prompts.dart';
import 'zip_preview_sheet.dart' show formatBytes;

/// A real PDF on disk (the type alone also covers unknown extensions).
bool isPdfDocument(DocumentFile document) =>
    document.localPath != null &&
    document.fileName.toLowerCase().endsWith('.pdf');

/// Whether the plan includes [feature]; if not, says which plans do and
/// offers them.
Future<bool> _allowed(BuildContext context, PlanFeature feature) async {
  if (PlanService.current.value.has(feature)) return true;
  await showPlansPrompt(
    context,
    title: AppConstants.pdfTools.tr(),
    message: AppConstants.pdfLocked.tr(),
  );
  return false;
}

/// Runs [work] behind a "Preparing the PDF…" dialog. Storage and other
/// failures are explained to the user; null means it didn't happen.
Future<T?> _run<T>(BuildContext context, Future<T> Function() work) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppTheme.surface,
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(AppConstants.pdfWorking.tr())),
          ],
        ),
      ),
    ),
  );
  try {
    final result = await work();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return result;
  } on StorageFullException catch (error) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      await showStorageFullDialog(context, error);
    }
  } catch (_) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showSnack(context, AppConstants.pdfFailed.tr());
    }
  }
  return null;
}

void _reportCreated(BuildContext context, DocumentFile? created) {
  if (created == null || !context.mounted) return;
  showSnack(
    context,
    AppConstants.pdfCreated.tr(namedArgs: {'name': created.title}),
  );
}

/// Merge / extract / compress / sign for one PDF.
Future<void> showPdfToolsSheet(
  BuildContext context,
  DocumentsService documentsService,
  DocumentFile document,
) async {
  if (!await _allowed(context, PlanFeature.pdfTools) || !context.mounted) {
    return;
  }
  final choice = await showOptionsSheet<String>(
    context: context,
    builder: (sheetContext) {
      Widget tile(String id, IconData icon, String label, [String? hint]) {
        return ListTile(
          leading: Icon(icon, color: AppTheme.primarySoft),
          title: Text(
            label,
            style: const TextStyle(color: AppTheme.text, fontSize: 15),
          ),
          subtitle: hint == null
              ? null
              : Text(hint, style: const TextStyle(color: AppTheme.mutedText)),
          onTap: () => Navigator.of(sheetContext).pop(id),
        );
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                AppConstants.pdfTools.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            tile('merge', Icons.merge_type_rounded, AppConstants.pdfMerge.tr()),
            tile(
              'extract',
              Icons.content_cut_rounded,
              AppConstants.pdfExtract.tr(),
            ),
            tile(
              'compress',
              Icons.compress_rounded,
              AppConstants.pdfCompress.tr(),
              AppConstants.pdfCompressHint.tr(),
            ),
            tile('sign', Icons.draw_outlined, AppConstants.pdfSign.tr()),
          ],
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'merge':
      await _merge(context, documentsService, document);
    case 'extract':
      await _extract(context, documentsService, document);
    case 'compress':
      await _compress(context, documentsService, document);
    case 'sign':
      await _sign(context, documentsService, document);
  }
}

Future<void> _merge(
  BuildContext context,
  DocumentsService documentsService,
  DocumentFile document,
) async {
  final snapshot = await documentsService.loadSnapshot();
  final others = [
    for (final other in snapshot.documents)
      if (other.id != document.id && isPdfDocument(other)) other,
  ];
  if (!context.mounted) return;
  if (others.isEmpty) {
    showSnack(context, AppConstants.pdfMergeEmpty.tr());
    return;
  }
  final picked = await showOptionsSheet<List<DocumentFile>>(
    context: context,
    builder: (_) => _MergePicker(first: document, candidates: others),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;
  final created = await _run(
    context,
    () => documentsService.mergePdfs(
      [document, ...picked],
      title:
          '${document.title} + ${AppConstants.pdfMergedSuffix.tr(namedArgs: {'count': '${picked.length}'})}',
    ),
  );
  if (context.mounted) _reportCreated(context, created);
}

class _MergePicker extends StatefulWidget {
  const _MergePicker({required this.first, required this.candidates});

  final DocumentFile first;
  final List<DocumentFile> candidates;

  @override
  State<_MergePicker> createState() => _MergePickerState();
}

class _MergePickerState extends State<_MergePicker> {
  // In the order they were ticked, which is the order they're joined in.
  final _picked = <DocumentFile>[];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppConstants.pdfMerge.tr(),
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppConstants.pdfMergePick.tr(),
              style: const TextStyle(color: AppTheme.mutedText),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              leading: const _OrderBadge(order: 1),
              title: Text(
                widget.first.title,
                style: const TextStyle(color: AppTheme.text),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final candidate in widget.candidates)
                    ListTile(
                      dense: true,
                      onTap: () => setState(() {
                        if (!_picked.remove(candidate)) _picked.add(candidate);
                      }),
                      leading: _picked.contains(candidate)
                          ? _OrderBadge(order: _picked.indexOf(candidate) + 2)
                          : const Icon(
                              Icons.radio_button_unchecked_rounded,
                              color: AppTheme.dimText,
                            ),
                      title: Text(
                        candidate.title,
                        style: const TextStyle(color: AppTheme.text),
                      ),
                      subtitle: Text(
                        candidate.sizeLabel,
                        style: const TextStyle(color: AppTheme.mutedText),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _picked.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(List.of(_picked)),
              child: Text(
                AppConstants.pdfMergeButton.tr(
                  namedArgs: {'count': '${_picked.length + 1}'},
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderBadge extends StatelessWidget {
  const _OrderBadge({required this.order});

  final int order;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 12,
      backgroundColor: AppTheme.accent,
      child: Text(
        '$order',
        style: TextStyle(
          color: AppTheme.onAccent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Future<void> _extract(
  BuildContext context,
  DocumentsService documentsService,
  DocumentFile document,
) async {
  final total = await _run(
    context,
    () => PdfTools.pageCount(document.localPath!),
  );
  if (total == null || !context.mounted) return;
  if (total < 2) {
    showSnack(context, AppConstants.pdfExtractSinglePage.tr());
    return;
  }
  var range = RangeValues(1, total.toDouble());
  final chosen = await showDialog<RangeValues>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(AppConstants.pdfExtract.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppConstants.pdfExtractRange.tr(
                namedArgs: {
                  'from': '${range.start.round()}',
                  'to': '${range.end.round()}',
                  'total': '$total',
                },
              ),
              style: const TextStyle(color: AppTheme.text, fontSize: 15),
            ),
            RangeSlider(
              values: range,
              min: 1,
              max: total.toDouble(),
              divisions: total - 1,
              labels: RangeLabels(
                '${range.start.round()}',
                '${range.end.round()}',
              ),
              onChanged: (value) => setState(() => range = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppConstants.commonCancel.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(range),
            child: Text(AppConstants.pdfCreate.tr()),
          ),
        ],
      ),
    ),
  );
  if (chosen == null || !context.mounted) return;
  final from = chosen.start.round();
  final to = chosen.end.round();
  final created = await _run(
    context,
    () => documentsService.extractPdfPages(
      document,
      from: from,
      to: to,
      title:
          '${document.title} (${AppConstants.pdfPagesSuffix.tr(namedArgs: {'from': '$from', 'to': '$to'})})',
    ),
  );
  if (context.mounted) _reportCreated(context, created);
}

Future<void> _compress(
  BuildContext context,
  DocumentsService documentsService,
  DocumentFile document,
) async {
  final sizes = await _run(
    context,
    () => documentsService.compressPdf(document),
  );
  if (sizes == null || !context.mounted) return;
  showSnack(
    context,
    sizes.after < sizes.before
        ? AppConstants.pdfCompressDone.tr(
            namedArgs: {
              'before': formatBytes(sizes.before),
              'after': formatBytes(sizes.after),
            },
          )
        : AppConstants.pdfCompressNone.tr(),
  );
}

Future<void> _sign(
  BuildContext context,
  DocumentsService documentsService,
  DocumentFile document,
) async {
  final total = await _run(
    context,
    () => PdfTools.pageCount(document.localPath!),
  );
  if (total == null || !context.mounted) return;
  final signature = await showOptionsSheet<_Signature>(
    context: context,
    builder: (_) => _SignaturePad(pageCount: total),
  );
  if (signature == null || !context.mounted) return;
  final created = await _run(
    context,
    () => documentsService.signPdf(
      document,
      signaturePng: signature.png,
      aspectRatio: signature.aspectRatio,
      page: signature.page,
      corner: signature.corner,
      title: '${document.title} (${AppConstants.pdfSignedSuffix.tr()})',
    ),
  );
  if (context.mounted) _reportCreated(context, created);
}

class _Signature {
  const _Signature({
    required this.png,
    required this.aspectRatio,
    required this.page,
    required this.corner,
  });

  final Uint8List png;
  final double aspectRatio;
  final int page;
  final SignatureCorner corner;
}

/// Draw a signature with a finger; pick the page and where it goes.
class _SignaturePad extends StatefulWidget {
  const _SignaturePad({required this.pageCount});

  final int pageCount;

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  static const _ink = Color(0xFF14286B);

  final _strokes = <List<Offset>>[];
  late int _page = widget.pageCount;
  SignatureCorner _corner = SignatureCorner.bottomRight;

  /// The strokes drawn on a transparent PNG, cropped to the ink.
  Future<_Signature?> _export() async {
    final points = _strokes.expand((stroke) => stroke).toList();
    if (points.isEmpty) return null;
    const pad = 8.0;
    const scale = 3.0;
    var left = points.first.dx, right = left;
    var top = points.first.dy, bottom = top;
    for (final point in points) {
      left = point.dx < left ? point.dx : left;
      right = point.dx > right ? point.dx : right;
      top = point.dy < top ? point.dy : top;
      bottom = point.dy > bottom ? point.dy : bottom;
    }
    final width = right - left + pad * 2;
    final height = bottom - top + pad * 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(pad - left, pad - top);
    _SignaturePainter(_strokes, _ink).paint(canvas, Size.infinite);
    final image = await recorder.endRecording().toImage(
      (width * scale).ceil(),
      (height * scale).ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return _Signature(
      png: bytes!.buffer.asUint8List(),
      aspectRatio: width / height,
      page: _page,
      corner: _corner,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppConstants.pdfSignTitle.tr(),
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(_strokes.clear),
                  child: Text(AppConstants.pdfSignClear.tr()),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // White, like the paper it ends up on.
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 190,
                color: Colors.white,
                child: GestureDetector(
                  onPanStart: (details) =>
                      setState(() => _strokes.add([details.localPosition])),
                  onPanUpdate: (details) =>
                      setState(() => _strokes.last.add(details.localPosition)),
                  child: CustomPaint(
                    painter: _SignaturePainter(_strokes, _ink),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                DropdownButton<int>(
                  value: _page,
                  dropdownColor: AppTheme.surfaceStrong,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var page = 1; page <= widget.pageCount; page++)
                      DropdownMenuItem(
                        value: page,
                        child: Text(
                          AppConstants.pdfSignPage.tr(
                            namedArgs: {'page': '$page'},
                          ),
                        ),
                      ),
                  ],
                  onChanged: (page) => setState(() => _page = page ?? _page),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<SignatureCorner>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: SignatureCorner.bottomLeft,
                        label: Text(AppConstants.pdfSignLeft.tr()),
                      ),
                      ButtonSegment(
                        value: SignatureCorner.bottomCenter,
                        label: Text(AppConstants.pdfSignCenter.tr()),
                      ),
                      ButtonSegment(
                        value: SignatureCorner.bottomRight,
                        label: Text(AppConstants.pdfSignRight.tr()),
                      ),
                    ],
                    selected: {_corner},
                    onSelectionChanged: (value) =>
                        setState(() => _corner = value.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _strokes.isEmpty
                  ? null
                  : () async {
                      final signature = await _export();
                      if (context.mounted) Navigator.of(context).pop(signature);
                    },
              child: Text(AppConstants.pdfSignButton.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes, this.ink);

  final List<List<Offset>> strokes;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.6, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length - 1; i++) {
        // Through the midpoints, so fast strokes come out smooth.
        final mid = Offset.lerp(stroke[i], stroke[i + 1], 0.5)!;
        path.quadraticBezierTo(stroke[i].dx, stroke[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(stroke.last.dx, stroke.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}

/// Asks what the copy is for, then shares it with "Copy for … – 10/2026"
/// over every page.
Future<void> shareWatermarkedCopy(
  BuildContext context,
  DocumentsService documentsService,
  DocumentFile document,
) async {
  if (!await _allowed(context, PlanFeature.watermark) || !context.mounted) {
    return;
  }
  final date = DateFormat('MM/yyyy').format(DateTime.now());
  final text = await showDialog<String>(
    context: context,
    builder: (_) => _WatermarkDialog(date: date),
  );
  if (text == null || !context.mounted) return;
  await _run(
    context,
    () => documentsService.shareWatermarkedCopy(
      document,
      overlay: (width, height) =>
          renderWatermarkOverlay(text, pageWidth: width, pageHeight: height),
      fileName: '${document.title} (${AppConstants.pdfWatermarkTitle.tr()}).pdf'
          .replaceAll('/', '-'),
    ),
  );
}

class _WatermarkDialog extends StatefulWidget {
  const _WatermarkDialog({required this.date});

  final String date;

  @override
  State<_WatermarkDialog> createState() => _WatermarkDialogState();
}

class _WatermarkDialogState extends State<_WatermarkDialog> {
  final _purpose = TextEditingController();

  static const _presets = [
    AppConstants.pdfPresetRent,
    AppConstants.pdfPresetBank,
    AppConstants.pdfPresetJob,
    AppConstants.pdfPresetInsurance,
  ];

  @override
  void dispose() {
    _purpose.dispose();
    super.dispose();
  }

  String get _text => AppConstants.pdfWatermarkText.tr(
    namedArgs: {'purpose': _purpose.text.trim(), 'date': widget.date},
  );

  @override
  Widget build(BuildContext context) {
    final ready = _purpose.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(AppConstants.pdfWatermarkTitle.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppConstants.pdfWatermarkHint.tr(),
            style: const TextStyle(color: AppTheme.mutedText, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _purpose,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: AppConstants.pdfWatermarkPurpose.tr(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in _presets)
                ActionChip(
                  label: Text(preset.tr()),
                  onPressed: () => setState(() => _purpose.text = preset.tr()),
                ),
            ],
          ),
          if (ready) ...[
            const SizedBox(height: 14),
            Text(
              _text,
              style: const TextStyle(
                color: Color(0xFFE57368),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppConstants.commonCancel.tr()),
        ),
        FilledButton.icon(
          onPressed: ready ? () => Navigator.of(context).pop(_text) : null,
          icon: const Icon(Icons.ios_share_rounded, size: 18),
          label: Text(AppConstants.actionsShare.tr()),
        ),
      ],
    );
  }
}
