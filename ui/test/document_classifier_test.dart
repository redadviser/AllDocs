import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/document_classifier.dart';

void main() {
  const classifier = DocumentClassifier();

  group('semantic type by language', () {
    final cases = <String, MapEntry<String, DocumentSemanticType>>{
      'Portuguese invoice': const MapEntry(
        'FATURA-RECIBO Nº 2024/001\nCliente: João Silva',
        DocumentSemanticType.invoice,
      ),
      'English receipt': const MapEntry(
        'RECEIPT\nThank you for your purchase',
        DocumentSemanticType.receipt,
      ),
      'Spanish contract': const MapEntry(
        'CONTRATO DE ARRENDAMIENTO\nEntre las partes...',
        DocumentSemanticType.contract,
      ),
      'French identity card': const MapEntry(
        "CARTE NATIONALE D'IDENTITE\nRépublique Française",
        DocumentSemanticType.identityDocument,
      ),
      'Portuguese ID (Cartão de Cidadão)': const MapEntry(
        'CARTÃO DE CIDADÃO\nRepública Portuguesa',
        DocumentSemanticType.identityDocument,
      ),
      'English medical': const MapEntry(
        'PRESCRIPTION\nDr. Smith Medical Report',
        DocumentSemanticType.medical,
      ),
      'Spanish insurance': const MapEntry(
        'PÓLIZA DE SEGURO\nNúmero de póliza: 12345',
        DocumentSemanticType.insurance,
      ),
      'Portuguese warranty': const MapEntry(
        'CERTIFICADO DE GARANTIA\nProduto: Máquina de lavar',
        DocumentSemanticType.warranty,
      ),
      'Unrecognized text': const MapEntry(
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit',
        DocumentSemanticType.other,
      ),
    };

    cases.forEach((name, expectation) {
      test(name, () {
        final result = classifier.classify(expectation.key);
        expect(result.semanticType, expectation.value);
      });
    });
  });

  group('confidence', () {
    test('no keyword match yields zero confidence', () {
      final result = classifier.classify('random unrelated text');
      expect(result.confidence, 0.0);
    });

    test('a single keyword match yields low-but-nonzero confidence', () {
      final result = classifier.classify('This document is a receipt');
      expect(result.confidence, 0.55);
    });

    test('multiple keyword matches raise confidence', () {
      final result = classifier.classify(
        'INVOICE\nTax invoice for services rendered',
      );
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });
  });

  group('validity date extraction', () {
    test('extracts a Portuguese "válido até" date for an ID document', () {
      final result = classifier.classify(
        'CARTÃO DE CIDADÃO\nNome: Ana Costa\nVálido até: 15/03/2028',
      );
      expect(result.semanticType, DocumentSemanticType.identityDocument);
      expect(result.validityDate, DateTime(2028, 3, 15));
    });

    test('extracts an English "expiry date" for a passport', () {
      final result = classifier.classify(
        'PASSPORT\nExpiry Date: 01/12/2030',
      );
      expect(result.validityDate, DateTime(2030, 12, 1));
    });

    test('extracts a Spanish "fecha de caducidad" for an insurance policy', () {
      final result = classifier.classify(
        'PÓLIZA DE SEGURO\nFecha de caducidad: 09.06.2027',
      );
      expect(result.validityDate, DateTime(2027, 6, 9));
    });

    test("extracts a French \"date d'expiration\" for a warranty", () {
      final result = classifier.classify(
        "GARANTIE\nDate d'expiration: 20-01-2026",
      );
      expect(result.validityDate, DateTime(2026, 1, 20));
    });

    test('does not extract a date for types where it is not relevant', () {
      final result = classifier.classify(
        'RECEIPT\nValid until: 01/01/2030',
      );
      expect(result.semanticType, DocumentSemanticType.receipt);
      expect(result.validityDate, isNull);
    });

    test('returns null when no date follows the validity keyword', () {
      final result = classifier.classify('CARTÃO DE CIDADÃO\nValidade: em breve');
      expect(result.validityDate, isNull);
    });

    test('rejects an impossible calendar date', () {
      final result = classifier.classify('CONTRATO\nValidade: 31/02/2027');
      expect(result.validityDate, isNull);
    });

    test('normalizes a two-digit year to the 2000s', () {
      final result = classifier.classify('CONTRATO\nValidade: 05/07/27');
      expect(result.validityDate, DateTime(2027, 7, 5));
    });
  });
}
