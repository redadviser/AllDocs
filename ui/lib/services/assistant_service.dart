import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_helpers.dart';
import 'auth_service.dart';
import 'current_user.dart';
import 'document_search.dart';

/// Why the assistant couldn't help, so the screen can say something useful.
enum AssistantProblem {
  /// The account isn't on Vault.
  notIncluded,

  /// This month's allowance is used up.
  allowanceUsed,

  /// The model declined (safety) or the answer came back incomplete.
  declined,

  /// No network, server down, or the assistant isn't configured there.
  unavailable,
}

class AssistantException implements Exception {
  const AssistantException(this.problem);

  final AssistantProblem problem;
}

class AssistantAnswer {
  const AssistantAnswer({
    required this.answer,
    required this.sourceIds,
    required this.found,
  });

  final String answer;
  final List<String> sourceIds;
  final bool found;
}

/// What the assistant read out of one document; null where it didn't say.
class AssistantFields {
  const AssistantFields({
    required this.documentType,
    required this.suggestedTitle,
    required this.suggestedTags,
    this.holderName,
    this.issueDate,
    this.expiryDate,
    this.documentNumber,
    this.nif,
    this.iban,
    this.policyNumber,
    this.amount,
    this.currency,
  });

  final String documentType;
  final String suggestedTitle;
  final List<String> suggestedTags;
  final String? holderName;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? documentNumber;
  final String? nif;
  final String? iban;
  final String? policyNumber;
  final double? amount;
  final String? currency;

  factory AssistantFields.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'] as Map<String, dynamic>?;
    return AssistantFields(
      documentType: json['document_type']?.toString() ?? 'other',
      suggestedTitle: json['suggested_title']?.toString() ?? '',
      suggestedTags: [
        for (final tag in (json['suggested_tags'] as List? ?? const []))
          tag.toString(),
      ],
      holderName: json['holder_name'] as String?,
      issueDate: DateTime.tryParse(json['issue_date']?.toString() ?? ''),
      expiryDate: DateTime.tryParse(json['expiry_date']?.toString() ?? ''),
      documentNumber: json['document_number'] as String?,
      nif: json['nif'] as String?,
      iban: json['iban'] as String?,
      policyNumber: json['policy_number'] as String?,
      amount: (amount?['value'] as num?)?.toDouble(),
      currency: amount?['currency'] as String?,
    );
  }
}

class AssistantSummary {
  const AssistantSummary({
    required this.summary,
    required this.keyPoints,
    required this.watchOut,
    required this.dates,
  });

  final String summary;
  final List<String> keyPoints;
  final List<String> watchOut;
  final List<({String label, DateTime date})> dates;

  factory AssistantSummary.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) => [
      for (final item in (json[key] as List? ?? const [])) item.toString(),
    ];
    return AssistantSummary(
      summary: json['summary']?.toString() ?? '',
      keyPoints: strings('key_points'),
      watchOut: strings('watch_out'),
      dates: [
        for (final item in (json['dates'] as List? ?? const []))
          if (DateTime.tryParse((item as Map)['date']?.toString() ?? '')
              case final date?)
            (label: item['label']?.toString() ?? '', date: date),
      ],
    );
  }
}

/// The Vault plan's document assistant (Claude, through the AllDocs
/// backend). The library stays on the phone: for a question, the few
/// documents that matter are picked here and only their text is sent; for
/// a summary or the fields of a document, only that document's text.
class AssistantService {
  const AssistantService._();

  // Mirror the backend's limits (src/modules/assistant/assistant.service.ts).
  static const maxDocuments = 5;
  static const maxDocumentChars = 24000;
  static const _timeout = Duration(seconds: 90);

  static String get _consentKey => CurrentUser.scoped('assistant.consent.v1');

