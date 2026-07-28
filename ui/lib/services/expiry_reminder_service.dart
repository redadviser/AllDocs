import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../common/app_constants.dart';
import '../models/document_file.dart';
import '../models/document_semantic_type.dart';
import 'reminder_scheduler.dart';

/// Schedules a local, on-device notification for a document's expiry date —
/// entirely local, no server involved (see the roadmap's Phase 1 vs. Phase 4
/// distinction in docs/architecture.md: this is the local-only reminder;
/// cross-device push comes later and is a deliberate, disclosed exception to
/// zero-knowledge sync, unlike this).
class ExpiryReminderService {
  ExpiryReminderService({
    FlutterLocalNotificationsPlugin? plugin,
    ReminderScheduler? scheduler,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _scheduler = scheduler ?? const ReminderScheduler();

  static const _channelId = 'expiry_reminders';

  final FlutterLocalNotificationsPlugin _plugin;
  final ReminderScheduler _scheduler;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    // No device-timezone lookup (that would need another plugin/dependency);
    // defaulting to UTC only shifts a "days ahead" reminder by hours, never
    // by a meaningful margin for this use case.

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    _initialized = true;
  }

  Future<void> requestPermission() async {
    await _ensureInitialized();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Schedules (or re-schedules, replacing any existing one) the reminder
  /// for this document, based on its [DocumentFile.validityDate]. Safe to
  /// call for every document regardless of type — a no-op if there's
  /// nothing to schedule.
  Future<void> syncReminder(DocumentFile document) async {
    await _ensureInitialized();

    final notificationId = stableNotificationId(document.id);
    await _plugin.cancel(notificationId);

    final plan = _scheduler.planFor(document);
    if (plan == null) return;

    await requestPermission();
    await _plugin.zonedSchedule(
      plan.notificationId,
      AppConstants.remindersExpiringTitle.tr(),
      AppConstants.remindersExpiringBody.tr(
        namedArgs: {
          'type': _typeLabel(document.semanticType),
          'date': DateFormat.yMMMd().format(document.validityDate!),
        },
      ),
      tz.TZDateTime.from(plan.scheduledFor, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          AppConstants.remindersChannelName.tr(),
          channelDescription: AppConstants.remindersChannelDescription.tr(),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Inexact is deliberate: a document expiring in weeks doesn't need
      // exact-alarm precision, and avoids requiring Android's
      // SCHEDULE_EXACT_ALARM permission for something this low-stakes.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelReminder(String documentId) async {
    await _ensureInitialized();
    await _plugin.cancel(stableNotificationId(documentId));
  }

  String _typeLabel(DocumentSemanticType? type) {
    final key = switch (type) {
      DocumentSemanticType.invoice => AppConstants.documentTypeInvoice,
      DocumentSemanticType.receipt => AppConstants.documentTypeReceipt,
      DocumentSemanticType.contract => AppConstants.documentTypeContract,
      DocumentSemanticType.identityDocument =>
        AppConstants.documentTypeIdentityDocument,
      DocumentSemanticType.medical => AppConstants.documentTypeMedical,
      DocumentSemanticType.insurance => AppConstants.documentTypeInsurance,
      DocumentSemanticType.warranty => AppConstants.documentTypeWarranty,
      DocumentSemanticType.other || null => AppConstants.documentTypeOther,
    };
    return key.tr();
  }
}
