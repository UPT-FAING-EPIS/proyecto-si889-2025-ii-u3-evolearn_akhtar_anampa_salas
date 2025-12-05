import 'api_service.dart';

/// Service for handling shared directories (shares)
class SharedService {
  final ApiService _api;

  SharedService(this._api);

  /// Get all shares (owned + invited)
  Future<Map<String, dynamic>> getMyShares() async {
    return await _api.get('get_my_shares.php');
  }

  /// Get updates for a specific share (polling)
  Future<Map<String, dynamic>> getShareUpdates({
    required int shareId,
    String? since,
  }) async {
    final params = <String, String>{
      'share_id': shareId.toString(),
    };
    if (since != null) {
      params['since'] = since;
    }
    return await _api.get('get_share_updates.php', queryParams: params);
  }

  /// Get cloud directory tree for a share
  Future<Map<String, dynamic>> getCloudDirectories(int shareId) async {
    return await _api.get('get_cloud_directories.php', queryParams: {
      'share_id': shareId.toString(),
    });
  }

  /// Search user by email for sharing
  Future<Map<String, dynamic>> searchUserByEmail(String email) async {
    return await _api.get('search_user_by_email.php', queryParams: {
      'email': email,
    });
  }

  /// Create a new share
  Future<Map<String, dynamic>> createShare({
    required String name,
    required List<int> directoryIds,
    required List<bool> includeSubtrees,
  }) async {
    return await _api.post('create_share.php', {
      'name': name,
      'directory_ids': directoryIds,
      'include_subtrees': includeSubtrees,
    });
  }

  /// Add user to share
  Future<Map<String, dynamic>> addShareUser({
    required int shareId,
    required int userId,
    required String role, // 'viewer' or 'editor'
  }) async {
    return await _api.post('add_share_user.php', {
      'share_id': shareId,
      'user_id': userId,
      'role': role,
    });
  }

  /// List users in a share
  Future<Map<String, dynamic>> listShareUsers(int shareId) async {
    return await _api.get('list_share_users.php', queryParams: {
      'share_id': shareId.toString(),
    });
  }

  /// Upload local folder tree to server before migrating to cloud
  Future<Map<String, dynamic>> uploadFolderTree({
    required String folderName,
    required List<Map<String, dynamic>> items,
  }) async {
    return await _api.post('upload_folder_tree.php', {
      'folder_name': folderName,
      'items': items,
    });
  }

  /// Migrate FS directory to cloud
  Future<Map<String, dynamic>> migrateToCloud({
    required String fsPath,
    required String shareName,
  }) async {
    return await _api.post('migrate_to_cloud.php', {
      'fs_path': fsPath,
      'share_name': shareName,
    });
  }

  /// Create share directly from uploaded folder (new flow)
  Future<Map<String, dynamic>> createShareFromUpload({
    required String folderName,
    required String shareName,
  }) async {
    return await _api.post('create_share_from_upload.php', {
      'folder_name': folderName,
      'share_name': shareName,
    });
  }

  /// Migrate cloud share back to local FS (owner only)
  Future<Map<String, dynamic>> migrateToLocal({
    required int shareId,
  }) async {
    return await _api.post('migrate_to_local.php', {
      'share_id': shareId,
    });
  }

  /// Get share history (events log)
  Future<Map<String, dynamic>> getShareHistory({
    required int shareId,
    int limit = 50,
    int offset = 0,
  }) async {
    return await _api.get('get_share_history.php', queryParams: {
      'share_id': shareId.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
  }

  /// Check lock status
  Future<Map<String, dynamic>> checkLock({
    required String type, // 'directory' or 'document'
    required int id,
  }) async {
    return await _api.get('check_lock.php', queryParams: {
      'type': type,
      'id': id.toString(),
    });
  }

  /// Release lock
  Future<Map<String, dynamic>> releaseLock({
    required String type,
    required int id,
  }) async {
    return await _api.post('release_lock.php', {
      'type': type,
      'id': id,
    });
  }

  /// Remove directories from share (unshare subdirectories)
  Future<Map<String, dynamic>> removeShareDirectories({
    required int shareId,
    required List<int> directoryIds,
  }) async {
    return await _api.post('remove_share_directories.php', {
      'share_id': shareId,
      'directory_ids': directoryIds,
    });
  }

  /// Update user role in share
  Future<Map<String, dynamic>> updateShareUserRole({
    required int shareId,
    required int userId,
    required String role, // 'viewer' or 'editor'
  }) async {
    return await _api.post('update_share_user_role.php', {
      'share_id': shareId,
      'user_id': userId,
      'role': role,
    });
  }

  /// Remove user from share
  Future<Map<String, dynamic>> removeShareUser({
    required int shareId,
    required int userId,
  }) async {
    return await _api.post('remove_share_user.php', {
      'share_id': shareId,
      'user_id': userId,
    });
  }

  /// Create a new directory in cloud
  Future<Map<String, dynamic>> createDirectory({
    required int directoryId,
    required String name,
    String colorHex = '#1565C0',
  }) async {
    return await _api.post('create_directory.php', {
      'parent_id': directoryId,
      'name': name,
      'color_hex': colorHex,
    });
  }

  /// Update directory (rename or change color)
  Future<Map<String, dynamic>> updateDirectory({
    required int directoryId,
    String? name,
    String? colorHex,
  }) async {
    final data = <String, dynamic>{'id': directoryId};
    if (name != null) data['name'] = name;
    if (colorHex != null) data['color_hex'] = colorHex;
    return await _api.post('update_directory.php', data);
  }

  /// Delete directory from cloud
  Future<Map<String, dynamic>> deleteDirectory(int directoryId) async {
    return await _api.post('delete_directory.php', {
      'id': directoryId,
    });
  }

  /// Move directory to another parent
  Future<Map<String, dynamic>> moveDirectory({
    required int directoryId,
    required int targetParentId,
  }) async {
    return await _api.post('move_directory.php', {
      'id': directoryId,
      'target_parent_id': targetParentId,
    });
  }

  /// Update document (rename)
  Future<Map<String, dynamic>> updateDocument({
    required int documentId,
    String? displayName,
  }) async {
    final data = <String, dynamic>{'document_id': documentId};
    if (displayName != null) data['new_name'] = displayName;
    return await _api.post('update_document.php', data);
  }

  /// Delete document from cloud
  Future<Map<String, dynamic>> deleteDocument(int documentId) async {
    return await _api.post('delete_document.php', {
      'document_id': documentId,
    });
  }

  /// Move document to another directory
  Future<Map<String, dynamic>> moveDocument({
    required int documentId,
    required int targetDirectoryId,
  }) async {
    return await _api.post('move_document.php', {
      'document_id': documentId,
      'target_directory_id': targetDirectoryId,
    });
  }

  /// Generate summary for a PDF document
  Future<Map<String, dynamic>> generateSummary(int documentId) async {
    return await _api.post('generate_summary.php', {
      'document_id': documentId,
    });
  }

  /// Upload PDF to cloud directory (owner/editor only)
  /// Returns a Map with document info if successful
  Future<Map<String, dynamic>> uploadPdfToDirectory({
    required int directoryId,
    required String fileName,
    required List<int> fileBytes,
  }) async {
    // This will use the uploadPdfToCloudDirectory method from ApiService
    return await _api.uploadPdfToCloudDirectory(
      directoryId: directoryId,
      fileName: fileName,
      fileBytes: fileBytes,
    );
  }
}
