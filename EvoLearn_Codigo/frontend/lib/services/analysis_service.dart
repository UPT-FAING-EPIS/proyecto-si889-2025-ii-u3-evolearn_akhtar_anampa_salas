import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

class AnalysisService {
  final ApiService _api;
  final String _baseUrl;

  // Constructor correctly takes ApiService and gets baseUrl
  AnalysisService(this._api) : _baseUrl = _api.baseUrl;

  // Single-flight map to deduplicate concurrent job creations per file/path
  static final Map<String, Completer<int>> _createJobInFlight = {};

  /// Submits a PDF for analysis and returns the job ID.
  /// The UI is responsible for polling the job status.
  Future<int> startAnalysisJob({
    required String path,
    required String fileName,
    String analysisType = 'summary_fast',
  }) async {
    await _api.ensureAuth();
    final auth = _api.authHeaders;
    final authHeader = auth['Authorization'];
    if (authHeader == null || authHeader.isEmpty) {
      throw Exception('Missing auth token');
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'default_user';
    final docsDir = await LocalStorageService.getDocumentsDir(userId);
    final filePath = p.join(docsDir.path, path);
    final file = File(filePath);
    final exists = await file.exists();
    print('[Analysis DEBUG] filePath=$filePath exists=$exists');
    if (exists) {
      try {
        final len = await file.length();
        print('[Analysis DEBUG] file size: $len');
      } catch (_) {}
    }
    final singleFlightKey = '$userId|$path|$analysisType';
    
    print('[Analysis] Iniciando análisis de PDF: $fileName');
    if (!await file.exists()) {
      throw Exception('Archivo no encontrado: $path');
    }

    // Single-flight: if a creation for this key is already in flight, await it
    final existing = _createJobInFlight[singleFlightKey];
    if (existing != null) {
      print('[Analysis] ⚠️ Job creation ya en curso para $singleFlightKey. Reutilizando.');
      return existing.future;
    }

    final completer = Completer<int>();
    _createJobInFlight[singleFlightKey] = completer;

    final url = Uri.parse('$_baseUrl/api/generate_summary.php');
    final request = http.MultipartRequest('POST', url);
    
    // Add only auth headers to avoid accidentally overwriting multipart Content-Type
    if (auth['Authorization'] != null) {
      request.headers['Authorization'] = auth['Authorization']!;
    }
    if (auth['X-Auth-Token'] != null) {
      request.headers['X-Auth-Token'] = auth['X-Auth-Token']!;
    }

    request.fields['file_name'] = fileName;
    request.fields['path'] = path;
    request.fields['analysis_type'] = analysisType;
    request.fields['model'] = 'gemini-2.5-flash'; // Default to stable v1-supported model
    request.files.add(await http.MultipartFile.fromPath('pdf', file.path));
    // Debug info about multipart payload being sent
    try {
      print('[Analysis DEBUG] multipart files: ${request.files.map((f) => f.filename).toList()}');
      print('[Analysis DEBUG] request.fields: ${request.fields}');
    } catch (_) {}

    print('[Analysis] Enviando archivo para crear Job...');
    http.StreamedResponse streamed;
    http.Response resp;
    try {
      streamed = await request.send().timeout(const Duration(seconds: 30));
      resp = await http.Response.fromStream(streamed);
    } catch (e) {
      // Ensure we clear in-flight on transport errors
      _createJobInFlight.remove(singleFlightKey);
      rethrow;
    }

    if (resp.statusCode != 202) { // Esperamos 202 Accepted
      String message = 'Error al crear la tarea de análisis (HTTP ${resp.statusCode})';
      try {
        final data = jsonDecode(resp.body);
        final err = (data is Map && data['error'] is String) ? data['error'] as String : null;
        if (err != null && err.isNotEmpty) message = err;
      } catch (_) {
        final snippet = resp.body.toString();
        if (snippet.startsWith('<!doctype html>') || snippet.startsWith('<!DOCTYPE html>')) {
          message = '404/Servidor no encontrado en ${url.toString()}';
        }
      }
      // Clear in-flight before throwing so a subsequent attempt can retry
      _createJobInFlight.remove(singleFlightKey);
      throw Exception(message);
    }

    // Parse JSON response with better error handling
    // Validar que la respuesta no esté vacía
    if (resp.body.isEmpty) {
      print('[Analysis] ❌ ERROR: Response body está VACÍO');
      throw Exception('El servidor envió una respuesta vacía');
    }

    // Log completo de la respuesta para diagnóstico
    print('[Analysis] 📋 Response status: ${resp.statusCode}');
    print('[Analysis] 📋 Response headers: ${resp.headers}');
    print('[Analysis] 📋 Response body (${resp.body.length} caracteres):');
    print('[Analysis] 📋 Body completo: "${resp.body}"');
    
    late final Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      print('[Analysis] ❌ JSON PARSE ERROR: $e');
      print('[Analysis] ❌ Body que falló: "${resp.body}"');
      print('[Analysis] ❌ Body length: ${resp.body.length}');
      print('[Analysis] ❌ Body bytes: ${resp.body.codeUnits}');
      print('[Analysis] ❌ Content-Type: ${resp.headers['content-type']}');
      // Fallback: intentar extraer job_id con RegExp cuando el cuerpo está truncado
      final reg = RegExp(r'"job_id"\s*:\s*(\d+)');
      final m = reg.firstMatch(resp.body);
      if (m != null) {
        final jid = int.tryParse(m.group(1) ?? '');
        if (jid != null) {
          print('[Analysis] ⚠️ JSON inválido pero se detectó job_id por regex: $jid');
          print('[Analysis] ⚠️ Continuando con job_id extraído.');
          return jid;
        }
      }
      // Clear in-flight before throwing
      _createJobInFlight.remove(singleFlightKey);
      throw Exception('Respuesta JSON inválida del servidor (posible truncamiento)');
    }

    final jobId = data['job_id'] as int?;
    if (jobId == null) {
      print('[Analysis] ERROR: No job_id en respuesta: $data');
      _createJobInFlight.remove(singleFlightKey);
      throw Exception('El servidor no devolvió un ID de tarea válido.');
    }
    print('[Analysis] Job creado con ID: $jobId');
    // Complete single-flight and cleanup
    if (!completer.isCompleted) completer.complete(jobId);
    _createJobInFlight.remove(singleFlightKey);
    return jobId;
  }
}

