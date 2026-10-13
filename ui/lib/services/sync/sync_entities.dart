import 'dart:convert';

import '../document_search.dart' show normalizeForSearch;

/// The library as device sync sees it: one flat map per document, shelf and
/// album, keyed `doc:<id>`, `shelf:<id>`, `album:<id>`. Only what is the
/// same on every device is in it — a document's stored file name instead of
/// this phone's path, a shelf without its albums, an album without its
/// document list (membership lives on the documents, in `album_ids`).
typedef SyncEntities = Map<String, Map<String, dynamic>>;

const _docPrefix = 'doc:';
const _shelfPrefix = 'shelf:';
const _albumPrefix = 'album:';

/// One entity's change. [full] carries the whole entity (it's new); without
/// it, [set] and [unset] are only the fields that changed, applied on top of
/// whatever the entity is by then — so two devices editing different fields
/// of the same document both keep their edit.
class SyncChange {
  const SyncChange.delete(this.key)
    : deleted = true,
      set = null,
      unset = null,
      full = false;

  const SyncChange.update(this.key, {this.set, this.unset, this.full = false})
    : deleted = false;

  final String key;
  final bool deleted;
  final bool full;
  final Map<String, dynamic>? set;
  final List<String>? unset;

  Map<String, dynamic> toJson() => {
    'k': key,
    if (deleted) 'd': true,
    if (full) 'n': true,
    if (set != null && set!.isNotEmpty) 's': set,
    if (unset != null && unset!.isNotEmpty) 'u': unset,
  };

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    final key = json['k'] as String;
    if (json['d'] == true) return SyncChange.delete(key);
    return SyncChange.update(
      key,
      set: (json['s'] as Map?)?.cast<String, dynamic>(),
      unset: (json['u'] as List?)?.cast<String>(),
      full: json['n'] == true,
    );
  }
}

bool isDocumentKey(String key) => key.startsWith(_docPrefix);
String documentKey(String id) => '$_docPrefix$id';
String idOfKey(String key) => key.substring(key.indexOf(':') + 1);

/// The stored file's name, without the folder.
String baseNameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

/// What identifies a document's file content across devices: its checksum,
/// or (for the rare document without one) its id and size.
String fileKeyOf(Map<String, dynamic> document) {
  final checksum = document['checksum']?.toString();
  if (checksum != null && checksum.isNotEmpty) return checksum;
  return 'id:${document['id']}:${document['size_bytes'] ?? 0}';
}

