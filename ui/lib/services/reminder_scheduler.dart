import '../models/document_file.dart';

/// When (and under what stable id) a document's expiry reminder should fire.
/// Pure decision logic, kept separate from [ExpiryReminderService] so it's
/// unit-testable without touching the notifications plugin.
class ReminderPlan {
  const ReminderPlan({required this.notificationId, required this.scheduledFor});

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
}

/// Deterministic per-document notification id, so re-scanning/re-scheduling
/// the same document updates its one reminder instead of piling up new ones.
int stableNotificationId(String documentId) => documentId.hashCode & 0x7fffffff;
