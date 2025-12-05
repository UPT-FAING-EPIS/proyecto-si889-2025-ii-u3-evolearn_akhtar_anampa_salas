import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  String? _token;
  void setToken(String token) => _token = token;
  void clearToken() => _token = null;
  String? getToken() => _token;

  Future<void> ensureAuth() => _ensureAuth();
  Future<void> _ensureAuth() async {
    if (_token == null || _token!.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('token');
      if (stored != null && stored.isNotEmpty) {
        _token = stored;
      }
    }
  }

  Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
    if (_token != null && _token!.isNotEmpty) 'X-Auth-Token': _token!,
  };

  /// TEST: Simple ping without auth to verify connectivity
  Future<Map<String, dynamic>> ping() async {
    final uri = Uri.parse('$baseUrl/api/ping.php');
    
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('🔔 PING TEST (NO AUTH)');
    debugPrint('  URL: $uri');
    debugPrint('  Base URL: $baseUrl');
    debugPrint('═══════════════════════════════════════════════════');

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      
      debugPrint('📥 PING RESPONSE');
      debugPrint('  Status: ${resp.statusCode}');
      debugPrint('  Body: ${resp.body}');
      debugPrint('═══════════════════════════════════════════════════');

      if (resp.statusCode == 200) {
        return jsonDecode(resp.body);
      } else {
        throw Exception('Ping failed with status ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ PING ERROR: $e');
      debugPrint('═══════════════════════════════════════════════════');
      rethrow;
    }
  }

  /// Generic GET request
  Future<Map<String, dynamic>> get(String endpoint, {Map<String, String>? queryParams}) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    var uri = Uri.parse('$baseUrl/api/$endpoint');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }

    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('🌐 GET REQUEST');
    debugPrint('  URL: $uri');
    debugPrint('  Base URL: $baseUrl');
    debugPrint('  Headers: ${authHeaders.keys.toList()}');
    debugPrint('═══════════════════════════════════════════════════');

    final resp = await http.get(uri, headers: authHeaders);
    
    debugPrint('📥 GET RESPONSE');
    debugPrint('  Status: ${resp.statusCode}');
    debugPrint('  Content-Type: ${resp.headers['content-type']}');
    debugPrint('  Body length: ${resp.body.length}');
    debugPrint('  Body preview: ${resp.body.substring(0, min(resp.body.length, 300))}');
    debugPrint('═══════════════════════════════════════════════════');

    final data = jsonDecode(resp.body);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return data;
    }

    throw Exception(data['error'] ?? 'Request failed');
  }

  /// Generic POST request
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> body) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    final uri = Uri.parse('$baseUrl/api/$endpoint');
    
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('🌐 POST REQUEST');
    debugPrint('  URL: $uri');
    debugPrint('  Base URL: $baseUrl');
    debugPrint('  Headers: ${authHeaders.keys.toList()}');
    debugPrint('  Body: ${jsonEncode(body).substring(0, min(jsonEncode(body).length, 200))}');
    debugPrint('═══════════════════════════════════════════════════');

    final resp = await http.post(
      uri,
      headers: authHeaders,
      body: jsonEncode(body),
    );

    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('📥 POST RESPONSE');
    debugPrint('  Status: ${resp.statusCode}');
    debugPrint('  Content-Type: ${resp.headers['content-type']}');
    debugPrint('  Body length: ${resp.body.length}');
    debugPrint('  Body preview: ${resp.body.substring(0, min(resp.body.length, 300))}');
    debugPrint('═══════════════════════════════════════════════════');

    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body);
    } catch (e) {
      debugPrint('❌ JSON decode failed: $e');
      debugPrint('❌ Raw response: ${resp.body}');
      throw Exception('Server returned invalid JSON: ${resp.body.substring(0, min(resp.body.length, 100))}');
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return data;
    }

    throw Exception(data['error'] ?? 'Request failed');
  }

  Future<String> register(
      String name, String email, String password, String confirm) async {
    final url = Uri.parse('$baseUrl/api/register.php');
    final resp = await http.post(
      url,
      // Enviar como form-url-encoded para compatibilidad con servidor desplegado
      body: {
        'name': name,
        'email': email,
        'password': password,
        'confirm_password': confirm,
      },
    );
    final data = jsonDecode(resp.body);
    if (resp.statusCode == 201 && data['success'] == true) {
      _token = data['token'];

      // Persist token and user info for session restore
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
      if (data['user'] != null && data['user']['id'] != null) {
        await prefs.setString('user_id', data['user']['id'].toString());
      }

      return _token!;
    }
    final err = data['error'];
    final msg = err is String ? err : (resp.statusCode == 409 ? 'El email ya está registrado' : 'Registro fallido');
    throw Exception(msg);
  }

  Future<String> login(String email, String password) async {
    final url = Uri.parse('$baseUrl/api/login.php');
    final resp = await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}));

    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body);
    } catch (_) {
      throw Exception('Respuesta no JSON del backend: ${resp.body}');
    }

    if (resp.statusCode == 200 && data['success'] == true) {
      final token = data['token'] as String;
      _token = token;
      // Persist token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
      return token;
    }
    throw Exception(data['error'] ?? 'Login failed');
  }

  Future<List<dynamic>> getTopics(int documentId) async {
    if (_token == null) throw Exception('Missing auth token');
    final url = Uri.parse('$baseUrl/api/get_topics.php?document_id=$documentId');
    final resp = await http.get(url, headers: authHeaders);
    final data = jsonDecode(resp.body);
    if (resp.statusCode == 200 && data['success'] == true) {
      return data['topics'] as List<dynamic>;
    }
    throw Exception(data['error'] ?? 'Failed to fetch topics');
  }

  // Directories
  Future<Map<String, dynamic>> listDirectories() async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'default_user';
    final fsTree = await LocalStorageService.buildDirectoryTree(userId, null);

    return {
      'success': true,
      'mode': 'fs',
      'fs_tree': fsTree,
    };
  }

  // Documents
  Future<Map<String, dynamic>> listDocuments({int? directoryId, String? path}) async {
    // List local files
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'default_user';

    final files = await LocalStorageService.listFiles(userId, path);
    final documents = <Map<String, dynamic>>[];

    for (final file in files) {
      if (file is File) {
        final fileName = file.path.split('/').last;
        final isPdf = fileName.toLowerCase().endsWith('.pdf');
        final isSummary = fileName.toLowerCase().startsWith('resumen_') &&
            fileName.toLowerCase().endsWith('.txt');

        if (isPdf || isSummary) {
          final stat = await file.stat();
          documents.add({
            'path': (path != null && path.isNotEmpty) ? '$path/$fileName' : fileName,
            'name': fileName,
            'size': await file.length(),
            'type': isSummary ? 'summary' : 'pdf',
            'display_name': fileName,
            'modified': stat.modified.toIso8601String(),
            'created': stat.changed.toIso8601String(),
          });
        }
      }
    }

    return {
      'success': true,
      'mode': 'fs',
      'fs_documents': documents,
    };
  }

  Future<Map<String, dynamic>> deleteDirectory({int? id, String? path}) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    if (path != null && path.isNotEmpty) {
      // Delete locally
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? 'default_user';

      final dirName = path.split('/').last;
      final parts = path.split('/').where((p) => p.isNotEmpty).toList();
      parts.removeLast();
      final parentPath = parts.join('/');

      final ok = await LocalStorageService.deleteDirectory(userId, dirName, parentPath.isEmpty ? null : parentPath);
      if (!ok) {
        throw Exception('No se pudo eliminar directorio local');
      }

      return {
        'success': true,
        'mode': 'fs',
        'message': 'Directorio eliminado localmente'
      };
    }

    throw Exception('Invalid parameters for deleteDirectory');
  }

  // --- Create directory ---
  Future<Map<String, dynamic>> createDirectory(
    String name, {
    int? parentId,
    String? parentPath,
    String? colorHex,
  }) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    // Create directory locally
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'default_user';

    final localPath = await LocalStorageService.createDirectory(
      userId, 
      name, 
      parentPath,
      colorHex: colorHex,
    );

    return {
      'success': true,
      'mode': 'fs',
      'fs_path': parentPath != null && parentPath.isNotEmpty 
          ? '$parentPath/$name' 
          : name,
      'local_path': localPath,
      'message': 'Directorio creado localmente'
    };
  }

  // --- Move directory ---
  Future<Map<String, dynamic>> moveDirectory({
    int? id,
    int? newParentId,
    String? path,
    String? newParentPath,
  }) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    if (path != null && path.isNotEmpty) {
      // Move directory locally
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? 'default_user';

      final newPath = await LocalStorageService.moveDirectory(
        userId, 
        path, 
        newParentPath,
      );

      return {
        'success': true,
        'mode': 'fs',
        'fs_path': newPath,
        'message': 'Directorio movido localmente'
      };
    }

    throw Exception('Invalid parameters for moveDirectory');
  }

  // --- NUEVO: método requerido por DirectoriesScreen ---
  Future<Map<String, dynamic>> updateDirectory({
    int? id,
    String? path,
    String? name,
    String? colorHex,
  }) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    final normalizedPath = path?.trim();

    Future<Map<String, dynamic>> _updateLocalDirectory(String? relativePath) async {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? 'default_user';

      final result = await LocalStorageService.updateDirectoryProperties(
        userId,
        relativePath,
        newName: name,
        colorHex: colorHex,
      );

      return {
        'success': true,
        'mode': 'fs',
        'fs_path': result['path'],
        'name': result['name'],
        'color': result['color'],
        'message': 'Directorio actualizado localmente',
      };
    }

    if (id == null && normalizedPath != null) {
      return await _updateLocalDirectory(normalizedPath);
    }

    final url = Uri.parse('$baseUrl/api/update_directory.php');
    final body = <String, dynamic>{
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (name != null) 'new_name': name,
      if (colorHex != null) 'color_hex': colorHex,
    };
    final resp =
        await http.post(url, headers: authHeaders, body: jsonEncode(body));
    final data = jsonDecode(resp.body);
    if (resp.statusCode == 200 && data['success'] == true) return data;
    throw Exception(data['error'] ?? 'No se pudo actualizar directorio');
  }

  Future<Map<String, dynamic>> uploadPdf(Uint8List fileBytes, String filename,
      {int? directoryId, String? relativePath}) async {
    if (_token == null) throw Exception('Missing auth token');

    // Save locally
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'default_user';

    // Save a copy in the documents root
    final localPath =
        await LocalStorageService.savePdfFile(userId, filename, fileBytes);

    // If the user is in a subdirectory, copy there too
    String effectiveFsPath = filename;
    if (relativePath != null && relativePath.isNotEmpty) {
      try {
        final copiedRel = await LocalStorageService.copyDocument(
          userId,
          filename,
          relativePath,
        );
        effectiveFsPath = copiedRel; // subcarpeta/archivo.pdf
      } catch (_) {
        // If copy fails, keep the root version
      }
    }

    return {
      'success': true,
      'mode': 'fs',
      'fs_path': effectiveFsPath,
      'local_path': localPath,
      'message': 'Archivo guardado localmente'
    };
  }

  Future<Map<String, dynamic>> moveDocument(
      {int? documentId,
      int? targetDirectoryId,
      String? path,
      String? newParentPath}) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    if (path != null && path.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? 'default_user';

      final newRelPath = await LocalStorageService.moveDocument(
        userId,
        path,
        (newParentPath != null && newParentPath.isNotEmpty) ? newParentPath : null,
      );

      return {
        'success': true,
        'mode': 'fs',
        'fs_path': newRelPath,
        'message': 'Documento movido localmente',
      };
    }

    throw Exception('Invalid parameters for moveDocument');
  }

  Future<Map<String, dynamic>> updateDocumentName(
      {int? documentId, required String newName, String? path}) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Nombre de documento inválido');
    }

    if (documentId == null && path != null) {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? 'default_user';
      final newRelPath =
          await LocalStorageService.renameDocument(userId, path, trimmedName);
      return {
        'success': true,
        'mode': 'fs',
        'fs_path': newRelPath,
        'message': 'Documento renombrado localmente',
      };
    }

    final url = Uri.parse('$baseUrl/api/update_document.php');
    final body = <String, dynamic>{
      if (documentId != null) 'document_id': documentId,
      if (path != null) 'path': path,
      'new_name': trimmedName,
    };
    final resp =
        await http.post(url, headers: authHeaders, body: jsonEncode(body));
    final data = jsonDecode(resp.body);
    if (resp.statusCode == 200 && data['success'] == true) return data;
    throw Exception(data['error'] ?? 'No se pudo renombrar documento');
  }

  Future<Map<String, dynamic>> deleteDocument(
      {int? documentId, String? path}) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    if (documentId == null && path != null) {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? 'default_user';

      final segments =
          path.split('/').where((segment) => segment.isNotEmpty).toList();
      if (segments.isEmpty) {
        throw Exception('Ruta de documento inválida');
      }
      final fileName = segments.last;
      final parentRel =
          segments.length > 1 ? segments.sublist(0, segments.length - 1).join('/') : '';

      final ok = await LocalStorageService.deleteFile(
        userId,
        fileName,
        parentRel.isEmpty ? null : parentRel,
      );
      if (!ok) {
        throw Exception('No se pudo eliminar documento local');
      }
      return {
        'success': true,
        'mode': 'fs',
        'message': 'Documento eliminado localmente',
      };
    }

    final url = Uri.parse('$baseUrl/api/delete_document.php');
    final body = <String, dynamic>{
      if (documentId != null) 'document_id': documentId,
      if (path != null) 'path': path,
    };
    final resp =
        await http.post(url, headers: authHeaders, body: jsonEncode(body));
    final data = jsonDecode(resp.body);
    if (resp.statusCode == 200 && data['success'] == true) return data;
    throw Exception(data['error'] ?? 'No se pudo eliminar documento');
  }

  Future<Map<String, dynamic>> deleteSummary({required String summaryPath}) async {
    final url = Uri.parse('$baseUrl/api/delete_document.php');
    final body = <String, dynamic>{
      'summary_path': summaryPath,
    };
    final resp =
        await http.post(url, headers: authHeaders, body: jsonEncode(body));
    final data = jsonDecode(resp.body);
    if (resp.statusCode == 200 && data['success'] == true) return data;
    throw Exception(data['error'] ?? 'No se pudo eliminar resumen');
  }

  // --- Fetch summary details ---
  /// Gets the details (including text) of a summary.
  Future<Map<String, dynamic>> fetchSummaryDetails({required String fsPath}) async {
    if (_token == null) throw Exception('Missing auth token');

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'default_user';

    final content = await LocalStorageService.readFileContent(userId, fsPath, null);
    if (content != null) {
      return {
        'success': true,
        'summary_text': content,
        'file_name': fsPath,
        'mode': 'fs',
      };
    } else {
      throw Exception('No se pudo leer el archivo de resumen');
    }
  }

  Future<Map<String, dynamic>> getSummaryStatus(int jobId) async {
    await _ensureAuth();
    if (_token == null) throw Exception('Missing auth token');

    final url = Uri.parse('$baseUrl/api/get_summary_status.php?job_id=$jobId');
    final resp = await http.get(url, headers: authHeaders)
        .timeout(const Duration(seconds: 15));
    
    final data = jsonDecode(resp.body);

    if (resp.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to fetch summary job status');
  }

  Future<Map<String, dynamic>> cancelSummary(int jobId) async {
    await _ensureAuth();
    if (_token == null) throw Exception('Missing auth token');

    final url = Uri.parse('$baseUrl/api/cancel_summary.php');
    final resp = await http.post(
      url,
      headers: authHeaders,
      body: jsonEncode({'job_id': jobId}),
    );
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body);
    } catch (_) {
      throw Exception('Respuesta no JSON al cancelar la tarea');
    }
    if (resp.statusCode == 200 && (data['success'] == true || data['status'] != null)) {
      return data;
    }
    throw Exception(data['error'] ?? 'No se pudo cancelar la tarea');
  }

  Future<int> generateSummary(Uint8List fileBytes, String filename) async {
    await _ensureAuth();
    if (_token == null) throw Exception('Missing auth token');

    final url = Uri.parse('$baseUrl/api/generate_summary.php');
    final req = http.MultipartRequest('POST', url);
    req.headers['Authorization'] = 'Bearer $_token';

    final file = http.MultipartFile.fromBytes('pdf', fileBytes, filename: filename);
    req.files.add(file);

    final streamed = await req.send();
    final respStr = await streamed.stream.bytesToString();
    final data = jsonDecode(respStr);

    if (streamed.statusCode == 200 && data['success'] == true) {
      return data['job_id'] as int;
    }
    throw Exception(data['error'] ?? 'Upload failed');
  }

  Future<Map<String, dynamic>> loginWithUser(String email, String password) async {
    final url = Uri.parse('$baseUrl/api/login.php');
    final resp = await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}));

    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body);
    } catch (_) {
      throw Exception('Respuesta no JSON del backend: ${resp.body}');
    }

    if (resp.statusCode == 200 && data['success'] == true) {
      _token = data['token'] as String;

      // Save user_id and token for local storage & sesión
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
      if (data['user'] != null && data['user']['id'] != null) {
        await prefs.setString('user_id', data['user']['id'].toString());
      }

      return data; // incluye 'user'
    }
    throw Exception(data['error'] ?? 'Login failed');
  }

  // Profile management methods
  Future<Map<String, dynamic>> changePassword(String currentPassword,
      String newPassword, String confirmPassword) async {
    if (_token == null) throw Exception('Missing auth token');

    final url = Uri.parse('$baseUrl/api/update_profile.php');
    final resp = await http.post(url,
        headers: authHeaders,
        body: jsonEncode({
          'action': 'change_password',
          'current_password': currentPassword,
          'new_password': newPassword,
          'confirm_password': confirmPassword,
        }));

    final data = jsonDecode(resp.body);
    if (resp.statusCode == 200 && data['success'] == true) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to change password');
  }

  Future<Map<String, dynamic>> updateProfile(String name) async {
    if (_token == null) throw Exception('Missing auth token');

    final url = Uri.parse('$baseUrl/api/update_profile.php');
    final resp = await http.post(url,
        headers: authHeaders,
        body: jsonEncode({
          'action': 'update_profile',
          'name': name,
        }));

    final data = jsonDecode(resp.body);
    if (resp.statusCode == 200 && data['success'] == true) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to update profile');
  }


  Future<List<Map<String, dynamic>>> generateQuizFromSummary(String summaryText, {int numQuestions = 6}) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    final url = Uri.parse('$baseUrl/api/generate_quiz.php');
    http.Response resp;
    try {
      resp = await http.post(
        url,
        headers: authHeaders,
        body: jsonEncode({
          'summary_text': summaryText,
          'num_questions': numQuestions,
          'model': 'gemini-2.5-flash',
        }),
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw Exception('Tiempo de espera agotado al generar quiz');
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body);
    } catch (_) {
      throw Exception('Respuesta no JSON al generar quiz');
    }

    if (resp.statusCode == 200 && data['success'] == true && data['questions'] is List) {
      final raw = (data['questions'] as List);
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    throw Exception(data['error'] ?? 'No se pudo generar el cuestionario');
  }

  Future<Map<String, dynamic>> fetchCoursesFromSummary(String summaryText) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }
    final url = Uri.parse('$baseUrl/api/get_courses.php');
    final resp = await http.post(
      url,
      headers: authHeaders,
      body: jsonEncode({ 'summary_text': summaryText }),
    );
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body);
    } catch (_) {
      throw Exception('Respuesta no JSON al obtener cursos');
    }
    if (resp.statusCode == 200 && data['success'] == true) {
      return data;
    }
    throw Exception(data['error'] ?? 'No se pudo obtener cursos');
  }

  // Nuevo: obtener cursos directamente por tema central
  /// Get or generate courses: first tries saved courses, then generates if needed
  Future<Map<String, dynamic>> getOrGenerateCourses(String tema) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }
    final url = Uri.parse('$baseUrl/api/get_or_generate_courses.php');
    final resp = await http.post(
      url,
      headers: authHeaders,
      body: jsonEncode({'tema': tema}),
    );
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body);
    } catch (_) {
      throw Exception('Respuesta no JSON al obtener cursos');
    }
    if (resp.statusCode == 200 && data['success'] == true) {
      return data;
    }
    throw Exception(data['error'] ?? 'No se pudo obtener cursos');
  }

  Future<Map<String, dynamic>> fetchCoursesByTopic(String tema) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }
    final url = Uri.parse('$baseUrl/api/get_courses.php');
    final resp = await http.post(
      url,
      headers: authHeaders,
      body: jsonEncode({'tema': tema}),
    );
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body);
    } catch (_) {
      throw Exception('Respuesta no JSON al obtener cursos');
    }
    if (resp.statusCode == 200 && data['success'] == true) {
      return data;
    }
    throw Exception(data['error'] ?? 'No se pudo obtener cursos');
  }

  Future<Map<String, dynamic>> copyDocument({required String path, String? newParentPath}) async {
    await _ensureAuth();
    if (_token == null || _token!.isEmpty) {
      throw Exception('Missing auth token');
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'default_user';

    final newRelPath = await LocalStorageService.copyDocument(
      userId,
      path,
      (newParentPath != null && newParentPath.isNotEmpty) ? newParentPath : null,
    );

    return {
      'success': true,
      'mode': 'fs',
      'fs_path': newRelPath,
      'message': 'Documento copiado localmente',
    };
  }

  /// Upload PDF to cloud directory
  Future<Map<String, dynamic>> uploadPdfToCloudDirectory({
    required int directoryId,
    required String fileName,
    required List<int> fileBytes,
  }) async {
    await _ensureAuth();
    if (_token == null) throw Exception('Missing auth token');

    final url = Uri.parse('$baseUrl/api/upload_to_share.php');
    final req = http.MultipartRequest('POST', url);
    req.headers['Authorization'] = 'Bearer $_token';
    
    // Add PDF file
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: fileName,
    ));
    
    // Add directory_id
    req.fields['directory_id'] = directoryId.toString();

    final streamed = await req.send();
    final respStr = await streamed.stream.bytesToString();
    final data = jsonDecode(respStr);

    if (streamed.statusCode == 201 && (data['success'] == true || data['document_id'] != null)) {
      return data;
    }
    throw Exception(data['error'] ?? 'Upload failed');
  }
}
