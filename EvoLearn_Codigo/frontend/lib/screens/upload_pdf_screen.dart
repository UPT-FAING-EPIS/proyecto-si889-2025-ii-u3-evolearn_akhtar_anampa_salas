import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
// AÑADIDO

class UploadPdfScreen extends StatefulWidget {
  final ApiService api;
  final int? directoryId; // AÑADIDO
  final String? relativePath; // NUEVO
  final String mode; // NUEVO
  const UploadPdfScreen({super.key, required this.api, this.directoryId, this.relativePath, this.mode = 'vip'}); // MODIFICADO

  @override
  State<UploadPdfScreen> createState() => _UploadPdfScreenState();
}

class _UploadPdfScreenState extends State<UploadPdfScreen> {
  List<PlatformFile> _pdfs = [];
  String? _status;
  bool _loading = false;
  double _progress = 0.0;
  final List<_ProcessedDoc> _processed = [];

  Future<void> _pickPdfs() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true);
    if (result != null) {
      setState(() {
        _pdfs = result.files;
      });
    }
  }

  Future<void> _processAll() async {
    if (_pdfs.isEmpty) return;
    setState(() {
      _loading = true;
      _status = 'Iniciando...';
      _progress = 0.0;
    });
    _processed.clear();
    try {
      for (int i = 0; i < _pdfs.length; i++) {
        final f = _pdfs[i];
        if (!mounted) return;
        setState(() {
          _status = 'Procesando ${i + 1} de ${_pdfs.length}: ${f.name}';
        });
        if (f.bytes == null) continue;
        final data = await widget.api.uploadPdf(
          f.bytes!, f.name,
          directoryId: widget.mode == 'vip' ? widget.directoryId : null,
          relativePath: widget.mode == 'fs' ? (widget.relativePath ?? '') : null,
        );
        _processed.add(_ProcessedDoc(docId: (data['document_id'] as int?), fileName: f.name, topics: null, fsPath: data['fs_path'] as String?));
        if (!mounted) return;
        setState(() {
          _progress = (i + 1) / _pdfs.length;
        });
      }
      if (!mounted) return;
      setState(() { _status = 'Completado: ${_processed.length} archivo(s) subido(s).'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _status = 'Error: $e'; });
    } finally {
      if (!mounted) return;
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = _pdfs.map((f) => f.name).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subir PDF'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _loading ? null : _pickPdfs,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Elegir PDFs'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _loading || _pdfs.isEmpty ? null : _processAll,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Procesar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_status != null) Text(_status!),
            if (_loading) LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text('Archivos para procesar:', style: Theme.of(context).textTheme.titleMedium),
            Expanded(
              child: ListView(
                children: names.map((n) => ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: Text(n),
                )).toList(),
              ),
            ),
            const Divider(),
            Text('Archivos procesados:', style: Theme.of(context).textTheme.titleMedium),
            Expanded(
              child: ListView(
                children: _processed.map((p) => ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(p.fileName),
                  subtitle: const Text('Archivo subido'),
                  trailing: null,
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessedDoc {
  final int? docId;
  final String fileName;
  final List<dynamic>? topics;
  final String? fsPath;
  _ProcessedDoc({required this.fileName, this.docId, this.topics, this.fsPath});
}
