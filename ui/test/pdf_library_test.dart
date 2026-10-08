import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:all_docs/models/models.dart';
import 'package:all_docs/services/documents_service.dart';
import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/pdf_tools.dart';
import 'package:all_docs/services/plan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late DocumentsService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('alldocs_pdf_library_');
    LocalDocumentsStore.debugDirectory = dir;
    // The phone's temp folder, where generated PDFs wait to be imported.
    final temp = Directory('${dir.path}/tmp')..createSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
    PlanService.current.value = PlanCatalog.builtIn.byId(AppPlan.premium);
    service = DocumentsService.local();
  });

  tearDown(() {
    service.dispose();
    PlanService.current.value = PlanCatalog.builtIn.byId(AppPlan.free);
    LocalDocumentsStore.debugDirectory = null;
    dir.deleteSync(recursive: true);
  });

  Future<DocumentFile> importPdf(String name, int pages) async {
    final doc = pw.Document();
    for (var i = 1; i <= pages; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Text('$name $i'),
        ),
      );
    }
    final source = Directory.systemTemp.createTempSync('pdf_src_');
    final file = File('${source.path}/$name.pdf');
    await file.writeAsBytes(await doc.save());
    final result = await service.importFilePaths([file.path]);
    return result.documents.single;
  }

  test('merge, extract and sign add new documents to the library', () async {
    final a = await importPdf('Contrato', 2);
    final b = await importPdf('Anexo', 3);
    final album = (await service.createAlbum(null, 'Casa'))!;
    await service.addDocumentsToAlbum([a.id], album);
    final contract = (await service.loadSnapshot()).documents.firstWhere(
      (d) => d.id == a.id,
    );

    final merged = await service.mergePdfs([
      contract,
      b,
    ], title: 'Contrato + anexo');
    expect(merged, isNotNull);
    expect(merged!.title, 'Contrato + anexo');
    expect(merged.albumIds, [album]);
    expect(await PdfTools.pageCount(merged.localPath!), 5);

    final part = await service.extractPdfPages(
      b,
      from: 2,
      to: 3,
      title: 'Anexo (páginas 2–3)',
    );
    expect(await PdfTools.pageCount(part!.localPath!), 2);

    final signature = img.Image(width: 300, height: 100, numChannels: 4);
    final signed = await service.signPdf(
      contract,
      signaturePng: Uint8List.fromList(img.encodePng(signature)),
      aspectRatio: 3,
      page: 2,
      corner: SignatureCorner.bottomRight,
      title: 'Contrato (assinado)',
    );
    expect(signed, isNotNull);

    final library = (await service.loadSnapshot()).documents;
    expect(library, hasLength(5));
  });

  test('compressing a document that cannot shrink leaves it alone', () async {
    final doc = await importPdf('Texto', 1);
    final sizes = await service.compressPdf(doc);
    expect(sizes.after, lessThanOrEqualTo(sizes.before));
    expect(File(doc.localPath!).existsSync(), isTrue);
  });
}
