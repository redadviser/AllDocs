class DocumentAlbum {
  const DocumentAlbum({
    required this.id,
    required this.shelfId,
    required this.name,
    required this.colorValue,
    required this.iconName,
    required this.position,
    required this.documentIds,
    this.coverDocumentId,
  });

  final String id;
  final String shelfId;
  final String name;
  final int colorValue;
  final String iconName;
  final int position;
  final List<String> documentIds;
  final String? coverDocumentId;

  int get documentCount => documentIds.length;

  DocumentAlbum copyWith({
    String? id,
    String? shelfId,
    String? name,
    int? colorValue,
    String? iconName,
    int? position,
    List<String>? documentIds,
    String? coverDocumentId,
  }) {
    return DocumentAlbum(
      id: id ?? this.id,
      shelfId: shelfId ?? this.shelfId,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconName: iconName ?? this.iconName,
      position: position ?? this.position,
      documentIds: documentIds ?? this.documentIds,
      coverDocumentId: coverDocumentId ?? this.coverDocumentId,
    );
  }

  factory DocumentAlbum.fromJson(Map<String, dynamic> json) {
    final ids = json['document_ids'];

    return DocumentAlbum(
      id: json['id']?.toString() ?? '',
      shelfId: json['shelf_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      colorValue: json['color_value'] is int
          ? json['color_value'] as int
          : 0xFF3F8DFF,
      iconName: json['icon_name']?.toString() ?? 'folder',
      position: json['position'] is int ? json['position'] as int : 0,
      documentIds: ids is List ? ids.map((id) => id.toString()).toList() : [],
      coverDocumentId: json['cover_document_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shelf_id': shelfId,
      'name': name,
      'color_value': colorValue,
      'icon_name': iconName,
      'position': position,
      'document_ids': documentIds,
      'cover_document_id': coverDocumentId,
    };
  }
}
