import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/sync/sync_entities.dart';
import 'package:all_docs/services/vault/vault_format.dart';

void main() {
  const dir = '/lib/documents';

  Map<String, dynamic> stateWith(List<Map<String, dynamic>> documents) => {
    'version': 3,
    'documents': documents,
    'shelves': <Map<String, dynamic>>[],
  };

  test('sealed and the local path never travel', () {
    final entities = entitiesFromState(
      stateWith([
        {
          'id': 'a',
          'file_name': 'cc.pdf',
          'local_path': '$dir/a.adv',
          'sealed': true,
        },
      ]),
    );
    final entity = entities[documentKey('a')]!;
    expect(entity.containsKey('sealed'), isFalse);
    expect(entity.containsKey('local_path'), isFalse);
    expect(entity['stored_name'], 'a.adv');
  });

  group('a received document lands', () {
    final fromSealedPhone = {
      documentKey('b'): {
        'id': 'b',
        'file_name': 'nif.pdf',
        'stored_name': 'b.adv',
      },
    };
    final fromPlainPhone = {
      documentKey('b'): {
        'id': 'b',
        'file_name': 'nif.pdf',
        'stored_name': 'b_nif.pdf',
      },
    };

    Map<String, dynamic> only(Map<String, dynamic> state) =>
        (state['documents'] as List).single as Map<String, dynamic>;

    test('sealed as <id>.adv on an encrypted phone', () {
      for (final incoming in [fromSealedPhone, fromPlainPhone]) {
        final document = only(
          stateFromEntities(
            incoming,
            current: stateWith([]),
            documentsDirectory: dir,
            sealing: true,
            fileExists: (_) => true,
          ),
        );
        expect(document['local_path'], '$dir/b.adv');
        expect(document['sealed'], isTrue);
      }
    });

    test('as a plain, non-.adv file on a phone that is not encrypted', () {
      final document = only(
        stateFromEntities(
          fromSealedPhone,
          current: stateWith([]),
          documentsDirectory: dir,
          fileExists: (_) => true,
        ),
      );
      expect(document['local_path'], '$dir/b_nif.pdf');
      expect(document.containsKey('sealed'), isFalse);
      expect(
        localFileName(fromPlainPhone.values.single, sealing: false),
        'b_nif.pdf',
      );
    });

    test("this phone's own copy not encrypted yet stays where it is", () {
      final document = only(
        stateFromEntities(
          fromPlainPhone,
          current: stateWith([
            {'id': 'b', 'local_path': '$dir/b_nif.pdf'},
          ]),
          documentsDirectory: dir,
          sealing: true,
          fileExists: (path) => path == '$dir/b_nif.pdf',
        ),
      );
      expect(document['local_path'], '$dir/b_nif.pdf');
      expect(document.containsKey('sealed'), isFalse);
    });
  });

  test('plainLength inverts sealedLength', () {
    for (final length in [0, 1, 1048575, 1048576, 1048577, 5 * 1048576 + 3]) {
      expect(VaultFormat.plainLength(VaultFormat.sealedLength(length)), length);
      expect(
        VaultFormat.plainLength(
          VaultFormat.sealedLength(length, chunkLog2: 16),
          chunkLog2: 16,
        ),
        length,
      );
    }
  });

  test(
    'a document id from another phone cannot leave the documents folder',
    () {
      final state = stateFromEntities(
        {
          documentKey('../../x'): {'id': '../../x', 'stored_name': 'x.pdf'},
          documentKey('ok_1'): {'id': 'ok_1', 'stored_name': 'ok_1_a.pdf'},
        },
        current: stateWith([]),
        documentsDirectory: dir,
        sealing: true,
        fileExists: (_) => true,
      );
      final ids = [for (final d in state['documents'] as List) d['id']];
      expect(ids, ['ok_1']);
      expect(isSafeDocumentId('../../x'), isFalse);
      expect(isSafeDocumentId(r'a\b'), isFalse);
      expect(isSafeDocumentId('doc_1700000000_abc'), isTrue);
    },
  );
}
