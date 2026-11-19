/// A group of documents and the space their files take.
class StorageBucket {
  const StorageBucket({this.count = 0, this.bytes = 0});

  final int count;
  final int bytes;

  StorageBucket add(int size) =>
      StorageBucket(count: count + 1, bytes: bytes + size);
}

/// Every document stored in the app (gallery, albums, archive and recycle
/// bin) with the space its files take, against the plan's document limit.
/// The recycle bin is shown but doesn't count towards the limit, so a full
/// library can always make room by deleting.
class StorageSummary {
  const StorageSummary({
    required this.limitDocuments,
    this.inAlbums = const StorageBucket(),
    this.withoutAlbum = const StorageBucket(),
    this.archivedOrDeleted = const StorageBucket(),
    this.trashBytes = 0,
    this.trashCount = 0,
  });

  /// null = no limit.
  final int? limitDocuments;

  /// Gallery documents that are in at least one album.
  final StorageBucket inAlbums;

  /// Gallery documents in no album.
  final StorageBucket withoutAlbum;

  /// Archived documents and the recycle bin.
  final StorageBucket archivedOrDeleted;

  /// The part of [archivedOrDeleted] that is in the recycle bin.
  final int trashBytes;
  final int trashCount;

  int get documentCount =>
      inAlbums.count + withoutAlbum.count + archivedOrDeleted.count;
  int get usedBytes =>
      inAlbums.bytes + withoutAlbum.bytes + archivedOrDeleted.bytes;

  /// What counts towards [limitDocuments]: everything but the recycle bin.
  int get countedDocuments => documentCount - trashCount;
  int? get freeDocuments => switch (limitDocuments) {
    null => null,
    final limit => countedDocuments >= limit ? 0 : limit - countedDocuments,
  };
  bool get isFull => !hasRoomFor(1);
  bool hasRoomFor(int documents) {
    final limit = limitDocuments;
    return limit == null || countedDocuments + documents <= limit;
  }

  double get usedRatio {
    final limit = limitDocuments;
    return limit == null || limit <= 0
        ? 0
        : (countedDocuments / limit).clamp(0.0, 1.0);
  }

  int get usedPercent => (usedRatio * 100).round();

  StorageSummary withLimit(int? limitDocuments) => StorageSummary(
    limitDocuments: limitDocuments,
    inAlbums: inAlbums,
    withoutAlbum: withoutAlbum,
    archivedOrDeleted: archivedOrDeleted,
    trashBytes: trashBytes,
    trashCount: trashCount,
  );
}
