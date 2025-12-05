import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/shared_service.dart';
import '../services/connectivity_service.dart';
import '../services/cache_service.dart';
import '../providers/share_refresh_notifier.dart';
import 'cloud_directory_view_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import 'dart:async';

class SharedScreen extends StatefulWidget {
  final ApiService api;
  const SharedScreen({super.key, required this.api});

  @override
  State<SharedScreen> createState() => _SharedScreenState();
}

class _SharedScreenState extends State<SharedScreen> {
  late SharedService _sharedService;
  List<dynamic> _ownedShares = [];
  List<dynamic> _invitedShares = [];
  bool _loading = true;
  String? _error;
  Timer? _pollingTimer;
  final Map<int, String> _lastUpdateTimestamps = {}; // shareId -> timestamp
  final Set<int> _sharesWithUpdates = {}; // shareIds with pending updates
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _sharedService = SharedService(widget.api);
    _loadShares();
    // Start polling for updates every 2 seconds
    _pollingTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _checkUpdates());
    
    // Listen for share refresh notifications from DirectoriesScreen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = context.read<ShareRefreshNotifier>();
      notifier.addListener(_onShareCreated);
    });
  }

  void _onShareCreated() {
    debugPrint('🔄 Share created - reloading shares list');
    _loadShares();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    try {
      final notifier = context.read<ShareRefreshNotifier>();
      notifier.removeListener(_onShareCreated);
    } catch (e) {
      // Notifier might not be available
    }
    super.dispose();
  }

  Future<void> _loadShares() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final connectivityService = context.read<ConnectivityService>();
      
      if (connectivityService.isOnline) {
        // Online: fetch from API and cache
        await widget.api.ensureAuth();
        
        final data = await _sharedService.getMyShares();
        if (!mounted) return;

        // Cache the data
        await CacheService.cacheShares(
          ownedShares: data['owned_shares'] ?? [],
          invitedShares: data['invited_shares'] ?? [],
        );

        setState(() {
          _ownedShares = data['owned_shares'] ?? [];
          _invitedShares = data['invited_shares'] ?? [];
          _loading = false;
        });
      } else {
        // Offline: load from cache
        final cachedData = CacheService.getCachedShares();
        final ownedShares = cachedData['owned_shares'] as List? ?? [];
        final invitedShares = cachedData['invited_shares'] as List? ?? [];

        if (ownedShares.isEmpty && invitedShares.isEmpty) {
          // No cached data
          if (!mounted) return;
          setState(() {
            _error = 'Sin conexión y sin datos cacheados. Conecta a internet.';
            _loading = false;
          });
        } else {
          // Show cached data with offline indicator
          if (!mounted) return;
          setState(() {
            _ownedShares = ownedShares;
            _invitedShares = invitedShares;
            _loading = false;
            _error = null; // Clear error, data is available offline
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      
      // Handle token errors
      if (await _handleTokenError(e)) {
        return;
      }
      
      // Try to load from cache on error
      final cachedData = CacheService.getCachedShares();
      final ownedShares = cachedData['owned_shares'] as List? ?? [];
      final invitedShares = cachedData['invited_shares'] as List? ?? [];

      if (ownedShares.isNotEmpty || invitedShares.isNotEmpty) {
        setState(() {
          _ownedShares = ownedShares;
          _invitedShares = invitedShares;
          _loading = false;
          _error = 'Modo offline - datos cacheados (error: ${e.toString()})';
        });
      } else {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _checkUpdates() async {
    if (!mounted || _loading || _isPolling) return;

    setState(() => _isPolling = true);

    try {
      // Ensure token is loaded
      await widget.api.ensureAuth();
      
      final allShares = [..._ownedShares, ..._invitedShares];

      for (final share in allShares) {
        if (!mounted) break;

        final shareId = share['id'] as int;
        final lastTimestamp = _lastUpdateTimestamps[shareId];

        try {
          final result = await _sharedService.getShareUpdates(
            shareId: shareId,
            since: lastTimestamp,
          );

          if (!mounted) break;

          final hasUpdates = result['has_updates'] as bool? ?? false;
          final serverTime = result['server_time'] as String?;

          if (serverTime != null) {
            _lastUpdateTimestamps[shareId] = serverTime;
          }

          if (hasUpdates) {
            setState(() {
              _sharesWithUpdates.add(shareId);
            });
          }
        } catch (e) {
          // Silently fail individual share polling errors
          debugPrint('Polling error for share $shareId: $e');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isPolling = false);
      }
    }
  }

  void _clearUpdateBadge(int shareId) {
    setState(() {
      _sharesWithUpdates.remove(shareId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updateCount = _sharesWithUpdates.length;
    final connectivityService = context.watch<ConnectivityService>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const SizedBox(width: 8),
              const Text('Directorios Compartidos'),
              if (connectivityService.isOffline) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Sin conexión',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (updateCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$updateCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              if (_isPolling) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.grey),
                ),
              ],
            ],
          ),
          backgroundColor: theme.colorScheme.surface,
          foregroundColor: theme.colorScheme.onSurface,
          elevation: 0,
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Usuario',
              onSelected: (value) {
                switch (value) {
                  case 'profile':
                    _goToProfile();
                    break;
                  case 'logout':
                    _logout();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person, color: Color(0xFF1976D2)),
                      SizedBox(width: 8),
                      Text('Mi Perfil'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Cerrar Sesión'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            labelColor: const Color(0xFF1976D2),
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: const Color(0xFF1976D2),
            tabs: const [
              Tab(
                text: 'Mis Directorios',
                icon: Icon(Icons.folder_shared),
              ),
              Tab(
                text: 'Directorios de Amigos',
                icon: Icon(Icons.people_alt),
              ),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(_error!,
                            style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadShares,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                : TabBarView(
                    children: [
                      // Tab 1: Mis Directorios (owned shares)
                      RefreshIndicator(
                        onRefresh: _loadShares,
                        child: _ownedShares.isEmpty
                            ? _buildEmptyStateOwned()
                            : ListView(
                                padding: const EdgeInsets.all(16),
                                children: _ownedShares
                                    .map((share) =>
                                        _buildShareCard(share, isOwned: true))
                                    .toList(),
                              ),
                      ),
                      // Tab 2: Directorios de Amigos (invited shares)
                      RefreshIndicator(
                        onRefresh: _loadShares,
                        child: _invitedShares.isEmpty
                            ? _buildEmptyStateInvited()
                            : ListView(
                                padding: const EdgeInsets.all(16),
                                children: _invitedShares
                                    .map((share) =>
                                        _buildShareCard(share, isOwned: false))
                                    .toList(),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildEmptyStateOwned() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_shared, size: 80, color: const Color(0xFF1976D2)),
          const SizedBox(height: 16),
          Text(
            'No tienes directorios compartidos',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Comparte una carpeta para colaborar',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateInvited() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_alt, size: 80, color: const Color(0xFF1976D2)),
          const SizedBox(height: 16),
          Text(
            'Nadie te ha compartido directorios',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Cuando alguien te comparta una carpeta, aparecerá aquí',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildShareCard(Map<String, dynamic> share, {required bool isOwned}) {
    final role = share['role']?.toString() ?? 'viewer';
    final shareName = share['name']?.toString() ?? 'Sin nombre';
    final memberCount = share['member_count'] ?? 0;
    final ownerName = share['owner_name']?.toString();
    // Safe guard: backend may send null; avoid casting boolean or other
    final dynamic rootDirRaw = share['root_directory'];
    final Map<String, dynamic>? rootDir = rootDirRaw is Map<String, dynamic> ? rootDirRaw : null;
    final dirColor = rootDir?['color_hex']?.toString() ?? '#1565C0';
    final shareId = share['id'] as int;
    final hasUpdates = _sharesWithUpdates.contains(shareId);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasUpdates ? Colors.green.shade300 : Colors.grey.shade200,
          width: hasUpdates ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openShare(share),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Folder icon with color and update indicator
              Stack(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _hexToColor(dirColor).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.folder_shared,
                      color: _hexToColor(dirColor),
                      size: 24,
                    ),
                  ),
                  if (hasUpdates)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Share info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            shareName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildRoleBadge(role),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (!isOwned && ownerName != null)
                      Text(
                        'Propietario: $ownerName',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (isOwned) ...[
                      Row(
                        children: [
                          Icon(Icons.people,
                              size: 14, color: const Color(0xFF1976D2)),
                          const SizedBox(width: 4),
                          Text(
                            '$memberCount ${memberCount == 1 ? 'miembro' : 'miembros'}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (share['shared_users'] != null &&
                          (share['shared_users'] as List).isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: (share['shared_users'] as List)
                              .take(3)
                              .map((user) {
                            final userName =
                                user['name']?.toString() ?? 'Usuario';
                            final userRole =
                                user['role']?.toString() ?? 'viewer';
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: userRole == 'editor'
                                    ? Colors.orange.shade50
                                    : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: userRole == 'editor'
                                      ? Colors.orange.shade200
                                      : Colors.blue.shade200,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    userRole == 'editor'
                                        ? Icons.edit
                                        : Icons.visibility,
                                    size: 12,
                                    color: userRole == 'editor'
                                        ? Colors.orange.shade700
                                        : Colors.blue.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    userName.split(' ').first,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: userRole == 'editor'
                                          ? Colors.orange.shade700
                                          : Colors.blue.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        if ((share['shared_users'] as List).length > 3)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '+${(share['shared_users'] as List).length - 3} más',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
              // Options menu for owners
              if (role == 'owner')
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: Colors.grey[700]),
                  onSelected: (value) async {
                    if (value == 'unmigrate') {
                      final result = await _confirmUnmigrate(share);
                      if (result == true) {
                        _loadShares();
                      }
                    } else if (value == 'users') {
                      _showUsersDialog(share);
                    } else if (value == 'unshare') {
                      final result = await _showUnshareDialog(share);
                      if (result == true) {
                        _loadShares();
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'users',
                      child: Row(
                        children: [
                          Icon(Icons.people, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('Ver usuarios'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'unshare',
                      child: Row(
                        children: [
                          Icon(Icons.remove_circle_outline, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Dejar de compartir'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'unmigrate',
                      child: Row(
                        children: [
                          Icon(Icons.folder, color: Colors.orange),
                          SizedBox(width: 8),
                          Text('Convertir a local'),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    IconData icon;
    Color color;
    String label;

    switch (role) {
      case 'owner':
        icon = Icons.star;
        color = const Color(0xFFFFB300); // Amber
        label = 'Propietario';
        break;
      case 'editor':
        icon = Icons.edit;
        color = const Color(0xFF43A047); // Green
        label = 'Editor';
        break;
      case 'viewer':
      default:
        icon = Icons.visibility;
        color = const Color(0xFF1E88E5); // Blue
        label = 'Visor';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _hexToColor(String hex) {
    final hexCode = hex.replaceAll('#', '');
    return Color(int.parse('FF$hexCode', radix: 16));
  }

  void _openShare(Map<String, dynamic> share) async {
    final connectivityService = context.read<ConnectivityService>();
    
    // Si estamos offline y no hay datos cacheados para este share, mostrar modal
    if (connectivityService.isOffline) {
      final shareId = share['id'] as int;
      final isAvailableOffline = CacheService.isShareAvailableOffline(shareId);
      
      if (!isAvailableOffline) {
        _showNoInternetModal('acceder a este directorio compartido');
        return;
      }
    }

    final shareId = share['id'] as int;

    // Clear update badge when opening
    _clearUpdateBadge(shareId);

    // Navigate to CloudDirectoryViewScreen to see shared content
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CloudDirectoryViewScreen(
          api: widget.api,
          share: share,
        ),
      ),
    );

    // Refresh the list after returning
    _loadShares();
  }

  void _showUsersDialog(Map<String, dynamic> share) {
    final sharedUsers = share['shared_users'] as List? ?? [];
    final shareName = share['name']?.toString() ?? 'Sin nombre';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
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
                    const Icon(Icons.people, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Usuarios compartidos',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            shareName,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
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
              // User list
              Flexible(
                child: sharedUsers.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.people_outline,
                                size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text(
                              'No hay usuarios compartidos',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _showAddUserDialog(share);
                              },
                              icon: const Icon(Icons.person_add),
                              label: const Text('Agregar usuario'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1976D2),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: sharedUsers.length,
                        itemBuilder: (context, index) {
                          final user = sharedUsers[index];
                          final userName =
                              user['name']?.toString() ?? 'Usuario';
                          final userEmail =
                              user['email']?.toString() ?? 'Sin email';
                          final userRole = user['role']?.toString() ?? 'viewer';
                          final userId = user['id'] as int;
                          final profileImage =
                              user['profile_image']?.toString();

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // Profile image
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: const Color(0xFF1976D2),
                                    backgroundImage: profileImage != null &&
                                            profileImage.isNotEmpty
                                        ? NetworkImage(
                                            '${widget.api.baseUrl}/$profileImage')
                                        : null,
                                    child: profileImage == null ||
                                            profileImage.isEmpty
                                        ? Text(
                                            userName.isNotEmpty
                                                ? userName[0].toUpperCase()
                                                : 'U',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  // User info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          userName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          userEmail,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Role badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: userRole == 'editor'
                                          ? Colors.green.shade50
                                          : Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: userRole == 'editor'
                                            ? Colors.green.shade300
                                            : Colors.blue.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          userRole == 'editor'
                                              ? Icons.edit
                                              : Icons.visibility,
                                          size: 14,
                                          color: userRole == 'editor'
                                              ? Colors.green.shade700
                                              : Colors.blue.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          userRole == 'editor'
                                              ? 'Editor'
                                              : 'Visor',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: userRole == 'editor'
                                                ? Colors.green.shade700
                                                : Colors.blue.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Actions menu
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert,
                                        color: Colors.grey[600], size: 20),
                                    onSelected: (value) async {
                                      if (value == 'change_role') {
                                        await _changeUserRole(
                                          share,
                                          userId,
                                          userName,
                                          userRole,
                                        );
                                      } else if (value == 'remove') {
                                        await _removeUserFromShare(
                                          share,
                                          userId,
                                          userName,
                                        );
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'change_role',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.swap_horiz,
                                              size: 18,
                                              color: Colors.blue,
                                            ),
                                            SizedBox(width: 8),
                                            Text('Cambiar rol'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Row(
                                          children: [
                                            Icon(Icons.person_remove,
                                                size: 18, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text(
                                              'Eliminar del share',
                                              style:
                                                  TextStyle(color: Colors.red),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // Add user button (when there are users)
              if (sharedUsers.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showAddUserDialog(share);
                      },
                      icon: const Icon(Icons.person_add),
                      label: const Text('Agregar más usuarios'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeUserRole(
    Map<String, dynamic> share,
    int userId,
    String userName,
    String currentRole,
  ) async {
    final shareId = share['id'] as int;
    String selectedRole = currentRole;

    // Show modal with dropdown
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.swap_horiz, color: Color(0xFF1976D2)),
              SizedBox(width: 12),
              Text('Cambiar rol de usuario'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF1976D2),
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Role selector label
              const Text(
                'Selecciona el nuevo rol:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              // Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedRole,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          selectedRole = newValue;
                        });
                      }
                    },
                    items: [
                      DropdownMenuItem(
                        value: 'viewer',
                        child: Row(
                          children: [
                            Icon(Icons.visibility,
                                size: 20, color: Colors.blue.shade700),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Visor',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Solo puede ver contenido',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'editor',
                        child: Row(
                          children: [
                            Icon(Icons.edit,
                                size: 20, color: Colors.green.shade700),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Editor',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Puede editar y crear contenido',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: selectedRole == currentRole
                  ? null
                  : () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
              ),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Cambiando rol...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _sharedService.updateShareUserRole(
        shareId: shareId,
        userId: userId,
        role: selectedRole,
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      final roleName = selectedRole == 'editor' ? 'Editor' : 'Visor';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rol actualizado a $roleName exitosamente'),
          backgroundColor: Colors.green,
        ),
      );

      _loadShares();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeUserFromShare(
    Map<String, dynamic> share,
    int userId,
    String userName,
  ) async {
    final shareId = share['id'] as int;

    // Show confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red),
            SizedBox(width: 8),
            Text('Eliminar usuario'),
          ],
        ),
        content: Text(
          '¿Eliminar a $userName del share?\n\n'
          'Esta persona perderá acceso a todos los directorios y archivos compartidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Eliminando usuario...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _sharedService.removeShareUser(
        shareId: shareId,
        userId: userId,
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuario eliminado del share exitosamente'),
          backgroundColor: Colors.green,
        ),
      );

      _loadShares();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool?> _showUnshareDialog(Map<String, dynamic> share) async {
    final shareId = share['id'] as int;
    final shareName = share['name']?.toString() ?? 'Sin nombre';
    final sharedUsers = share['shared_users'] as List? ?? [];
    final memberCount = sharedUsers.length;
    final dynamic rootDirRaw = share['root_directory'];
    final Map<String, dynamic>? rootDir = rootDirRaw is Map<String, dynamic> ? rootDirRaw : null;
    final rootDirId = rootDir?['id'] as int?;

    // Load directory tree
    final List<Map<String, dynamic>> directories = [];
    bool isLoading = true;
    String? error;

    final selectedDirs = <int>{};
    bool selectedRoot = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          // Load directories on first build
          if (isLoading && directories.isEmpty) {
            _sharedService.getCloudDirectories(shareId).then((data) {
              setState(() {
                final tree = data['tree'] as List? ?? [];
                // Add root directory first
                if (tree.isNotEmpty && rootDirId != null) {
                  directories.add({
                    'id': rootDirId,
                    'name': shareName,
                    'level': 0,
                    'is_root': true,
                  });
                }
                // Flatten tree to get all subdirectories
                void flatten(List items, int level) {
                  for (var item in items) {
                    final children = item['children'] as List? ?? [];
                    if (children.isNotEmpty) {
                      for (var child in children) {
                        directories.add({
                          'id': child['id'],
                          'name': child['name'],
                          'level': level + 1,
                          'is_root': false,
                        });
                        final subChildren = child['children'] as List? ?? [];
                        if (subChildren.isNotEmpty) {
                          flatten([child], level + 1);
                        }
                      }
                    }
                  }
                }

                flatten(tree, 0);
                isLoading = false;
              });
            }).catchError((e) {
              setState(() {
                error = e.toString();
                isLoading = false;
              });
            });
          }

          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.remove_circle_outline,
                            color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Dejar de compartir',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                shareName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Flexible(
                    child: isLoading
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : error != null
                            ? Padding(
                                padding: const EdgeInsets.all(40),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.error_outline,
                                        size: 64, color: Colors.red),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Error: $error',
                                      style: const TextStyle(color: Colors.red),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                children: [
                                  // Info card
                                  Container(
                                    margin: const EdgeInsets.all(16),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.people,
                                                size: 18,
                                                color: Colors.red.shade700),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Compartido con $memberCount ${memberCount == 1 ? 'usuario' : 'usuarios'}',
                                              style: TextStyle(
                                                color: Colors.red.shade700,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children:
                                              sharedUsers.take(5).map((user) {
                                            final userName =
                                                user['name']?.toString() ??
                                                    'Usuario';
                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.red.shade300,
                                                ),
                                              ),
                                              child: Text(
                                                userName.split(' ').first,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.red.shade900,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                        if (memberCount > 5)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Text(
                                              '+${memberCount - 5} más',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.red.shade700,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        const Divider(height: 16),
                                        if (selectedRoot)
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.warning,
                                                    size: 16,
                                                    color:
                                                        Colors.orange.shade900),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'Al seleccionar el directorio raíz, TODOS los usuarios perderán acceso',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors
                                                          .orange.shade900,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        else
                                          Text(
                                            'Selecciona directorios específicos para dejar de compartir',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: directories.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No hay directorios',
                                              style:
                                                  TextStyle(color: Colors.grey),
                                            ),
                                          )
                                        : ListView.builder(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16),
                                            itemCount: directories.length,
                                            itemBuilder: (context, index) {
                                              final dir = directories[index];
                                              final dirId = dir['id'] as int;
                                              final dirName =
                                                  dir['name']?.toString() ??
                                                      'Sin nombre';
                                              final level =
                                                  dir['level'] as int? ?? 0;
                                              final isRoot =
                                                  dir['is_root'] as bool? ??
                                                      false;
                                              final isSelected = isRoot
                                                  ? selectedRoot
                                                  : selectedDirs
                                                      .contains(dirId);

                                              return CheckboxListTile(
                                                value: isSelected,
                                                enabled:
                                                    !selectedRoot || isRoot,
                                                onChanged: (checked) {
                                                  setState(() {
                                                    if (isRoot) {
                                                      selectedRoot =
                                                          checked == true;
                                                      if (selectedRoot) {
                                                        selectedDirs.clear();
                                                      }
                                                    } else {
                                                      if (checked == true) {
                                                        selectedDirs.add(dirId);
                                                      } else {
                                                        selectedDirs
                                                            .remove(dirId);
                                                      }
                                                    }
                                                  });
                                                },
                                                title: Padding(
                                                  padding: EdgeInsets.only(
                                                      left: level * 16.0),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        isRoot
                                                            ? Icons
                                                                .folder_special
                                                            : Icons.folder,
                                                        size: 20,
                                                        color: isRoot
                                                            ? Colors.red[700]
                                                            : Colors.grey[600],
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          dirName,
                                                          style: TextStyle(
                                                            fontWeight: isRoot
                                                                ? FontWeight
                                                                    .bold
                                                                : FontWeight
                                                                    .normal,
                                                            color: isRoot
                                                                ? Colors
                                                                    .red[900]
                                                                : null,
                                                          ),
                                                        ),
                                                      ),
                                                      if (isRoot)
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 2),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors
                                                                .red.shade100,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                          ),
                                                          child: Text(
                                                            'RAÍZ',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: Colors
                                                                  .red.shade700,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                  ),
                  // Actions
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: (selectedDirs.isEmpty && !selectedRoot) ||
                                  isLoading
                              ? null
                              : () async {
                                  Navigator.pop(context);
                                  if (selectedRoot) {
                                    // Eliminar TODOS los usuarios
                                    await _removeAllUsersFromShare(share);
                                  } else {
                                    // Dejar de compartir subdirectorios específicos
                                    await _unshareDirectories(
                                        shareId, selectedDirs.toList());
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: Text(selectedRoot
                              ? 'Eliminar todos los usuarios'
                              : 'Dejar de compartir'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return null;
  }

  Future<void> _removeAllUsersFromShare(Map<String, dynamic> share) async {
    final shareId = share['id'] as int;
    final shareName = share['name']?.toString() ?? 'Sin nombre';
    final sharedUsers = share['shared_users'] as List? ?? [];

    // Confirm
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red),
            SizedBox(width: 8),
            Text('Confirmar acción'),
          ],
        ),
        content: Text(
          '¿Estás seguro de eliminar TODOS los usuarios del share "$shareName"?\n\n'
          '${sharedUsers.length} ${sharedUsers.length == 1 ? 'usuario perderá' : 'usuarios perderán'} acceso.\n\n'
          'Esta acción NO eliminará el share de la base de datos. '
          'Usa "Convertir a local" para eso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar todos'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Eliminando usuarios...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Remove each user
      for (var user in sharedUsers) {
        final userId = user['id'] as int;
        await _sharedService.removeShareUser(
          shareId: shareId,
          userId: userId,
        );
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${sharedUsers.length} ${sharedUsers.length == 1 ? 'usuario eliminado' : 'usuarios eliminados'} exitosamente'),
          backgroundColor: Colors.green,
        ),
      );

      _loadShares();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _unshareDirectories(int shareId, List<int> directoryIds) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Dejando de compartir...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _sharedService.removeShareDirectories(
        shareId: shareId,
        directoryIds: directoryIds,
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subdirectorios removidos exitosamente'),
          backgroundColor: Colors.green,
        ),
      );

      _loadShares();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showAddUserDialog(Map<String, dynamic> share) async {
    final shareId = share['id'] as int;
    final shareName = share['name']?.toString() ?? 'Sin nombre';

    final emailController = TextEditingController();
    String selectedRole = 'viewer';
    bool isSearching = false;
    String? searchError;
    Map<String, dynamic>? foundUser;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 450),
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
                                'Agregar usuario',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                shareName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
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
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Email field
                        TextField(
                          controller: emailController,
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
                        ),
                        const SizedBox(height: 16),
                        // Search button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: isSearching
                                ? null
                                : () async {
                                    final email = emailController.text.trim();
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
                                      final result = await _sharedService
                                          .searchUserByEmail(email);
                                      final user = result['user']
                                          as Map<String, dynamic>?;

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
                                      setState(() {
                                        foundUser = null;
                                        searchError = e
                                            .toString()
                                            .replaceAll('Exception: ', '');
                                        isSearching = false;
                                      });
                                    }
                                  },
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                          size: 18, color: Colors.blue),
                                      SizedBox(width: 8),
                                      Text('Visor',
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
                                          size: 18, color: Colors.green),
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
                              onPressed: () async {
                                Navigator.pop(context);
                                // Show loading
                                showDialog(
                                  context: this.context,
                                  barrierDismissible: false,
                                  builder: (context) => const Center(
                                    child: Card(
                                      child: Padding(
                                        padding: EdgeInsets.all(20),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(),
                                            SizedBox(height: 16),
                                            Text('Agregando usuario...'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );

                                try {
                                  await _sharedService.addShareUser(
                                    shareId: shareId,
                                    userId: foundUser!['id'] as int,
                                    role: selectedRole,
                                  );

                                  if (!mounted) return;
                                  Navigator.pop(this.context); // Close loading

                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Usuario agregado exitosamente'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );

                                  _loadShares();
                                } catch (e) {
                                  if (!mounted) return;
                                  Navigator.pop(this.context); // Close loading

                                  final errorMsg = e
                                      .toString()
                                      .replaceAll('Exception: ', '');

                                  // Check if user already exists
                                  if (errorMsg
                                      .toLowerCase()
                                      .contains('already has this role')) {
                                    ScaffoldMessenger.of(this.context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'El usuario ya tiene acceso con este rol'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(this.context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $errorMsg'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.person_add),
                              label: const Text('Agregar al compartido'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool?> _confirmUnmigrate(Map<String, dynamic> share) async {
    final shareName = share['name']?.toString() ?? 'Sin nombre';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Text('Convertir a local'),
          ],
        ),
        content: Text(
          'Esta acción hará lo siguiente:\n\n'
          '1. Copiará todos los archivos de la base de datos a tu sistema de archivos local\n'
          '2. Eliminará el compartido "$shareName" de la sección Compartidos\n'
          '3. Todos los usuarios invitados perderán acceso\n\n'
          'Los archivos permanecerán en tu dispositivo como carpeta local.\n\n'
          '¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Convertir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    // Show loading
    if (!mounted) return false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Convirtiendo a local...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final shareId = share['id'] as int;
      await _sharedService.migrateToLocal(shareId: shareId);

      if (!mounted) return false;
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Carpeta convertida a local exitosamente'),
          backgroundColor: Colors.green,
        ),
      );

      return true;
    } catch (e) {
      if (!mounted) return false;
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );

      return false;
    }
  }

  void _goToProfile() {
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileScreen(api: widget.api)),
      );
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    widget.api.clearToken();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginScreen(api: widget.api)),
        (route) => false,
      );
    }
  }

  /// Handles invalid token errors by clearing session and redirecting to login.
  /// Returns true if the error was a token error, false otherwise.
  Future<bool> _handleTokenError(dynamic error) async {
    final errorMsg = error.toString().toLowerCase();
    
    if (errorMsg.contains('invalid token') || 
        errorMsg.contains('token expired') ||
        errorMsg.contains('missing bearer token') ||
        errorMsg.contains('missing auth token') ||
        errorMsg.contains('exception: invalid token')) {
      
      // Clear session
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      widget.api.clearToken();
      
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginScreen(api: widget.api)),
          (route) => false,
        );
      }
      return true;
    }
    return false;
  }

  void _showNoInternetModal(String actionName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.orange, size: 24),
            const SizedBox(width: 12),
            const Text('Sin conexión a internet'),
          ],
        ),
        content: Text(
          'Para $actionName necesitas estar conectado a internet.\n\nPor favor, conectate a una red Wi-Fi o datos móviles para continuar.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}
