import '../models/models.dart';

/// Lowercases and strips Portuguese/Spanish/French diacritics so "fatura",
/// "Fatúra" and "FATURA" all match. Pure, so it's usable inside isolates.
String normalizeForSearch(String value) {
  const from = 'áàâãäåçéèêëíìîïñóòôõöúùûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index < 0 ? char : to[index]);
  }
  return buffer.toString();
}

List<String> searchTokens(String query) {
  return normalizeForSearch(
    query,
  ).split(RegExp(r'[\s_\-.,;:/]+')).where((token) => token.isNotEmpty).toList();
}

enum SearchDateRange { any, last7Days, last30Days, thisYear, older }

class DocumentSearchFilter {
  const DocumentSearchFilter({
    this.query = '',
    this.type,
    this.dateRange = SearchDateRange.any,
    this.tag,
    this.favoritesOnly = false,
  });

  final String query;
  final DocumentType? type;
  final SearchDateRange dateRange;
  final String? tag;
  final bool favoritesOnly;

  bool get isEmpty =>
      query.trim().isEmpty &&
      type == null &&
      dateRange == SearchDateRange.any &&
      tag == null &&
      !favoritesOnly;

  DocumentSearchFilter copyWith({
    String? query,
    DocumentType? type,
    bool clearType = false,
    SearchDateRange? dateRange,
    String? tag,
    bool clearTag = false,
    bool? favoritesOnly,
  }) {
    return DocumentSearchFilter(
      query: query ?? this.query,
      type: clearType ? null : type ?? this.type,
      dateRange: dateRange ?? this.dateRange,
      tag: clearTag ? null : tag ?? this.tag,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    );
  }
}

/// A search hit, with where the match came from so the UI can say "found in
/// the document text" when the name itself doesn't contain the query.
class DocumentSearchHit {
  const DocumentSearchHit({
    required this.document,
    required this.score,
    this.textSnippet,
  });

  final DocumentFile document;
  final int score;

  /// Excerpt around the match inside the extracted text, when the match was
  /// in the content rather than the name.
  final String? textSnippet;
}

/// Searches documents by name, tags, album names, detected type and the
/// text extracted from inside them (OCR / Office text).
List<DocumentSearchHit> searchDocuments(
  List<DocumentFile> documents,
  DocumentSearchFilter filter, {
  Map<String, String> albumNames = const {},
  DateTime? now,
}) {
  final tokens = searchTokens(filter.query);
  final today = now ?? DateTime.now();
  final hits = <DocumentSearchHit>[];

  for (final document in documents) {
    if (filter.type != null && document.type != filter.type) continue;
    if (filter.favoritesOnly && !document.isFavorite) continue;
    if (filter.tag != null && !document.tags.contains(filter.tag)) continue;
    if (!_inRange(document.importedAt, filter.dateRange, today)) continue;

    if (tokens.isEmpty) {
      hits.add(DocumentSearchHit(document: document, score: 0));
      continue;
    }

    final name = normalizeForSearch('${document.title} ${document.fileName}');
    final meta = normalizeForSearch(
      [
        ...document.tags,
        for (final id in document.albumIds) albumNames[id] ?? '',
        document.semanticType?.name ?? '',
      ].join(' '),
    );
    final text = _normalizedText(document);

    var score = 0;
    var matchedInTextOnly = false;
    var allMatched = true;
    for (final token in tokens) {
      if (name.contains(token)) {
        score += name.startsWith(token) ? 12 : 8;
      } else if (meta.contains(token)) {
        score += 5;
      } else if (text.contains(token)) {
        score += 2;
        matchedInTextOnly = true;
      } else {
        allMatched = false;
        break;
      }
    }
    if (!allMatched) continue;

    hits.add(
      DocumentSearchHit(
        document: document,
        score: score,
        textSnippet: matchedInTextOnly
            ? _snippet(document.ocrText!, text, tokens.first)
            : null,
      ),
    );
  }

  hits.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final aDate = a.document.importedAt ?? DateTime(1970);
    final bDate = b.document.importedAt ?? DateTime(1970);
    return bDate.compareTo(aDate);
  });
  return hits;
}

// Normalizing up to 20k chars per document on every keystroke was the slow
// part of searching; keep the result per document text.
final Map<String, (int, String)> _normalizedTextCache = {};

String _normalizedText(DocumentFile document) {
  final text = document.ocrText;
  if (text == null || text.isEmpty) return '';
  final cached = _normalizedTextCache[document.id];
  if (cached != null && cached.$1 == text.hashCode) return cached.$2;
  final normalized = normalizeForSearch(text);
  if (_normalizedTextCache.length > 3000) _normalizedTextCache.clear();
  _normalizedTextCache[document.id] = (text.hashCode, normalized);
  return normalized;
}

bool _inRange(DateTime? date, SearchDateRange range, DateTime now) {
  if (range == SearchDateRange.any) return true;
  if (date == null) return false;
  final age = now.difference(date);
  return switch (range) {
    SearchDateRange.any => true,
    SearchDateRange.last7Days => age.inDays < 7,
    SearchDateRange.last30Days => age.inDays < 30,
    SearchDateRange.thisYear => date.year == now.year,
    SearchDateRange.older => date.year < now.year,
  };
}

String _snippet(String original, String normalized, String token) {
  final index = normalized.indexOf(token);
  if (index < 0) return '';
  // normalizeForSearch maps one char to one char, so indices line up.
  final start = (index - 40).clamp(0, original.length);
  final end = (index + token.length + 60).clamp(0, original.length);
  final excerpt = original
      .substring(start, end)
      .replaceAll(RegExp(r'\s+'), ' ');
  return '${start > 0 ? '…' : ''}${excerpt.trim()}${end < original.length ? '…' : ''}';
}

/// Album-name keywords (pt/en/es/fr) per detected document type, used to
/// suggest "this looks like an invoice → add to Invoices?".
const albumKeywordsBySemanticType = <DocumentSemanticType, List<String>>{
  DocumentSemanticType.invoice: [
    'fatura',
    'factura',
    'facture',
    'invoice',
    'contas',
  ],
  DocumentSemanticType.receipt: [
    'recibo',
    'receipt',
    'recu',
    'ticket',
    'talao',
  ],
  DocumentSemanticType.contract: ['contrato', 'contract', 'contrat'],
  DocumentSemanticType.identityDocument: [
    'identi',
    'pessoa',
    'personal',
    'personnel',
    'documento',
    'id',
  ],
  DocumentSemanticType.medical: ['saude', 'medic', 'health', 'sante', 'salud'],
  DocumentSemanticType.insurance: ['seguro', 'insurance', 'assurance'],
  DocumentSemanticType.warranty: ['garantia', 'warranty', 'garantie'],
};

DocumentAlbum? albumForSemanticType(
  DocumentSemanticType type,
  List<DocumentAlbum> albums,
) {
  final keywords = albumKeywordsBySemanticType[type];
  if (keywords == null) return null;
  for (final album in albums) {
    final name = normalizeForSearch(album.name);
    final words = name.split(RegExp(r'\s+'));
    for (final keyword in keywords) {
      // Short keywords ("id") must match a whole word, longer ones a prefix.
      final matches = keyword.length <= 2
          ? words.contains(keyword)
          : words.any((word) => word.startsWith(keyword));
      if (matches) return album;
    }
  }
  return null;
}
