/// OAuth client configuration for the cloud integrations.
///
/// TODO(cloud setup): these need real app registrations before the
/// "Connect" buttons work — until then the providers report
/// `isConfigured == false` and the Cloud tab says so instead of failing.
/// See "Cloud integrations" in docs/architecture.md.
class CloudConfig {
  const CloudConfig._();

  /// Must match `appAuthRedirectScheme` in android/app/build.gradle.kts (and
  /// CFBundleURLSchemes on iOS).
  static const redirectUri = 'com.eupasoft.alldocs:/oauth2redirect';

  /// Microsoft Entra (Azure AD) app registration → "Application (client)
  /// ID". Platform: "Mobile and desktop", redirect URI = [redirectUri].
  /// Delegated permissions: Files.ReadWrite, User.Read, offline_access.
  static const oneDriveClientId = '';

  /// Dropbox App Console → "App key" (no secret needed, PKCE is used).
  /// Permissions: files.metadata.read, files.content.read,
  /// files.content.write, account_info.read. Redirect URI = [redirectUri].
  static const dropboxAppKey = '';

  /// Google Drive reuses the Google Sign-In OAuth clients (see
  /// GoogleAuthConfig); it only needs the Drive API enabled in the same
  /// Google Cloud project and the scopes below on the consent screen.
  static const googleDriveEnabled = true;
}
