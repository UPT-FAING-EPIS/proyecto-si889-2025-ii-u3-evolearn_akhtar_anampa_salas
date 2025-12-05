import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:io';
import '../services/document_cache_service.dart';
import '../services/connectivity_service.dart';
import 'package:provider/provider.dart';

/// Hybrid document viewer - handles PDFs and TXTs (with markdown support)
class HybridDocumentViewer extends StatefulWidget {
  final String documentId;
  final String displayName;
  final String documentUrl;
  final String mimeType;
  final String authToken;
  final bool isTextFile;

  const HybridDocumentViewer({
    super.key,
    required this.documentId,
    required this.displayName,
    required this.documentUrl,
    required this.mimeType,
    required this.authToken,
    required this.isTextFile,
  });

  @override
  State<HybridDocumentViewer> createState() => _HybridDocumentViewerState();
}

class _HybridDocumentViewerState extends State<HybridDocumentViewer>
    with WidgetsBindingObserver {
  late Future<File> _documentFuture;
  String _textContent = '';
  bool _loadingText = false;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  String? _error;
  bool _isAppResuming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeDocument();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App is resuming from hot reload or background
      _isAppResuming = true;
      if (_isDownloading) {
        // If download was interrupted, restart it
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _isDownloading) {
            _initializeDocument();
          }
        });
      }
    } else if (state == AppLifecycleState.paused) {
      // App is pausing (hot reload, going to background, etc)
      _isAppResuming = false;
    }
  }

  void _initializeDocument() {
    _documentFuture = DocumentCacheService.downloadAndCacheDocument(
      url: widget.documentUrl,
      documentId: widget.documentId,
      fileName: widget.displayName,
      authToken: widget.authToken,
      onProgress: (progress) {
        if (mounted && !_isAppResuming) {
          setState(() {
            _downloadProgress = progress;
            _isDownloading = progress < 1.0;
          });
        }
      },
    );

    // If it's a text file, also load the content
    if (widget.isTextFile) {
      _loadTextContent();
    }
  }

  Future<void> _loadTextContent() async {
    if (!mounted) return;
    
    setState(() {
      _loadingText = true;
      _error = null;
    });

    try {
      final file = await _documentFuture;
      final content = await file.readAsString();
      
      if (!mounted) return;
      
      setState(() {
        _textContent = content;
        _loadingText = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _error = 'Error al cargar el contenido: $e';
        _loadingText = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectivityService = context.watch<ConnectivityService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.displayName,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          if (!connectivityService.isOnline)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.orange, size: 18),
                  const SizedBox(width: 4),
                  const Text('Offline', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          // Debug button (for both PDF and TXT files)
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Debug Info',
            onPressed: _showDebugInfo,
          ),
        ],
      ),
      body: widget.isTextFile
          ? _buildTextViewer()
          : _buildPdfViewer(),
    );
  }

  Widget _buildTextViewer() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTextContent,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_loadingText) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando contenido...'),
          ],
        ),
      );
    }

    // Show progress while downloading (but NOT at 100%)
    if (_isDownloading && _downloadProgress < 0.99) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  minHeight: 10,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).primaryColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Descargando... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<File>(
      future: _documentFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Descargando documento...'),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _initializeDocument());
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }

        final file = snapshot.data;
        if (file == null) {
          return const Center(child: Text('Archivo no disponible'));
        }

        // Debug: Log file info for text files
        file.length().then((size) {
          debugPrint('📄 Text File Debug:');
          debugPrint('   Path: ${file.path}');
          debugPrint('   Size: $size bytes');
        });

        // Display markdown content
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with actions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined,
                        color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'copy') {
                          _copyToClipboard();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'copy',
                          child: Row(
                            children: [
                              Icon(Icons.content_copy, size: 18),
                              SizedBox(width: 8),
                              Text('Copiar todo'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Markdown content
              if (_textContent.isNotEmpty)
                MarkdownBody(
                  data: _textContent,
                  selectable: true,
                  onTapLink: (text, href, title) {
                    if (href != null) {
                      // Handle links if needed
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Link: $href')),
                      );
                    }
                  },
                )
              else
                Center(
                  child: Text(
                    'El archivo está vacío',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPdfViewer() {
    return FutureBuilder<File>(
      future: _documentFuture,
      builder: (context, snapshot) {
        // Mostrar barra de progreso mientras descarga (pero NO cuando esté en 100%)
        if (_isDownloading && _downloadProgress < 0.99) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _downloadProgress,
                      minHeight: 10,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Descargando PDF... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Cargando PDF...'),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Error: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isDownloading = false;
                      _downloadProgress = 0.0;
                      _initializeDocument();
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }

        final file = snapshot.data;
        if (file == null) {
          return const Center(child: Text('Archivo no disponible'));
        }

        // Debug: Log file info
        file.length().then((size) {
          debugPrint('📄 PDF File Debug:');
          debugPrint('   Path: ${file.path}');
          debugPrint('   Size: $size bytes (${(size / 1024 / 1024).toStringAsFixed(2)} MB)');
        });

        return SfPdfViewer.file(
          file,
          pageLayoutMode: PdfPageLayoutMode.continuous,
          interactionMode: PdfInteractionMode.selection,
          enableDocumentLinkAnnotation: true,
          onDocumentLoadFailed: (details) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error cargando PDF: ${details.description}'),
                backgroundColor: Colors.red,
              ),
            );
          },
        );
      },
    );
  }

  void _copyToClipboard() {
    if (_textContent.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay contenido para copiar')),
      );
      return;
    }

    Clipboard.setData(ClipboardData(text: _textContent));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Contenido copiado al portapapeles'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showDebugInfo() async {
    try {
      final cacheDir = await DocumentCacheService.getCacheDir();
      final fileExtension = widget.displayName.split('.').last;
      final cachedFile = File('${cacheDir.path}/doc_${widget.documentId}.$fileExtension');

      if (!await cachedFile.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archivo no está en caché')),
        );
        return;
      }

      final fileSize = await cachedFile.length();
      final lastModified = await cachedFile.lastModified();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Información del Archivo'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Nombre: ${widget.displayName}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('Tamaño: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB'),
                const SizedBox(height: 8),
                Text('Bytes: $fileSize'),
                const SizedBox(height: 8),
                Text('Modificado: ${lastModified.toString()}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Text('Ruta: ${cachedFile.path}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

