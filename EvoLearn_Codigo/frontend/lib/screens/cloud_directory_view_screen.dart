import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/shared_service.dart';
import '../services/connectivity_service.dart';
import 'quiz_screen.dart';
import 'hybrid_document_viewer_screen.dart';

/// Pantalla para ver el contenido de un directorio compartido (cloud)
/// Muestra la estructura de carpetas y archivos que fueron migrados a la nube
/// con todas las funcionalidades de gestión disponibles para owner y editor
class CloudDirectoryViewScreen extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> share;

  const CloudDirectoryViewScreen({
    super.key,
    required this.api,
    required this.share,
  });

  @override
  State<CloudDirectoryViewScreen> createState() =>
      _CloudDirectoryViewScreenState();
}

class _CloudDirectoryViewScreenState extends State<CloudDirectoryViewScreen> {
  late SharedService _sharedService;
  bool _loading = true;
  String? _error;
  Timer? _syncTimer;
  String? _lastUpdateTimestamp;
  bool _isSyncing = false;
  bool _isCreatingDir = false;
  bool _isAnalyzing = false;
  bool _isUploadingPdf = false;
  bool _lastUpdateWasDetected = false; // Track if we just detected an update

  // Navigation stack for browsing subdirectories
  List<Map<String, dynamic>> _navigationStack = [];
  Map<String, dynamic>? _currentDirectory;
  
  // Track role to determine permissions
  late String _userRole;

  @override
  void initState() {
    super.initState();
    _sharedService = SharedService(widget.api);
    _userRole = widget.share['role']?.toString() ?? 'viewer';
    _loadShareDetails();
    _startSyncPolling();
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

      if (hasUpdates && !_lastUpdateWasDetected) {
        _lastUpdateWasDetected = true;
        // Reload all data
        await _loadShareDetails(silent: true);
        
        // Show notification about updates
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.refresh, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text('Cambios detectados. Actualizando...'),
                ],
              ),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
          
