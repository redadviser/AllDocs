import 'package:flutter/material.dart';

class AppConstants {
  static const translationsPath = 'assets/translations';
  static const supportedLocales = [
    Locale('pt'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
  ];
  static const fallbackLocale = Locale('pt');

  static const appTitle = 'app.title';

  static const navShelf = 'nav.shelf';
  static const navArchive = 'nav.archive';
  static const navProfile = 'nav.profile';

  static const authTitle = 'auth.title';
  static const authSubtitle = 'auth.subtitle';
  static const authDisplayName = 'auth.display_name';
  static const authEmail = 'auth.email';
  static const authPassword = 'auth.password';
  static const authForgot = 'auth.forgot';
  static const authForgotHint = 'auth.forgot_hint';
  static const authLogin = 'auth.login';
  static const authSignup = 'auth.signup';
  static const authToggleToSignup = 'auth.toggle_to_signup';
  static const authToggleToLogin = 'auth.toggle_to_login';
  static const authContinueWithAllId = 'auth.continue_with_allid';
  static const authContinueWithGoogle = 'auth.continue_with_google';
  static const authOrDivider = 'auth.or_divider';
  static const authOffline = 'auth.offline';
  static const authLoginError = 'auth.login_error';

  static const securityGreetingMorning = 'security.greeting_morning';
  static const securityGreetingAfternoon = 'security.greeting_afternoon';
  static const securityGreetingEvening = 'security.greeting_evening';
  static const securityCreatePinTitle = 'security.create_pin_title';
  static const securityCreatePinSubtitle = 'security.create_pin_subtitle';
  static const securityUnlockTitle = 'security.unlock_title';
  static const securityUnlockSubtitle = 'security.unlock_subtitle';
  static const securityPin = 'security.pin';
  static const securityConfirmPin = 'security.confirm_pin';
  static const securitySavePin = 'security.save_pin';
  static const securityUnlock = 'security.unlock';
  static const securityEnableBiometrics = 'security.enable_biometrics';
  static const securityUseBiometrics = 'security.use_biometrics';
  static const securityPinLength = 'security.pin_length';
  static const securityPinMismatch = 'security.pin_mismatch';
  static const securityInvalidPin = 'security.invalid_pin';
  static const securityBiometricReason = 'security.biometric_reason';
  static const securityBiometricUnavailable = 'security.biometric_unavailable';
  static const securityDevicesTitle = 'security.devices_title';
  static const securityDevicesSubtitle = 'security.devices_subtitle';
  static const securityDevicesCurrent = 'security.devices_current';
  static const securityDevicesLastSeen = 'security.devices_last_seen';
  static const securityDevicesEmpty = 'security.devices_empty';
  static const securityDevicesLoadError = 'security.devices_load_error';
  static const securityDevicesRetry = 'security.devices_retry';
  static const securityDevicesEndSession = 'security.devices_end_session';
  static const securityDevicesEndSessionConfirmTitle =
      'security.devices_end_session_confirm_title';
  static const securityDevicesEndSessionConfirmMessage =
      'security.devices_end_session_confirm_message';
  static const securityDevicesEndSessionError =
      'security.devices_end_session_error';
  static const securityDevicesEndAll = 'security.devices_end_all';
  static const securityDevicesEndAllConfirmTitle =
      'security.devices_end_all_confirm_title';
  static const securityDevicesEndAllConfirmMessage =
      'security.devices_end_all_confirm_message';
  static const securityDevicesEndAllError = 'security.devices_end_all_error';
  static const securityDevicesPlatformAndroid =
      'security.devices_platform_android';
  static const securityDevicesPlatformIos = 'security.devices_platform_ios';
  static const securityDevicesPlatformOther =
      'security.devices_platform_other';

  static const commonCancel = 'common.cancel';
  static const commonCreate = 'common.create';
  static const commonDelete = 'common.delete';
  static const commonImport = 'common.import';
  static const commonImportAll = 'common.import_all';
  static const commonViewAll = 'common.view_all';
  static const commonMoreOptions = 'common.more_options';
  static const commonOpenDocument = 'common.open_document';
  static const commonFavorite = 'common.favorite';
  static const commonRemoveFavorite = 'common.remove_favorite';
  static const commonClose = 'common.close';

  static const docshelfTitle = 'docshelf.title';
  static const docshelfCreateFirstShelfTitle =
      'docshelf.create_first_shelf_title';
  static const docshelfCreateFirstShelfMessage =
      'docshelf.create_first_shelf_message';
  static const docshelfNewShelf = 'docshelf.new_shelf';
  static const docshelfShelfName = 'docshelf.shelf_name';
  static const docshelfDefaultShelfName = 'docshelf.default_shelf_name';
  static const docshelfNewAlbum = 'docshelf.new_album';
  static const docshelfAlbumName = 'docshelf.album_name';
  static const docshelfCreateAlbum = 'docshelf.create_album';
  static const docshelfDeleteShelf = 'docshelf.delete_shelf';
  static const docshelfDeleteShelfTitle = 'docshelf.delete_shelf_title';
  static const docshelfDeleteShelfMessage = 'docshelf.delete_shelf_message';
  static const docshelfDeleteAlbum = 'docshelf.delete_album';
  static const docshelfDeleteAlbumTitle = 'docshelf.delete_album_title';
  static const docshelfDeleteAlbumMessage = 'docshelf.delete_album_message';
  static const docshelfRecent = 'docshelf.recent';
  static const docshelfFavorites = 'docshelf.favorites';
  static const docshelfRecentEmpty = 'docshelf.recent_empty';
  static const docshelfFavoritesEmpty = 'docshelf.favorites_empty';
  static const docshelfAlbumEmptyTitle = 'docshelf.album_empty_title';
  static const docshelfAlbumEmptyMessage = 'docshelf.album_empty_message';
  static const docshelfDocumentCount = 'docshelf.document_count';
  static const docshelfColor = 'docshelf.color';
  static const docshelfIcon = 'docshelf.icon';

  static const archiveTitle = 'archive.title';
  static const archiveUnorganized = 'archive.unorganized';
  static const archiveDeviceFolders = 'archive.device_folders';
  static const archiveRecentlyImported = 'archive.recently_imported';
  static const archiveViewHistory = 'archive.view_history';
  static const archiveAddDocument = 'archive.add_document';
  static const archiveSelectFromPhoneTitle = 'archive.select_from_phone_title';
  static const archiveSelectFromPhoneSubtitle =
      'archive.select_from_phone_subtitle';
  static const archiveScanDocumentTitle = 'archive.scan_document_title';
  static const archiveScanDocumentSubtitle = 'archive.scan_document_subtitle';
  static const archiveScanStarting = 'archive.scan_starting';
  static const archiveScanDone = 'archive.scan_done';
  static const archiveScanFailed = 'archive.scan_failed';
  static const archiveImportCloudTitle = 'archive.import_cloud_title';
  static const archiveImportCloudSubtitle = 'archive.import_cloud_subtitle';
  static const archiveAll = 'archive.all';
  static const archiveImage = 'archive.image';
  static const archiveNew = 'archive.new';
  static const archiveArchive = 'archive.archive';
  static const archiveArchiveIn = 'archive.archive_in';
  static const archiveNoAlbums = 'archive.no_albums';
  static const archiveUnorganizedEmpty = 'archive.unorganized_empty';
  static const archiveOpenFolder = 'archive.open_folder';
  static const archiveSelectFolder = 'archive.select_folder';
  static const archiveDeviceFolderDownloads = 'archive.device_folder_downloads';
  static const archiveDeviceFolderDocuments = 'archive.device_folder_documents';
  static const archiveDeviceFolderWhatsapp = 'archive.device_folder_whatsapp';
  static const archiveDeviceFolderScans = 'archive.device_folder_scans';
  static const archiveDeviceFolderDrive = 'archive.device_folder_drive';
  static const archiveDeviceFolderCount = 'archive.device_folder_count';
  static const archiveSearchDevice = 'archive.search_device';
  static const archiveSearchDeviceSubtitle = 'archive.search_device_subtitle';
  static const archiveSearchingDevice = 'archive.searching_device';
  static const archiveAllDeviceDocuments = 'archive.all_device_documents';
  static const archiveDocumentTypes = 'archive.document_types';
  static const archiveTypeCount = 'archive.type_count';
  static const archiveSourceFolder = 'archive.source_folder';
  static const archiveFolderOpenFailed = 'archive.folder_open_failed';
  static const archiveDeviceFolderFound = 'archive.device_folder_found';
  static const archiveImportedCount = 'archive.imported_count';
  static const archiveNoSupportedDocuments = 'archive.no_supported_documents';
  static const archiveNoFilterResults = 'archive.no_filter_results';
  static const archiveDocumentImported = 'archive.document_imported';
  static const archiveImportFailed = 'archive.import_failed';
  static const archiveFeatureSoon = 'archive.feature_soon';

  static const profileTitle = 'profile.title';
  static const profileSettings = 'profile.settings';
  static const profileSettingsHint = 'profile.settings_hint';
  static const profileStorage = 'profile.storage';
  static const profileStorageUsedOf = 'profile.storage_used_of';
  static const profileStoragePercent = 'profile.storage_percent';
  static const profileStorageUsed = 'profile.storage_used';
  static const profileStorageAvailable = 'profile.storage_available';
  static const profileDocuments = 'profile.documents';
  static const profileCategories = 'profile.categories';
  static const profileAlbums = 'profile.albums';
  static const profileFavorites = 'profile.favorites';
  static const profileCustomization = 'profile.customization';
  static const profilePrimaryColor = 'profile.primary_color';
  static const profileFontSize = 'profile.font_size';
  static const profileContrastMode = 'profile.contrast_mode';
  static const profileContrastDescription = 'profile.contrast_description';
  static const profileCloudSync = 'profile.cloud_sync';
  static const profileActive = 'profile.active';
  static const profileAutoBackup = 'profile.auto_backup';
  static const profileDaily = 'profile.daily';
  static const profileBiometricLock = 'profile.biometric_lock';
  static const profileExportDocuments = 'profile.export_documents';
  static const profileExportPickerTitle = 'profile.export_picker_title';
  static const profileExportDone = 'profile.export_done';
  static const profileExportEmpty = 'profile.export_empty';
  static const profileLanguage = 'profile.language';
  static const profilePortuguese = 'profile.portuguese';
  static const profileEnglish = 'profile.english';
  static const profileSpanish = 'profile.spanish';
  static const profileFrench = 'profile.french';
  static const profileSecurity = 'profile.security';
  static const profileSecuritySubtitle = 'profile.security_subtitle';
  static const profilePlanTitle = 'profile.plan_title';
  static const profilePlanFreeSubtitle = 'profile.plan_free_subtitle';
  static const profilePlanActiveSubtitle = 'profile.plan_active_subtitle';
  static const profileManagePlan = 'profile.manage_plan';
  static const profileBackendFeature = 'profile.backend_feature';
  static const profileSupportTitle = 'profile.support_title';
  static const profileFaq = 'profile.faq';
  static const profileContactSupport = 'profile.contact_support';
  static const profileContactSupportSubject = 'profile.contact_support_subject';
  static const profileRateApp = 'profile.rate_app';
  static const profilePrivacyPolicy = 'profile.privacy_policy';
  static const profileLinkOpenError = 'profile.link_open_error';

  static const faqTitle = 'faq.title';
  static const faqQ1Question = 'faq.q1_question';
  static const faqQ1Answer = 'faq.q1_answer';
  static const faqQ2Question = 'faq.q2_question';
  static const faqQ2Answer = 'faq.q2_answer';
  static const faqQ3Question = 'faq.q3_question';
  static const faqQ3Answer = 'faq.q3_answer';
  static const faqQ4Question = 'faq.q4_question';
  static const faqQ4Answer = 'faq.q4_answer';
  static const faqQ5Question = 'faq.q5_question';
  static const faqQ5Answer = 'faq.q5_answer';
  static const faqQ6Question = 'faq.q6_question';
  static const faqQ6Answer = 'faq.q6_answer';
  static const faqQ7Question = 'faq.q7_question';
  static const faqQ7Answer = 'faq.q7_answer';

  static const documentTypeInvoice = 'document_type.invoice';
  static const documentTypeReceipt = 'document_type.receipt';
  static const documentTypeContract = 'document_type.contract';
  static const documentTypeIdentityDocument = 'document_type.identity_document';
  static const documentTypeMedical = 'document_type.medical';
  static const documentTypeInsurance = 'document_type.insurance';
  static const documentTypeWarranty = 'document_type.warranty';
  static const documentTypeOther = 'document_type.other';

  static const remindersChannelName = 'reminders.channel_name';
  static const remindersChannelDescription = 'reminders.channel_description';
  static const remindersExpiringTitle = 'reminders.expiring_title';
  static const remindersExpiringBody = 'reminders.expiring_body';
  static const remindersSectionTitle = 'reminders.section_title';
  static const remindersEmpty = 'reminders.empty';
  static const remindersDueLabel = 'reminders.due_label';

  static const permissionStorageTitle = 'permission.storage_title';
  static const permissionStorageMessage = 'permission.storage_message';
  static const permissionStorageButton = 'permission.storage_button';
  static const permissionStorageRetry = 'permission.storage_retry';

  static const errorLoadDocuments = 'error.load_documents';
}
