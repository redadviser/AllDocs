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
  static const authEmail = 'auth.email';
  static const authPassword = 'auth.password';
  static const authForgot = 'auth.forgot';
  static const authForgotHint = 'auth.forgot_hint';
  static const authLogin = 'auth.login';
  static const authSignup = 'auth.signup';
  static const authToggleToSignup = 'auth.toggle_to_signup';
  static const authToggleToLogin = 'auth.toggle_to_login';
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
  static const profilePremiumPlan = 'profile.premium_plan';
  static const profilePremiumRenewal = 'profile.premium_renewal';
  static const profileManagePlan = 'profile.manage_plan';
  static const profileBackendFeature = 'profile.backend_feature';

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