          // Trigger UI update
          if (mounted) {
            setState(() {
              // Force rebuild to show updated data
            });
          }
        }
      } else if (!hasUpdates) {
        _lastUpdateWasDetected = false;
      }
    } catch (e) {
      debugPrint('❌ Polling error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _loadShareDetails({bool silent = false}) async {
    if (!mounted) return;

    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final shareId = widget.share['id'] as int;
      final data = await _sharedService.getCloudDirectories(shareId);

      if (!mounted) return;

      setState(() {
        _loading = false;

        // Get the root directory
        Map<String, dynamic>? rootDirectory;
        if (data['directories'] != null) {
          final directories = data['directories'] as List;
          if (directories.isNotEmpty) {
            rootDirectory = directories.first as Map<String, dynamic>;
          }
        }

        // If refreshing (silent=true), update the current directory if it matches the root
        if (silent && _currentDirectory != null && rootDirectory != null) {
          // Check if we're viewing the root directory
          final currentIsRoot = _currentDirectory!['parent_id'] == null;
          final rootIsRoot = rootDirectory['parent_id'] == null;
          
          if (currentIsRoot && rootIsRoot) {
            // We're viewing the root, update it with fresh data
            _currentDirectory = rootDirectory;
            _navigationStack.clear(); // Reset navigation since we're refreshing
          }
        } else if (_currentDirectory == null && rootDirectory != null) {
          // First load
          _currentDirectory = rootDirectory;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _navigateToSubdirectory(Map<String, dynamic> directory) {
    setState(() {
      if (_currentDirectory != null) {
        _navigationStack.add(_currentDirectory!);
      }
      _currentDirectory = directory;
    });
  }

  void _navigateBack() {
    if (_navigationStack.isNotEmpty) {
      setState(() {
        _currentDirectory = _navigationStack.removeLast();
      });
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _createDirectory() async {
    // Check connectivity first
    final connectivityService = context.read<ConnectivityService>();
    if (connectivityService.isOffline) {
      _showNoInternetModal('crear carpetas');
      return;
    }

    if (_isCreatingDir) return;
    
    final controller = TextEditingController();
    
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva Carpeta'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nombre de la carpeta',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (confirm != true || controller.text.isEmpty || !mounted) return;

    setState(() => _isCreatingDir = true);

    try {
      final dirId = _currentDirectory?['id'] as int?;
      if (dirId == null) throw Exception('Directorio actual no válido');

      final result = await _sharedService.createDirectory(
        directoryId: dirId,
        name: controller.text,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Carpeta "${controller.text}" creada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadShareDetails();
      } else {
        throw Exception(result['error'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingDir = false);
      }
    }
  }

  Future<void> _renameDirectory(Map<String, dynamic> directory) async {
    final currentName = directory['name']?.toString() ?? 'Carpeta';
    final controller = TextEditingController(text: currentName);

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar Carpeta'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nuevo nombre',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final newName = controller.text.isNotEmpty ? controller.text : currentName;
    _showLoadingDialog('Renombrando a "$newName"...');

    try {
      final dirId = directory['id'] as int?;
      if (dirId == null) throw Exception('ID de carpeta no válido');

      final result = await _sharedService.updateDirectory(
        directoryId: dirId,
        name: newName,
      );

      if (!mounted) return;
      Navigator.pop(context); // Cerrar loading dialog

      if (result['success'] == true) {
        _showSuccessDialog('✓ Renombrada a "$newName"');
        // Auto-actualizar después de 1 segundo
        Future.delayed(const Duration(seconds: 1), () async {
          if (mounted) {
            await _loadShareDetails();
          }
        });
      } else {
        throw Exception(result['error'] ?? 'Error al renombrar');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _deleteDirectory(Map<String, dynamic> directory) async {
    final dirName = directory['name']?.toString() ?? 'Carpeta';

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Carpeta'),
        content: Text('¿Estás seguro de que deseas eliminar "$dirName"?\nEsta acción es permanente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    _showLoadingDialog('Eliminando "$dirName"...');

    try {
      final dirId = directory['id'] as int?;
      if (dirId == null) throw Exception('ID de carpeta no válido');

      final result = await _sharedService.deleteDirectory(dirId);

      if (!mounted) return;
      Navigator.pop(context); // Cerrar loading dialog

      if (result['success'] == true) {
        _showSuccessDialog('✓ "$dirName" eliminada correctamente');
        // Auto-actualizar después de 1 segundo
        Future.delayed(const Duration(seconds: 1), () async {
          if (mounted) {
            await _loadShareDetails();
          }
        });
      } else {
        throw Exception(result['error'] ?? 'Error al eliminar');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _openDocument(Map<String, dynamic> document) async {
    final docId = document['id'] as int?;
    final name = document['display_name']?.toString() ?? 'Documento';
    final mimeType = document['mime_type']?.toString() ?? '';

    if (docId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: No se puede abrir el documento'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Get auth token from ApiService
    final token = widget.api.getToken();
    
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: No hay sesión activa'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Construct document URL based on share_id and document_id
    final shareId = widget.share['id'] as int?;
    if (shareId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: No se puede acceder al documento'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final documentUrl = '${widget.api.baseUrl}/api/get_document_content.php?share_id=$shareId&document_id=$docId';

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HybridDocumentViewer(
            documentUrl: documentUrl,
            displayName: name,
            documentId: docId.toString(),
            mimeType: mimeType,
            authToken: token,
            isTextFile: mimeType == 'text/plain' || name.toLowerCase().endsWith('.txt'),
          ),
        ),
      );
    }
  }

  Future<void> _renameDocument(Map<String, dynamic> document) async {
    final currentName = document['display_name']?.toString() ?? 'Archivo';
    final controller = TextEditingController(text: currentName);

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar Documento'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nuevo nombre',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final newName = controller.text.isNotEmpty ? controller.text : currentName;
    _showLoadingDialog('Renombrando a "$newName"...');

    try {
      final docId = document['id'] as int?;
      if (docId == null) throw Exception('ID de documento no válido');

      final result = await _sharedService.updateDocument(
        documentId: docId,
        displayName: newName,
      );

      if (!mounted) return;
      Navigator.pop(context); // Cerrar loading dialog

      if (result['success'] == true) {
        _showSuccessDialog('✓ Renombrado a "$newName"');
        // Auto-actualizar después de 1 segundo
        Future.delayed(const Duration(seconds: 1), () async {
          if (mounted) {
            await _loadShareDetails();
          }
        });
      } else {
        throw Exception(result['error'] ?? 'Error al renombrar');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _moveDocument(Map<String, dynamic> document) async {
    final docName = document['display_name']?.toString() ?? 'Documento';
    final docId = document['id'] as int?;
    
    if (docId == null) return;

    // Show directory selection dialog
    Map<String, dynamic>? selectedDir = _currentDirectory;
    
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mover Documento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('¿Mover "$docName" a otra carpeta?'),
            const SizedBox(height: 16),
            Text(
              'Carpeta destino: ${selectedDir?['name'] ?? 'Raíz'}',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mover'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted || selectedDir == null) return;

    _showLoadingDialog('Moviendo "$docName"...');

    try {
      final targetDirId = selectedDir['id'] as int?;
      if (targetDirId == null) throw Exception('Carpeta destino no válida');

      final result = await _sharedService.moveDocument(
        documentId: docId,
        targetDirectoryId: targetDirId,
      );

      if (!mounted) return;
      Navigator.pop(context); // Cerrar loading dialog

      if (result['success'] == true) {
        _showSuccessDialog('✓ "$docName" movido correctamente');
        // Auto-actualizar después de 1 segundo
        Future.delayed(const Duration(seconds: 1), () async {
          if (mounted) {
            await _loadShareDetails();
          }
        });
      } else {
        throw Exception(result['error'] ?? 'Error al mover');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _moveDirectory(Map<String, dynamic> directory) async {
    final dirName = directory['name']?.toString() ?? 'Carpeta';
    final dirId = directory['id'] as int?;
    
    if (dirId == null) return;

    // Show directory selection dialog (exclude the current directory from targets)
    Map<String, dynamic>? selectedDir = _currentDirectory;
    
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mover Carpeta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('¿Mover "$dirName" a otra carpeta?'),
            const SizedBox(height: 16),
            Text(
              'Carpeta destino: ${selectedDir?['name'] ?? 'Raíz'}',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mover'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted || selectedDir == null) return;

    try {
      final targetParentId = selectedDir['id'] as int?;
      if (targetParentId == null) return;

      final result = await _sharedService.moveDirectory(
        directoryId: dirId,
        targetParentId: targetParentId,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$dirName" movida correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadShareDetails();
      } else {
        throw Exception(result['error'] ?? 'Error al mover');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _generateQuizFromTxt(Map<String, dynamic> document) async {
    final docName = document['display_name']?.toString() ?? 'Documento';
    final fsPath = document['text_content']?.toString() ?? '';
    
    if (fsPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se puede generar quiz: contenido no disponible'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show modal to select number of questions
    int? selectedQuestions = await showDialog<int?>(
      context: context,
      builder: (ctx) => _buildQuizQuestionCountDialog(),
    );

    if (selectedQuestions == null || !mounted) return;

    // Navigate to QuizScreen with selected number of questions
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuizScreen(
          api: widget.api,
          sourceName: docName,
          fsPath: fsPath,
          numQuestions: selectedQuestions,
        ),
      ),
    );
  }

  Widget _buildQuizQuestionCountDialog() {
    int? selectedCount;

    return StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        title: Row(
          children: [
            Icon(Icons.quiz, color: Theme.of(ctx).primaryColor, size: 28),
            const SizedBox(width: 12),
            Text(
              'Generar Quiz',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selecciona la cantidad de preguntas:',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            // Opción 1: 5 preguntas
            _buildQuestionCountOption(
              ctx,
              count: 5,
              label: '5 preguntas',
              subtitle: 'Quiz rápido',
              selectedCount: selectedCount,
              onSelect: (count) {
                setState(() => selectedCount = count);
              },
            ),
            const SizedBox(height: 12),
            // Opción 2: 8 preguntas
            _buildQuestionCountOption(
              ctx,
              count: 8,
              label: '8 preguntas',
              subtitle: 'Quiz estándar',
              selectedCount: selectedCount,
              onSelect: (count) {
                setState(() => selectedCount = count);
              },
            ),
            const SizedBox(height: 12),
            // Opción 3: 12 preguntas
            _buildQuestionCountOption(
              ctx,
              count: 12,
              label: '12 preguntas',
              subtitle: 'Quiz completo',
              selectedCount: selectedCount,
              onSelect: (count) {
                setState(() => selectedCount = count);
              },
            ),
            const SizedBox(height: 12),
            // Opción 4: 15 preguntas
            _buildQuestionCountOption(
              ctx,
              count: 15,
              label: '15 preguntas',
              subtitle: 'Quiz exhaustivo',
              selectedCount: selectedCount,
              onSelect: (count) {
                setState(() => selectedCount = count);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancelar',
              style: TextStyle(color: Theme.of(ctx).primaryColor),
            ),
          ),
          ElevatedButton(
            onPressed: selectedCount == null
                ? null
                : () => Navigator.pop(ctx, selectedCount),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).primaryColor,
              disabledBackgroundColor: Colors.grey[300],
            ),
            child: const Text(
              'Continuar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCountOption(
    BuildContext ctx, {
    required int count,
    required String label,
    required String subtitle,
    required int? selectedCount,
    required Function(int) onSelect,
  }) {
    final isSelected = selectedCount == count;
    final primaryColor = Theme.of(ctx).primaryColor;
    final isDark = Theme.of(ctx).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? primaryColor : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
          width: isSelected ? 2 : 1,
        ),
        color: isSelected
            ? primaryColor.withOpacity(0.1)
            : (isDark ? Colors.grey[900] : Colors.white),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(count),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? primaryColor : (isDark ? Colors.grey[600]! : Colors.grey[400]!),
                      width: 2,
                    ),
                    color: isSelected ? primaryColor : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isSelected ? primaryColor : null,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteDocument(Map<String, dynamic> document) async {
    final docName = document['display_name']?.toString() ?? 'Documento';

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Documento'),
        content: Text('¿Estás seguro de que deseas eliminar "$docName"?\nEsta acción es permanente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    _showLoadingDialog('Eliminando "$docName"...');

    try {
      final docId = document['id'] as int?;
      if (docId == null) throw Exception('ID de documento no válido');

      final result = await _sharedService.deleteDocument(docId);

      if (!mounted) return;
      Navigator.pop(context); // Cerrar loading dialog

      if (result['success'] == true) {
        _showSuccessDialog('✓ "$docName" eliminado correctamente');
        // Auto-actualizar después de 1 segundo
        Future.delayed(const Duration(seconds: 1), () async {
          if (mounted) {
            await _loadShareDetails();
          }
        });
      } else {
        throw Exception(result['error'] ?? 'Error al eliminar');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _analyzeDocument(Map<String, dynamic> document) async {
    if (_isAnalyzing) return;

    final name = document['display_name']?.toString() ?? 'PDF';
    final docId = document['id'] as int?;

    if (docId == null) return;

    setState(() => _isAnalyzing = true);

    try {
      _showLoadingDialog('📊 Analizando: $name\nGenerando resumen...');

      final result = await _sharedService.generateSummary(docId);

      if (!mounted) return;
      Navigator.pop(context); // Cerrar loading dialog

      if (result['success'] == true) {
        _showSuccessDialog('✓ "$name" analizado correctamente\nResumen generado');
        // Auto-actualizar después de 1.5 segundos
        Future.delayed(const Duration(milliseconds: 1500), () async {
          if (mounted) {
            await _loadShareDetails();
          }
        });
      } else {
        throw Exception(result['error'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
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

  void _showSuccessDialog(String message, {Duration duration = const Duration(milliseconds: 1500)}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
    
    Future.delayed(duration, () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shareName = widget.share['name']?.toString() ?? 'Sin nombre';
    final ownerName = widget.share['owner_name']?.toString();

    return WillPopScope(
      onWillPop: () async {
        if (_navigationStack.isNotEmpty) {
          _navigateBack();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateBack,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentDirectory?['name']?.toString() ?? shareName,
                style: const TextStyle(fontSize: 18),
              ),
              if (ownerName != null)
                Text(
                  'Compartido por: $ownerName',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.normal),
                ),
            ],
          ),
          actions: [
            _buildRoleBadge(_userRole),
            const SizedBox(width: 8),
            if (_isSyncing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
          ],
        ),
        floatingActionButton: (_userRole == 'owner' || _userRole == 'editor')
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    onPressed: _isUploadingPdf ? null : _uploadPdfToCloud,
                    tooltip: 'Subir PDF',
                    heroTag: 'upload_pdf',
                    child: const Icon(Icons.upload_file),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton(
                    onPressed: _isCreatingDir ? null : _createDirectory,
                    tooltip: 'Nueva Carpeta',
                    heroTag: 'create_dir',
                    child: const Icon(Icons.create_new_folder_outlined),
                  ),
                ],
              )
            : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildErrorView()
                : _buildDirectoryContent(),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
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
    );
  }

  Widget _buildDirectoryContent() {
    if (_currentDirectory == null) {
      return const Center(
        child: Text('No hay contenido para mostrar'),
      );
    }

    final subdirectories = _currentDirectory!['subdirectories'] as List? ?? [];
    final documents = _currentDirectory!['documents'] as List? ?? [];

    if (subdirectories.isEmpty && documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Esta carpeta está vacía',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...subdirectories.map((subdir) => _buildDirectoryCard(subdir)),
        ...documents.map((doc) => _buildDocumentCard(doc)),
      ],
    );
  }

  Widget _buildDirectoryCard(Map<String, dynamic> directory) {
    final name = directory['name']?.toString() ?? 'Sin nombre';
    final colorHex = directory['color_hex']?.toString() ?? '#1565C0';
    final subdirCount = (directory['subdirectories'] as List?)?.length ?? 0;
    final docCount = (directory['documents'] as List?)?.length ?? 0;
    final canEdit = _userRole == 'owner' || _userRole == 'editor';
    final isRootDir = directory['parent_id'] == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToSubdirectory(directory),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _hexToColor(colorHex).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.folder,
                  color: _hexToColor(colorHex),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$subdirCount carpetas, $docCount archivos',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              if (canEdit && !isRootDir)
                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    switch (value) {
                      case 'rename':
                        await _renameDirectory(directory);
                        break;
                      case 'move':
                        await _moveDirectory(directory);
                        break;
                      case 'delete':
                        await _deleteDirectory(directory);
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit, color: Color(0xFF1976D2)),
                          SizedBox(width: 8),
                          Text('Renombrar'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'move',
                      child: Row(
                        children: [
                          Icon(Icons.drive_file_move, color: Color(0xFF1976D2)),
                          SizedBox(width: 8),
                          Text('Mover'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Eliminar', style: TextStyle(color: Colors.red)),
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

  Widget _buildDocumentCard(Map<String, dynamic> document) {
    final name = document['display_name']?.toString() ?? 'Sin nombre';
    final mimeType = document['mime_type']?.toString() ?? '';
    final size = document['size_bytes'] as int? ?? 0;
    final sizeStr = _formatFileSize(size);
    
    // Detectar tipo de archivo por extension o mime_type
    final isTextFile = name.toLowerCase().endsWith('.txt') || 
                       mimeType.toLowerCase() == 'text/plain';
    final canEdit = _userRole == 'owner' || _userRole == 'editor';

    final iconData = isTextFile ? Icons.description_outlined : Icons.picture_as_pdf_outlined;
    final iconColor = isTextFile ? Colors.blue[700] : Colors.red[700];
    final bgColor = isTextFile ? Colors.blue.shade50 : Colors.red.shade50;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDocument(document),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  iconData,
                  color: iconColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sizeStr,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) async {
                  switch (value) {
                    case 'view':
                      _openDocument(document);
                      break;
                    case 'quiz':
                      if (isTextFile) {
                        await _generateQuizFromTxt(document);
                      }
                      break;
                    case 'rename':
                      if (canEdit) await _renameDocument(document);
                      break;
                    case 'move':
                      if (canEdit) await _moveDocument(document);
                      break;
                    case 'delete':
                      if (canEdit) await _deleteDocument(document);
                      break;
                    case 'analyze':
                      if (canEdit && !isTextFile) {
                        await _analyzeDocument(document);
                      }
                      break;
                  }
                },
                itemBuilder: (ctx) {
                  if (isTextFile) {
                    // Summary document menu
                    return [
                      const PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(Icons.visibility, color: Color(0xFF1976D2)),
                            SizedBox(width: 8),
                            Text('Ver'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'quiz',
                        child: Row(
                          children: [
                            Icon(Icons.quiz, color: Color(0xFF1976D2)),
                            SizedBox(width: 8),
                            Text('Generar Quiz'),
                          ],
                        ),
                      ),
                      if (canEdit) ...[
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: Color(0xFF1976D2)),
                              SizedBox(width: 8),
                              Text('Renombrar'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Eliminar', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ];
                  } else {
                    // PDF document menu
                    return [
                      const PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(Icons.visibility, color: Color(0xFF1976D2)),
                            SizedBox(width: 8),
                            Text('Ver'),
                          ],
                        ),
                      ),
                      if (canEdit) ...[
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'analyze',
                          child: Row(
                            children: [
                              Icon(Icons.analytics, color: Color(0xFF1976D2)),
                              SizedBox(width: 8),
                              Text('Analizar'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: Color(0xFF1976D2)),
                              SizedBox(width: 8),
                              Text('Renombrar'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'move',
                          child: Row(
                            children: [
                              Icon(Icons.drive_file_move, color: Color(0xFF1976D2)),
                              SizedBox(width: 8),
                              Text('Mover'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Eliminar', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ];
                  }
                },
              ),
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
        color = Colors.amber;
        label = 'Propietario';
        break;
      case 'editor':
        icon = Icons.edit;
        color = Colors.green;
        label = 'Editor';
        break;
      case 'viewer':
      default:
        icon = Icons.visibility;
        color = Colors.blue;
        label = 'Visor';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _uploadPdfToCloud() async {
    // Check connectivity first
    final connectivityService = context.read<ConnectivityService>();
    if (connectivityService.isOffline) {
      _showNoInternetModal('subir archivos PDF');
      return;
    }

    if (_isUploadingPdf) return;
    if (_currentDirectory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un directorio primero'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isUploadingPdf = true);

    try {
      // Usar FilePicker para seleccionar PDF del dispositivo
      final pickerResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (pickerResult == null || pickerResult.files.isEmpty) {
        return; // Usuario canceló
      }

      final pickedFile = pickerResult.files.first;
      if (pickedFile.path == null || pickedFile.path!.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo leer el archivo - ruta inválida'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (!mounted) return;
      final selectedFile = File(pickedFile.path!);

      // Verificar que el archivo existe
      if (!await selectedFile.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El archivo no existe'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final fileName = selectedFile.path.split('/').last;
      final fileBytes = await selectedFile.readAsBytes();
      final dirId = _currentDirectory!['id'] as int?;
      if (dirId == null) throw Exception('ID de directorio inválido');

      // Subir PDF a la base de datos
      final uploadResult = await _sharedService.uploadPdfToDirectory(
        directoryId: dirId,
        fileName: fileName,
        fileBytes: fileBytes,
      );

      if (!mounted) return;

      if (uploadResult['success'] == true || uploadResult['document_id'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF "$fileName" subido correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadShareDetails();
      } else {
        throw Exception(uploadResult['error'] ?? 'Error al subir PDF');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPdf = false);
      }
    }
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
            const Text('Sin conexión'),
          ],
        ),
        content: Text(
          'Para $actionName necesitas estar conectado a internet.\n\nPor favor, conectate a una red Wi-Fi o datos móviles.',
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