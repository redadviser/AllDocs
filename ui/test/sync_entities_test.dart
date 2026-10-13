import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/sync/sync_crypto.dart';
import 'package:all_docs/services/sync/sync_entities.dart';

Map<String, dynamic> _state({
  List<Map<String, dynamic>> documents = const [],
  List<Map<String, dynamic>> shelves = const [],
}) => {
  'version': 3,
  'device_folder_paths': {'documents': '/storage/Docs'},
  'starter_shelf_version': 2,
  'documents': documents,
  'shelves': shelves,
};

Map<String, dynamic> _doc(
  String id, {
  String title = 'Doc',
  List<String> albums = const [],
  String? checksum,
}) => {
  'id': id,
  'title': title,
  'file_name': '$id.pdf',
  'local_path': '/phone/documents/$id.pdf',
  'album_ids': albums,
  'album_id': albums.isEmpty ? null : albums.first,
  'checksum': checksum ?? 'sum-$id',
  'imported_at': '2026-10-0${id.length}T10:00:00.000',
  'is_favorite': false,
  'tags': <String>[],
};

Map<String, dynamic> _shelf(
  String id,
  String name, {
  int position = 0,
  bool hidden = false,
  List<Map<String, dynamic>> albums = const [],
}) => {
  'id': id,
  'name': name,
  'position': position,
  'albums': albums,
  if (hidden) 'hidden': true,
};

Map<String, dynamic> _album(
  String id,
  String name, {
  required String shelf,
  int position = 0,
  List<String> documents = const [],
}) => {
  'id': id,
  'shelf_id': shelf,
  'name': name,
  'color_value': 1,
  'icon_name': 'folder',
  'position': position,
  'document_ids': documents,
  'cover_document_id': documents.isEmpty ? null : documents.first,
};

