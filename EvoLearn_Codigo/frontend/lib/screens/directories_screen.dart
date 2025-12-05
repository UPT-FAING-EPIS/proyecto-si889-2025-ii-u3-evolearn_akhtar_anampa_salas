import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:math';

// Service Imports
import '../services/api_service.dart';
import '../services/analysis_service.dart';
import '../services/local_storage_service.dart';
import '../providers/theme_provider.dart';
import '../providers/share_refresh_notifier.dart';

// Screen Imports
import 'profile_screen.dart';
import 'login_screen.dart';
import 'summary_screen.dart';
import 'quiz_screen.dart';
import '../widgets/share_folder_dialog.dart';
import 'pdf_viewer_screen.dart';
import 'courses_screen.dart';

class DirectoriesScreen extends StatefulWidget {
  final ApiService api;
  const DirectoriesScreen({super.key, required this.api});

  @override
  State<DirectoriesScreen> createState() => _DirectoriesScreenState();
}

class _DirectoriesScreenState extends State<DirectoriesScreen> {
  // State Variables
  int? _currentDirId; // null = root in VIP mode
  List<dynamic> _dirTree = []; // VIP directory structure
  List<Map<String, dynamic>> _flatDirs = []; // Flattened VIP directories
  List<dynamic> _docs = []; // Raw documents list from API
  bool _loading = true;
  String? _error;
  String _mode = 'vip'; // Current mode ('vip' or 'fs')
  Map<String, dynamic>? _fsRoot; // FS directory structure root
  String? _currentPath; // null or '' = root in FS mode
  int _tabIndex = 0;
  bool _isAnalyzing = false; // Prevenir análisis múltiples simultáneos
  final Set<String> _analyzingPaths = {}; // Paths actualmente en análisis
  DateTime? _lastAnalysisAttempt; // Timestamp del último intento de análisis

  late AnalysisService _analysisService; // Instance of the analysis service

  @override
  void initState() {
    super.initState();
    _analysisService = AnalysisService(widget.api); // Initialize AnalysisService
    // Restore last location before fetching data
    _restoreLocation().then((_) => _refresh());
  }

