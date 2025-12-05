// Permite override por --dart-define=BASE_URL=http://<host>:<puerto>
const String _definedBaseUrl = String.fromEnvironment('BASE_URL');

String getBaseUrl() =>
    _definedBaseUrl.isNotEmpty ? _definedBaseUrl : 'http://localhost:8003';