void main() {
  group('entities', () {
    test('drop what is only true on this phone', () {
      final entities = entitiesFromState(
        _state(
          documents: [
            _doc('d1', albums: ['a1']),
          ],
          shelves: [
            _shelf(
              's1',
              'Casa',
              albums: [
                _album('a1', 'Contas', shelf: 's1', documents: ['d1']),
              ],
            ),
          ],
        ),
      );
      expect(entities.keys, containsAll(['doc:d1', 'shelf:s1', 'album:a1']));
      expect(entities['doc:d1']!.containsKey('local_path'), isFalse);
      expect(entities['doc:d1']!['stored_name'], 'd1.pdf');
      expect(entities['shelf:s1']!.containsKey('albums'), isFalse);
      expect(entities['album:a1']!.containsKey('document_ids'), isFalse);
      expect(entities['album:a1']!['shelf_id'], 's1');
    });

    test('round trip keeps the library and this phone\'s settings', () {
      final state = _state(
        documents: [
          _doc('d1', albums: ['a1']),
          _doc('d22'),
        ],
        shelves: [
          _shelf(
            's1',
            'Casa',
            albums: [
              _album('a1', 'Contas', shelf: 's1', documents: ['d1']),
            ],
          ),
        ],
      );
      final back = stateFromEntities(
        entitiesFromState(state),
        current: state,
        documentsDirectory: '/phone/documents',
      );
      expect(sameJson(back, state), isTrue);
    });

    test('a field edited on each device keeps both edits', () {
      final base = entitiesFromState(_state(documents: [_doc('d1')]));
      final onA = entitiesFromState(
        _state(documents: [_doc('d1', title: 'Novo nome')]),
      );
      final onB = entitiesFromState(
        _state(documents: [_doc('d1')..['is_favorite'] = true]),
      );
      final server = copyEntities(base);
      applyChanges(server, diffEntities(base, onA));
      applyChanges(server, diffEntities(base, onB));
      expect(server['doc:d1']!['title'], 'Novo nome');
      expect(server['doc:d1']!['is_favorite'], isTrue);
    });

    test('a deletion wins over an edit made at the same time', () {
      final base = entitiesFromState(_state(documents: [_doc('d1')]));
      final server = copyEntities(base);
      applyChanges(server, diffEntities(base, {}));
      applyChanges(
        server,
        diffEntities(
          base,
          entitiesFromState(_state(documents: [_doc('d1', title: 'x')])),
        ),
      );
      expect(server.containsKey('doc:d1'), isFalse);
    });

    test('changes survive their JSON form', () {
      final base = entitiesFromState(_state(documents: [_doc('d1')]));
      final next = entitiesFromState(
        _state(
          documents: [
            _doc('d1', title: 'T')..remove('tags'),
            _doc('d2'),
          ],
        ),
      );
      final wire =
          jsonDecode(
                jsonEncode([
                  for (final c in diffEntities(base, next)) c.toJson(),
                ]),
              )
              as List;
      final applied = copyEntities(base);
      applyChanges(applied, [
        for (final raw in wire)
          SyncChange.fromJson(raw as Map<String, dynamic>),
      ]);
      expect(sameJson(applied, next), isTrue);
    });

    test('a document whose file has not arrived stays out, its album too', () {
      final entities = entitiesFromState(
        _state(
          documents: [
            _doc('d1', albums: ['a1']),
            _doc('d2', albums: ['a1']),
          ],
          shelves: [
            _shelf(
              's1',
              'Casa',
              albums: [
                _album('a1', 'Contas', shelf: 's1', documents: ['d1', 'd2']),
              ],
            ),
          ],
        ),
      );
      final state = stateFromEntities(
        entities,
        current: _state(),
        documentsDirectory: '/b/documents',
        withheld: {'d2'},
      );
      expect([for (final d in state['documents'] as List) d['id']], ['d1']);
      final album = (state['shelves'] as List).first['albums'].first as Map;
      expect(album['document_ids'], ['d1']);
      expect(
        (state['documents'] as List).first['local_path'],
        '/b/documents/d1.pdf',
      );
      expect(state['device_folder_paths'], {'documents': '/storage/Docs'});
    });

    test('an album whose shelf went away lands on the first shelf', () {
      final entities = entitiesFromState(
        _state(
          shelves: [
            _shelf('s1', 'Casa'),
            _shelf('s2', 'Ocultos', position: 1, hidden: true),
          ],
        ),
      );
      entities['album:a9'] = {
        'id': 'a9',
        'shelf_id': 'gone',
        'name': 'Novo',
        'position': 0,
      };
      final state = stateFromEntities(
        entities,
        current: _state(),
        documentsDirectory: '/x',
      );
      final shelves = state['shelves'] as List;
      expect((shelves.first['albums'] as List).single['id'], 'a9');
      expect((shelves.first['albums'] as List).single['shelf_id'], 's1');
    });
  });

  group('joining', () {
    test('same-named shelves and albums merge, the same file is kept once', () {
      final existing = entitiesFromState(
        _state(
          documents: [
            _doc('dA', albums: ['aA'], checksum: 'same'),
          ],
          shelves: [
            _shelf(
              'sA',
              'A minha casa',
              albums: [
                _album('aA', 'Contas', shelf: 'sA', documents: ['dA']),
              ],
            ),
          ],
        ),
      );
      final local = entitiesFromState(
        _state(
          documents: [
            _doc('dB', albums: ['aB2'], checksum: 'same'),
            _doc('dB2', albums: ['aB']),
          ],
          shelves: [
            _shelf(
              'sB',
              'A Minha Casa',
              albums: [
                _album('aB', 'contas', shelf: 'sB', documents: ['dB2']),
                _album(
                  'aB2',
                  'Saúde',
                  shelf: 'sB',
                  position: 1,
                  documents: ['dB'],
                ),
              ],
            ),
            _shelf('sB3', 'Trabalho', position: 1),
          ],
        ),
      );
      final result = mergeJoiningLibrary(existing, local);
      final merged = result.merged;
      expect(merged.keys.where((k) => k.startsWith('shelf:')), [
        'shelf:sA',
        'shelf:sB3',
      ]);
      expect(merged['shelf:sB3']!['position'], 1);
      expect(merged.containsKey('album:aB'), isFalse);
      expect(merged['album:aB2']!['shelf_id'], 'sA');
      expect(merged['doc:dB2']!['album_ids'], ['aA']);
      expect(merged.containsKey('doc:dB'), isFalse);
      expect(merged['doc:dA']!['album_ids'], ['aA', 'aB2']);
      expect(result.sameDocument, {'dB': 'dA'});
    });
  });

  group('crypto', () {
    final key = List<int>.generate(32, (i) => i);

    test('batches open only with the same key', () async {
      final crypto = SyncCrypto(key);
      final sealed = await crypto.sealJson({
        'changes': ['olá'],
      });
      expect(await crypto.openJson(sealed), {
        'changes': ['olá'],
      });
      final other = SyncCrypto(List<int>.generate(32, (i) => 31 - i));
      expect(
        () => other.openJson(sealed),
        throwsA(isA<SyncDecryptException>()),
      );
      sealed[20] ^= 1;
      expect(
        () => crypto.openJson(sealed),
        throwsA(isA<SyncDecryptException>()),
      );
    });

    test(
      'files round-trip across chunk boundaries and refuse tampering',
      () async {
        final crypto = SyncCrypto(key);
        final dir = await Directory.systemTemp.createTemp('sync_crypto_');
        addTearDown(() => dir.delete(recursive: true));
        for (final size in [
          0,
          5,
          SyncCrypto.chunkSize,
          SyncCrypto.chunkSize * 2 + 7,
        ]) {
          final plain = File('${dir.path}/p$size')
            ..writeAsBytesSync(List<int>.generate(size, (i) => i % 251));
          final sealed = File('${dir.path}/s$size');
          await sealed.writeAsBytes([
            for (final part in await crypto.sealFile(plain).toList()) ...part,
          ]);
          expect(await sealed.length(), SyncCrypto.sealedLength(size));
          final back = File('${dir.path}/b$size');
          await crypto.openFile(sealed, back);
          expect(await back.readAsBytes(), await plain.readAsBytes());

          if (size > SyncCrypto.chunkSize) {
            // Cut at a chunk boundary: the new "last" chunk wasn't sealed as last.
            final cut = File('${dir.path}/c$size')
              ..writeAsBytesSync(
                (await sealed.readAsBytes()).sublist(
                  0,
                  12 + SyncCrypto.chunkSize + 16,
                ),
              );
            expect(
              () => crypto.openFile(cut, File('${dir.path}/x$size')),
              throwsA(isA<SyncDecryptException>()),
            );
          }
        }
        expect(crypto.blobIdFor('abc'), hasLength(64));
        expect(
          crypto.blobIdFor('abc'),
          isNot(SyncCrypto(List.filled(32, 7)).blobIdFor('abc')),
        );
      },
    );
  });
}
