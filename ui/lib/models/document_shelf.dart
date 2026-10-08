import 'document_album.dart';

class DocumentShelf {
  const DocumentShelf({
    required this.id,
    required this.name,
    required this.position,
    required this.albums,
    this.hidden = false,
    this.isDefaultHidden = false,
  });

  final String id;
  final String name;
  final int position;
  final List<DocumentAlbum> albums;

  /// On the hidden side, behind the hidden albums' PIN.
  final bool hidden;

  /// The hidden side's own shelf ("Hidden"): always there, can't be renamed
  /// or deleted, and its name follows the app's language.
  final bool isDefaultHidden;

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
      hidden: hidden,
      isDefaultHidden: isDefaultHidden,
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
      hidden: json['hidden'] == true,
      isDefaultHidden: json['default_hidden'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'position': position,
      'albums': albums.map((album) => album.toJson()).toList(),
      if (hidden) 'hidden': true,
      if (isDefaultHidden) 'default_hidden': true,
    };
  }
}