/// Generates quiz questions for a given PDF document.
Future<List<Map<String, dynamic>>> generateQuizFromPdf({
  required String mode,      // 'vip' or 'fs'
  String? documentId,     // VIP mode identifier
  String? path,           // FS mode identifier
  required String fileName, // Used for placeholder text
}) async {
  // --- Placeholder for Actual Gemini AI Call ---
  // Similar to summarizePdf, this will involve:
  // 1. Fetching PDF content if needed.
  // 2. Calling Gemini with prompts designed to generate multiple-choice questions.
  // 3. Parsing the response (likely JSON) into the desired question format.
  print('Simulating Gemini quiz generation for: $fileName');
  await Future.delayed(const Duration(seconds: 5)); // Reduced simulation time

  // Simple pseudo-randomness for placeholder correct answers
  final baseSeed = DateTime.now().second + fileName.length;

  // Placeholder quiz data structure
  return List.generate(6, (i) => {
    'question': 'Pregunta ${i + 1} simulada sobre "$fileName"',
    'options': List.generate(4, (j) => 'Opción ${j + 1} para P.${i + 1} (simulada)'),
    // Generate a somewhat predictable but varying correct index
    'correctIndex': (baseSeed + i * 2) % 4,
  });
  // --- End Placeholder ---

  // Note: Unlike the summary, there's currently no backend call here
  // to save the generated quiz questions. This could be added if needed.
}

extension _PathUtils on String {
  String withoutExtension() {
    final name = this;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

class AnalysisProgress {
  final double progress; // 0.0 - 1.0
  final String status;   // pending | processing | completed | failed
  const AnalysisProgress(this.progress, this.status);
}

/// Orquesta el análisis con backend usando job + polling y guarda el resumen localmente.
/// Devuelve: {'summary_text': String, 'fs_summary_path': String, 'saved_abs_path': String}
Future<Map<String, String>> summarizePdf({
  required AnalysisService service,
  required String mode, // solo 'fs'
  required String path, // ruta relativa del PDF
  required String fileName,
  String analysisType = 'summary_fast',
  void Function(AnalysisProgress p)? onProgress,
  void Function(int jobId)? onJobCreated,
  bool Function()? cancelRequested,
}) async {
  if (mode != 'fs') {
    throw Exception('Solo se soporta modo FS para análisis en esta versión');
  }

  final jobId = await service.startAnalysisJob(
    path: path,
    fileName: fileName,
    analysisType: analysisType,
  );
  try {
    onJobCreated?.call(jobId);
  } catch (_) {}

  onProgress?.call(const AnalysisProgress(0.1, 'pending'));

  final startedAt = DateTime.now();
  DateTime lastActivityAt = startedAt;
  const overallMaxWait = Duration(minutes: 20);
  const idleMaxWait = Duration(minutes: 6);
  String status = 'pending';
  double prog = 0.0;
  double maxProgressSeen = 0.1; // Iniciar en 10% para evitar volver a 0% visual
  double lastProg = 0.1;
  String lastStatus = status;
  Map<String, dynamic>? lastJob;

  while (true) {
    if (cancelRequested != null && cancelRequested()) {
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
      final data = await service._api.getSummaryStatus(jobId);
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

      // Actualizar último progreso/actividad (usar progreso real para detectar cambios)
      if (prog > lastProg + 0.01 || displayStatus != lastStatus) {
        lastProg = prog;
        lastStatus = displayStatus;
        lastActivityAt = now;
      }

      // Mostrar siempre el progreso máximo observado en la UI (mínimo 10%)
      onProgress?.call(AnalysisProgress(maxProgressSeen, displayStatus));

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

  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id') ?? 'default_user';

  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  final pdfName = segments.isNotEmpty ? segments.last : fileName;
  final parentRel = segments.length > 1 ? segments.sublist(0, segments.length - 1).join('/') : '';

  // Include analysis type in the filename so different summaries for the same PDF
  // (e.g. summary_fast vs summary_detailed) are stored separately and
  // re-generating one does not overwrite the other.
  final suffix = analysisType.startsWith('summary_')
      ? analysisType.substring('summary_'.length)
      : analysisType;
  final summaryFileName = 'resumen_${pdfName.withoutExtension()}_${suffix}.txt';
  final savedPathAbs = await LocalStorageService.saveSummaryFile(
    userId,
    summaryFileName,
    summaryText,
    parentRel.isEmpty ? null : parentRel,
  );

  final fsSummaryRel = parentRel.isEmpty ? summaryFileName : '$parentRel/$summaryFileName';
  onProgress?.call(const AnalysisProgress(1.0, 'completed'));

  return {
    'summary_text': summaryText,
    'fs_summary_path': fsSummaryRel,
    'saved_abs_path': savedPathAbs,
  };
}