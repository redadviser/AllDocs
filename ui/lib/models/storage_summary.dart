/// A group of documents and the space their files take.
class StorageBucket {
  const StorageBucket({this.count = 0, this.bytes = 0});

  final int count;
  final int bytes;

  StorageBucket add(int size) =>
      StorageBucket(count: count + 1, bytes: bytes + size);
}

/// Space taken by every document file stored in the app — gallery, albums,
/// archive and recycle bin — measured on disk, against the plan's limit.
/// The recycle bin is shown but doesn't count towards the limit, so a full
/// library can always make room by deleting.
class StorageSummary {
  const StorageSummary({
    required this.limitBytes,
    this.inAlbums = const StorageBucket(),
    this.withoutAlbum = const StorageBucket(),
    this.archivedOrDeleted = const StorageBucket(),
    this.trashBytes = 0,
  });

  final int limitBytes;

  /// Gallery documents that are in at least one album.
  final StorageBucket inAlbums;

  /// Gallery documents in no album.
  final StorageBucket withoutAlbum;

  /// Archived documents and the recycle bin.
  final StorageBucket archivedOrDeleted;

  /// The part of [archivedOrDeleted] that is in the recycle bin.
  final int trashBytes;

  int get documentCount =>
      inAlbums.count + withoutAlbum.count + archivedOrDeleted.count;
  int get usedBytes =>
      inAlbums.bytes + withoutAlbum.bytes + archivedOrDeleted.bytes;

  /// What counts towards [limitBytes]: everything but the recycle bin.
  int get countedBytes => usedBytes - trashBytes;
  int get freeBytes =>
      countedBytes >= limitBytes ? 0 : limitBytes - countedBytes;
  bool get isFull => countedBytes >= limitBytes;
  bool hasRoomFor(int bytes) => countedBytes + bytes <= limitBytes;

  double get usedRatio =>
      limitBytes <= 0 ? 0 : (countedBytes / limitBytes).clamp(0.0, 1.0);
  int get usedPercent => (usedRatio * 100).round();

  StorageSummary withLimit(int limitBytes) => StorageSummary(
    limitBytes: limitBytes,
    inAlbums: inAlbums,
    withoutAlbum: withoutAlbum,
    archivedOrDeleted: archivedOrDeleted,
    trashBytes: trashBytes,
  );
}
