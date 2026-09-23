import 'document_semantic_type.dart';
import 'document_type.dart';

/// Where a document originally came from. Kept on the document so cloud
/// imports can later be checked for a newer remote version (see
/// [DocumentFile.cloudFileId]).
enum DocumentSource {
  local,
  zip,
  scan,
  device,
  shared,
  oneDrive,
  googleDrive,
  dropbox,
}

DocumentSource documentSourceFromName(String? raw) {
  for (final source in DocumentSource.values) {
    if (source.name == raw) return source;
  }
  return DocumentSource.local;
}

class DocumentFile {
  const DocumentFile({
    required this.id,
    required this.title,
    required this.fileName,
    required this.type,
    required this.dateLabel,
    required this.sizeLabel,
    this.localPath,
    this.sizeBytes = 0,
    this.importedAt,
    this.timeLabel,
    this.categoryId,
    this.albumIds = const [],
    this.tags = const [],
    this.isFavorite = false,
    this.isNew = false,
    this.isImported = false,
    this.isArchived = false,
    this.deletedAt,
    this.pageCount,
    this.isSearchable = false,
    this.ocrText,
    this.semanticType,
    this.classificationConfidence,
    this.validityDate,
    this.suggestionDismissed = false,
    this.checksum,
    this.source = DocumentSource.local,
    this.cloudFileId,
    this.cloudVersion,
  });

  final String id;
  final String title;
  final String fileName;
  final DocumentType type;
  final String dateLabel;
  final String sizeLabel;
  final String? localPath;
  final int sizeBytes;
  final DateTime? importedAt;
  final String? timeLabel;
  final String? categoryId;

  /// Every album this document belongs to. A document can live in several
  /// albums at once (e.g. "Clients", "Contracts" and "2026") without the file
  /// being duplicated.
  final List<String> albumIds;
  final List<String> tags;
  final bool isFavorite;
  final bool isNew;
  final bool isImported;

  /// Archiving is only a flag: the file never moves, so it is instant and
  /// reversible. Archived documents are hidden from the gallery.
  final bool isArchived;

  /// Set when the document is in the recycle bin. The file is only removed
  /// from disk on "delete permanently" (or after the bin retention period).
  final DateTime? deletedAt;
  final int? pageCount;
  final bool isSearchable;

  /// Text extracted from the document (OCR for scans/images/PDFs, plain text
  /// for Office/text formats). Backs in-document search.
  final String? ocrText;

  /// Best-guess document type from on-device OCR-text classification (see
  /// [DocumentClassifier]). Null for documents imported before this existed,
  /// or where classification hasn't run.
  final DocumentSemanticType? semanticType;

  /// 0.0-1.0 confidence in [semanticType]. UI should treat low-confidence
  /// results as a suggestion, never file documents automatically on the
  /// strength of this alone.
  final double? classificationConfidence;

  /// Expiry/validity date extracted from the document's OCR text, for types
  /// where that's meaningful (ID documents, insurance, warranties,
  /// contracts). Drives the local "expiring soon" reminders.
  final DateTime? validityDate;

  /// The user said no to the "looks like an invoice, add to Invoices?"
  /// suggestion for this document — don't ask again.
  final bool suggestionDismissed;

  /// SHA-256 of the stored file, used to skip importing the same file twice.
  final String? checksum;
  final DocumentSource source;
  final String? cloudFileId;

  /// Provider-specific version marker (eTag / rev / modifiedTime) captured at
  /// import time, compared later to detect a newer remote version.
  final String? cloudVersion;

  /// First album, kept for the places that only need "is it organized".
  String? get albumId => albumIds.isEmpty ? null : albumIds.first;
  bool get isDeleted => deletedAt != null;
  bool get isActive => !isArchived && deletedAt == null;
  bool get isFromCloud => cloudFileId != null && cloudFileId!.isNotEmpty;

