import 'dart:io';

// Permite override por --dart-define=BASE_URL=http://<host>:<puerto>
const String _definedBaseUrl = String.fromEnvironment('BASE_URL');

String getBaseUrl() {
  // Si viene por dart-define, úsalo.
  if (_definedBaseUrl.isNotEmpty) {
    return _definedBaseUrl;
  }

  // Android emulador usa el host loopback del host: 10.0.2.2
  // iOS simulador y escritorio pueden usar 127.0.0.1
  if (Platform.isAndroid) {
    return 'http://161.132.49.24:8003';
  }
  return 'http://161.132.49.24:8003';
}
