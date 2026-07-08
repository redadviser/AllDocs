import 'document_file.dart';

class DeviceFolderScan {
  const DeviceFolderScan({
    required this.folderId,
    required this.path,
    required this.title,
    required this.documents,
  });

  final String folderId;
  final String path;
  final String title;
  final List<DocumentFile> documents;
}
