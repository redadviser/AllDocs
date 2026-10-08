import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/models/models.dart';
import 'package:all_docs/services/assistant_service.dart';

DocumentFile _doc(String id, String title, String? text, {List<String> tags = const []}) {
  return DocumentFile(
    id: id,
    title: title,
    fileName: '$id.pdf',
    type: DocumentType.pdf,
    dateLabel: '',
    sizeLabel: '',
    ocrText: text,
    tags: tags,
  );
}

void main() {
  final library = [
    _doc('car', 'Seguro automóvel', 'Apólice AU-778812. O seguro do carro é válido até 14/03/2027.'),
    _doc('home', 'Seguro casa', 'Seguro multirriscos habitação, válido até 01/02/2027.', tags: ['casa']),
    _doc('bill', 'Fatura luz março', 'EDP Comercial. Total a pagar 54,20 EUR.'),
    _doc('scan', 'Digitalização', null),
  ];

  test('picks the documents that match the question, best first', () {
    final picked = AssistantService.relevantDocuments(
      library,
      'Quando expira o seguro do carro?',
    );
    expect(picked.first.id, 'car');
    expect(picked.map((d) => d.id), contains('home'));
    expect(picked.map((d) => d.id), isNot(contains('bill')));
  });

  test('common words alone match nothing, so nothing is sent', () {
    expect(AssistantService.relevantDocuments(library, 'Quando é o meu?'), isEmpty);
  });

  test('documents without text are never sent', () {
    expect(
      AssistantService.relevantDocuments(library, 'digitalização'),
      isEmpty,
    );
  });

  test('a long document is cut to the passages around the question', () {
    final filler = 'Cláusula genérica sem interesse. ' * 2000;
    final long = _doc(
      'contract',
      'Contrato',
      '${filler}O período de fidelização é de 24 meses.$filler',
    );
    final text = AssistantService.documentText(long, question: 'fidelização');
    expect(text.length, lessThanOrEqualTo(AssistantService.maxDocumentChars));
    expect(text, contains('fidelização é de 24 meses'));
  });

  test('reads the extracted fields, leaving unknown ones null', () {
    final fields = AssistantFields.fromJson({
      'document_type': 'insurance',
      'suggested_title': 'Seguro auto',
      'suggested_tags': ['carro'],
      'holder_name': 'Ana Silva',
      'issue_date': null,
      'expiry_date': '2027-03-14',
      'document_number': null,
      'nif': '123456789',
      'iban': null,
      'policy_number': 'AU-778812',
      'amount': {'value': 312.4, 'currency': 'EUR'},
    });
    expect(fields.expiryDate, DateTime(2027, 3, 14));
    expect(fields.issueDate, isNull);
    expect(fields.amount, 312.4);
    expect(fields.suggestedTags, ['carro']);
  });
}
