<?php
/**
 * Direct file download - bypass PHP streaming, use web server's native capabilities
 * GET /api/get_document_direct.php?document_id=X&share_id=Y
 * 
 * Strategy: Verify auth, then use X-Sendfile (Apache/Nginx) or direct readfile
 * Avoids PHP dev server streaming limitations
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
    // Retry auth
    $user = null;
    for ($attempt = 1; $attempt <= 3; $attempt++) {
        try {
            $user = requireAuth($pdo, false);
            break;
        } catch (Exception $e) {
            error_log("[direct] Auth attempt $attempt/3 failed");
            if ($attempt < 3) sleep(1);
            else throw $e;
        }
    }
} catch (Exception $e) {
    error_log('[get_document_direct] Auth error: ' . $e->getMessage());
    http_response_code(401);
    exit('Not authorized');
}

$documentId = isset($_GET['document_id']) ? (int)$_GET['document_id'] : 0;
$shareId = isset($_GET['share_id']) ? (int)$_GET['share_id'] : 0;

if ($documentId <= 0) {
    http_response_code(400);
    exit('document_id required');
}

try {
    // Get document info
    $stmt = $pdo->prepare('
        SELECT d.id, d.user_id, d.directory_id, d.display_name, d.file_rel_path, d.mime_type, dir.cloud_managed
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
            exit('No access to share');
        }
    }

    if ($doc['cloud_managed']) {
        try {
            requireDocumentPermission($pdo, (int)$user['id'], $documentId);
        } catch (Exception $e) {
            http_response_code(403);
            exit('No permissions');
        }
    } else {
        if ((int)$doc['user_id'] !== (int)$user['id']) {
            http_response_code(403);
            exit('No permissions');
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
        exit('File not found');
    }

    $fileSize = filesize($filePath);
    $ext = strtolower(pathinfo($filePath, PATHINFO_EXTENSION));

    // Determine MIME type
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

    // Clear any buffering
    while (ob_get_level()) {
        ob_end_clean();
    }

    // Send headers
    http_response_code(200);
    header('Content-Type: ' . $contentType);
    header('Content-Disposition: inline; filename="' . addslashes($fileName) . '"');
    header('Content-Length: ' . $fileSize);
    header('Cache-Control: no-cache, must-revalidate, max-age=0, private');
    header('Pragma: public');
    header('Expires: 0');
    header('Accept-Ranges: bytes');
    header('Connection: close');

    // Disable compression and buffering
    ini_set('zlib.output_compression', 'Off');
    header('Content-Encoding: identity');
    ini_set('output_buffering', 'Off');
    set_time_limit(0);
    ignore_user_abort(false);

    error_log("[direct] Starting download: $fileName ($fileSize bytes)");

    // Use readfile with chunking to handle large files
    // readfile respects output_buffering = Off and streams directly
    $chunkSize = 8192;
    $handle = fopen($filePath, 'rb');
    
    if ($handle) {
        while (!feof($handle) && !connection_aborted()) {
            $chunk = fread($handle, $chunkSize);
            if ($chunk === false || $chunk === '') break;
            
            echo $chunk;
            flush();
        }
        fclose($handle);
        error_log("[direct] Completed: $fileSize bytes");
    } else {
        error_log("[direct] Failed to open file");
        http_response_code(500);
        exit('Error opening file');
    }

} catch (Exception $e) {
    error_log('[get_document_direct] Exception: ' . $e->getMessage());
    http_response_code(500);
    exit('Server error');
}

exit(0);
