import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/local_documents_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('alldocs_migration_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
  });

  tearDown(() {
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  Map<String, dynamic> readRawState() {
    final file = File('${tempDir.path}/alldocs_state.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  void writeRawState(Map<String, dynamic> state) {
    File(
      '${tempDir.path}/alldocs_state.json',
    ).writeAsStringSync(jsonEncode(state));
  }

  Map<String, dynamic> v1StateFixture() {
    return {
      // No 'version' key at all, matching real pre-migration installs.
      'shelves': [
        {
          'id': 'shelf_seed',
          'name': 'Documentos',
          'position': 0,
          'albums': [
            {
              'id': 'album_1700000000000_pessoais',
              'shelf_id': 'shelf_seed',
              'name': 'Pessoais',
              'color_value': 0xFF3F8DFF,
              'icon_name': 'folder',
              'position': 0,
              'document_ids': ['doc_mock'],
              'cover_document_id': 'doc_mock',
            },
          ],
        },
        {
          'id': 'shelf_user',
          'name': 'A Minha Estante',
          'position': 1,
          'albums': [
            {
              'id': 'album_user_contratos',
              'shelf_id': 'shelf_user',
              'name': 'Contratos',
              'color_value': 0xFF3F8DFF,
              'icon_name': 'folder',
              'position': 0,
              'document_ids': ['doc_real'],
              'cover_document_id': 'doc_real',
            },
          ],
        },
      ],
      'documents': [
        {
          'id': 'doc_mock',
          'title': 'Documento Mock',
          'file_name': 'mock.pdf',
          'type': 'pdf',
          'date_label': '01/01/2024',
          'size_label': '1 KB',
          'size_bytes': 1024,
          'imported_at': DateTime(2024, 1, 1).toIso8601String(),
          'album_id': 'album_1700000000000_pessoais',
          'is_new': false,
          'is_imported': true,
        },
        {
          'id': 'doc_real',
          'title': 'Contrato Real',
          'file_name': 'contrato.pdf',
          'type': 'pdf',
          'date_label': '02/01/2024',
          'size_label': '2 KB',
          'size_bytes': 2048,
          'imported_at': DateTime(2024, 1, 2).toIso8601String(),
          'album_id': 'album_user_contratos',
          'is_new': false,
          'is_imported': true,
        },
      ],
      'device_folder_paths': <String, String>{},
    };
  }

  test('migrates seeded mock albums into the inbox and bumps the version', () async {
    writeRawState(v1StateFixture());

    final snapshot = await const LocalDocumentsStore().loadSnapshot();

    // The seeded "Documentos" shelf only ever held the mock album, so once
    // that album is stripped out the now-empty shelf is dropped too.
    expect(
      snapshot.shelves.where((shelf) => shelf.name == 'Documentos'),
      isEmpty,
    );

    // A real, user-created shelf/album must survive migration untouched.
    final userShelf = snapshot.shelves.singleWhere(
      (shelf) => shelf.id == 'shelf_user',
    );
    expect(userShelf.albums.single.id, 'album_user_contratos');
    expect(
      snapshot.documentsForAlbum('album_user_contratos').single.id,
      'doc_real',
    );

    // The document that lived only in the removed mock album lands unfiled.
    final migratedDoc = snapshot.documents.singleWhere(
      (doc) => doc.id == 'doc_mock',
    );
    expect(migratedDoc.albumId, isNull);
    expect(migratedDoc.isNew, isTrue);
    expect(
      snapshot.unorganizedDocuments.map((doc) => doc.id),
      contains('doc_mock'),
    );

    // Migration is persisted back to disk, not just applied in memory.
    expect(readRawState()['version'], 2);
  });

  test('does not re-run migration once the state is already on version 2', () async {
    final alreadyMigrated = Map<String, dynamic>.from(v1StateFixture());
    alreadyMigrated['version'] = 2;
    writeRawState(alreadyMigrated);

    final snapshot = await const LocalDocumentsStore().loadSnapshot();

    // With version already at 2, the mock-seed cleanup must not run, even
    // though the fixture still contains a mock-shaped album.
    expect(
      snapshot.shelves.where((shelf) => shelf.name == 'Documentos'),
      isNotEmpty,
    );
    final migratedDoc = snapshot.documents.singleWhere(
      (doc) => doc.id == 'doc_mock',
    );
    expect(migratedDoc.albumId, 'album_1700000000000_pessoais');
  });

  test('recovers with a clean initial state when the JSON file is corrupt', () async {
    File(
      '${tempDir.path}/alldocs_state.json',
    ).writeAsStringSync('{not valid json');

    final snapshot = await const LocalDocumentsStore().loadSnapshot();

    expect(snapshot.documents, isEmpty);
    expect(snapshot.shelves, isEmpty);
    expect(readRawState()['version'], 2);
  });
}
