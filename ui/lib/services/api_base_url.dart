class ApiBaseUrl {
  const ApiBaseUrl._();

  // TODO(Phase 1 deploy): point this at the deployed AllDocs backend once it
  // exists. Inert while LocalModeConfig.isLocalOnly is true.
  static const String baseUrl = 'http://localhost:3000';
  static const Duration requestTimeout = Duration(seconds: 12);
}
