import '../models/document_file.dart';

/// When (and under what stable id) a document's expiry reminder should fire.
/// Pure decision logic, kept separate from [ExpiryReminderService] so it's
/// unit-testable without touching the notifications plugin.
class ReminderPlan {
  const ReminderPlan({
    required this.notificationId,
    required this.scheduledFor,
  });

  final int notificationId;
  final DateTime scheduledFor;
}

class ReminderScheduler {
  const ReminderScheduler({this.leadTime = const Duration(days: 14)});

  /// How far ahead of [DocumentFile.validityDate] to notify.
  final Duration leadTime;

  /// Returns null when there's nothing to schedule: no validity date, or the
  /// lead time has already passed (scanning an already-expiring document
  /// doesn't retroactively notify — Phase 4's cross-device push is where a
  /// "documents already expiring" surface belongs, not a background alarm).
  ReminderPlan? planFor(DocumentFile document, {DateTime? now}) {
    final validityDate = document.validityDate;
    if (validityDate == null) return null;

    final scheduledFor = validityDate.subtract(leadTime);
    final reference = now ?? DateTime.now();
    if (!scheduledFor.isAfter(reference)) return null;

    return ReminderPlan(
      notificationId: stableNotificationId(document.id),
      scheduledFor: scheduledFor,
    );
  }

  /// The documents whose reminder should be scheduled: active ones with a
  /// reminder still ahead, soonest first — only the first [limit] when the
  /// plan caps them (the next one takes a freed slot on a later sync).
  List<DocumentFile> pick(
    Iterable<DocumentFile> documents, {
    int? limit,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final due = [
      for (final document in documents)
        if (document.isActive && planFor(document, now: reference) != null)
          document,
    ]..sort((a, b) => a.validityDate!.compareTo(b.validityDate!));
    return limit == null || due.length <= limit ? due : due.sublist(0, limit);
  }
}

/// Deterministic per-document notification id, so re-scanning/re-scheduling
/// the same document updates its one reminder instead of piling up new ones.
int stableNotificationId(String documentId) => documentId.hashCode & 0x7fffffff;
