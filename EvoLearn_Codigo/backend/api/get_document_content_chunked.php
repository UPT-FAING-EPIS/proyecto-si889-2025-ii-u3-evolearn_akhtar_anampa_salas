<?php
/**
 * Alternative download endpoint with better streaming for large files
 * GET /api/get_document_content_chunked.php?document_id=X&share_id=Y
 * 
 * Uses optimized streaming for reliability with large files
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
    error_log('[get_document_content_chunked] Database connection error: ' . $e->getMessage());
    http_response_code(500);
    exit('Error de conexión a la base de datos');
}

try {
    $user = requireAuth($pdo, false);
} catch (Exception $e) {
    error_log('[get_document_content_chunked] Auth error: ' . $e->getMessage());
    http_response_code(401);
    exit('No autorizado');
}

$documentId = isset($_GET['document_id']) ? (int)$_GET['document_id'] : 0;
$shareId = isset($_GET['share_id']) ? (int)$_GET['share_id'] : 0;

if ($documentId <= 0) {
    http_response_code(400);
    exit('document_id requerido');
}

// Get document info
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

if (!$doc) {
    http_response_code(404);
    exit('Document not found');
}

// Verify permissions
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

if ($doc['cloud_managed']) {
    try {
        requireDocumentPermission($pdo, (int)$user['id'], $documentId);
    } catch (Exception $e) {
        http_response_code(403);
        exit('No tienes permisos');
    }
} else {
    if ((int)$doc['user_id'] !== (int)$user['id']) {
        http_response_code(403);
        exit('No tienes permisos');
    }
}

// Get file path
$fileRelPath = $doc['file_rel_path'];
$userPrefix = 'uploads/' . (int)$user['id'] . '/';
if (strpos($fileRelPath, $userPrefix) === 0) {
    $fileRelPath = substr($fileRelPath, strlen($userPrefix));
}

$filePath = absPathForUser((int)$user['id'], $fileRelPath);

if (!is_file($filePath)) {
    http_response_code(404);
    exit('Archivo no encontrado');
}

$fileSize = filesize($filePath);
$ext = strtolower(pathinfo($filePath, PATHINFO_EXTENSION));

if ($ext === 'pdf') {
    $contentType = 'application/pdf';
} elseif ($ext === 'txt') {
    $contentType = 'text/plain; charset=utf-8';
} else {
    $contentType = 'application/octet-stream';
}

$fileName = $doc['display_name'];
if (!str_ends_with($fileName, '.' . $ext)) {
    $fileName .= '.' . $ext;
}

// CRITICAL: Send headers in correct order
header('Content-Type: ' . $contentType);
header('Content-Disposition: inline; filename="' . $fileName . '"');
header('Content-Length: ' . $fileSize);
header('Cache-Control: no-cache, must-revalidate, max-age=0, private');
header('Pragma: public');
header('Expires: 0');
header('Accept-Ranges: bytes');
header('Connection: keep-alive');
header('Keep-Alive: timeout=600, max=100');

// Disable compression
ini_set('zlib.output_compression', 'Off');
header('Content-Encoding: identity');

// Clear any buffering
while (ob_get_level()) {
    ob_end_clean();
}

// Disable automatic buffering
ini_set('output_buffering', 'Off');
ini_set('default_socket_timeout', '600');

// Increase limits
set_time_limit(0);
ignore_user_abort(false);

error_log('[get_document_content_chunked] Starting download: ' . $fileName . ' (' . $fileSize . ' bytes)');

// Stream file
$handle = fopen($filePath, 'rb');
if (!$handle) {
    error_log('[get_document_content_chunked] Failed to open: ' . $filePath);
    http_response_code(500);
    exit('Error abriendo archivo');
}

$bytesRead = 0;
$chunkSize = 16384; // 16KB chunks for more stability

try {
    while (!feof($handle) && !connection_aborted() && $bytesRead < $fileSize) {
        $chunk = fread($handle, $chunkSize);
        
        if ($chunk === false || $chunk === '') {
            break;
        }
        
        echo $chunk;
        $bytesRead += strlen($chunk);
        
        // Force output to socket immediately
        flush();
        
        if ($bytesRead % 163840 === 0) { // Every 160KB
            error_log('[chunked] Sent ' . $bytesRead . ' / ' . $fileSize . ' bytes');
        }
    }
    
    error_log('[get_document_content_chunked] Completed: ' . $bytesRead . ' / ' . $fileSize . ' bytes');
} catch (Exception $e) {
    error_log('[get_document_content_chunked] Exception: ' . $e->getMessage());
} finally {
    fclose($handle);
}

exit(0);
