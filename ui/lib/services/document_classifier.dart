import '../models/document_semantic_type.dart';

export '../models/document_semantic_type.dart';

/// Result of classifying a scanned/imported document's OCR text.
class DocumentClassification {
  const DocumentClassification({
    required this.semanticType,
    required this.confidence,
    this.validityDate,
  });

  /// Best-guess document type.
  final DocumentSemanticType semanticType;

  /// 0.0 (no signal) to 1.0 (strong keyword match). Callers should treat
  /// this as a suggestion, not ground truth — never auto-file silently
  /// below a confidence threshold.
  final double confidence;

  /// Only populated for types where an expiry/validity date is meaningful
  /// (identity documents, insurance, warranties, contracts) and a date was
  /// found near a recognized "valid until"-style phrase.
  final DateTime? validityDate;
}

/// Rule-based (keyword + regex) classifier covering pt/en/es/fr, the
/// languages AllDocs already ships. Deliberately simple and explainable
/// rather than a trained model — see docs/architecture.md's product
/// roadmap (Phase 1) for why, and Phase 6 for the planned upgrade path
/// once there's real usage data to train on.
class DocumentClassifier {
  const DocumentClassifier();

  static const Map<DocumentSemanticType, List<String>> _keywordsByType = {
    DocumentSemanticType.invoice: [
      'fatura',
      'factura',
      'invoice',
      'facture',
      'tax invoice',
    ],
    DocumentSemanticType.receipt: [
      'recibo',
      'talao',
      'receipt',
      'recu',
      'ticket de caisse',
    ],
    DocumentSemanticType.contract: [
      'contrato',
      'contract',
      'contrat',
      'agreement',
    ],
    DocumentSemanticType.identityDocument: [
      'cartao de cidadao',
      'bilhete de identidade',
      'passaporte',
      'carta de conducao',
      'documento nacional de identidad',
      'dni',
      'pasaporte',
      'carnet de conducir',
      'passport',
      'driver license',
      'driving licence',
      'identity card',
      'national id',
      "carte nationale d'identite",
      'carte nationale identite',
      'passeport',
      'permis de conduire',
    ],
    DocumentSemanticType.medical: [
      'receita medica',
      'relatorio medico',
      'boletim de saude',
      'receta medica',
      'informe medico',
      'prescription',
      'medical report',
      'diagnosis',
      'ordonnance',
      'rapport medical',
    ],
    DocumentSemanticType.insurance: [
      'apolice de seguro',
      'apolice',
      'poliza de seguro',
      'insurance policy',
      'policy number',
      'police assurance',
      'assurance',
    ],
    DocumentSemanticType.warranty: [
      'garantia',
      'warranty',
      'guarantee',
      'garantie',
    ],
  };

  static const List<String> _validityKeywords = [
    'valido ate',
    'data de validade',
    'validade',
    'fecha de caducidad',
    'caducidad',
    "date d'expiration",
    'date expiration',
    'valid until',
    'expiry date',
    'expiration date',
  ];

  static const Set<DocumentSemanticType> _dateRelevantTypes = {
    DocumentSemanticType.identityDocument,
    DocumentSemanticType.insurance,
    DocumentSemanticType.warranty,
    DocumentSemanticType.contract,
  };

  DocumentClassification classify(String rawText) {
    final normalized = _normalize(rawText);

    var bestType = DocumentSemanticType.other;
    var bestMatches = 0;

    for (final entry in _keywordsByType.entries) {
      final matches = entry.value
          .where((keyword) => normalized.contains(keyword))
          .length;
      if (matches > bestMatches) {
        bestMatches = matches;
        bestType = entry.key;
      }
    }

    final confidence = switch (bestMatches) {
      0 => 0.0,
      1 => 0.55,
      2 => 0.8,
      _ => 0.95,
    };

    final validityDate = _dateRelevantTypes.contains(bestType)
        ? _extractValidityDate(rawText, normalized)
        : null;

    return DocumentClassification(
      semanticType: bestType,
      confidence: confidence,
      validityDate: validityDate,
    );
  }

  DateTime? _extractValidityDate(String rawText, String normalized) {
    for (final keyword in _validityKeywords) {
      final index = normalized.indexOf(keyword);
      if (index == -1) continue;

      final windowStart = index.clamp(0, rawText.length);
      final windowEnd = (index + keyword.length + 40).clamp(0, rawText.length);
      final date = _firstDateIn(rawText.substring(windowStart, windowEnd));
      if (date != null) return date;
    }
    return null;
  }

  DateTime? _firstDateIn(String text) {
    final match = RegExp(
      r'(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})',
    ).firstMatch(text);
    if (match == null) return null;

    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    var year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    try {
      final date = DateTime(year, month, day);
      // Reject impossible dates like 31/02 that DateTime would otherwise
      // silently roll forward into March.
      if (date.month != month || date.day != day) return null;
      return date;
    } catch (_) {
      return null;
    }
  }

  String _normalize(String text) {
    final lower = text.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      buffer.writeCharCode(_stripDiacritic(rune));
    }
    return buffer.toString();
  }

  static const Map<int, int> _diacriticMap = {
    0xE1: 0x61, // á -> a
    0xE0: 0x61, // à -> a
    0xE2: 0x61, // â -> a
    0xE3: 0x61, // ã -> a
    0xE4: 0x61, // ä -> a
    0xE9: 0x65, // é -> e
    0xE8: 0x65, // è -> e
    0xEA: 0x65, // ê -> e
    0xEB: 0x65, // ë -> e
    0xED: 0x69, // í -> i
    0xEC: 0x69, // ì -> i
    0xEE: 0x69, // î -> i
    0xEF: 0x69, // ï -> i
    0xF3: 0x6F, // ó -> o
    0xF2: 0x6F, // ò -> o
    0xF4: 0x6F, // ô -> o
    0xF5: 0x6F, // õ -> o
    0xF6: 0x6F, // ö -> o
    0xFA: 0x75, // ú -> u
    0xF9: 0x75, // ù -> u
    0xFB: 0x75, // û -> u
    0xFC: 0x75, // ü -> u
    0xE7: 0x63, // ç -> c
    0xF1: 0x6E, // ñ -> n
  };

  int _stripDiacritic(int rune) => _diacriticMap[rune] ?? rune;
}
