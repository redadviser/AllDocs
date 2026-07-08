import 'document_album.dart';

class DocumentShelf {
  const DocumentShelf({
    required this.id,
    required this.name,
    required this.position,
    required this.albums,
  });

  final String id;
  final String name;
  final int position;
  final List<DocumentAlbum> albums;

  DocumentShelf copyWith({
    String? id,
    String? name,
    int? position,
    List<DocumentAlbum>? albums,
  }) {
    return DocumentShelf(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      albums: albums ?? this.albums,
    );
  }

  factory DocumentShelf.fromJson(Map<String, dynamic> json) {
    final albums = json['albums'];

    return DocumentShelf(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      position: json['position'] is int ? json['position'] as int : 0,
      albums: albums is List
          ? albums
                .whereType<Map<String, dynamic>>()
                .map(DocumentAlbum.fromJson)
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'position': position,
      'albums': albums.map((album) => album.toJson()).toList(),
    };
  }
}
