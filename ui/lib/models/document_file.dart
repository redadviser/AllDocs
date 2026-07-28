import 'document_semantic_type.dart';
import 'document_type.dart';

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
    this.albumId,
    this.isFavorite = false,
    this.isNew = false,
    this.isImported = false,
    this.pageCount,
    this.isSearchable = false,
    this.ocrText,
    this.semanticType,
    this.classificationConfidence,
    this.validityDate,
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
  final String? albumId;
  final bool isFavorite;
  final bool isNew;
  final bool isImported;
  final int? pageCount;
  final bool isSearchable;
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
    String? albumId,
    bool? isFavorite,
    bool? isNew,
    bool? isImported,
    int? pageCount,
    bool? isSearchable,
    String? ocrText,
    DocumentSemanticType? semanticType,
    double? classificationConfidence,
    DateTime? validityDate,
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
      albumId: clearAlbumId ? null : albumId ?? this.albumId,
      isFavorite: isFavorite ?? this.isFavorite,
      isNew: isNew ?? this.isNew,
      isImported: isImported ?? this.isImported,
      pageCount: pageCount ?? this.pageCount,
      isSearchable: isSearchable ?? this.isSearchable,
      ocrText: ocrText ?? this.ocrText,
      semanticType: semanticType ?? this.semanticType,
      classificationConfidence:
          classificationConfidence ?? this.classificationConfidence,
      validityDate: validityDate ?? this.validityDate,
    );
  }

  factory DocumentFile.fromJson(Map<String, dynamic> json) {
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
      albumId: json['album_id']?.toString(),
      isFavorite: json['is_favorite'] == true,
      isNew: json['is_new'] == true,
      isImported: json['is_imported'] == true,
      pageCount: json['page_count'] is int ? json['page_count'] as int : null,
      isSearchable: json['is_searchable'] == true,
      ocrText: json['ocr_text']?.toString(),
      semanticType: documentSemanticTypeFromName(
        json['semantic_type']?.toString(),
      ),
      classificationConfidence: (json['classification_confidence'] as num?)
          ?.toDouble(),
      validityDate: DateTime.tryParse(
        json['validity_date']?.toString() ?? '',
      ),
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
      'is_favorite': isFavorite,
      'is_new': isNew,
      'is_imported': isImported,
      'page_count': pageCount,
      'is_searchable': isSearchable,
      'ocr_text': ocrText,
      'semantic_type': semanticType?.name,
      'classification_confidence': classificationConfidence,
      'validity_date': validityDate?.toIso8601String(),
    };
  }
}
