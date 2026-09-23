import '../cloud_keys.dart';
import '../google_auth_config.dart';

/// OAuth client configuration for the cloud integrations. The ids live in
/// the backend's .env and reach the app through [CloudKeys]; a provider
/// without its id reports `isConfigured == false` and the Connections page
/// says so instead of failing. See "Cloud integrations" in
/// docs/architecture.md for how to register each app.
class CloudConfig {
  const CloudConfig._();

  /// Must match `appAuthRedirectScheme` in android/app/build.gradle.kts (and
  /// CFBundleURLSchemes on iOS), and be registered as a redirect URI in the
  /// Microsoft and Dropbox app consoles.
  static const redirectUri = 'com.eupasoft.alldocs:/oauth2redirect';

  /// Microsoft Entra (Azure AD) app registration → "Application (client)
  /// ID". Platform: "Mobile and desktop", redirect URI = [redirectUri].
  /// Delegated permissions: Files.ReadWrite, User.Read, offline_access.
  static String get oneDriveClientId => CloudKeys.oneDriveClientId ?? '';

  /// Dropbox App Console → "App key" (no secret needed, PKCE is used).
  /// Permissions: files.metadata.read, files.content.read,
  /// files.content.write, account_info.read. Redirect URI = [redirectUri].
  static String get dropboxAppKey => CloudKeys.dropboxAppKey ?? '';

  /// Google Drive reuses the Google Sign-In OAuth clients; it also needs
  /// the Drive API enabled in the same Google Cloud project and the scopes
  /// of GoogleDriveProvider on the consent screen.
  static bool get googleDriveEnabled => GoogleAuthConfig.isConfigured;
}
