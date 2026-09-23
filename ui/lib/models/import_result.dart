import 'document_file.dart';

/// Outcome of an import: the documents actually added, plus how many picked
/// files were skipped because the exact same file (same SHA-256) is already
/// in AllDocs.
class ImportResult {
  const ImportResult({this.documents = const [], this.skippedDuplicates = 0});

  static const empty = ImportResult();

  final List<DocumentFile> documents;
  final int skippedDuplicates;

  int get count => documents.length;
  bool get isEmpty => documents.isEmpty;

  ImportResult operator +(ImportResult other) => ImportResult(
    documents: [...documents, ...other.documents],
    skippedDuplicates: skippedDuplicates + other.skippedDuplicates,
  );
}
