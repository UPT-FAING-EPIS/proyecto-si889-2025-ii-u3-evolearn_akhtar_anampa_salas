<?php
/**
 * SIMPLE FILE DOWNLOAD - No streaming, no compression, no JSON
 * Just send the raw file bytes
 * 
 * GET /api/download.php?document_id=X&share_id=Y
 */

declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';
require_once __DIR__ . '/../includes/fs.php';
require_once __DIR__ . '/../includes/permissions.php';

try {
    $pdo = getPDO();
    // Auth with retry
    $user = null;
    for ($attempt = 1; $attempt <= 3; $attempt++) {
        try {
            $user = requireAuth($pdo, false);
            break;
        } catch (Exception $e) {
            if ($attempt < 3) sleep(1);
            else throw $e;
        }
    }
} catch (Exception $e) {
    http_response_code(401);
    exit('Unauthorized');
}

$documentId = isset($_GET['document_id']) ? (int)$_GET['document_id'] : 0;
$shareId = isset($_GET['share_id']) ? (int)$_GET['share_id'] : 0;

if ($documentId <= 0) {
    http_response_code(400);
    exit('Bad request');
}

try {
    // Get document
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
        exit('Not found');
    }

    // Check permissions
    if ($shareId > 0) {
        $stmt = $pdo->prepare('
            SELECT 1 FROM directory_shares ds
            LEFT JOIN directory_share_users dsu ON ds.id = dsu.share_id AND dsu.user_id = ?
            WHERE ds.id = ? AND (ds.owner_user_id = ? OR dsu.user_id IS NOT NULL)
        ');
        $stmt->execute([(int)$user['id'], $shareId, (int)$user['id']]);
        if (!$stmt->fetch()) {
            http_response_code(403);
            exit('Forbidden');
        }
    } else {
        if ((int)$doc['user_id'] !== (int)$user['id']) {
            http_response_code(403);
            exit('Forbidden');
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
    $mimeType = match($ext) {
        'pdf' => 'application/pdf',
        'txt' => 'text/plain; charset=utf-8',
        default => 'application/octet-stream',
    };

    // Build filename
    $fileName = $doc['display_name'];
    if (!str_ends_with($fileName, '.' . $ext)) {
        $fileName .= '.' . $ext;
    }

    // CRITICAL: Disable ALL buffering and compression
    while (ob_get_level()) ob_end_clean();
    ini_set('output_buffering', 'Off');
    ini_set('zlib.output_compression', 'Off');
    set_time_limit(0);

    // Send headers ONCE
    http_response_code(200);
    header('Content-Type: ' . $mimeType);
    header('Content-Length: ' . $fileSize);
    header('Content-Disposition: inline; filename="' . addslashes($fileName) . '"');
    header('Cache-Control: no-cache, must-revalidate');
    header('Pragma: public');
    header('Expires: 0');
    header('Connection: close');

    // CRITICAL: readfile() is the ONLY reliable way to stream in PHP
    // It reads and outputs in small chunks WITHOUT loading entire file in memory
    readfile($filePath);
    exit(0);

} catch (Exception $e) {
    http_response_code(500);
    exit('Server error');
}
