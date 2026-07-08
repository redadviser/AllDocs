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
    };
  }
}
