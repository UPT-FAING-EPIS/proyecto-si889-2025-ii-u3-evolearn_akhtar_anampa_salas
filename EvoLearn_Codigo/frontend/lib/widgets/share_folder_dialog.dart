import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/shared_service.dart';
import '../services/local_storage_service.dart';

class ShareFolderDialog extends StatefulWidget {
  final ApiService api;
  final String fsPath;
  final String folderName;
  final String userId;

  const ShareFolderDialog({
    super.key,
    required this.api,
    required this.fsPath,
    required this.folderName,
    required this.userId,
  });

  @override
  State<ShareFolderDialog> createState() => _ShareFolderDialogState();
}

class _ShareFolderDialogState extends State<ShareFolderDialog> {
  final _emailController = TextEditingController();
  late SharedService _sharedService;

  String selectedRole = 'viewer';
  bool isSearching = false;
  bool isAdding = false;
  String? searchError;
  Map<String, dynamic>? foundUser;

  // Lista de usuarios pendientes por agregar
  final List<Map<String, dynamic>> _pendingUsers = [];

  @override
  void initState() {
    super.initState();
    _sharedService = SharedService(widget.api);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        searchError = 'Ingresa un email';
      });
      return;
    }

    setState(() {
      isSearching = true;
      searchError = null;
    });

    try {
      final result = await _sharedService.searchUserByEmail(email);
      final user = result['user'] as Map<String, dynamic>?;

      if (!mounted) return;

      setState(() {
        if (user != null) {
          foundUser = user;
          searchError = null;
        } else {
          foundUser = null;
          searchError = 'Usuario no encontrado';
        }
        isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        foundUser = null;
        searchError = e.toString().replaceAll('Exception: ', '');
        isSearching = false;
      });
    }
  }

  void _addUserToPendingList() {
    if (foundUser == null) return;

    // Verificar si el usuario ya está en la lista
    final userId = foundUser!['id'] as int;
    final alreadyAdded = _pendingUsers.any((u) => u['user']['id'] == userId);

    if (alreadyAdded) {
      // Show warning after current frame to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este usuario ya está en la lista'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      });
      return;
    }

    setState(() {
      _pendingUsers.add({
        'user': foundUser,
        'role': selectedRole,
      });
      // Reset form
      _emailController.clear();
      foundUser = null;
      selectedRole = 'viewer'; // viewer = Lector
      searchError = null;
    });
  }

  void _removeUserFromPending(int index) {
    setState(() {
      _pendingUsers.removeAt(index);
    });
  }

  Future<void> _shareWithAllUsers() async {
    try {
      debugPrint('🟢 _shareWithAllUsers called');
      debugPrint('   - fsPath: ${widget.fsPath}');
      debugPrint('   - folderName: ${widget.folderName}');
      debugPrint('   - pendingUsers: ${_pendingUsers.length}');

      if (_pendingUsers.isEmpty) {
        // Use addPostFrameCallback to avoid calling setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Agrega al menos un usuario para compartir'),
              backgroundColor: Colors.orange,
            ),
          );
        });
        return;
      }

      debugPrint('🟢 Setting isAdding = true');
      setState(() => isAdding = true);

      // Show progress dialog
      String progressMessage = 'Preparando...';

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return WillPopScope(
              onWillPop: () async => false,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(40),
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(
                          progressMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

      void updateProgress(String message) {
        progressMessage = message;
        if (mounted) setState(() {});
      }

      // Step 0: Upload local folder tree to server (sequential & lightweight)
      debugPrint('🔵 Scanning local folder tree: ${widget.fsPath}');
      updateProgress('Escaneando carpeta local...');

      // Get all files and subdirectories from local device
      final dirPaths = await LocalStorageService.scanDirectoryStructure(
        widget.userId,
        widget.fsPath,
      );

      final fileEntries = await LocalStorageService.listFilesInTree(
        widget.userId,
        widget.fsPath,
      );

      debugPrint(
          '📦 Found ${dirPaths.length} subdirs + ${fileEntries.length} files');

      // Build items list with all directories first, then files
      final items = <Map<String, dynamic>>[];

      // Add all subdirectories
      for (final dirPath in dirPaths) {
        // Normalize path separators to forward slashes for backend (Windows: \ -> /)
        final normalizedPath = dirPath.replaceAll('\\', '/');
        items.add({
          'type': 'directory',
          'path': normalizedPath,
          'name': normalizedPath.split('/').last,
        });
      }

      // Add all files (with base64 content read on-demand to avoid OOM)
      for (int i = 0; i < fileEntries.length; i++) {
        final entry = fileEntries[i];
        final relPath = entry['path'] as String;
        final name = entry['name'] as String;

        updateProgress(
            'Preparando archivo ${i + 1} de ${fileEntries.length}...');

        // Read file on-demand
        final b64 = await LocalStorageService.readDocsFileAsBase64(
          widget.userId,
          relPath,
        );

        // Normalize path separators to forward slashes for backend (Windows: \ -> /)
        final normalizedPath = relPath.replaceAll('\\', '/');
        items.add({
          'type': 'file',
          'path': normalizedPath,
          'name': name,
          'content': b64,
        });
      }

      // Upload all at once (backend now handles it all)
      updateProgress('Subiendo ${items.length} elementos al servidor...');

      debugPrint('🔵 Uploading folder tree: ${items.length} items');

      final uploadResult = await _sharedService.uploadFolderTree(
        folderName: widget.folderName,
        items: items,
      );

      debugPrint('✅ Upload successful: ${uploadResult.toString()}');

      // Step 1: Create share directly from uploaded folder
      updateProgress('Creando share...');

      // Usar el nombre original de la carpeta (el backend ya sanitiza internamente)
      // Solo sanitizamos el nombre del share para evitar caracteres especiales
      final shareName = 'Compartir_${widget.folderName.replaceAll(' ', '_')}';

      debugPrint(
          '🔵 Creating share from upload: folderName=${widget.folderName}, shareName=$shareName');

      final shareResult = await _sharedService.createShareFromUpload(
        folderName: widget.folderName, // Usar nombre original, no sanitizado
        shareName: shareName,
      );

      debugPrint('✅ Share creation successful: ${shareResult.toString()}');

      final shareId = shareResult['share_id'] as int;

      // Step 2: Add all users to share
      updateProgress('Agregando usuarios...');

      int successCount = 0;
      int failCount = 0;
      final errors = <String>[];

      for (final pending in _pendingUsers) {
        try {
          final user = pending['user'] as Map<String, dynamic>;
          final role = pending['role'] as String;

          debugPrint('🔵 Adding user: ${user['email']}, role=$role');

          await _sharedService.addShareUser(
            shareId: shareId,
            userId: user['id'] as int,
            role: role,
          );
          successCount++;
        } catch (e) {
          failCount++;
          final userName =
              (pending['user'] as Map<String, dynamic>)['name'] ?? 'Usuario';
          final errorMsg = e.toString().replaceAll('Exception: ', '');
          errors.add('$userName: $errorMsg');
          debugPrint('❌ Failed to add user: $errorMsg');
        }
      }

      if (!mounted) return;

      // Prepare result for caller
      final resultPayload = {
        'success': successCount > 0 && failCount == 0,
        'successCount': successCount,
        'failCount': failCount,
        'errors': errors,
      };

      // Update progress message
      updateProgress('Completando...');

      // Wait 2 seconds
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      // Close progress dialog
      Navigator.pop(context);

      // Close share dialog returning result
      Navigator.pop(context, resultPayload);
    } catch (e, stackTrace) {
      debugPrint('❌ CRITICAL ERROR in _shareWithAllUsers: $e');
      debugPrint('Stack trace: $stackTrace');

      if (!mounted) return;
      setState(() => isAdding = false);

      final errorMsg = e.toString().replaceAll('Exception: ', '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al compartir: $errorMsg'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Compartir carpeta',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.folderName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Content - Scrollable
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.blue.shade700, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Agrega uno o más usuarios. Al compartir, la carpeta se moverá a la nube y se eliminará del almacenamiento local.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Email field
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email del usuario',
                          hintText: 'usuario@ejemplo.com',
                          prefixIcon: const Icon(Icons.email),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          errorText: searchError,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) {
                          setState(() {
                            searchError = null;
                            foundUser = null;
                          });
                        },
                        onSubmitted: (_) => _searchUser(),
                      ),
                      const SizedBox(height: 16),
                      // Search button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isSearching ? null : _searchUser,
                          icon: isSearching
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.search),
                          label: Text(isSearching ? 'Buscando...' : 'Buscar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      // Found user card
                      if (foundUser != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: const Color(0xFF1976D2),
                                child: Text(
                                  (foundUser!['name']?.toString() ?? 'U')[0]
                                      .toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      foundUser!['name']?.toString() ??
                                          'Usuario',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      foundUser!['email']?.toString() ??
                                          'Sin email',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.check_circle,
                                  color: Colors.green.shade700),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Role selector
                        const Text(
                          'Rol:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                value: 'viewer',
                                groupValue: selectedRole,
                                onChanged: (value) {
                                  setState(() {
                                    selectedRole = value!;
                                  });
                                },
                                title: const Row(
                                  children: [
                                    Icon(Icons.visibility,
                                        size: 18, color: Color(0xFF1976D2)),
                                    SizedBox(width: 8),
                                    Text('Lector',
                                        style: TextStyle(fontSize: 14)),
                                  ],
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<String>(
                                value: 'editor',
                                groupValue: selectedRole,
                                onChanged: (value) {
                                  setState(() {
                                    selectedRole = value!;
                                  });
                                },
                                title: const Row(
                                  children: [
                                    Icon(Icons.edit,
                                        size: 18, color: Color(0xFF1976D2)),
                                    SizedBox(width: 8),
                                    Text('Editor',
                                        style: TextStyle(fontSize: 14)),
                                  ],
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Add button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: isAdding ? null : _addUserToPendingList,
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar a la lista'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],

                      // Lista de usuarios pendientes
                      if (_pendingUsers.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.people,
                                size: 20, color: Color(0xFF1976D2)),
                            const SizedBox(width: 8),
                            Text(
                              'Usuarios a compartir (${_pendingUsers.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _pendingUsers.length,
                            itemBuilder: (context, index) {
                              final pending = _pendingUsers[index];
                              final user =
                                  pending['user'] as Map<String, dynamic>;
                              final role = pending['role'] as String;
                              final roleName =
                                  role == 'editor' ? 'Editor' : 'Lector';
                              final roleIcon = role == 'editor'
                                  ? Icons.edit
                                  : Icons.visibility;
                              const roleColor = Color(0xFF1976D2);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 1,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF1976D2),
                                    radius: 20,
                                    child: Text(
                                      (user['name']?.toString() ?? 'U')[0]
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    user['name']?.toString() ?? 'Usuario',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Row(
                                    children: [
                                      Icon(roleIcon,
                                          size: 14, color: roleColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        roleName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: roleColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    color: Colors.red,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () =>
                                        _removeUserFromPending(index),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Share button (main action)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: isAdding
                                ? null
                                : () async {
                                    debugPrint(
                                        '🔴 BUTTON PRESSED - About to call _shareWithAllUsers');
                                    try {
                                      await _shareWithAllUsers();
                                    } catch (e, stack) {
                                      debugPrint(
                                          '🔴 CRITICAL ERROR in button handler: $e');
                                      debugPrint('Stack: $stack');
                                    }
                                  },
                            icon: isAdding
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload),
                            label: Text(isAdding
                                ? 'Compartiendo...'
                                : 'Compartir con ${_pendingUsers.length} ${_pendingUsers.length == 1 ? "usuario" : "usuarios"}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1976D2),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
