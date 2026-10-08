import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:all_docs/models/models.dart';
import 'package:all_docs/services/documents_service.dart';
import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/plan_service.dart';
import 'package:all_docs/services/secure_zip_extractor.dart';

void main() {
  late Directory tempDir;
  late DocumentsService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('alldocs_limit_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
    PlanService.current.value = const AppPlan(
      id: AppPlan.free,
      name: 'Pocket',
      priceMonthlyCents: 0,
      priceYearlyCents: 0,
      storageBytes: 1000,
      maxActiveReminders: 3,
      maxDevices: 1,
      features: {},
    );
    service = DocumentsService.local();
  });

  tearDown(() {
    service.dispose();
    PlanService.current.value = PlanCatalog.builtIn.byId(AppPlan.free);
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  // Content differs per file name: identical files are skipped as duplicates.
  List<ExtractedZipEntry> file(String name, int length) => [
    ExtractedZipEntry(fileName: name, bytes: utf8.encode(name[0] * length)),
  ];

  test('an import that would pass the plan limit is refused', () async {
    await service.importExtractedZipEntries(file('a.txt', 600));

    await expectLater(
      service.importExtractedZipEntries(file('b.txt', 600)),
      throwsA(
        isA<StorageFullException>()
            .having((e) => e.neededBytes, 'neededBytes', 600)
            .having((e) => e.summary.freeBytes, 'freeBytes', 400),
      ),
    );
    final snapshot = await service.loadSnapshot();
    expect(snapshot.documents, hasLength(1));
    expect(snapshot.profile.storageSummary.limitBytes, 1000);
  });

  test('emptying space into the recycle bin makes room', () async {
    final first = await service.importExtractedZipEntries(file('a.txt', 600));
    await service.moveToTrash([first.documents.single.id]);

    final second = await service.importExtractedZipEntries(file('b.txt', 600));
    expect(second.documents, hasLength(1));
  });

  test('a bigger plan raises the limit straight away', () async {
    await service.importExtractedZipEntries(file('a.txt', 600));
    PlanService.current.value = PlanCatalog.builtIn.byId(AppPlan.premium);

    final result = await service.importExtractedZipEntries(file('b.txt', 600));
    expect(result.documents, hasLength(1));
  });
}