  /// Restores the last viewed directory location from SharedPreferences.
  Future<void> _restoreLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('mode');
    final savedDirId = prefs.getInt('current_dir_id');
    final savedPath = prefs.getString('current_path');
    if (mounted) {
      // Check if the widget is still mounted
      setState(() {
        if (savedMode != null) _mode = savedMode;
        // Use -1 as the saved value for root (null)
        _currentDirId = (savedDirId != null && savedDirId >= 0) ? savedDirId : null;
        _currentPath = savedPath ?? _currentPath; // Keep current if nothing saved
      });
    }
  }

  /// Saves the current directory location to SharedPreferences.
  Future<void> _saveLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_screen', 'directories'); // Mark last screen
    await prefs.setString('mode', _mode);
    await prefs.setInt('current_dir_id', _currentDirId ?? -1); // Save -1 for root (null)
    await prefs.setString('current_path', _currentPath ?? '');
  }

  /// Refreshes the directory and document lists from the API.
  Future<void> _refresh() async {
    if (!mounted) return; // Don't refresh if widget is disposed
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dirsResp = await widget.api.listDirectories();
      if (!mounted) return;
      final currentMode = dirsResp['mode']?.toString() ?? 'vip';

      // Reset location if mode changed unexpectedly (e.g., user downgraded)
      if (_mode != currentMode) {
        _currentDirId = null;
        _currentPath = '';
        _mode = currentMode;
      }

      Map<String, dynamic> docsResp;
      if (_mode == 'vip') {
        _dirTree = (dirsResp['directories'] as List<dynamic>? ?? []);
        _flatDirs = _flatten(_dirTree);
        docsResp = await widget.api.listDocuments(directoryId: _currentDirId);
        // Unificar documentos PDF y resúmenes (si el backend devuelve 'summaries')
        final documents = (docsResp['documents'] as List<dynamic>? ?? []);
        final summaries = (docsResp['summaries'] as List<dynamic>? ?? []);
        _docs = [
          ...documents,
          ...summaries.map((s) => {
                'id': s['id'] ?? s['summary_id'],
                'display_name': s['display_name'] ?? s['name'] ?? 'Resumen',
                'created_at': s['created_at'] ?? '',
                'type': 'summary',
                'original_doc_id': s['original_doc_id'],
                'path': s['path'], // si el backend lo proporciona
              }),
        ];
      } else {
        // FS Mode
        _fsRoot = dirsResp['fs_tree'] as Map<String, dynamic>?;
        _currentPath ??= ''; // raíz
        final effectivePath = (_currentPath?.isEmpty ?? true) ? null : _currentPath;
        docsResp = await widget.api.listDocuments(path: effectivePath);
        _docs = (docsResp['fs_documents'] as List<dynamic>? ?? []);
      }
    } catch (e) {
      if (mounted) {
        // Handle token errors
        if (await _handleTokenError(e)) {
          return;
        }
        setState(() {
          _error = "Error: ${e.toString()}";
        }); // Provide clearer error
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _saveLocation(); // Save location after successful or failed refresh
      }
    }
  }

  /// Flattens the hierarchical directory tree (VIP mode).
  List<Map<String, dynamic>> _flatten(List<dynamic> dirs) {
    final out = <Map<String, dynamic>>[];
    for (final d in dirs) {
      if (d is Map<String, dynamic>) {
        // Type check
        out.add({
          'id': d['id'],
          'parent_id': d['parent_id'],
          'name': d['name'],
          'color_hex': d['color_hex']
        });
        if (d['children'] is List) {
          out.addAll(_flatten(d['children'] as List<dynamic>));
        }
      }
    }
    return out;
  }

  /// Finds a directory by ID in the flattened list (VIP mode).
  Map<String, dynamic>? _dirById(int? id) {
    if (id == null) return null;
    // Use try-firstWhere for safety
    try {
      return _flatDirs.firstWhere((d) => d['id'] == id);
    } catch (e) {
      return null; // Return null if not found
    }
  }

  /// Finds a node in the FS tree by its path (FS mode).
  Map<String, dynamic>? _fsFindNodeByPath(Map<String, dynamic>? node, String path) {
    if (node == null) return null;
    if ((node['path'] as String? ?? '') == path) return node;
    final children = node['directories'] as List<dynamic>? ?? [];
    for (final child in children) {
      if (child is Map<String, dynamic>) {
        final found = _fsFindNodeByPath(child, path);
        if (found != null) return found;
      }
    }
    return null;
  }

  // Removed unused helper _collectChildren; direct child retrieval uses _childrenNormalized.


  /// Builds the breadcrumb path for FS mode.
  List<Map<String, dynamic>> _breadcrumbFs() {
    final crumbs = <Map<String, dynamic>>[];
    final curPath = _currentPath ?? '';
    if (curPath.isEmpty) return crumbs;

    final parts = curPath.split('/').where((p) => p.isNotEmpty).toList();
    String accumulatedPath = '';
    for (final part in parts) {
      accumulatedPath = accumulatedPath.isEmpty ? part : '$accumulatedPath/$part';
      final node = _fsFindNodeByPath(_fsRoot, accumulatedPath);
      crumbs.add({
        'name': node?['name'] ?? part,
        'path': accumulatedPath,
        'color_hex': (node?['color'] as String?) ?? '#1565C0',
      });
    }
    return crumbs;
  }

  /// Returns a normalized list of child directories for the current view.
  List<Map<String, dynamic>> _childrenNormalized() {
    if (_mode == 'vip') {
      final children = <dynamic>[];
      // Directly collect children based on parent_id from the flat list
      for (final dir in _flatDirs) {
        if (dir['parent_id'] == _currentDirId) {
          children.add(dir);
        }
      }
      // Sort children alphabetically by name
      children.sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));

      return children
          .map((d) => {
                'kind': 'vip',
                'id': d['id'],
                'name': d['name'] ?? 'Unnamed',
                'color_hex': d['color_hex'] ?? '#1565C0',
              })
          .toList();
    } else {
      // FS Mode
      final node = _fsFindNodeByPath(_fsRoot, _currentPath ?? '');
      final fsChildren = (node?['directories'] as List<dynamic>? ?? []);
      // Sort children alphabetically by name
      fsChildren.sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));

      return fsChildren
          .whereType<Map<String, dynamic>>()
          .map((d) => {
                'kind': 'fs',
                'path': d['path'] ?? '',
                'name': d['name'] ?? 'Unnamed',
                'color_hex': (d['color'] as String?) ?? '#1565C0',
              })
          .toList();
    }
  }

  /// Returns a normalized list of documents for the current view.
  List<Map<String, dynamic>> _docsNormalized() {
    // Assuming _docs is already populated correctly by _refresh for the current mode
    return _docs.whereType<Map<String, dynamic>>().map((d) {
      if (_mode == 'vip') {
        return {
          'kind': 'vip',
          'id': d['id'], // Assume 'id' exists for VIP docs
          'display_name': d['display_name'] ?? 'Documento',
          'created_at': d['created_at'] ?? '',
          'type': d['type'] ?? 'pdf', // Include type
          'original_doc_id': d['original_doc_id'], // Include for summaries
          'path': d['path'], // algunos backends pueden adjuntar path para resumen
        };
      } else {
        // FS mode
        final name = d['name'] as String? ?? '';
        final inferredType = name.toLowerCase().endsWith('.txt') ? 'summary' : 'pdf';
        return {
          'kind': 'fs',
          'path': d['path'] ?? '',
          'display_name': d['name'] ?? 'Archivo',
          'size': d['size'] ?? 0,
          'type': d['type'] ?? inferredType,
          'modified': d['modified'],
          'created': d['created'],
        };
      }
    }).toList();
  }
  // --- UI Building Methods ---

  /// Builds the breadcrumb bar widget.
  Widget _breadcrumbBar() {
    final crumbs = _breadcrumbFs();
    final total = crumbs.length;

    List<Widget> buildCrumbWidgets(List<Map<String, dynamic>> items) {
      final widgets = <Widget>[];
      for (int i = 0; i < items.length; i++) {
        widgets.add(const Text('/'));
        widgets.add(
          InkWell(
            onTap: () {
              setState(() {
                if (_mode == 'vip') {
                  _currentDirId = items[i]['id'] as int?;
                } else {
                  _currentPath = items[i]['path'] as String?;
                }
              });
              _saveLocation();
              _refresh();
            },
            child: Chip(label: Text(items[i]['name'] as String? ?? '...')),
          ),
        );
      }
      return widgets;
    }

    Future<void> openCrumbsPicker() async {
      await showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: ListView.builder(
              itemCount: crumbs.length,
              itemBuilder: (ctx, i) {
                final name = crumbs[i]['name'] as String? ?? '...';
                return ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text(name),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      if (_mode == 'vip') {
                        _currentDirId = crumbs[i]['id'] as int?;
                      } else {
                        _currentPath = crumbs[i]['path'] as String?;
                      }
                    });
                    _saveLocation();
                    _refresh();
                  },
                );
              },
            ),
          );
        },
      );
    }

    // Build condensed list: show Root, then if many, an ellipsis chip, then last two
    final rowChildren = <Widget>[
      InkWell(
        onTap: () {
          setState(() {
            _currentDirId = null;
            _currentPath = '';
          });
          _saveLocation();
          _refresh();
        },
        child: const Chip(label: Text('Raíz')),
      ),
    ];

    if (total <= 3) {
      rowChildren.addAll(buildCrumbWidgets(crumbs));
    } else {
      // Show interactive ellipsis that opens a picker for middle levels
      final visible = [crumbs[total - 2], crumbs[total - 1]];
      rowChildren.add(const Text('/'));
      rowChildren.add(
        InkWell(
          onTap: openCrumbsPicker,
          child: const Chip(label: Text('…')),
        ),
      );
      rowChildren.addAll(buildCrumbWidgets(visible));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: rowChildren,
      ),
    );
  }

  // --- Dialogs and Actions ---

  /// Shows a dialog to pick a color from a predefined grid.
  Future<String?> _pickColorHex(BuildContext context, {String initialHex = '#1565C0'}) async {
    final colors = [
      '#1565C0', '#2E7D32', '#C62828', '#6A1B9A', '#FF8F00',
      '#0097A7', '#8E24AA', '#5D4037', '#00796B', '#F4511E',
      '#3949AB', '#D81B60', '#00ACC1', '#1B5E20', '#BF360C',
    ];
    String selected = initialHex;
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Elegir color'),
            content: StatefulBuilder(
              // Use StatefulBuilder for dialog UI updates
              builder: (BuildContext context, StateSetter setStateDialog) {
                return SizedBox(
                  width: 320, // Adjust width as needed
                  height: 150, // Adjust height as needed
                  child: GridView.builder(
                    // Use GridView.builder
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: colors.length,
                    itemBuilder: (context, index) {
                      final hex = colors[index];
                      final bool isSelected = hex == selected;
                      return GestureDetector(
                        onTap: () {
                          setStateDialog(() {
                            // Update the dialog state
                            selected = hex;
                          });
                          // Optionally close dialog immediately on selection:
                          // Navigator.pop(ctx, true);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _hexToColor(hex), // Use helper
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).primaryColorDark
                                  : Colors.grey.shade300,
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                          child: isSelected // Add checkmark
                              ? Icon(Icons.check, color: Theme.of(context).canvasColor, size: 20)
                              : null,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              // Added a separate Save button
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
            ],
          );
        }) ??
        false;
    return ok ? selected : null;
  }

  /// Shows the dialog to create a new directory.
  Future<void> _createDir() async {
    final nameCtrl = TextEditingController();
    String selectedColor = '#1565C0'; // Default color
    final List<String> colorOptions = [
      '#1565C0', '#2E7D32', '#C62828', '#6A1B9A', '#FF8F00',
      '#0097A7', '#8E24AA', '#5D4037', '#00796B', '#F4511E',
      '#3949AB', '#D81B60', '#00ACC1', '#1B5E20', '#BF360C',
    ];

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          // Use StatefulBuilder for color picker UI update
          builder: (BuildContext context, StateSetter setStateDialog) {
            return AlertDialog(
              title: const Text('Nueva carpeta'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  autofocus: true,
                ),
                const SizedBox(height: 15),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Color:', style: TextStyle(fontSize: 16))),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.maxFinite,
                  height: 150,
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: colorOptions.length,
                    itemBuilder: (context, index) {
                      final hex = colorOptions[index];
                      final bool isSelected = hex == selectedColor;
                      return GestureDetector(
                        onTap: () {
                          setStateDialog(() {
                            selectedColor = hex;
                          }); // Update dialog state
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _hexToColor(hex),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).primaryColorDark
                                  : Colors.grey.shade300,
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                          child: isSelected
                              ? Icon(Icons.check, color: Theme.of(context).canvasColor, size: 20)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
              ],
            );
          },
        );
      },
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      _showLoadingDialog("Creando carpeta...");
      try {
        if (_mode == 'vip') {
          await widget.api.createDirectory(nameCtrl.text.trim(),
              parentId: _currentDirId, colorHex: selectedColor);
        } else {
          await widget.api.createDirectory(nameCtrl.text.trim(),
              parentPath: _currentPath ?? '', colorHex: selectedColor);
        }
        if (mounted) Navigator.pop(context);
        await _refresh();
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al crear: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Shows a dialog to pick a target directory (VIP mode).
  Future<int?> _chooseTargetDir({Set<int> exclude = const {}}) async {
    if (_mode == 'fs') return null;

    int? targetId = _currentDirId;
    final options = _flatDirs.where((d) => !exclude.contains(d['id'] as int)).toList();
    // Sort options for better display (optional)
    options.sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));

    return await showDialog<int?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Mover a Carpeta'),
            content: DropdownButtonFormField<int?>(
              initialValue: targetId,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('► Raíz')),
                ...options.map((d) => DropdownMenuItem<int>(
                      value: d['id'] as int,
                      child: Text('    ${d['name'] as String? ?? 'Unnamed'}'), // Indentation
                    ))
              ],
              onChanged: (v) {
                setStateDialog(() {
                  targetId = v;
                });
              },
              decoration: const InputDecoration(labelText: 'Carpeta Destino'),
              isExpanded: true,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, targetId),
                  child: const Text('Mover Aquí')),
            ],
          );
        });
      },
    );
  }

  /// Shows a dialog to pick a target directory path (FS mode).
  Future<String?> _chooseTargetFsDirPath({Set<String> exclude = const {}}) async {
    final List<Map<String, String>> flatStructure = [];
    void walk(Map<String, dynamic>? node, int level) {
      if (node == null) return;
      final path = node['path'] as String? ?? '';
      final name = node['name'] as String? ?? 'Unnamed';
      if (!exclude.contains(path)) {
        String indent = '  ' * level;
        flatStructure.add({
          'path': path,
          'displayName': path.isEmpty ? '► Raíz' : '$indent└─ $name',
        });
      }
      final children = node['directories'] as List<dynamic>? ?? [];
      children.sort((a, b) => (a['name'] as String? ?? '').compareTo(
          b['name'] as String? ?? '')); // Sort children
      for (final child in children) {
        if (child is Map<String, dynamic>) {
          walk(child, level + 1);
        }
      }
    }

    walk(_fsRoot, 0); // Start from root

    String? targetPath = _currentPath ?? '';

    return await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Mover a Carpeta'),
            content: DropdownButtonFormField<String?>(
              initialValue: targetPath,
              items: flatStructure
                  .map((d) => DropdownMenuItem<String?>(
                        value: d['path'],
                        child: Text(d['displayName']!),
                      ))
                  .toList(),
              onChanged: (v) {
                setStateDialog(() {
                  targetPath = v;
                });
              },
              decoration: const InputDecoration(labelText: 'Carpeta Destino'),
              isExpanded: true,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, targetPath),
                  child: const Text('Mover Aquí')),
            ],
          );
        });
      },
    );
  }

  /// Renames a directory (VIP mode).
  Future<void> _renameDir(int id, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar carpeta'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nuevo nombre'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (ok == true && ctrl.text.trim().isNotEmpty && ctrl.text.trim() != currentName) {
      _showLoadingDialog('Renombrando...');
      try {
        await widget.api.updateDirectory(id: id, name: ctrl.text.trim());
        if (mounted) Navigator.pop(context);
        await _refresh();
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al renombrar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Opens the share folder dialog for a filesystem folder
  Future<void> _shareFolderFs(String path, String folderName) async {
    // Get user_id from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'default_user';
    
    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ShareFolderDialog(
        api: widget.api,
        fsPath: path,
        folderName: folderName,
        userId: userId,
      ),
    );

    bool shouldRefresh = false;
    if (result is Map) {
      final successCount = (result['successCount'] ?? 0) as int;
      final failCount = (result['failCount'] ?? 0) as int;
      final errors = (result['errors'] as List?)?.cast<String>() ?? const <String>[];

      // Delete local folder after successful share
      if (successCount > 0) {
        try {
          final deleted = await LocalStorageService.deleteFolderTree(userId, path);
          if (deleted) {
            debugPrint('✅ Local folder deleted: $path');
          } else {
            debugPrint('⚠️ Failed to delete local folder: $path');
          }
        } catch (e) {
          debugPrint('❌ Error deleting local folder: $e');
        }
      }

      if (successCount > 0 && failCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$successCount ${successCount == 1 ? "usuario agregado" : "usuarios agregados"} exitosamente.\nLa carpeta ahora está en la nube y fue eliminada del almacenamiento local.'
            ),
            backgroundColor: Colors.green,
          ),
        );
        shouldRefresh = true;
        // Notify SharedScreen to refresh the shared folders list
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.read<ShareRefreshNotifier>().notifyShareCreated(0);
          }
        });
      } else if (successCount > 0 && failCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$successCount ${successCount == 1 ? "usuario agregado" : "usuarios agregados"} correctamente.\n$failCount ${failCount == 1 ? "falló" : "fallaron"}.${errors.isNotEmpty ? '\n' + errors.join(', ') : ''}'
            ),
            backgroundColor: Colors.orange,
          ),
        );
        shouldRefresh = true;
        // Notify SharedScreen to refresh the shared folders list
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.read<ShareRefreshNotifier>().notifyShareCreated(0);
          }
        });
      } else if (errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${errors.join(', ')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else if (result == true) {
      shouldRefresh = true;
    }

    if (shouldRefresh) {
      await _refresh();
    }
  }

  /// Renames a directory (FS mode).
  Future<void> _renameDirFs(String path, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar carpeta'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nuevo nombre'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (ok == true && ctrl.text.trim().isNotEmpty && ctrl.text.trim() != currentName) {
      _showLoadingDialog('Renombrando...');
      try {
        await widget.api.updateDirectory(path: path, name: ctrl.text.trim());
        if (mounted) Navigator.pop(context);
        await _refresh();
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al renombrar: $e'), backgroundColor: Colors.red));
      }
    }
  }



  /// Changes the color of a directory (FS mode).
  Future<void> _changeColorFs(String path) async {
    final Map<String, dynamic>? currentDir = _fsFindNodeByPath(_fsRoot, path);
    final String initialColor = (currentDir?['color'] as String?) ?? '#1565C0';

    final picked = await _pickColorHex(context, initialHex: initialColor);
    if (picked != null && picked != initialColor) {
      _showLoadingDialog('Cambiando color...');
      try {
        await widget.api.updateDirectory(path: path, colorHex: picked);
        if (mounted) Navigator.pop(context);
        await _refresh();
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al cambiar color: $e'), backgroundColor: Colors.red));
      }
    }
  }



  /// Moves a directory (FS mode).
  Future<void> _moveDirFs(String path) async {
    final node = _fsFindNodeByPath(_fsRoot, path);
    if (node == null) return;

    final excludePaths = <String>{path};
    // Implementation for collectDescendantPaths
    void collectDescendantPaths(Map<String, dynamic>? n) {
      if (n == null) return;
      final children = n['directories'] as List<dynamic>? ?? [];
      for (final child in children) {
        if (child is Map<String, dynamic>) {
          final childPath = child['path'] as String?;
          if (childPath != null) {
            excludePaths.add(childPath);
            collectDescendantPaths(child); // Recurse
          }
        }
      }
    }
    collectDescendantPaths(node);

    final targetPath = await _chooseTargetFsDirPath(exclude: excludePaths);

    List<String> parts = path.split('/');
    parts.removeLast();
    String currentParentPath = parts.join('/');

    // Normalizar: null o string vacío significa raíz
    final normalizedTargetPath = targetPath == null || targetPath.isEmpty ? '' : targetPath;
    
    if (normalizedTargetPath != currentParentPath) {
      _showLoadingDialog('Moviendo carpeta...');
      try {
        await widget.api.moveDirectory(path: path, newParentPath: normalizedTargetPath.isEmpty ? '' : normalizedTargetPath);
        if (mounted) Navigator.pop(context);
        if (path == _currentPath) {
          final nodeName = path.split('/').last;
          setState(() {
            _currentPath = normalizedTargetPath.isEmpty ? nodeName : '$normalizedTargetPath/$nodeName';
          });
        }
        await _refresh();
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al mover: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Deletes a directory (VIP mode).
  Future<void> _deleteDir(int id) async {
    final bool? ok = await _showDeleteConfirmationDialog('esta carpeta y todo su contenido');
    if (ok == true) {
      _showLoadingDialog('Eliminando...');
      try {
        await widget.api.deleteDirectory(id: id);
        if (mounted) Navigator.pop(context);
        if (_currentDirId == id) {
          final cur = _dirById(id);
          setState(() {
            _currentDirId = cur?['parent_id'];
          });
          _saveLocation();
        }
        await _refresh();
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Deletes a directory (FS mode).
  Future<void> _deleteDirFs(String path) async {
    final bool? ok = await _showDeleteConfirmationDialog('esta carpeta y todo su contenido');
    if (ok == true) {
      _showLoadingDialog('Eliminando...');
      try {
        await widget.api.deleteDirectory(path: path);
        if (mounted) Navigator.pop(context);
        if (_currentPath == path) {
          final parts = path.split('/').where((p) => p.isNotEmpty).toList();
          parts.removeLast();
          setState(() {
            _currentPath = parts.join('/');
          });
          _saveLocation();
        }
        await _refresh();
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // --- Document Actions ---

  /// Renames a document (FS mode).
  Future<void> _renameDocFs(String path, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final bool? ok = await _showRenameDialog(ctrl, 'Documento');

    String newName = ctrl.text.trim();
    if (currentName.toLowerCase().endsWith('.pdf') && !newName.toLowerCase().endsWith('.pdf')) {
      newName += '.pdf';
    }
    // Also handle summary renaming if needed
    if (currentName.toLowerCase().endsWith('.txt') && !newName.toLowerCase().endsWith('.txt')) {
      newName += '.txt'; // Keep txt extension for summaries
    }

    if (ok == true && newName.isNotEmpty && newName != currentName) {
      _showLoadingDialog('Renombrando...');
      try {
        // 'path' ya es una ruta relativa completa (p.ej. 'subcarpeta/archivo.pdf' o 'archivo.pdf')
        final relativePath = path;
        await widget.api.updateDocumentName(
          path: relativePath,
          newName: newName,
        );
        if (mounted) Navigator.pop(context);
        await _refresh();
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al renombrar: $e'), backgroundColor: Colors.red));
      }
    }
  }



  /// Moves a document (FS mode).
  Future<void> _moveDocFs(String path) async {
    final targetPath = await _chooseTargetFsDirPath(); // No exclusion needed

    // 'path' ya es la ruta relativa completa del archivo
    final sourceRelPath = path;

    // Padre actual real
    final parts = sourceRelPath.split('/').where((p) => p.isNotEmpty).toList();
    parts.removeLast();
    final currentParentPath = parts.join('/');

    // Normalizar: null o string vacío significa raíz
    final normalizedTargetPath = (targetPath == null || targetPath.isEmpty) ? '' : targetPath;

    if (normalizedTargetPath != currentParentPath) {
      _showLoadingDialog('Moviendo documento...');
      try {
        await widget.api.moveDocument(
          path: sourceRelPath,
          newParentPath: normalizedTargetPath.isEmpty ? '' : normalizedTargetPath,
        );
        if (mounted) Navigator.pop(context);
        await _refresh();
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al mover: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }



  /// Deletes a document or summary (FS mode).
  Future<void> _deleteDocFs(String path) async {
    final fileName = path.split('/').last;
    final bool isSummary = fileName.toLowerCase().startsWith('resumen_') &&
        fileName.toLowerCase().endsWith('.txt');
    final String itemType = isSummary ? 'este resumen' : 'este documento';
    final bool? ok = await _showDeleteConfirmationDialog(itemType);

    if (ok == true) {
      _showLoadingDialog('Eliminando ${isSummary ? "resumen" : "documento"}...');
      try {
        // 'path' ya es una ruta relativa completa
        await widget.api.deleteDocument(path: path);
        if (mounted) Navigator.pop(context);
        await _refresh();
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Picks and uploads PDF files.
  Future<void> _pickAndProcessPdfs() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          allowMultiple: true,
          withData: true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar archivos: $e'), backgroundColor: Colors.orange));
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final filesToUpload = result.files.where((f) => f.bytes != null).toList();
    if (filesToUpload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudieron leer los archivos seleccionados.'),
          backgroundColor: Colors.orange));
      return;
    }

    _showLoadingDialog('Subiendo ${filesToUpload.length} PDF(s)...');
    int successCount = 0;
    List<String> errors = [];

    try {
      // Obtener el path actual del directorio
      final uploadPath = _currentPath ?? '';
      print('[Upload] Subiendo a path: "$uploadPath"');
      
      for (final file in filesToUpload) {
        try {
          await widget.api.uploadPdf(
            file.bytes!,
            file.name,
            directoryId: null, // Solo FS mode
            relativePath: uploadPath,
          );
          successCount++;
        } catch (e) {
          errors.add('${file.name}: $e');
        }
      }
    } finally {
      if (mounted) Navigator.pop(context); // Close dialog

      String message;
      Color bgColor;
      if (errors.isEmpty) {
        message = '$successCount PDF(s) subido(s) exitosamente.';
        bgColor = Colors.green;
      } else if (successCount > 0) {
        message = '$successCount subido(s), ${errors.length} con error(es).';
        bgColor = Colors.orange;
        // print("Errores de subida:\n${errors.join('\n')}");
      } else {
        message = 'Error al subir ${errors.length} PDF(s).';
        bgColor = Colors.red;
        // print("Errores de subida:\n${errors.join('\n')}");
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message), backgroundColor: bgColor));
      await _refresh();
    }
  }

  /// Converts HEX color string to Color object.
  Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return Colors.grey;
    } // Default on error
  }

  // --- Analysis Methods ---

  /// Shows dialog to choose analysis type.
  Future<String?> _showAnalyzeOptions() async {
    return showDialog<String>(
      context: context,
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

  /// Initiates analysis for an FS document.
  Future<void> _analyzeDocFs(String path, String displayName) async {
    // ===== CRITICAL: ALL CHECKS MUST BE AT START BEFORE ANY ASYNC =====
    // Check global lock first (synchronous check)
    if (_isAnalyzing) {
      print('[DirectoriesScreen] ❌ Bloqueado: _isAnalyzing ya es true');
      return;
    }

    // Check path lock second (synchronous check)
    if (_analyzingPaths.contains(path)) {
      print('[DirectoriesScreen] ❌ Bloqueado: path "$path" ya en análisis');
      return;
    }

    // Check debounce third (synchronous check)
    final now = DateTime.now();
    if (_lastAnalysisAttempt != null &&
        now.difference(_lastAnalysisAttempt!).inMilliseconds < 2000) {
      print('[DirectoriesScreen] ❌ Bloqueado: debounce < 2 segundos');
      return;
    }

    // ==== SET LOCKS IMMEDIATELY AND TRIGGER UI REBUILD ====
    _isAnalyzing = true;
    _analyzingPaths.add(path);
    _lastAnalysisAttempt = now;
    print('[DirectoriesScreen] ✅ Locks activados para: "$path"');
    
    // CRITICAL: Call setState immediately to disable UI before async dialog
    if (mounted) setState(() {});

    String? type;
    try {
      type = await _showAnalyzeOptions();
      if (type == null || !mounted) {
        // Usuario canceló - resetear flags
        _isAnalyzing = false;
        _analyzingPaths.remove(path);
        if (mounted) setState(() {});
        return;
      }
    } catch (e) {
      _isAnalyzing = false;
      _analyzingPaths.remove(path);
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
                  final result = await summarizePdf(
                    service: _analysisService,
                    mode: 'fs',
                    path: path,
                    fileName: displayName,
                    analysisType: analysisType,
                    onProgress: (p) {
                      if (!mounted || !dialogActive) return;
                      try {
                        setStateDialog(() {
                          progress = p.progress;
                          statusLabel = _progressStatusText(p, displayName);
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
                      _analyzingPaths.remove(path);
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
                    await _refresh();
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
                      _analyzingPaths.remove(path);
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
                        content: Text('Error al analizar: $friendlyMsg'),
                        backgroundColor: bgColor,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                }
              });
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF1976D2)),
                  const SizedBox(width: 8),
                  const Text('Analizando documento'),
                ],
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                    // Barra de progreso con animación suave
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        tween: Tween<double>(begin: 0, end: progress),
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress >= 1.0 ? Colors.green : const Color(0xFF1976D2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                            maxLines: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: progress >= 1.0 ? Colors.green.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: progress >= 1.0 ? Colors.green.shade700 : const Color(0xFF1976D2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton.icon(
                  onPressed: cancelPressed
                      ? null
                      : () async {
                          // Presionar STOP: marcar cancelación y pedir al backend cancelar
                          setStateDialog(() {
                            cancelPressed = true;
                            statusLabel = 'Cancelando...';
                          });
                          final jid = currentJobId;
                          if (jid != null) {
                            try {
                              await widget.api.cancelSummary(jid);
                            } catch (_) {}
                          }
                        },
                  icon: const Icon(Icons.stop_circle_outlined, size: 20),
                  label: const Text('Detener'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _progressStatusText(AnalysisProgress p, String name) {
    switch (p.status) {
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

  /// Legacy placeholder for VIP analysis (no longer supported in modo FS-only).
  Future<void> _analyzeDocVip(int docId, String displayName) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'La generación de resúmenes VIP no está disponible en esta versión.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // --- Navigation Methods ---

  /// Navigates to the Summary screen.
// --- Navigation Methods ---

  /// Navigates to the Summary screen.
  void _viewSummary(Map<String, dynamic> docData) async {
    if (!mounted) return;
    _showLoadingDialog('Cargando resumen...');
    try {
      final path = docData['path'] as String?;
      if (path == null || path.isEmpty) throw Exception('Path del resumen faltante.');
      final details = await widget.api.fetchSummaryDetails(fsPath: path);
      if (mounted) Navigator.pop(context);
      final summaryText = details['summary_text'] as String? ?? '(Sin contenido)';
      final displayName = docData['display_name'] ?? 'Resumen';
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SummaryScreen(
          title: displayName,
          summaryText: summaryText,
          api: widget.api,
        ),
      ));
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el resumen: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Navigates to the Quiz screen.
  void _generateQuiz(Map<String, dynamic> docData) async {
    if (!mounted) return;
    final displayName = docData['display_name'] ?? 'Quiz';
    final fsPath = docData['path'] as String?;

    if (fsPath == null || fsPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener la ruta del resumen')),
      );
      return;
    }

    // Show modal to select number of questions
    int? selectedQuestions = await showDialog<int?>(
      context: context,
      builder: (ctx) => _buildQuizQuestionCountDialog(),
    );

    if (selectedQuestions == null || !mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(
          sourceName: displayName,
          api: widget.api,
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

  /// Muestra cursos relacionados con el resumen.
  Future<void> _viewCourses(Map<String, dynamic> docData) async {
    if (!mounted) return;
    final fsPath = docData['path'] as String?;
    if (fsPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener la ruta del resumen')),
      );
      return;
    }

    _showLoadingDialog('Extrayendo tema y buscando cursos...');
    
    try {
      // Obtener detalles del resumen
      final details = await widget.api.fetchSummaryDetails(fsPath: fsPath);
      final summaryText = (details['summary_text'] as String?) ?? '';
      
      // Extraer tema del resumen (buscar el primer título H1 en Markdown)
      String tema = '';
      final lines = summaryText.split('\n');
      for (final line in lines) {
        if (line.trim().startsWith('# ')) {
          tema = line.trim().substring(2).trim();
          // Remover emojis del inicio
          tema = tema.replaceFirst(RegExp(r'^[\u{1F300}-\u{1F9FF}]\s*', unicode: true), '');
          break;
        }
      }
      
      if (tema.isEmpty) {
        tema = docData['display_name'] ?? 'Tema general';
      }
      
      // Obtener cursos desde Perplexity
      final data = await widget.api.fetchCoursesByTopic(tema);
      final courses = (data['courses'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      
      if (!mounted) return;
      Navigator.pop(context); // Cerrar loading dialog
      
      if (courses.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se encontraron cursos para: $tema')),
        );
        return;
      }
      
      // Abrir pantalla de cursos
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CoursesScreen(tema: tema, courses: courses, api: widget.api),
        ),
      );
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

  /// Shows preferences dialog with theme toggle.
  void _showPreferences() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Preferencias'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Tema oscuro'),
              subtitle: const Text('Activar modo oscuro'),
              value: Provider.of<ThemeProvider>(context, listen: true).isDarkMode,
              onChanged: (value) {
                Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
              },
              secondary: const Icon(Icons.dark_mode),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// Shows VIP upgrade dialog.
  void _showUpgradeVipDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.star, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('Volverse VIP'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¡Mejora tu experiencia con EstudiaFácil VIP!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('Beneficios VIP:'),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Almacenamiento en la nube')),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Acceso desde cualquier dispositivo')),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Sincronización automática')),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Respaldo seguro de tus documentos')),
              ],
            ),
            SizedBox(height: 16),
            Text(
              'Actualmente estás usando el modo gratuito que guarda archivos localmente en tu dispositivo.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Más tarde'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('¡Función VIP próximamente disponible!'),
                  backgroundColor: Color(0xFFFFD700),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: const Text('¡Quiero ser VIP!'),
          ),
        ],
      ),
    );
  }

  /// Navigates to the Profile screen.
  void _goToProfile() {
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileScreen(api: widget.api)),
      );
    }
  }

  /// Logs the user out and returns to LoginScreen.
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Limpia token del ApiService y preferencias locales
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

  // --- Helper Methods ---

  /// Extracts a user-friendly error message from an exception
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
    
    // Mensaje genérico
    return 'Error desconocido. Intenta de nuevo';
  }

  // --- Helper Dialogs ---

  /// Shows a standard loading dialog. Must be closed manually.
  void _showLoadingDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 16),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a generic rename dialog.
  Future<bool?> _showRenameDialog(TextEditingController controller, String itemType) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Renombrar $itemType'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nuevo nombre'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
  }

  /// Shows a generic confirmation dialog for deletion.
  Future<bool?> _showDeleteConfirmationDialog(String itemDescription) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content:
            Text('¿Seguro que quieres eliminar $itemDescription? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar Definitivamente'),
          ),
        ],
      ),
    );
  }

  // --- Main Build Method ---
  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> childrenDirs = _childrenNormalized();
    final List<Map<String, dynamic>> currentDocs = _docsNormalized();

    return Scaffold(
      appBar: AppBar(
        title: _breadcrumbBar(),
        titleSpacing: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Usuario',
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  _goToProfile();
                  break;
                case 'preferences':
                  _showPreferences();
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (context) {
              return [
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
                  value: 'preferences',
                  child: Row(
                    children: [
                      Icon(Icons.settings, color: Color(0xFF1976D2)),
                      SizedBox(width: 8),
                      Text('Preferencias'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      floatingActionButton: _tabIndex == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  onPressed: _pickAndProcessPdfs,
                  tooltip: 'Subir PDF',
                  heroTag: 'upload',
                  child: const Icon(Icons.upload_file),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  onPressed: _createDir,
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
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 10),
                      Text(_error ?? 'Ocurrió un error desconocido',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                        onPressed: _refresh,
                      )
                    ],
                  ),
                ))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      // --- Subfolders Section ---
                      if (childrenDirs.isNotEmpty) ...[
                        const Text('Subcarpetas',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...childrenDirs.map((d) {
                            final color = _hexToColor(d['color_hex'] ?? '#1565C0');
                            return ListTile(
                              leading: Icon(Icons.folder_open, color: color),
                              title: Text(d['name'] ?? 'Unnamed'),
                              onTap: () {
                                setState(() {
                                  _currentPath = d['path'] as String?;
                                });
                                _saveLocation();
                                _refresh();
                              },
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Opciones de carpeta',
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) {
                                  final String path = d['path'] as String;
                                  switch (value) {
                                    case 'share':
                                      _shareFolderFs(path, d['name']);
                                      break;
                                    case 'rename':
                                      _renameDirFs(path, d['name']);
                                      break;
                                    case 'color':
                                      _changeColorFs(path);
                                      break;
                                    case 'move':
                                      _moveDirFs(path);
                                      break;
                                    case 'delete':
                                      _deleteDirFs(path);
                                      break;
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                      value: 'share', 
                                      child: Row(
                                        children: [
                                          Icon(Icons.folder_shared, color: Color(0xFF1976D2)),
                                          SizedBox(width: 8),
                                          Text('Compartir'),
                                        ],
                                      )),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                      value: 'rename', 
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit, color: Color(0xFF1976D2)),
                                          SizedBox(width: 8),
                                          Text('Renombrar'),
                                        ],
                                      )),
                                  const PopupMenuItem(
                                      value: 'color', 
                                      child: Row(
                                        children: [
                                          Icon(Icons.palette, color: Color(0xFF1976D2)),
                                          SizedBox(width: 8),
                                          Text('Cambiar color'),
                                        ],
                                      )),
                                  const PopupMenuItem(
                                      value: 'move', 
                                      child: Row(
                                        children: [
                                          Icon(Icons.drive_file_move, color: Color(0xFF1976D2)),
                                          SizedBox(width: 8),
                                          Text('Mover'),
                                        ],
                                      )),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                      value: 'delete', 
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Eliminar', style: TextStyle(color: Colors.red)),
                                        ],
                                      )),
                                ],
                              ),
                              dense: true,
                            );
                          }),
                        const Divider(height: 24),
                      ],

                      // --- Documents Section ---
                      const Text('Documentos',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (currentDocs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          child: Center(
                              child: Text('No hay documentos aquí. \nSube un PDF para empezar.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey))),
                        )
                      else
                        ...currentDocs.map((d) {
                          final String docType = d['type'] ?? 'pdf';
                          final String displayName = d['display_name'] ?? 'Archivo';
                          final IconData leadingIcon = docType == 'summary'
                              ? Icons.description_outlined
                              : Icons.picture_as_pdf_outlined;
                          final Color iconColor = docType == 'summary'
                              ? const Color(0xFF1976D2) // Azul para Summary/Resumen
                              : const Color(0xFFD32F2F); // Rojo para PDF
                          final int? docSize = d['size'] as int?; // Handle potential null size

                          return ListTile(
                            leading: Icon(leadingIcon, color: iconColor),
                            title: Text(displayName),
                            subtitle: Text(
                              (() {
                                      final modStr = _formatDateTimeStr(d['modified'] as String?);
                                      final creStr = _formatDateTimeStr(d['created'] as String?);
                                      final sizeStr = _formatBytes(docSize ?? 0);
                                      final base = docType == 'pdf' ? 'Tamaño: $sizeStr' : 'Resumen · $sizeStr';
                                      if (modStr != null && creStr != null) {
                                        return '$base · Modificado: $modStr · Creado: $creStr';
                                      } else if (modStr != null) {
                                        return '$base · Modificado: $modStr';
                                      } else if (creStr != null) {
                                        return '$base · Creado: $creStr';
                                      } else {
                                        return base;
                                      }
                                    })(),
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            onTap: () {
                              if (docType == 'summary') {
                                _viewSummary(d);
                              } else {
                                // For a PDF, show analysis options - WITH LOCK CHECK
                                if (_isAnalyzing) {
                                  print('[DirectoriesScreen] ❌ Tap ignorado: análisis en progreso');
                                  return;
                                }
                                _analyzeDocFs(d['path'] as String, d['display_name'] ?? 'Doc');
                              }
                            },
                            trailing: PopupMenuButton<String>(
                                tooltip: 'Opciones',
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) async {
                                  final String path = d['path'] as String;
                                  switch (value) {
                                    case 'rename':
                                      _renameDocFs(path, displayName);
                                      break;
                                    case 'move':
                                      _moveDocFs(path);
                                      break;
                                    case 'delete':
                                      _deleteDocFs(path);
                                      break;
                                    case 'view':
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PdfViewerScreen(
                                            relativePath: path,
                                            title: displayName,
                                          ),
                                        ),
                                      );
                                      break;
                                    case 'analyze':
                                      if (!_isAnalyzing) {
                                        _analyzeDocFs(path, displayName);
                                      }
                                      break;
                                    case 'quiz':
                                      _generateQuiz(d);
                                      break;
                                    case 'courses':
                                      _viewCourses(d);
                                      break;
                                  }
                                },
                                itemBuilder: (ctx) {
                                  if (docType == 'summary') {
                                    return [
                                      const PopupMenuItem(
                                          value: 'quiz', 
                                          child: Row(
                                            children: [
                                              Icon(Icons.quiz, color: Color(0xFF1976D2)),
                                              SizedBox(width: 8),
                                              Text('Generar Quiz'),
                                            ],
                                          )),
                                      const PopupMenuItem(
                                          value: 'courses', 
                                          child: Row(
                                            children: [
                                              Icon(Icons.school, color: Color(0xFF1976D2)),
                                              SizedBox(width: 8),
                                              Text('Ver Cursos'),
                                            ],
                                          )),
                                      const PopupMenuItem(
                                          value: 'rename', 
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit, color: Color(0xFF1976D2)),
                                              SizedBox(width: 8),
                                              Text('Renombrar'),
                                            ],
                                          )),
                                      const PopupMenuItem(
                                          value: 'move', 
                                          child: Row(
                                            children: [
                                              Icon(Icons.drive_file_move, color: Color(0xFF1976D2)),
                                              SizedBox(width: 8),
                                              Text('Mover'),
                                            ],
                                          )),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete, color: Colors.red),
                                              SizedBox(width: 8),
                                              Text('Eliminar', style: TextStyle(color: Colors.red)),
                                            ],
                                          )),
                                    ];
                                  } else {
                                    // It's a PDF
                                    return [
                                      const PopupMenuItem(
                                          value: 'view', 
                                          child: Row(
                                            children: [
                                              Icon(Icons.picture_as_pdf, color: Color(0xFF1976D2)),
                                              SizedBox(width: 8),
                                              Text('Ver'),
                                            ],
                                          )),
                                      const PopupMenuItem(
                                          value: 'analyze', 
                                          child: Row(
                                            children: [
                                              Icon(Icons.analytics, color: Color(0xFF1976D2)),
                                              SizedBox(width: 8),
                                              Text('Analizar'),
                                            ],
                                          )),
                                      const PopupMenuItem(
                                          value: 'rename', 
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit, color: Color(0xFF1976D2)),
                                              SizedBox(width: 8),
                                              Text('Renombrar'),
                                            ],
                                          )),
                                      const PopupMenuItem(
                                          value: 'move', 
                                          child: Row(
                                            children: [
                                              Icon(Icons.drive_file_move, color: Color(0xFF1976D2)),
                                              SizedBox(width: 8),
                                              Text('Mover'),
                                            ],
                                          )),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete, color: Colors.red),
                                              SizedBox(width: 8),
                                              Text('Eliminar', style: TextStyle(color: Colors.red)),
                                            ],
                                          )),
                                    ];
                                  }
                                }),
                            dense: true,
                          );
                        }), // End map for docs
                    ],
                  ),
                ),
    );
  }

  // Helper function to format bytes
  String _formatBytes(int bytes, [int decimals = 1]) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor(); // log requires dart:math
    return ((bytes / pow(1024, i)).toStringAsFixed(decimals)) + ' ' + suffixes[i]; // pow requires dart:math
  }

  String? _formatDateTimeStr(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final dt = DateTime.parse(iso).toLocal();
      final two = (int n) => n.toString().padLeft(2, '0');
      final dd = two(dt.day);
      final mm = two(dt.month);
      final yyyy = dt.year.toString();
      final hh = two(dt.hour);
      final min = two(dt.minute);
      return '$dd/$mm/$yyyy $hh:$min';
    } catch (_) {
      return null;
    }
  }
}