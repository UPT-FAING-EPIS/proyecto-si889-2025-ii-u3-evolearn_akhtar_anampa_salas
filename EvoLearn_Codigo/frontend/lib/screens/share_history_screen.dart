import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/shared_service.dart';

class ShareHistoryScreen extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> share;

  const ShareHistoryScreen({
    super.key,
    required this.api,
    required this.share,
  });

  @override
  State<ShareHistoryScreen> createState() => _ShareHistoryScreenState();
}

class _ShareHistoryScreenState extends State<ShareHistoryScreen> {
  late SharedService _sharedService;
  List<dynamic> _events = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _totalEvents = 0;
  int _currentOffset = 0;
  final int _pageSize = 50;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _sharedService = SharedService(widget.api);
    _loadHistory();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_loadingMore && _hasMore) {
        _loadMoreHistory();
      }
    }
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _currentOffset = 0;
    });

    try {
      final shareId = widget.share['id'] as int;
      final data = await _sharedService.getShareHistory(
        shareId: shareId,
        limit: _pageSize,
        offset: 0,
      );

      if (!mounted) return;

      setState(() {
        _events = data['events'] ?? [];
        _totalEvents = data['total_events'] ?? 0;
        _hasMore = data['has_more'] ?? false;
        _currentOffset = _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMoreHistory() async {
    if (!mounted || _loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);

    try {
      final shareId = widget.share['id'] as int;
      final data = await _sharedService.getShareHistory(
        shareId: shareId,
        limit: _pageSize,
        offset: _currentOffset,
      );

      if (!mounted) return;

      setState(() {
        _events.addAll(data['events'] ?? []);
        _hasMore = data['has_more'] ?? false;
        _currentOffset += _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shareName = widget.share['name']?.toString() ?? 'Sin nombre';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Historial'),
            Text(
              shareName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
            tooltip: 'Recargar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadHistory,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _events.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 80, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(
                            'No hay eventos registrados',
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Header with count
                        Container(
                          padding: const EdgeInsets.all(16),
                          color: Colors.grey[100],
                          child: Row(
                            children: [
                              Icon(Icons.event_note, size: 20, color: Colors.grey[700]),
                              const SizedBox(width: 8),
                              Text(
                                '$_totalEvents ${_totalEvents == 1 ? 'evento' : 'eventos'}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Events list
                        Expanded(
                          child: ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _events.length + (_loadingMore ? 1 : 0),
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              if (index >= _events.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              return _buildEventTile(_events[index]);
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildEventTile(Map<String, dynamic> event) {
    final action = event['action']?.toString() ?? 'unknown';
    final userName = event['user_name']?.toString() ?? 'Usuario';
    final createdAt = event['created_at']?.toString();
    final directoryName = event['directory_name']?.toString();
    final documentName = event['document_name']?.toString();
    final details = event['details'] as Map<String, dynamic>?;

    // Parse and format timestamp
    String timeAgo = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt);
        final now = DateTime.now();
        final diff = now.difference(dt);

        if (diff.inMinutes < 1) {
          timeAgo = 'Ahora mismo';
        } else if (diff.inHours < 1) {
          timeAgo = 'Hace ${diff.inMinutes} min';
        } else if (diff.inDays < 1) {
          timeAgo = 'Hace ${diff.inHours} h';
        } else if (diff.inDays < 7) {
          timeAgo = 'Hace ${diff.inDays} días';
        } else {
          timeAgo = DateFormat('dd/MM/yyyy HH:mm').format(dt);
        }
      } catch (_) {
        timeAgo = createdAt;
      }
    }

    // Build event message and icon
    IconData icon;
    Color iconColor;
    String message;

    switch (action) {
      case 'share_created':
        icon = Icons.add_circle_outline;
        iconColor = Colors.green;
        message = 'creó el compartido';
        break;
      case 'user_added':
        icon = Icons.person_add;
        iconColor = Colors.blue;
        final addedUserName = details?['added_user_name'] ?? 'un usuario';
        final role = details?['role'] ?? 'viewer';
        final roleText = role == 'editor' ? 'como editor' : 'como visor';
        message = 'agregó a $addedUserName $roleText';
        break;
      case 'user_removed':
        icon = Icons.person_remove;
        iconColor = Colors.orange;
        final removedUserName = details?['removed_user_name'] ?? 'un usuario';
        message = 'eliminó a $removedUserName';
        break;
      case 'role_changed':
        icon = Icons.admin_panel_settings;
        iconColor = Colors.purple;
        final targetUser = details?['target_user_name'] ?? 'un usuario';
        final newRole = details?['new_role'] ?? '';
        final roleText = newRole == 'editor' ? 'editor' : 'visor';
        message = 'cambió el rol de $targetUser a $roleText';
        break;
      case 'directory_created':
        icon = Icons.create_new_folder;
        iconColor = Colors.blue;
        message = 'creó la carpeta ${directoryName ?? 'sin nombre'}';
        break;
      case 'directory_renamed':
        icon = Icons.drive_file_rename_outline;
        iconColor = Colors.indigo;
        final oldName = details?['old_name'] ?? '';
        final newName = details?['new_name'] ?? directoryName ?? '';
        message = 'renombró "$oldName" a "$newName"';
        break;
      case 'directory_moved':
        icon = Icons.drive_file_move;
        iconColor = Colors.teal;
        message = 'movió la carpeta ${directoryName ?? ''}';
        break;
      case 'directory_deleted':
        icon = Icons.delete_outline;
        iconColor = Colors.red;
        message = 'eliminó la carpeta ${directoryName ?? 'sin nombre'}';
        break;
      case 'document_uploaded':
        icon = Icons.upload_file;
        iconColor = Colors.green;
        message = 'subió ${documentName ?? 'un documento'}';
        break;
      case 'document_renamed':
        icon = Icons.edit_note;
        iconColor = Colors.indigo;
        final oldDocName = details?['old_name'] ?? '';
        final newDocName = details?['new_name'] ?? documentName ?? '';
        message = 'renombró "$oldDocName" a "$newDocName"';
        break;
      case 'document_moved':
        icon = Icons.snippet_folder;
        iconColor = Colors.teal;
        message = 'movió ${documentName ?? 'un documento'}';
        break;
      case 'document_deleted':
        icon = Icons.delete_sweep;
        iconColor = Colors.red;
        message = 'eliminó ${documentName ?? 'un documento'}';
        break;
      default:
        icon = Icons.info_outline;
        iconColor = Colors.grey;
        message = action;
    }

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: userName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: ' $message'),
          ],
        ),
      ),
      subtitle: Text(
        timeAgo,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      dense: true,
    );
  }
}