  /// Whether the user agreed to send document text to the assistant.
  static Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_consentKey) ?? false;
  }

  static Future<void> giveConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentKey, true);
  }

  /// Documents the assistant can read (those with text: digital PDFs, Office
  /// files, or scans after OCR).
  static bool canRead(DocumentFile document) =>
      (document.ocrText ?? '').trim().isNotEmpty;

  /// The documents most likely to answer [question], best first: words of
  /// the question found in the title, tags, type or text. Empty when none
  /// match — then nothing is worth sending.
  static List<DocumentFile> relevantDocuments(
    List<DocumentFile> documents,
    String question,
  ) {
    final words = searchTokens(
      question,
    ).where((word) => word.length >= 3 && !_stopWords.contains(word)).toList();
    if (words.isEmpty) return const [];
    final scored = <(DocumentFile, int)>[];
    for (final document in documents) {
      if (!canRead(document)) continue;
      final name = normalizeForSearch(
        '${document.title} ${document.tags.join(' ')} '
        '${document.semanticType?.name ?? ''}',
      );
      final text = normalizeForSearch(document.ocrText!);
      var score = 0;
      for (final word in words) {
        if (name.contains(word)) score += 5;
        if (text.contains(word)) score += 1;
      }
      if (score > 0) scored.add((document, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (document, _) in scored.take(maxDocuments)) document];
  }

  /// What is sent for [document]: a few facts the app already knows, then
  /// its text — for a long document, the passages around the question's
  /// words, up to the backend's limit.
  static String documentText(DocumentFile document, {String? question}) {
    final facts = [
      if (document.validityDate case final date?)
        'Validity date known to the app: ${date.toIso8601String().substring(0, 10)}',
      if (document.tags.isNotEmpty) 'Tags: ${document.tags.join(', ')}',
    ].join('\n');
    final budget = maxDocumentChars - facts.length - 2;
    final text = document.ocrText ?? '';
    final body = text.length <= budget || question == null
        ? (text.length <= budget ? text : text.substring(0, budget))
        : _passages(text, question, budget);
    return facts.isEmpty ? body : '$facts\n\n$body';
  }

  static String _passages(String text, String question, int budget) {
    final lower = normalizeForSearch(text);
    final words = searchTokens(question).where((w) => w.length >= 3);
    final ranges = <(int, int)>[];
    const radius = 900;
    for (final word in words) {
      var from = 0;
      while (true) {
        final at = lower.indexOf(word, from);
        if (at < 0) break;
        ranges.add((
          (at - radius).clamp(0, text.length),
          (at + radius).clamp(0, text.length),
        ));
        from = at + word.length;
      }
    }
    if (ranges.isEmpty) return text.substring(0, budget);
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final buffer = StringBuffer();
    var end = -1;
    for (final (start, stop) in ranges) {
      final from = start < end ? end : start;
      if (from >= stop) continue;
      final piece = text.substring(from, stop);
      if (buffer.length + piece.length + 5 > budget) break;
      if (buffer.isNotEmpty && from != end) buffer.write('\n…\n');
      buffer.write(piece);
      end = stop;
    }
    return buffer.toString();
  }

  static Future<({int used, int limit})> usage() async {
    final data = await _call('/api/assistant/usage', null);
    return (
      used: (data['used'] as num?)?.toInt() ?? 0,
      limit: (data['limit'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<AssistantAnswer> ask(
    String question,
    List<DocumentFile> documents, {
    required String language,
  }) async {
    final data = await _call('/api/assistant/ask', {
      'question': question,
      'language': language,
      'documents': [
        for (final document in documents) _payload(document, question),
      ],
    });
    return AssistantAnswer(
      answer: data['answer']?.toString() ?? '',
      sourceIds: [
        for (final id in (data['source_ids'] as List? ?? const []))
          id.toString(),
      ],
      found: data['found'] == true,
    );
  }

  static Future<AssistantFields> extract(
    DocumentFile document, {
    required String language,
  }) async {
    final data = await _call('/api/assistant/extract', {
      'language': language,
      'document': _payload(document, null),
    });
    return AssistantFields.fromJson(data);
  }

  static Future<AssistantSummary> summarize(
    DocumentFile document, {
    required String language,
  }) async {
    final data = await _call('/api/assistant/summarize', {
      'language': language,
      'document': _payload(document, null),
    });
    return AssistantSummary.fromJson(data);
  }

  static Map<String, dynamic> _payload(DocumentFile document, String? q) => {
    'id': document.id,
    'title': document.title,
    'text': documentText(document, question: q),
  };

  static Future<Map<String, dynamic>> _call(
    String path,
    Map<String, dynamic>? body,
  ) async {
    final token = await AuthService.tokenStore.read();
    final headers = ApiHelpers.headersWithToken(token);
    final res = body == null
        ? await ApiHelpers.get(path, headers: headers).catchError(
            (_) => throw const AssistantException(AssistantProblem.unavailable),
          )
        : await ApiHelpers.post(
            path,
            headers: headers,
            body: jsonEncode(body),
            timeout: _timeout,
          ).catchError(
            (_) => throw const AssistantException(AssistantProblem.unavailable),
          );
    switch (res.statusCode) {
      case 200:
        return jsonDecode(res.body) as Map<String, dynamic>;
      case 403:
        throw const AssistantException(AssistantProblem.notIncluded);
      case 429:
        throw const AssistantException(AssistantProblem.allowanceUsed);
      case 422:
        throw const AssistantException(AssistantProblem.declined);
      default:
        throw const AssistantException(AssistantProblem.unavailable);
    }
  }

  // Common words that would match almost any document.
  static const _stopWords = {
    'que',
    'qual',
    'quais',
    'quando',
    'onde',
    'como',
    'quanto',
    'quanta',
    'para',
    'por',
    'com',
    'sem',
    'dos',
    'das',
    'uma',
    'meu',
    'minha',
    'meus',
    'minhas',
    'the',
    'what',
    'when',
    'where',
    'how',
    'which',
    'my',
    'and',
    'for',
    'with',
    'cual',
    'cuando',
    'donde',
    'mis',
    'quel',
    'quelle',
    'quand',
    'mon',
    'mes',
    'est',
    'pour',
    'avec',
    'tem',
    'tenho',
    'foi',
    'sao',
  };
}
