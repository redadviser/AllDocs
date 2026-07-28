import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/models/document_file.dart';
import 'package:all_docs/models/document_semantic_type.dart';
import 'package:all_docs/models/document_type.dart';
import 'package:all_docs/services/reminder_scheduler.dart';

DocumentFile _document({String id = 'doc1', DateTime? validityDate}) {
  return DocumentFile(
    id: id,
    title: 'Test',
    fileName: 'test.pdf',
    type: DocumentType.pdf,
    dateLabel: '01/01/2026',
    sizeLabel: '1 KB',
    semanticType: DocumentSemanticType.identityDocument,
    validityDate: validityDate,
  );
}

void main() {
  const scheduler = ReminderScheduler(leadTime: Duration(days: 14));
  final now = DateTime(2026, 1, 1);

  test('returns null when the document has no validity date', () {
    expect(scheduler.planFor(_document(), now: now), isNull);
  });

  test('schedules the reminder leadTime before the validity date', () {
    final plan = scheduler.planFor(
      _document(validityDate: DateTime(2026, 3, 1)),
      now: now,
    );

    expect(plan, isNotNull);
    expect(plan!.scheduledFor, DateTime(2026, 3, 1).subtract(const Duration(days: 14)));
  });

  test('returns null once the lead time has already passed', () {
    // Validity date is only 5 days out, but the lead time is 14 days.
    final plan = scheduler.planFor(
      _document(validityDate: now.add(const Duration(days: 5))),
      now: now,
    );
    expect(plan, isNull);
  });

  test('returns null for a validity date already in the past', () {
    final plan = scheduler.planFor(
      _document(validityDate: DateTime(2025, 1, 1)),
      now: now,
    );
    expect(plan, isNull);
  });

  test('the notification id is stable for the same document id', () {
    final planA = scheduler.planFor(
      _document(id: 'same-id', validityDate: DateTime(2026, 6, 1)),
      now: now,
    );
    final planB = scheduler.planFor(
      _document(id: 'same-id', validityDate: DateTime(2027, 9, 1)),
      now: now,
    );

    expect(planA!.notificationId, planB!.notificationId);
  });

  test('different documents get different notification ids', () {
    final planA = scheduler.planFor(
      _document(id: 'doc-a', validityDate: DateTime(2026, 6, 1)),
      now: now,
    );
    final planB = scheduler.planFor(
      _document(id: 'doc-b', validityDate: DateTime(2026, 6, 1)),
      now: now,
    );

    expect(planA!.notificationId, isNot(planB!.notificationId));
  });

  test('a custom lead time changes when the reminder fires', () {
    const shortLead = ReminderScheduler(leadTime: Duration(days: 2));
    final plan = shortLead.planFor(
      _document(validityDate: now.add(const Duration(days: 5))),
      now: now,
    );

    expect(plan, isNotNull);
    expect(plan!.scheduledFor, now.add(const Duration(days: 3)));
  });
}
