class LocalModeConfig {
  const LocalModeConfig._();

  // Flip this once the AllDocs backend exists and AuthService talks to it.
  static const bool isLocalOnly = true;
}
