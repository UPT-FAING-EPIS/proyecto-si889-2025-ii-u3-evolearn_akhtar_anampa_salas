import 'package:flutter/foundation.dart';

/// Notifies listeners when a new share has been created.
/// This is used to trigger automatic refresh of the SharedScreen (Compartidos tab)
/// after a share is created from the DirectoriesScreen.
class ShareRefreshNotifier extends ChangeNotifier {
  void notifyShareCreated(int shareId) {
    debugPrint('📢 ShareRefreshNotifier: Share created (ID: $shareId)');
    notifyListeners();
  }
}
