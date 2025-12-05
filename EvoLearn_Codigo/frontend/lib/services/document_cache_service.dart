import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Service for downloading and caching documents (PDFs, TXTs)
/// Strategy: Cache-First + Direct Streaming (NO base64 due to PHP server limitations)
/// - Step 1: Check cache (instant access, no network needed)
/// - Step 2: Stream download directly (respects Content-Length, handles chunking)
///
/// WHY: PHP dev server has hard limits on response size (~2-4KB) that break base64.
/// Base64 takes 813KB file → 1.05MB JSON → truncated by server.
/// Direct streaming is more reliable and transparent to the client.
class DocumentCacheService {
  static const String _documentsCacheDirName = 'documents_cache';
  static const Duration _downloadTimeout =
      Duration(seconds: 60); // Increased timeout
  static const int _maxRetries = 3; // Retry on connection closed

  /// Get the cache directory for documents
  static Future<Directory> getCacheDir() async {
    final cacheDir = await getTemporaryDirectory();
    final docCacheDir = Directory('${cacheDir.path}/$_documentsCacheDirName');

    if (!await docCacheDir.exists()) {
      await docCacheDir.create(recursive: true);
    }

    return docCacheDir;
  }

  /// Download and cache document
  /// 1. Check cache first (instant if exists)
  /// 2. Stream download with progress tracking
  /// 3. Save to cache for future use
  static Future<File> downloadAndCacheDocument({
    required String url,
    required String documentId,
    required String fileName,
    required String? authToken,
    Function(double)? onProgress, // 0.0 to 1.0
  }) async {
    // Debug: log basic info about the requested download
    debugPrint('📄 [DocumentCache] Requesting download');
    debugPrint('📄 [DocumentCache]  URL: $url');
    debugPrint('📄 [DocumentCache]  documentId: $documentId');
    debugPrint('📄 [DocumentCache]  fileName: $fileName');
    debugPrint(
        '📄 [DocumentCache]  hasToken: ${authToken != null && authToken.isNotEmpty}');

    final cacheDir = await getCacheDir();
    final fileExtension = fileName.split('.').last;
    final cachedFile =
        File('${cacheDir.path}/doc_${documentId}.$fileExtension');

    // ✅ STEP 1: CACHE-FIRST - Use cached file if available
    if (await cachedFile.exists()) {
      final fileSize = await cachedFile.length();
      debugPrint('✅ Usando caché ($fileSize bytes)');
      onProgress?.call(1.0);
      return cachedFile;
    }

    debugPrint('📥 Descargando documento...');
    final tempFile = File('${cacheDir.path}/doc_${documentId}.tmp');

    // ✅ STEP 2: STREAM DOWNLOAD WITH RETRIES
    Exception? lastError;
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        debugPrint('🔗 GET $url (intento $attempt/$_maxRetries)');

        // Clean up any partial download from previous attempt
        if (await tempFile.exists()) {
          await tempFile.delete();
        }

        final success = await _downloadViaStreaming(
          url: url,
          authToken: authToken,
          tempFile: tempFile,
          onProgress: onProgress,
        );

        if (success) {
          // Save to cache
          final fileSizeAfter = await tempFile.length();
          if (fileSizeAfter > 0) {
            try {
              await tempFile.rename(cachedFile.path);
              debugPrint('✅ En caché: $fileSizeAfter bytes');
            } catch (e) {
              debugPrint('⚠️  Caché: $e');
            }
            onProgress?.call(1.0);
            return await cachedFile.exists() ? cachedFile : tempFile;
          }
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('❌ Descarga (intento $attempt): $e');

        // Only retry on connection errors, not on 404 or auth errors
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('404') ||
            errorStr.contains('401') ||
            errorStr.contains('403') ||
            errorStr.contains('no encontrado')) {
          debugPrint('🔴 Error no recuperable, no se reintentará');
          break;
        }

        if (attempt < _maxRetries) {
          // Wait before retry with exponential backoff
          final delay = Duration(seconds: attempt * 2);
          debugPrint('⏳ Esperando ${delay.inSeconds}s antes de reintentar...');
          await Future.delayed(delay);
        }
      }
    }

    // Clean up failed temp file
    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }

    throw lastError ??
        Exception('No se pudo descargar después de $_maxRetries intentos\n\n'
            'Intenta nuevamente');
  }

  /// Stream download directly (no base64 encoding)
  /// This is the most reliable method for PHP dev server
  static Future<bool> _downloadViaStreaming({
    required String url,
    required String? authToken,
    required File tempFile,
    required Function(double)? onProgress,
  }) async {
    try {
      final headers = <String, String>{};
      if (authToken != null && authToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      // Debug: log headers (without exposing full token)
      debugPrint('🌐 [DocumentCache] Starting streaming download');
      debugPrint('🌐 [DocumentCache]  URL: $url');
      debugPrint(
          '🌐 [DocumentCache]  Auth header present: ${headers.containsKey('Authorization')}');

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(headers);
      request.headers['Connection'] = 'keep-alive';

      final streamedResponse = await client.send(request).timeout(
            _downloadTimeout,
            onTimeout: () => throw TimeoutException(
                'Connection timeout after $_downloadTimeout', _downloadTimeout),
          );

      debugPrint(
          '📊 [DocumentCache] Status: ${streamedResponse.statusCode}, Size: ${streamedResponse.contentLength}');

      if (streamedResponse.statusCode == 200) {
        final contentLength = streamedResponse.contentLength ?? 0;
        int receivedBytes = 0;

        final ioSink = tempFile.openWrite();

        try {
          debugPrint('⬇️  Descargando $contentLength bytes...');

          await for (var chunk in streamedResponse.stream) {
            if (chunk.isEmpty) continue;

            ioSink.add(chunk);
            receivedBytes += chunk.length;

            if (contentLength > 0) {
              final progress = (receivedBytes / contentLength).clamp(0.0, 1.0);
              onProgress?.call(progress);
            }
          }

          await ioSink.flush();
          await ioSink.close();

          debugPrint(
              '✅ [DocumentCache] Descarga completada: $receivedBytes bytes');

          // Verify we got all bytes
          if (contentLength > 0 && receivedBytes < contentLength) {
            final percentage =
                ((receivedBytes / contentLength) * 100).toStringAsFixed(1);
            throw Exception(
                'Descarga incompleta: $receivedBytes/$contentLength ($percentage%)');
          }

          return true; // Success
        } catch (e) {
          await ioSink.close();
          rethrow;
        }
      } else if (streamedResponse.statusCode == 401 ||
          streamedResponse.statusCode == 403) {
        throw Exception(
            'Sin autorización (HTTP ${streamedResponse.statusCode})');
      } else if (streamedResponse.statusCode == 404) {
        throw Exception('Archivo no encontrado (HTTP 404)');
      } else {
        throw Exception('Error HTTP ${streamedResponse.statusCode}');
      }
    } catch (e) {
      debugPrint('🔴 [DocumentCache] Stream error: $e');
      rethrow;
    }
  }

  /// Get cached document file
  static Future<File?> getCachedDocument({
    required String documentId,
    required String fileExtension,
  }) async {
    final cacheDir = await getCacheDir();
    final cachedFile =
        File('${cacheDir.path}/doc_${documentId}.$fileExtension');

    if (await cachedFile.exists()) {
      return cachedFile;
    }
    return null;
  }

  /// Clear all cached documents
  static Future<void> clearCache() async {
    final cacheDir = await getCacheDir();
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  }

  /// Get cache size in bytes
  static Future<int> getCacheSize() async {
    final cacheDir = await getCacheDir();
    int totalSize = 0;

    if (await cacheDir.exists()) {
      final files = cacheDir.listSync(recursive: true);
      for (final file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }
    }

    return totalSize;
  }
}
