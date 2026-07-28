class GoogleAuthConfig {
  const GoogleAuthConfig._();

  // TODO(AllID setup): fill in once the Google Cloud OAuth clients exist —
  // see the "Sign in with Google (AllID)" checklist in docs/architecture.md.
  // Must match the backend's GOOGLE_SIGNIN_WEB_CLIENT_ID so the ID token's
  // audience is one the server accepts.
  static const String? serverClientId = null;
}
