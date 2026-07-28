import 'device_folder.dart';
import 'document_album.dart';
import 'document_category.dart';
import 'document_file.dart';
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

  DocumentAlbum? albumById(String albumId) {
    for (final shelf in shelves) {
      for (final album in shelf.albums) {
        if (album.id == albumId) return album;
      }
    }
    return null;
  }

  List<DocumentFile> documentsForAlbum(String albumId) {
    return documents.where((document) => document.albumId == albumId).toList();
  }
}