Map<String, dynamic> _copy(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

/// [state] (the documents store's JSON) as entities.
SyncEntities entitiesFromState(Map<String, dynamic> state) {
  final entities = <String, Map<String, dynamic>>{};
  for (final raw in (state['documents'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final id = raw['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    final document = _copy(raw);
    final path = document.remove('local_path')?.toString();
    if (path != null && path.isNotEmpty) {
      document['stored_name'] = baseNameOf(path);
    }
    // Derived from album_ids; rebuilt when the library is written.
    document.remove('album_id');
    entities[documentKey(id)] = document;
  }
  for (final rawShelf in (state['shelves'] as List? ?? const [])) {
    if (rawShelf is! Map) continue;
    final shelfId = rawShelf['id']?.toString() ?? '';
    if (shelfId.isEmpty) continue;
    final shelf = _copy(rawShelf)..remove('albums');
    entities['$_shelfPrefix$shelfId'] = shelf;
    for (final rawAlbum in (rawShelf['albums'] as List? ?? const [])) {
      if (rawAlbum is! Map) continue;
      final albumId = rawAlbum['id']?.toString() ?? '';
      if (albumId.isEmpty) continue;
      final album = _copy(rawAlbum)
        ..remove('document_ids')
        ..['shelf_id'] = shelfId;
      entities['$_albumPrefix$albumId'] = album;
    }
  }
  return entities;
}

/// What turns [from] into [to].
List<SyncChange> diffEntities(SyncEntities from, SyncEntities to) {
  final changes = <SyncChange>[];
  for (final entry in to.entries) {
    final before = from[entry.key];
    if (before == null) {
      changes.add(
        SyncChange.update(entry.key, set: _copy(entry.value), full: true),
      );
      continue;
    }
    final set = <String, dynamic>{};
    for (final field in entry.value.entries) {
      if (!before.containsKey(field.key) ||
          !sameJson(before[field.key], field.value)) {
        set[field.key] = field.value;
      }
    }
    final unset = [
      for (final field in before.keys)
        if (!entry.value.containsKey(field)) field,
    ];
    if (set.isNotEmpty || unset.isNotEmpty) {
      changes.add(
        SyncChange.update(
          entry.key,
          set: set.isEmpty ? null : _copy(set),
          unset: unset.isEmpty ? null : unset,
        ),
      );
    }
  }
  for (final key in from.keys) {
    if (!to.containsKey(key)) changes.add(SyncChange.delete(key));
  }
  return changes;
}

/// Applies [changes] to [entities], in order. An edit to an entity that no
/// longer exists is dropped: a deletion wins over a concurrent edit.
void applyChanges(SyncEntities entities, Iterable<SyncChange> changes) {
  for (final change in changes) {
    if (change.deleted) {
      entities.remove(change.key);
      continue;
    }
    final existing = entities[change.key];
    if (existing == null && !change.full) continue;
    final target = change.full
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(existing!);
    if (change.set != null) target.addAll(_copy(change.set!));
    for (final field in change.unset ?? const <String>[]) {
      target.remove(field);
    }
    entities[change.key] = target;
  }
}

/// Whether two JSON values are the same, whatever order their keys are in.
bool sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || !sameJson(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

SyncEntities copyEntities(SyncEntities entities) => {
  for (final entry in entities.entries) entry.key: _copy(entry.value),
};

/// The documents store's JSON for [entities], leaving out [withheld]
/// documents (their file hasn't reached this phone yet). Keeps from
/// [current] what isn't synced (this phone's own settings) and the order
/// things were in, so applying a remote change doesn't shuffle the library.
Map<String, dynamic> stateFromEntities(
  SyncEntities entities, {
  required Map<String, dynamic> current,
  required String documentsDirectory,
  Set<String> withheld = const {},
}) {
  final state = <String, dynamic>{
    for (final entry in current.entries)
      if (entry.key != 'documents' && entry.key != 'shelves')
        entry.key: entry.value,
  };

  int orderIn(List? list, String id) {
    final index =
        list?.indexWhere((raw) => raw is Map && raw['id'] == id) ?? -1;
    return index < 0 ? 1 << 30 : index;
  }

  final currentDocuments = current['documents'] as List?;
  final documents = <Map<String, dynamic>>[
    for (final entry in entities.entries)
      if (isDocumentKey(entry.key) && !withheld.contains(idOfKey(entry.key)))
        _copy(entry.value),
  ];
  documents.sort((a, b) {
    final byOrder = orderIn(
      currentDocuments,
      a['id'],
    ).compareTo(orderIn(currentDocuments, b['id']));
    if (byOrder != 0) return byOrder;
    final byDate = (a['imported_at']?.toString() ?? '').compareTo(
      b['imported_at']?.toString() ?? '',
    );
    return byDate != 0
        ? byDate
        : a['id'].toString().compareTo(b['id'].toString());
  });

  // Shelves by position, albums on theirs by position.
  final shelves = [
    for (final entry in entities.entries)
      if (entry.key.startsWith(_shelfPrefix)) _copy(entry.value),
  ]..sort(_byPosition);
  final albums = [
    for (final entry in entities.entries)
      if (entry.key.startsWith(_albumPrefix)) _copy(entry.value),
  ]..sort(_byPosition);
  final albumIds = {for (final album in albums) album['id']};

  // Previous order of each album's documents.
  final previousOrder = <String, List<String>>{};
  for (final shelf in (current['shelves'] as List? ?? const [])) {
    if (shelf is! Map) continue;
    for (final album in (shelf['albums'] as List? ?? const [])) {
      if (album is! Map) continue;
      previousOrder[album['id'].toString()] = [
        for (final id in (album['document_ids'] as List? ?? const []))
          id.toString(),
      ];
    }
  }

  final members = <String, List<String>>{};
  for (final document in documents) {
    final ids = [
      for (final id in (document['album_ids'] as List? ?? const []))
        if (albumIds.contains(id.toString())) id.toString(),
    ];
    document['album_ids'] = ids;
    document['album_id'] = ids.isEmpty ? null : ids.first;
    final stored = document.remove('stored_name')?.toString();
    if (stored != null && stored.isNotEmpty) {
      document['local_path'] = '$documentsDirectory/$stored';
    }
    for (final albumId in ids) {
      members.putIfAbsent(albumId, () => []).add(document['id'].toString());
    }
  }

  final shelvesById = {for (final shelf in shelves) shelf['id']: shelf};
  for (final shelf in shelves) {
    shelf['albums'] = <Map<String, dynamic>>[];
  }
  for (final album in albums) {
    var shelf = shelvesById[album['shelf_id']];
    // Its shelf was deleted on another device while this one added the
    // album: it moves to the first shelf on the same side.
    shelf ??= shelves
        .where((s) => (s['hidden'] == true) == false)
        .followedBy(shelves)
        .firstOrNull;
    if (shelf == null) continue;
    album['shelf_id'] = shelf['id'];
    final inAlbum = members[album['id'].toString()] ?? const [];
    final before = previousOrder[album['id'].toString()] ?? const [];
    album['document_ids'] = [
      for (final id in before)
        if (inAlbum.contains(id)) id,
      for (final id in inAlbum)
        if (!before.contains(id)) id,
    ];
    final cover = album['cover_document_id']?.toString();
    final ids = album['document_ids'] as List;
    if (cover == null || !ids.contains(cover)) {
      album['cover_document_id'] = ids.isEmpty ? null : ids.first;
    }
    (shelf['albums'] as List).add(album);
  }

  state['documents'] = documents;
  state['shelves'] = shelves;
  return state;
}

int _byPosition(Map<String, dynamic> a, Map<String, dynamic> b) {
  final pa = a['position'] is int ? a['position'] as int : 0;
  final pb = b['position'] is int ? b['position'] as int : 0;
  return pa != pb
      ? pa.compareTo(pb)
      : a['id'].toString().compareTo(b['id'].toString());
}

/// A phone joining a sync already holds its own library: it's merged into
/// [existing] (what the other devices have) instead of duplicated. Shelves
/// with the same name (same side, visible or hidden) become one, albums
/// with the same name on the same shelf too, and a document already there
/// (same file) is kept once. Returns the merged entities and, for each
/// local document dropped as a duplicate, the document it is the same as.
({SyncEntities merged, Map<String, String> sameDocument}) mergeJoiningLibrary(
  SyncEntities existing,
  SyncEntities local,
) {
  final merged = copyEntities(existing);
  String name(Map<String, dynamic> entity) =>
      normalizeForSearch(entity['name']?.toString() ?? '');

  final shelfMap = <String, String>{};
  var nextShelfPosition = existing.keys
      .where((key) => key.startsWith(_shelfPrefix))
      .length;
  for (final entry in local.entries.where(
    (e) => e.key.startsWith(_shelfPrefix),
  )) {
    final shelf = entry.value;
    final hidden = shelf['hidden'] == true;
    final match = existing.entries
        .where(
          (e) =>
              e.key.startsWith(_shelfPrefix) &&
              (e.key == entry.key ||
                  ((e.value['hidden'] == true) == hidden &&
                      name(e.value) == name(shelf))),
        )
        .firstOrNull;
    if (match != null) {
      shelfMap[shelf['id'].toString()] = match.value['id'].toString();
    } else {
      shelfMap[shelf['id'].toString()] = shelf['id'].toString();
      // After the shelves already there.
      merged[entry.key] = {...shelf, 'position': nextShelfPosition++};
    }
  }

  final albumMap = <String, String>{};
  for (final entry in local.entries.where(
    (e) => e.key.startsWith(_albumPrefix),
  )) {
    final album = entry.value;
    final shelfId =
        shelfMap[album['shelf_id']?.toString()] ?? album['shelf_id'];
    final match = existing.entries
        .where(
          (e) =>
              e.key.startsWith(_albumPrefix) &&
              (e.key == entry.key ||
                  (e.value['shelf_id'] == shelfId &&
                      name(e.value) == name(album))),
        )
        .firstOrNull;
    if (match != null) {
      albumMap[album['id'].toString()] = match.value['id'].toString();
    } else {
      albumMap[album['id'].toString()] = album['id'].toString();
      merged[entry.key] = {...album, 'shelf_id': shelfId};
    }
  }

  final byFile = <String, String>{
    for (final entry in existing.entries)
      if (isDocumentKey(entry.key)) fileKeyOf(entry.value): entry.key,
  };
  final sameDocument = <String, String>{};
  for (final entry in local.entries.where((e) => isDocumentKey(e.key))) {
    final document = Map<String, dynamic>.from(entry.value);
    final albums = [
      for (final id in (document['album_ids'] as List? ?? const []))
        albumMap[id.toString()] ?? id.toString(),
    ];
    final twin = existing.containsKey(entry.key)
        ? entry.key
        : byFile[fileKeyOf(document)];
    if (twin != null) {
      // Already there: keep theirs, adding this phone's albums to it.
      final kept = merged[twin]!;
      kept['album_ids'] = {
        ...(kept['album_ids'] as List? ?? const []).map((id) => id.toString()),
        ...albums,
      }.toList();
      if (twin != entry.key) sameDocument[idOfKey(entry.key)] = idOfKey(twin);
      continue;
    }
    document['album_ids'] = albums;
    merged[entry.key] = document;
  }
  return (merged: merged, sameDocument: sameDocument);
}
