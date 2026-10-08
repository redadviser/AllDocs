class ApiBaseUrl {
  const ApiBaseUrl._();

  /// The production backend; `--dart-define=ALLDOCS_API_URL=...` points a
  /// build (or a test) at another one, e.g. a local server.
  static const String baseUrl = String.fromEnvironment(
    'ALLDOCS_API_URL',
    defaultValue: 'https://all-docs-backend.triplanai.eupasoft.com',
  );
  static const Duration requestTimeout = Duration(seconds: 12);
}
