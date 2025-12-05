import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/shared_service.dart';
import 'share_history_screen.dart';
import 'pdf_viewer_screen.dart';
import 'summary_screen.dart';
import 'courses_screen.dart';

class ShareDetailScreen extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> share;

  const ShareDetailScreen({
    super.key,
    required this.api,
    required this.share,
  });

  @override
  State<ShareDetailScreen> createState() => _ShareDetailScreenState();
}

class _ShareDetailScreenState extends State<ShareDetailScreen> {
  late SharedService _sharedService;
  Map<String, dynamic>? _shareData;
  bool _loading = true;
  String? _error;
  Timer? _syncTimer;
  String? _lastUpdateTimestamp;
  bool _isSyncing = false;
  // Legacy variables - now handled within modal dialog during analysis
  // Keeping these to avoid breaking the UI rendering code
  Map<int, int> _analysisProgress = {}; // document_id -> progress (0-100)
  Map<int, String> _analysisStatus = {}; // document_id -> 'analyzing', 'completed'
  bool _isAnalyzing = false; // Prevenir análisis múltiples simultáneos
  final Set<int> _analyzingDocuments = {}; // Document IDs actualmente en análisis
  DateTime? _lastAnalysisAttempt; // Timestamp del último intento de análisis

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 ShareDetailScreen initState START');
    _sharedService = SharedService(widget.api);
    _loadShareDetails();
    _startSyncPolling();
    debugPrint('🚀 ShareDetailScreen initState END');
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  void _startSyncPolling() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && !_loading) {
        _pollUpdates();
      }
    });
  }

  Future<void> _pollUpdates() async {
    if (_isSyncing || !mounted) return;

    setState(() => _isSyncing = true);

    try {
      final shareId = widget.share['id'] as int;
      final result = await _sharedService.getShareUpdates(
        shareId: shareId,
        since: _lastUpdateTimestamp,
      );

      if (!mounted) return;

      final hasUpdates = result['has_updates'] as bool? ?? false;
      final serverTime = result['server_time'] as String?;

      if (serverTime != null) {
        _lastUpdateTimestamp = serverTime;
      }

      if (hasUpdates) {
        // Reload share data silently (without showing loading spinner)
        final data = await _sharedService.getCloudDirectories(shareId);
        if (mounted) {
          setState(() {
            _shareData = data;
          });
        }
      }
    } catch (e) {
      // Silently fail polling errors to avoid disrupting user
      debugPrint('Polling error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _testConnectivity() async {
    debugPrint('🔔 TESTING CONNECTIVITY FROM FLUTTER');
    try {
      final result = await widget.api.ping();
      debugPrint('✅ PING SUCCESS: $result');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Connection OK! Check console for details.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ PING FAILED: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Connection Failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _loadShareDetails() async {
    if (!mounted) return;
    
    debugPrint('🔄 _loadShareDetails START');
    
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final shareId = widget.share['id'] as int;
      debugPrint('🔄 Loading share $shareId...');
      final data = await _sharedService.getCloudDirectories(shareId);
      debugPrint('🔄 Data received: $data');
      if (!mounted) return;

      setState(() {
        _shareData = data;
        _loading = false;
      });
      debugPrint('🔄 _loadShareDetails SUCCESS - data set');
    } catch (e) {
      debugPrint('🔄 _loadShareDetails ERROR: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shareName = widget.share['name']?.toString() ?? 'Sin nombre';
    final role = widget.share['role']?.toString() ?? 'viewer';
    final ownerName = widget.share['owner_name']?.toString();
    final isOwner = role == 'owner';

    debugPrint('🏗️  BUILD: _loading=$_loading, _error=$_error, _shareData!=null=${_shareData != null}');

    return Scaffold(
      appBar: AppBar(
        title: Text(shareName),
        actions: [
          // TEST BUTTON FOR CONNECTIVITY
          IconButton(
            icon: const Icon(Icons.signal_cellular_alt),
            onPressed: _testConnectivity,
            tooltip: 'Test connection',
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _openHistory,
            tooltip: 'Ver historial',
          ),
          if (isOwner)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'unmigrate') {
                  _confirmUnmigrate();
                }
              },
              itemBuilder: (context) => [
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
            ),
          if (ownerName != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  ownerName,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          _buildRoleBadge(role),
          const SizedBox(width: 8),
          if (_isSyncing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 16),
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
                        onPressed: _loadShareDetails,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _buildDirectoryTree(),
    );
  }

  Future<void> _confirmUnmigrate() async {
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
        content: const Text(
          'Esta acción eliminará el compartido y todos los usuarios invitados perderán acceso.\n\n'
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
            child: const Text('Convertir a local'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _performUnmigrate();
    }
  }

  Future<void> _performUnmigrate() async {
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
      final shareId = widget.share['id'] as int;
      await _sharedService.migrateToLocal(shareId: shareId);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Carpeta convertida a local exitosamente'),
          backgroundColor: Colors.green,
        ),
      );

      // Return to Compartidos screen
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShareHistoryScreen(
          api: widget.api,
          share: widget.share,
        ),
      ),
    );
  }

  Widget _buildDirectoryTree() {
    final directories = _shareData?['directories'] as List<dynamic>? ?? [];

    debugPrint('🌳 Building directory tree with ${directories.length} directories');
    debugPrint('   _shareData keys: ${_shareData?.keys.toList()}');
    if (directories.isNotEmpty) {
      debugPrint('   First directory: ${directories[0]}');
    }

    if (directories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No hay directorios compartidos',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: directories.length,
      itemBuilder: (context, index) {
        final dir = directories[index] as Map<String, dynamic>;
        return _buildDirectoryCard(dir);
      },
    );
  }

  Widget _buildDirectoryCard(Map<String, dynamic> dir) {
    final dirName = dir['name']?.toString() ?? 'Sin nombre';
    final dirColor = dir['color_hex']?.toString() ?? '#1565C0';
    final documents = dir['documents'] as List<dynamic>? ?? [];
    final subdirs = dir['subdirectories'] as List<dynamic>? ?? [];

    debugPrint('📁 Directory: name=$dirName, docs=${documents.length}, subdirs=${subdirs.length}');
    if (documents.isNotEmpty) {
      debugPrint('   Documents structure: ${documents.runtimeType}');
      debugPrint('   First doc: ${documents[0]}');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(
          Icons.folder,
          color: _hexToColor(dirColor),
        ),
        title: Text(dirName),
        subtitle: Text('${documents.length} documentos, ${subdirs.length} subcarpetas'),
        children: [
          if (documents.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.description, size: 16, color: Colors.grey),
                  SizedBox(width: 8),
                  Text(
                    'Documentos',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ],
              ),
            ),
            ...documents.map((doc) => _buildDocumentTile(doc)),
          ],
          if (subdirs.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.folder, size: 16, color: Colors.grey),
                  SizedBox(width: 8),
                  Text(
                    'Subcarpetas',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ],
              ),
            ),
            ...subdirs.map((subdir) => Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _buildDirectoryCard(subdir),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildDocumentTile(Map<String, dynamic> doc) {
    final docName = doc['display_name']?.toString() ?? 'Sin nombre';
    final docId = doc['id'] as int?;
    final docType = doc['type']?.toString() ?? 'pdf';
    final isAnalyzing = _analysisStatus[docId] == 'analyzing';
    final progress = _analysisProgress[docId] ?? 0;

    debugPrint('📄 Document: name=$docName, id=$docId, type=$docType');
    debugPrint('   Full doc data: $doc');

    return ListTile(
      dense: true,
      leading: Icon(
        docType == 'summary' ? Icons.description : Icons.picture_as_pdf,
        size: 20,
        color: docType == 'summary' ? Colors.blue : Colors.red,
      ),
      title: Text(docName, style: const TextStyle(fontSize: 14)),
      trailing: isAnalyzing
          ? SizedBox(
              width: 20,
              height: 20,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      value: progress / 100,
                      strokeWidth: 2,
                    ),
                  ),
                  Text(
                    '$progress%',
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            )
          : Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
      onTap: () => _handleDocumentTap(doc, docType),
    );
  }

  void _handleDocumentTap(Map<String, dynamic> doc, String docType) {
    if (docType == 'summary') {
      // View summary (TXT file)
      _viewSummary(doc);
    } else if (docType == 'pdf') {
      // Show options: View PDF or Analyze
      _showPdfOptions(doc);
    }
  }

  void _showPdfOptions(Map<String, dynamic> doc) {
    final docName = doc['display_name']?.toString() ?? 'Sin nombre';
    final docId = doc['id'] as int?;
    final hasSummary = doc['summary_path'] != null;

    if (docId == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              docName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _viewPdf(doc);
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Ver PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  final docId = doc['id'] as int?;
                  final docName = doc['display_name']?.toString() ?? 'Sin nombre';
                  if (docId != null) {
                    _analyzeDocShare(docId, docName);
                  }
                },
                icon: const Icon(Icons.analytics),
                label: const Text('Analizar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            if (hasSummary) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _viewCoursesFromShare(doc);
                  },
                  icon: const Icon(Icons.school),
                  label: const Text('Ver Cursos'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _viewSummary(Map<String, dynamic> doc) {
    final docName = doc['display_name']?.toString() ?? 'Sin nombre';
    final summaryPath = doc['summary_path']?.toString();

    if (summaryPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo encontrar la ruta del resumen'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show summary content in a dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('📝 $docName'),
        content: FutureBuilder<String>(
          future: _loadSummaryContent(summaryPath),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            return SingleChildScrollView(
              child: Text(snapshot.data ?? 'Sin contenido'),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _viewPdf(Map<String, dynamic> doc) {
    final docId = doc['id'] as int?;
    final docName = doc['display_name']?.toString() ?? 'Sin nombre';
    final shareId = widget.share['id'] as int?;

    if (docId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo identificar el documento'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Build PDF URL with auth
    String pdfUrl = '${widget.api.baseUrl}/api/get_document_content.php'
        '?document_id=$docId&type=pdf';
    if (shareId != null) {
      pdfUrl += '&share_id=$shareId';
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(
          pdfUrl: pdfUrl,
          title: docName,
          api: widget.api,
        ),
      ),
    );
  }

  Future<String> _loadSummaryContent(String path) async {
    try {
      // Use the ApiService's get method with a custom endpoint for TXT files
      await widget.api.ensureAuth();
      
      final response = await http.get(
        Uri.parse('${widget.api.baseUrl}/api/get_document_content.php')
            .replace(queryParameters: {'path': path}),
        headers: widget.api.authHeaders,
      );
      
      if (response.statusCode == 200) {
        return response.body;
      } else if (response.statusCode == 401) {
        throw 'No hay sesión activa';
      } else {
        throw 'Error ${response.statusCode}';
      }
    } catch (e) {
      throw 'Error cargando el resumen: $e';
    }
  }

  Widget _buildRoleBadge(String role) {
    IconData icon;
    Color color;
    String label;

    switch (role) {
      case 'owner':
        icon = Icons.star;
        color = const Color(0xFFFFB300);
        label = 'Propietario';
        break;
      case 'editor':
        icon = Icons.edit;
        color = const Color(0xFF43A047);
        label = 'Editor';
        break;
      case 'viewer':
      default:
        icon = Icons.visibility;
        color = const Color(0xFF1E88E5);
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

  // ===== ANALYSIS METHODS =====

  /// Muestra un diálogo para seleccionar tipo de análisis (Rápido o Detallado)
  Future<String?> _showAnalyzeOptions() async {
    return await showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Tipo de Análisis'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flash_on),
              title: const Text('Resumen Rápido'),
              subtitle: const Text('Breve y conciso.'),
              onTap: () => Navigator.pop(ctx, 'summary_fast'),
            ),
            ListTile(
              leading: const Icon(Icons.article),
              title: const Text('Resumen Detallado'),
              subtitle: const Text('Más profundo y completo.'),
              onTap: () => Navigator.pop(ctx, 'summary_detailed'),
            ),
          ],
        ),
      ),
    );
  }

  /// Inicia el análisis de un documento en el share con barra de progreso modal
  Future<void> _analyzeDocShare(int docId, String displayName) async {
    // ===== CRITICAL: ALL CHECKS MUST BE AT START BEFORE ANY ASYNC =====
    // Check global lock first (synchronous check)
    if (_isAnalyzing) {
      print('[ShareDetailScreen] ❌ Bloqueado: _isAnalyzing ya es true');
      return;
    }

    // Check document lock second (synchronous check)
    if (_analyzingDocuments.contains(docId)) {
      print('[ShareDetailScreen] ❌ Bloqueado: docId $docId ya en análisis');
      return;
    }

    // Check debounce third (synchronous check)
    final now = DateTime.now();
    if (_lastAnalysisAttempt != null &&
        now.difference(_lastAnalysisAttempt!).inMilliseconds < 2000) {
      print('[ShareDetailScreen] ❌ Bloqueado: debounce < 2 segundos');
      return;
    }

    // ==== SET LOCKS IMMEDIATELY AND TRIGGER UI REBUILD ====
    _isAnalyzing = true;
    _analyzingDocuments.add(docId);
    _lastAnalysisAttempt = now;
    print('[ShareDetailScreen] ✅ Locks activados para docId: $docId');

    // CRITICAL: Call setState immediately to disable UI before async dialog
    if (mounted) setState(() {});

    String? type;
    try {
      type = await _showAnalyzeOptions();
      if (type == null || !mounted) {
        // Usuario canceló - resetear flags
        _isAnalyzing = false;
        _analyzingDocuments.remove(docId);
        if (mounted) setState(() {});
        return;
      }
    } catch (e) {
      _isAnalyzing = false;
      _analyzingDocuments.remove(docId);
      if (mounted) setState(() {});
      return;
    }

    // At this point type is non-null
    final analysisType = type;

    // Dialogo con barra de progreso acoplado a la superposición de carga
    double progress = 0.0;
    String statusLabel = 'Preparando...';
    bool started = false; // Evita múltiples ejecuciones al reconstruir el diálogo
    bool dialogActive = true; // Evita setState en diálogo ya cerrado

    int? currentJobId; // Para poder cancelar
    bool cancelPressed = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            if (!started) {
              started = true;
              // Iniciar el proceso solo UNA vez
              Future.microtask(() async {
                try {
                  // Para shares, usamos el endpoint generate_summary.php
                  // que requiere document_id
                  final result = await _generateShareSummary(
                    documentId: docId,
                    fileName: displayName,
                    analysisType: analysisType,
                    onProgress: (progress, status) {
                      if (!mounted || !dialogActive) return;
                      try {
                        setStateDialog(() {
                          progress = progress;
                          statusLabel = status;
                        });
                      } catch (_) {
                        // Dialog might have been disposed between tick and UI update
                      }
                    },
                    onJobCreated: (jid) {
                      if (!mounted || !dialogActive) return;
                      try {
                        setStateDialog(() {
                          currentJobId = jid;
                        });
                      } catch (_) {}
                    },
                    cancelRequested: () => cancelPressed,
                  );

                  if (!mounted) return;
                  // Cerrar diálogo inmediatamente
                  dialogActive = false;
                  if (Navigator.of(dialogCtx, rootNavigator: true).canPop()) {
                    Navigator.of(dialogCtx, rootNavigator: true).pop();
                  }

                  // Limpiar estado
                  if (mounted) {
                    setState(() {
                      _isAnalyzing = false;
                      _analyzingDocuments.remove(docId);
                    });
                  }

                  // Pequeña pausa para asegurar que el diálogo se cerró
                  await Future.delayed(const Duration(milliseconds: 100));

                  if (!mounted) return;
                  // Abrir pantalla de resumen
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SummaryScreen(
                        title: displayName,
                        summaryText: result['summary_text'] ?? '',
                        api: widget.api,
                      ),
                    ),
                  );

                  if (mounted) {
                    // Recargar datos del share
                    final shareId = widget.share['id'] as int;
                    final data = await _sharedService.getCloudDirectories(shareId);
                    if (mounted) {
                      setState(() {
                        _shareData = data;
                      });
                    }
                  }
                } catch (e) {
                  if (!mounted) return;

                  // Cerrar diálogo inmediatamente
                  dialogActive = false;
                  if (Navigator.of(dialogCtx, rootNavigator: true).canPop()) {
                    Navigator.of(dialogCtx, rootNavigator: true).pop();
                  }

                  // Limpiar estado
                  if (mounted) {
                    setState(() {
                      _isAnalyzing = false;
                      _analyzingDocuments.remove(docId);
                    });
                  }

                  // Pequeña pausa
                  await Future.delayed(const Duration(milliseconds: 100));

                  if (!mounted) return;

                  // Mostrar error
                  final errStr = e.toString().toLowerCase();
                  if (errStr.contains('cancelado')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Análisis cancelado'),
                        backgroundColor: Colors.grey,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  } else {
                    final rawMsg = _getErrorMessage(e);
                    // Detectar errores de tamaño o falta de archivo y mostrar mensaje amigable
                    String friendlyMsg = rawMsg;
                    Color bgColor = Colors.red;
                    final sizeKeywords = ['demasiado grande', 'upload_max_filesize', 'post_max_size', '413', 'excede'];
                    final missingKeywords = ['no se detectó', 'no se seleccionó', 'missing file', 'se requiere un archivo'];
                    final joined = '$errStr ${rawMsg.toString().toLowerCase()}';
                    if (sizeKeywords.any((k) => joined.contains(k))) {
                      friendlyMsg = 'El archivo excede el límite permitido. Reduce su tamaño (p. ej. <40MB) o intenta con otro archivo.';
                      bgColor = Colors.orange;
                    } else if (missingKeywords.any((k) => joined.contains(k))) {
                      friendlyMsg = 'No se detectó un PDF válido. Asegúrate de seleccionar un archivo .pdf y vuelve a intentarlo.';
                      bgColor = Colors.orange;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(friendlyMsg),
                        backgroundColor: bgColor,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                }
              });
            }
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Analizando "$displayName"',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress < 1.0 ? Colors.blue : Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: currentJobId != null
                          ? () {
                              cancelPressed = true;
                            }
                          : null,
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancelar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Genera resumen para un documento en un share
  Future<Map<String, String>> _generateShareSummary({
    required int documentId,
    required String fileName,
    required String analysisType,
    required void Function(double progress, String status) onProgress,
    required void Function(int jobId) onJobCreated,
    required bool Function() cancelRequested,
  }) async {
    // Iniciar el job
    final startResponse = await _sharedService.generateSummary(documentId);

    if (startResponse['success'] != true) {
      throw Exception(startResponse['error'] ?? 'No se pudo iniciar el análisis');
    }

    final jobId = startResponse['job_id'] as int?;
    if (jobId == null) {
      throw Exception('No se recibió job_id del servidor');
    }

    try {
      onJobCreated(jobId);
    } catch (_) {}

    onProgress(0.1, 'pending');

    final startedAt = DateTime.now();
    DateTime lastActivityAt = startedAt;
    const overallMaxWait = Duration(minutes: 20);
    const idleMaxWait = Duration(minutes: 6);
    String status = 'pending';
    double prog = 0.0;
    double maxProgressSeen = 0.1;
    double lastProg = 0.1;
    String lastStatus = status;
    Map<String, dynamic>? lastJob;

    while (true) {
      if (cancelRequested()) {
        throw Exception('Cancelado por el usuario');
      }

      final now = DateTime.now();
      if (now.difference(startedAt) > overallMaxWait) {
        throw Exception('Tiempo de espera agotado (límite global alcanzado)');
      }
      if (now.difference(lastActivityAt) > idleMaxWait) {
        throw Exception('Tiempo de espera agotado (sin progreso reciente)');
      }

      try {
        final data = await widget.api.getSummaryStatus(jobId);
        final job = data['job'] as Map<String, dynamic>?;
        lastJob = job;
        status = (job?['status'] as String?) ?? 'unknown';
        final perc = (job?['progress'] as num?)?.toDouble() ?? 0.0;
        prog = (perc / 100.0).clamp(0.0, 1.0);

        // Evitar retroceso: solo actualizar si el progreso es mayor
        if (prog > maxProgressSeen) {
          maxProgressSeen = prog;
        }

        // Detectar modo cuota/cola para feedback en UI
        String displayStatus = status;
        final errMsg = (job?['error_message'] as String?)?.toLowerCase() ?? '';
        if (status == 'pending' && errMsg.contains('rate limited')) {
          displayStatus = 'waiting_quota';
        } else if (status == 'pending') {
          final waited = now.difference(startedAt);
          if (waited > const Duration(seconds: 10)) {
            displayStatus = 'queued';
          }
        }

        // Actualizar último progreso/actividad
        if (prog > lastProg + 0.01 || displayStatus != lastStatus) {
          lastProg = prog;
          lastStatus = displayStatus;
          lastActivityAt = now;
        }

        // Mostrar siempre el progreso máximo observado en la UI
        onProgress(maxProgressSeen, _progressStatusText(displayStatus, fileName));

        if (status == 'completed') break;
        if (status == 'canceled') {
          throw Exception('Cancelado por el usuario');
        }
        if (status == 'failed') {
          final err = (job?['error_message'] as String?) ?? 'Fallo en análisis';
          throw Exception(err);
        }
      } catch (e) {
        // Errores transitorios: esperar y reintentar
      }

      await Future.delayed(const Duration(seconds: 2));
    }

    final summaryText = (lastJob?['summary_text'] as String?) ?? '';
    if (summaryText.trim().isEmpty) {
      throw Exception('Resumen vacío devuelto por el servidor');
    }

    onProgress(1.0, 'Completado');

    return {
      'summary_text': summaryText,
      'job_id': jobId.toString(),
    };
  }

  /// Traduce el estado del análisis a un mensaje legible
  String _progressStatusText(String status, String name) {
    switch (status) {
      case 'waiting_quota':
        return 'Esperando cuota de IA...';
      case 'queued':
        return 'En cola, esperando turno...';
      case 'pending':
        return 'Iniciando análisis...';
      case 'processing':
        return 'Procesando "$name"...';
      case 'completed':
        return 'Completado';
      case 'failed':
        return 'Falló el análisis';
      case 'canceled':
        return 'Cancelado por el usuario';
      default:
        return 'Analizando...';
    }
  }

  /// Convierte excepciones en mensajes amigables
  String _getErrorMessage(dynamic e) {
    final errorStr = e.toString().toLowerCase();

    // Errores de conexión
    if (errorStr.contains('socketexception') || errorStr.contains('failed host lookup')) {
      return 'Error de conexión. Verifica tu internet';
    }
    if (errorStr.contains('timeout')) {
      return 'Tiempo de espera agotado. Intenta de nuevo';
    }

    // Errores de archivo
    if (errorStr.contains('archivo no encontrado') || errorStr.contains('file not found')) {
      return 'El archivo PDF no se encontró';
    }
    if (errorStr.contains('no contiene texto') || errorStr.contains('no extractable text')) {
      return 'El PDF no contiene texto extraíble';
    }
    if (errorStr.contains('demasiado grande') || errorStr.contains('too large')) {
      return 'El archivo PDF es demasiado grande (máximo 50MB)';
    }
    if (errorStr.contains('corrupto') || errorStr.contains('corrupt')) {
      return 'El archivo PDF parece estar dañado';
    }

    // Errores de IA
    if (errorStr.contains('no se pudo generar') || errorStr.contains('ia no respondió')) {
      return 'El servicio de IA no respondió. Intenta de nuevo';
    }
    if (errorStr.contains('resumen vacío') || errorStr.contains('empty')) {
      return 'No se pudo generar el resumen. El PDF puede estar vacío';
    }

    // Errores de autenticación
    if (errorStr.contains('invalid token') || errorStr.contains('token expired')) {
      return 'Sesión expirada. Por favor inicia sesión de nuevo';
    }

    // Errores del servidor
    if (errorStr.contains('500') || errorStr.contains('server error')) {
      return 'Error del servidor. Intenta más tarde';
    }

    // Extraer mensaje del error si es una Exception
    if (e is Exception) {
      final msg = e.toString();
      // Remover "Exception: " del inicio si existe
      if (msg.startsWith('Exception: ')) {
        return msg.substring(11);
      }
      return msg;
    }

    return e.toString();
  }

  Color _hexToColor(String hex) {
    final hexCode = hex.replaceAll('#', '');
    return Color(int.parse('FF$hexCode', radix: 16));
  }

  Future<void> _viewCoursesFromShare(Map<String, dynamic> doc) async {
    if (!mounted) return;

    final summaryPath = doc['summary_path']?.toString();
    if (summaryPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo encontrar la ruta del resumen'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _showLoadingDialog('Extrayendo tema y buscando cursos...');

    try {
      // Cargar contenido del resumen
      final summaryText = await _loadSummaryContent(summaryPath);

      // Extraer tema del resumen (buscar el primer título H1 en Markdown)
      String tema = '';
      final lines = summaryText.split('\n');
      for (final line in lines) {
        if (line.trim().startsWith('# ')) {
          tema = line.trim().substring(2).trim();
          // Remover emojis del inicio
          tema = tema.replaceFirst(
            RegExp(r'^[\u{1F300}-\u{1F9FF}]\s*', unicode: true),
            '',
          );
          break;
        }
      }

      if (tema.isEmpty) {
        tema = doc['display_name'] ?? 'Tema general';
      }

      // Obtener cursos desde el backend
      final data = await widget.api.fetchCoursesByTopic(tema);
      final courses = (data['courses'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      Navigator.pop(context); // Cerrar loading dialog

      if (courses.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se encontraron cursos para: $tema')),
          );
        }
        return;
      }

      // Abrir pantalla de cursos
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CoursesScreen(
              tema: tema,
              courses: courses,
              api: widget.api,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al buscar cursos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
