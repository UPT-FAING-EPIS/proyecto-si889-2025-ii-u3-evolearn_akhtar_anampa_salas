<?php
/**
 * Get document content (PDF or summary) for cloud-managed documents
 * GET /api/get_document_content.php?document_id=X&type=pdf|summary
 * 
 * Supports both FS and cloud-managed documents
 * Returns file content with proper headers
 */

declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';
require_once __DIR__ . '/../includes/fs.php';
require_once __DIR__ . '/../includes/permissions.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    exit('Method not allowed');
}

try {
    $pdo = getPDO();
} catch (Exception $e) {
    error_log('[get_document_content] Database connection error: ' . $e->getMessage());
    http_response_code(500);
    exit('Error de conexión a la base de datos');
}

try {
    $user = requireAuth($pdo, false);
} catch (Exception $e) {
    error_log('[get_document_content] Auth error: ' . $e->getMessage());
    http_response_code(401);
    exit('No autorizado');
}

$documentId = isset($_GET['document_id']) ? (int)$_GET['document_id'] : 0;
$shareId = isset($_GET['share_id']) ? (int)$_GET['share_id'] : 0;
$type = isset($_GET['type']) ? trim($_GET['type']) : 'pdf';
$fsPath = isset($_GET['fs_path']) ? normalizeRelativePath(trim($_GET['fs_path'])) : '';

// LOGGING
error_log('[get_document_content] documentId=' . $documentId . ', shareId=' . $shareId . ', type=' . $type . ', fsPath=' . $fsPath);

