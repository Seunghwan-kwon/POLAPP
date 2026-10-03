const String defaultApiServerUrl = 'http://127.0.0.1:4440';

const String apiServerUrl = String.fromEnvironment(
  'API_SERVER_URL',
  defaultValue: defaultApiServerUrl,
);

const String wsServerUrl = String.fromEnvironment(
  'WS_SERVER_URL',
  defaultValue: apiServerUrl,
);

String apiEndpoint(String path) {
  final base = apiServerUrl.endsWith('/')
      ? apiServerUrl.substring(0, apiServerUrl.length - 1)
      : apiServerUrl;
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return '$base$normalizedPath';
}
