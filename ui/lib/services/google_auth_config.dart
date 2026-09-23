import 'dart:io';

import 'cloud_keys.dart';

/// Google OAuth clients, from the backend (see [CloudKeys]). See the
/// "Cloud integrations" checklist in docs/architecture.md.
class GoogleAuthConfig {
  const GoogleAuthConfig._();

  /// Web client id of the Google Cloud project. Android needs it to sign
  /// in at all, and it's one of the audiences the backend accepts for the
  /// ID token (GOOGLE_SIGNIN_WEB_CLIENT_ID).
  static String? get serverClientId => CloudKeys.googleWebClientId;

  /// iOS client id (its reversed form must also be a URL scheme, set in
  /// ios/Flutter/CloudKeys.xcconfig). Null elsewhere.
  static String? get iosClientId =>
      Platform.isIOS ? CloudKeys.googleIosClientId : null;

  /// Whether Google Sign-In (and so Google Drive) can work on this build.
  static bool get isConfigured =>
      Platform.isIOS ? iosClientId != null : serverClientId != null;
}
