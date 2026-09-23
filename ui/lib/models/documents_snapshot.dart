import 'device_folder.dart';
import 'document_album.dart';
import 'document_category.dart';
import 'document_file.dart';
import 'document_semantic_type.dart';
import 'document_shelf.dart';
import 'user_profile.dart';

class DocumentsSnapshot {
  const DocumentsSnapshot({
    required this.shelves,
    required this.documents,
    required this.categories,
    required this.recentDocuments,
    required this.favoriteDocuments,
    required this.unorganizedDocuments,
    required this.deviceFolders,
    required this.recentImports,
    required this.profile,
    this.expiringDocuments = const [],
    this.archivedDocuments = const [],
    this.trashDocuments = const [],
    this.tags = const [],
    this.suggestions = const [],
  });

  final List<DocumentShelf> shelves;
  final List<DocumentFile> documents;
  final List<DocumentCategory> categories;
  final List<DocumentFile> recentDocuments;
  final List<DocumentFile> favoriteDocuments;
  final List<DocumentFile> unorganizedDocuments;
  final List<DeviceFolder> deviceFolders;
  final List<DocumentFile> recentImports;
  final UserProfile profile;

  /// Documents with a known [DocumentFile.validityDate], soonest first —
  /// backs the "expiring soon" reminders section.
  final List<DocumentFile> expiringDocuments;

  /// Archived (hidden from the gallery, still searchable from Archive).
  final List<DocumentFile> archivedDocuments;

  /// Recycle bin, most recently deleted first.
  final List<DocumentFile> trashDocuments;

  /// Every tag in use, alphabetically.
  final List<String> tags;

  /// Unorganized documents whose detected type matches an album (or could
  /// start one), e.g. "looks like an invoice → Invoices".
  final List<AlbumSuggestion> suggestions;

  /// How long a newly added document stays in the gallery's "Recent" row.
  static const recentWindow = Duration(hours: 1);

  /// Documents added to the gallery (not in any album) within
  /// [recentWindow] before [now], newest first.
  List<DocumentFile> recentAt(DateTime now) {
    final cutoff = now.subtract(recentWindow);
    return unorganizedDocuments
        .where((document) => document.importedAt?.isAfter(cutoff) ?? false)
        .toList();
  }

  /// Every album across all shelves, in shelf order.
  List<DocumentAlbum> get albums => [
    for (final shelf in shelves) ...shelf.albums,
  ];

  DocumentAlbum? albumById(String albumId) {
    for (final shelf in shelves) {
      for (final album in shelf.albums) {
        if (album.id == albumId) return album;
      }
    }
    return null;
  }

  List<DocumentFile> documentsForAlbum(String albumId) {
    return documents
        .where((document) => document.albumIds.contains(albumId))
        .toList();
  }

  DocumentsSnapshot copyWith({
    List<DocumentShelf>? shelves,
    List<DocumentFile>? documents,
    List<DocumentCategory>? categories,
    List<DocumentFile>? recentDocuments,
    List<DocumentFile>? favoriteDocuments,
    List<DocumentFile>? unorganizedDocuments,
    List<DeviceFolder>? deviceFolders,
    List<DocumentFile>? recentImports,
    UserProfile? profile,
    List<DocumentFile>? expiringDocuments,
    List<DocumentFile>? archivedDocuments,
    List<DocumentFile>? trashDocuments,
    List<String>? tags,
    List<AlbumSuggestion>? suggestions,
  }) {
    return DocumentsSnapshot(
      shelves: shelves ?? this.shelves,
      documents: documents ?? this.documents,
      categories: categories ?? this.categories,
      recentDocuments: recentDocuments ?? this.recentDocuments,
      favoriteDocuments: favoriteDocuments ?? this.favoriteDocuments,
      unorganizedDocuments: unorganizedDocuments ?? this.unorganizedDocuments,
      deviceFolders: deviceFolders ?? this.deviceFolders,
      recentImports: recentImports ?? this.recentImports,
      profile: profile ?? this.profile,
      expiringDocuments: expiringDocuments ?? this.expiringDocuments,
      archivedDocuments: archivedDocuments ?? this.archivedDocuments,
      trashDocuments: trashDocuments ?? this.trashDocuments,
      tags: tags ?? this.tags,
      suggestions: suggestions ?? this.suggestions,
    );
  }
}

class AlbumSuggestion {
  const AlbumSuggestion({
    required this.document,
    required this.semanticType,
    this.album,
  });

  final DocumentFile document;
  final DocumentSemanticType semanticType;

  /// Existing album that matches [semanticType]; null means "create one".
  final DocumentAlbum? album;
}