// Cloud mode: get by document_id and optional share_id
if ($documentId > 0) {
    $stmt = $pdo->prepare('
        SELECT 
            d.id,
            d.user_id,
            d.directory_id,
            d.display_name,
            d.file_rel_path,
            d.mime_type,
            dir.cloud_managed
        FROM documents d
        LEFT JOIN directories dir ON d.directory_id = dir.id
        WHERE d.id = ?
    ');
    $stmt->execute([$documentId]);
    $doc = $stmt->fetch(PDO::FETCH_ASSOC);
    
    error_log('[get_document_content] doc found: ' . json_encode($doc));
    
    if (!$doc) {
        error_log('[get_document_content] Document not found: ' . $documentId);
        http_response_code(404);
        exit('Document not found');
    }
    
    // If share_id provided, verify access to share
    if ($shareId > 0) {
        $shareStmt = $pdo->prepare('
            SELECT ds.id FROM directory_shares ds
            LEFT JOIN directory_share_users dsu ON ds.id = dsu.share_id AND dsu.user_id = ?
            WHERE ds.id = ? AND (ds.owner_user_id = ? OR dsu.user_id IS NOT NULL)
        ');
        $shareStmt->execute([(int)$user['id'], $shareId, (int)$user['id']]);
        if (!$shareStmt->fetch()) {
            http_response_code(403);
            exit('No tienes acceso a este share');
        }
    }
    
    // Check permissions
    if ($doc['cloud_managed']) {
        try {
            requireDocumentPermission($pdo, (int)$user['id'], $documentId);
        } catch (Exception $e) {
            http_response_code(403);
            exit('No tienes permisos para ver este documento');
        }
    } else {
        if ((int)$doc['user_id'] !== (int)$user['id']) {
            http_response_code(403);
            exit('No tienes permisos para ver este documento');
        }
    }
    
    // Determine file path and content type
    $fileRelPath = $doc['file_rel_path'];
    if (empty($fileRelPath)) {
        error_log('[get_document_content] file_rel_path is empty for document ' . $documentId);
        http_response_code(404);
        exit('Ruta de archivo no disponible');
    }
    
    // HOTFIX: Remove user prefix if it exists (for backward compatibility with old data)
    // Old format: uploads/11/file.pdf -> should be: file.pdf or Redes/Lab1/file.pdf
    $userPrefix = 'uploads/' . (int)$user['id'] . '/';
    if (strpos($fileRelPath, $userPrefix) === 0) {
        $fileRelPath = substr($fileRelPath, strlen($userPrefix));
        error_log('[get_document_content] Removed user prefix from path. New path: ' . $fileRelPath);
    }
    
    $filePath = absPathForUser((int)$user['id'], $fileRelPath);
    error_log('[get_document_content] fileRelPath=' . $fileRelPath . ', filePath=' . $filePath);
    
    // Determine content type from mime_type or file extension
    $mimeType = $doc['mime_type'] ?? '';
    if (in_array($mimeType, ['application/pdf', 'text/plain'])) {
        $contentType = $mimeType;
        // Ensure text files have charset specification
        if ($mimeType === 'text/plain' && strpos($mimeType, 'charset') === false) {
            $contentType = 'text/plain; charset=utf-8';
        }
    } else {
        $ext = strtolower(pathinfo($filePath, PATHINFO_EXTENSION));
        if ($ext === 'pdf') {
            $contentType = 'application/pdf';
        } elseif ($ext === 'txt') {
            $contentType = 'text/plain; charset=utf-8';
        } else {
            error_log('[get_document_content] Unsupported file type: ' . $ext);
            http_response_code(400);
            exit('Tipo de archivo no soportado');
        }
    }
    
    $fileName = $doc['display_name'];
    if (!str_ends_with($fileName, '.pdf') && !str_ends_with($fileName, '.txt')) {
        $ext = strtolower(pathinfo($filePath, PATHINFO_EXTENSION));
        $fileName .= '.' . $ext;
    }
    
} elseif ($fsPath !== '') {
    // FS mode: direct file access
    $filePath = absPathForUser((int)$user['id'], $fsPath);
    error_log('[get_document_content] FS mode: fsPath=' . $fsPath . ', filePath=' . $filePath);
    
    $ext = strtolower(pathinfo($filePath, PATHINFO_EXTENSION));
    if ($ext === 'pdf') {
        $contentType = 'application/pdf';
    } elseif ($ext === 'txt') {
        $contentType = 'text/plain; charset=utf-8';
    } else {
        error_log('[get_document_content] Unsupported file type in FS mode: ' . $ext);
        http_response_code(400);
        exit('Tipo de archivo no soportado');
    }
    
    $fileName = basename($filePath);
} else {
    error_log('[get_document_content] No documentId or fsPath provided');
    http_response_code(400);
    exit('document_id o fs_path es requerido');
}

// Check file exists
if (!is_file($filePath)) {
    error_log('[get_document_content] File not found: ' . $filePath . ' (exists: ' . file_exists($filePath) . ', is_file: ' . is_file($filePath) . ')');
    http_response_code(404);
    exit('Archivo no encontrado: ' . $filePath);
}

error_log('[get_document_content] Serving file: ' . $filePath);

// Serve file with better error handling
header('Content-Type: ' . $contentType);
header('Content-Disposition: inline; filename="' . $fileName . '"');
$fileSize = filesize($filePath);
header('Content-Length: ' . $fileSize);
header('Cache-Control: no-cache, must-revalidate, max-age=0');
header('Pragma: public');
header('Expires: 0');
header('Accept-Ranges: bytes');

// IMPORTANT: Disable any compression that might corrupt binary data
header('Content-Encoding: identity');
header('Content-Transfer-Encoding: binary');

// CRITICAL: Connection headers to keep connection alive
header('Connection: keep-alive');
header('Keep-Alive: timeout=600, max=100');

// Flush headers immediately
if (function_exists('apache_setenv')) {
    @apache_setenv('no-gzip', '1');
}
@ini_set('zlib.output_compression', '0');

// Disable output buffering to prevent memory issues
while (ob_get_level()) {
    ob_end_flush();
}

// Increase limits for large files
set_time_limit(600);  // 10 minutes for large files
ini_set('max_execution_time', '600');
ignore_user_abort(false);

// Log file size for debugging
error_log('[get_document_content] Starting to stream file: ' . $filePath . ' (' . $fileSize . ' bytes)');

// Open file and stream
$handle = fopen($filePath, 'rb');
if ($handle === false) {
    error_log('[get_document_content] Failed to open file: ' . $filePath);
    http_response_code(500);
    exit('No se pudo abrir el archivo');
}

$bytesRead = 0;
$totalBytes = 0;
$chunkSize = 65536; // 64KB chunks for better performance

try {
    while (!feof($handle) && !connection_aborted()) {
        $chunk = fread($handle, $chunkSize);
        if ($chunk === false) {
            error_log('[get_document_content] Error reading chunk from: ' . $filePath);
            break;
        }
        
        $chunkLen = strlen($chunk);
        if ($chunkLen > 0) {
            echo $chunk;
            $totalBytes += $chunkLen;
            
            // Flush output to send data immediately
            if (ob_get_level() > 0) {
                @ob_flush();
            }
            @flush();
            
            // Log progress for debugging (every 256KB)
            if ($totalBytes % 262144 === 0) {
                error_log('[get_document_content] Streamed ' . $totalBytes . ' bytes of ' . $fileSize . ' (' . round($totalBytes / $fileSize * 100, 1) . '%)');
            }
        }
    }
    
    // Final status
    if (connection_aborted()) {
        error_log('[get_document_content] Connection aborted by client after ' . $totalBytes . ' bytes');
    } else {
        error_log('[get_document_content] Completed streaming ' . $totalBytes . ' bytes for file: ' . $filePath);
    }
} catch (Exception $e) {
    error_log('[get_document_content] Exception during streaming: ' . $e->getMessage());
} finally {
    @fclose($handle);
}

exit;
