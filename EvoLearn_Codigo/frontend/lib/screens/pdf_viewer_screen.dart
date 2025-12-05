import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../services/local_storage_service.dart';
import '../services/api_service.dart';

class PdfViewerScreen extends StatefulWidget {
  final String relativePath; // e.g. 'subcarpeta/archivo.pdf' o 'archivo.pdf'
  final String? title;
  final String? pdfUrl; // For network PDFs (from shares)
  final ApiService? api; // For auth headers when using network URL

  const PdfViewerScreen({
    super.key,
    this.relativePath = '',
    this.title,
    this.pdfUrl,
    this.api,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _controller = PdfViewerController();
  Future<File?>? _fileFuture;
  bool _isNetworkPdf = false;

  @override
  void initState() {
    super.initState();
    _isNetworkPdf = widget.pdfUrl != null && widget.pdfUrl!.isNotEmpty;
    if (!_isNetworkPdf) {
      _fileFuture = _resolveFile();
    }
  }

  Future<File?> _resolveFile() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'default_user';
    final docsDir = await LocalStorageService.getDocumentsDir(userId);
    final file = File('${docsDir.path}/${widget.relativePath}');
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.title ?? widget.relativePath.split('/').last;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('PDF: $name'),
        backgroundColor: isDarkMode 
            ? const Color(0xFF1F1F1F)
            : Colors.white,
        elevation: 1,
      ),
      body: _isNetworkPdf
          ? _buildNetworkPdfViewer()
          : _buildLocalPdfViewer(),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'pdf_zoom_in',
            onPressed: () => _controller.zoomLevel = _controller.zoomLevel + 0.25,
            backgroundColor: const Color(0xFF1976D2),
            child: const Icon(Icons.zoom_in),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'pdf_zoom_out',
            onPressed: () => _controller.zoomLevel = (_controller.zoomLevel - 0.25).clamp(1.0, 5.0),
            backgroundColor: const Color(0xFF1976D2),
            child: const Icon(Icons.zoom_out),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkPdfViewer() {
    return SfPdfViewer.network(
      widget.pdfUrl!,
      controller: _controller,
      headers: widget.api?.authHeaders,
      pageLayoutMode: PdfPageLayoutMode.single,
      onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
        debugPrint('PDF load failed: ${details.error}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar PDF: ${details.error}'),
            backgroundColor: Colors.red,
          ),
        );
      },
      onDocumentLoaded: (PdfDocumentLoadedDetails details) {
        debugPrint('PDF cargado exitosamente');
      },
    );
  }

  Widget _buildLocalPdfViewer() {
    return FutureBuilder<File?>(
      future: _fileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  'Error al abrir PDF',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.file_present, size: 48, color: Colors.grey[500]),
                const SizedBox(height: 16),
                Text(
                  'Archivo PDF no encontrado',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'El archivo PDF puede haber sido movido o eliminado',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return SfPdfViewer.file(
          file, 
          controller: _controller,
          pageLayoutMode: PdfPageLayoutMode.single,
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}