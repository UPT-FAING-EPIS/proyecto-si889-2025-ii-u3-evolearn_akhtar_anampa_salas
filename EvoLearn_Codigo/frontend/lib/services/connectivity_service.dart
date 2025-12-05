import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Service for monitoring internet connectivity
class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  bool _isOnline = true;
  late Stream<List<ConnectivityResult>> _connectivityStream;

  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  ConnectivityService() {
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectivityStatus(result);
    } catch (e) {
      _isOnline = false;
    }

    _connectivityStream = _connectivity.onConnectivityChanged;
    _connectivityStream.listen(_updateConnectivityStatus);
  }

  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = results.contains(ConnectivityResult.none) == false &&
        results.isNotEmpty;

    // Solo notificar si cambió el estado
    if (wasOnline != _isOnline) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