  DocumentFile copyWith({
    String? id,
    String? title,
    String? fileName,
    DocumentType? type,
    String? dateLabel,
    String? sizeLabel,
    String? localPath,
    int? sizeBytes,
    DateTime? importedAt,
    String? timeLabel,
    String? categoryId,
    List<String>? albumIds,
    List<String>? tags,
    bool? isFavorite,
    bool? isNew,
    bool? isImported,
    bool? isArchived,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    int? pageCount,
    bool? isSearchable,
    String? ocrText,
    DocumentSemanticType? semanticType,
    double? classificationConfidence,
    DateTime? validityDate,
    bool? suggestionDismissed,
    String? checksum,
    DocumentSource? source,
    String? cloudFileId,
    String? cloudVersion,
    bool clearAlbumId = false,
  }) {
    return DocumentFile(
      id: id ?? this.id,
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      type: type ?? this.type,
      dateLabel: dateLabel ?? this.dateLabel,
      sizeLabel: sizeLabel ?? this.sizeLabel,
      localPath: localPath ?? this.localPath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      importedAt: importedAt ?? this.importedAt,
      timeLabel: timeLabel ?? this.timeLabel,
      categoryId: categoryId ?? this.categoryId,
      albumIds: clearAlbumId ? const [] : albumIds ?? this.albumIds,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      isNew: isNew ?? this.isNew,
      isImported: isImported ?? this.isImported,
      isArchived: isArchived ?? this.isArchived,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      pageCount: pageCount ?? this.pageCount,
      isSearchable: isSearchable ?? this.isSearchable,
      ocrText: ocrText ?? this.ocrText,
      semanticType: semanticType ?? this.semanticType,
      classificationConfidence:
          classificationConfidence ?? this.classificationConfidence,
      validityDate: validityDate ?? this.validityDate,
      suggestionDismissed: suggestionDismissed ?? this.suggestionDismissed,
      checksum: checksum ?? this.checksum,
      source: source ?? this.source,
      cloudFileId: cloudFileId ?? this.cloudFileId,
      cloudVersion: cloudVersion ?? this.cloudVersion,
    );
  }

  factory DocumentFile.fromJson(Map<String, dynamic> json) {
    // Older state files only had a single `album_id`.
    final rawAlbumIds = json['album_ids'];
    final albumIds = rawAlbumIds is List
        ? rawAlbumIds.map((id) => id.toString()).where((id) => id.isNotEmpty)
        : [
            if (json['album_id'] != null &&
                json['album_id'].toString().isNotEmpty)
              json['album_id'].toString(),
          ];
    final rawTags = json['tags'];

    return DocumentFile(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      type: documentTypeFromName(json['type']?.toString()),
      dateLabel: json['date_label']?.toString() ?? '',
      sizeLabel: json['size_label']?.toString() ?? '',
      localPath: json['local_path']?.toString(),
      sizeBytes: json['size_bytes'] is int ? json['size_bytes'] as int : 0,
      importedAt: DateTime.tryParse(json['imported_at']?.toString() ?? ''),
      timeLabel: json['time_label']?.toString(),
      categoryId: json['category_id']?.toString(),
      albumIds: albumIds.toSet().toList(),
      tags: rawTags is List
          ? rawTags.map((tag) => tag.toString()).toList()
          : const [],
      isFavorite: json['is_favorite'] == true,
      isNew: json['is_new'] == true,
      isImported: json['is_imported'] == true,
      isArchived: json['is_archived'] == true,
      deletedAt: DateTime.tryParse(json['deleted_at']?.toString() ?? ''),
      pageCount: json['page_count'] is int ? json['page_count'] as int : null,
      isSearchable: json['is_searchable'] == true,
      ocrText: json['ocr_text']?.toString(),
      semanticType: documentSemanticTypeFromName(
        json['semantic_type']?.toString(),
      ),
      classificationConfidence: (json['classification_confidence'] as num?)
          ?.toDouble(),
      validityDate: DateTime.tryParse(json['validity_date']?.toString() ?? ''),
      suggestionDismissed: json['suggestion_dismissed'] == true,
      checksum: json['checksum']?.toString(),
      source: documentSourceFromName(json['source']?.toString()),
      cloudFileId: json['cloud_file_id']?.toString(),
      cloudVersion: json['cloud_version']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'file_name': fileName,
      'type': type.name,
      'date_label': dateLabel,
      'size_label': sizeLabel,
      'local_path': localPath,
      'size_bytes': sizeBytes,
      'imported_at': importedAt?.toIso8601String(),
      'time_label': timeLabel,
      'category_id': categoryId,
      'album_id': albumId,
      'album_ids': albumIds,
      'tags': tags,
      'is_favorite': isFavorite,
      'is_new': isNew,
      'is_imported': isImported,
      'is_archived': isArchived,
      'deleted_at': deletedAt?.toIso8601String(),
      'page_count': pageCount,
      'is_searchable': isSearchable,
      'ocr_text': ocrText,
      'semantic_type': semanticType?.name,
      'classification_confidence': classificationConfidence,
      'validity_date': validityDate?.toIso8601String(),
      'suggestion_dismissed': suggestionDismissed,
      'checksum': checksum,
      'source': source.name,
      'cloud_file_id': cloudFileId,
      'cloud_version': cloudVersion,
    };
  }
}
