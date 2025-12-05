import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

/// Service for offline caching with Hive
class CacheService {
  static const String _sharesBoxName = 'shares_cache';
  static const String _documentsBoxName = 'documents_cache';
  static const String _syncMetadataBoxName = 'sync_metadata';

  static late Box<Map> _sharesBox;
  static late Box<Map> _documentsBox;
  static late Box _syncMetadataBox;
  static bool _initialized = false;

  /// Initialize Hive and open boxes
  static Future<void> initialize() async {
    if (_initialized) return;

    final appDir = await getApplicationDocumentsDirectory();
    Hive.init(appDir.path);

    _sharesBox = await Hive.openBox<Map>(_sharesBoxName);
    _documentsBox = await Hive.openBox<Map>(_documentsBoxName);
    _syncMetadataBox = await Hive.openBox(_syncMetadataBoxName);

    _initialized = true;
  }

  /// Cache share data (owned and invited)
  static Future<void> cacheShares({
    required List<dynamic> ownedShares,
    required List<dynamic> invitedShares,
  }) async {
    await _sharesBox.clear();

    int index = 0;
    for (final share in ownedShares) {
      await _sharesBox.put('owned_$index', Map<String, dynamic>.from(share as Map));
      index++;
    }

    index = 0;
    for (final share in invitedShares) {
      await _sharesBox.put('invited_$index', Map<String, dynamic>.from(share as Map));
      index++;
    }

    // Update last sync time
    await _syncMetadataBox.put('shares_last_sync', DateTime.now().toIso8601String());
  }

  /// Get cached shares
  static Map<String, dynamic> getCachedShares() {
    final ownedShares = <Map<String, dynamic>>[];
    final invitedShares = <Map<String, dynamic>>[];

    for (final key in _sharesBox.keys) {
      final share = _sharesBox.get(key);
      if (share != null) {
        if (key.toString().startsWith('owned_')) {
          ownedShares.add(Map<String, dynamic>.from(share));
        } else if (key.toString().startsWith('invited_')) {
          invitedShares.add(Map<String, dynamic>.from(share));
        }
      }
    }

    return {
      'owned_shares': ownedShares,
      'invited_shares': invitedShares,
      'last_sync': _syncMetadataBox.get('shares_last_sync'),
    };
  }

  /// Cache directory structure and documents
  static Future<void> cacheDirectory({
    required int directoryId,
    required Map<String, dynamic> directoryData,
  }) async {
    await _documentsBox.put('dir_$directoryId', directoryData);
  }

  /// Get cached directory
  static Map<String, dynamic>? getCachedDirectory(int directoryId) {
    final data = _documentsBox.get('dir_$directoryId');
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  /// Mark shares as available offline
  static Future<void> markShareAsOfflineAvailable(int shareId) async {
    await _syncMetadataBox.put('share_${shareId}_offline', true);
  }

  /// Check if share is available offline
  static bool isShareAvailableOffline(int shareId) {
    return _syncMetadataBox.get('share_${shareId}_offline') == true;
  }

  /// Clear all cache
  static Future<void> clearCache() async {
    await _sharesBox.clear();
    await _documentsBox.clear();
    await _syncMetadataBox.clear();
  }

  /// Get last sync timestamp
  static DateTime? getLastSyncTime() {
    final timestamp = _syncMetadataBox.get('shares_last_sync') as String?;
    if (timestamp != null) {
      try {
        return DateTime.parse(timestamp);
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}
