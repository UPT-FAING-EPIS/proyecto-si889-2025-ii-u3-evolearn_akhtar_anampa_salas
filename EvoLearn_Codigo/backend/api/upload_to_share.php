<?php
/**
 * Upload a PDF or TXT file directly to a share directory
 * POST /api/upload_to_share.php
 * 
 * Multipart form data:
 * - file: The PDF or TXT file to upload
 * - directory_id: Target directory ID (must be part of a share)
 * 
 * Response: { success: true, document_id: N, display_name: "...", file_rel_path: "..." }
 */

declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';
require_once __DIR__ . '/../includes/fs.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit('Method not allowed');
}

$pdo = getPDO();
$user = requireAuth($pdo);

$directoryId = isset($_POST['directory_id']) ? (int)$_POST['directory_id'] : 0;

error_log('[upload_to_share] directoryId=' . $directoryId . ', userId=' . $user['id']);

if ($directoryId <= 0) {
    http_response_code(400);
    exit('directory_id es requerido');
}

// Verify directory exists
$dirStmt = $pdo->prepare('SELECT id, user_id FROM directories WHERE id = ?');
$dirStmt->execute([$directoryId]);
$dir = $dirStmt->fetch(PDO::FETCH_ASSOC);

if (!$dir) {
    http_response_code(404);
    exit('Directorio no encontrado');
}

// Check if user has access - simpler approach: user is owner of a share that contains this dir
// OR the directory user_id matches (they own it)
$accessStmt = $pdo->prepare('
    SELECT 1 FROM (
        SELECT ds.id
        FROM directory_shares ds
        WHERE (ds.owner_user_id = ? OR ds.id IN (
            SELECT share_id FROM directory_share_users WHERE user_id = ?
        ))
        AND (
            ds.directory_root_id = ?
            OR ds.directory_root_id IN (
                WITH RECURSIVE parents AS (
                    SELECT id, parent_id FROM directories WHERE id = ?
                    UNION ALL
                    SELECT d.id, d.parent_id FROM directories d
                    JOIN parents p ON d.id = p.parent_id
                )
                SELECT id FROM parents
            )
        )
    ) tmp
');
$accessStmt->execute([(int)$user['id'], (int)$user['id'], $directoryId, $directoryId]);
$hasAccess = $accessStmt->fetch(PDO::FETCH_ASSOC);

if (!$hasAccess) {
    error_log('[upload_to_share] Access DENIED. userId=' . $user['id'] . ' dirId=' . $directoryId);
    http_response_code(403);
    exit('No tienes acceso a este directorio');
}

error_log('[upload_to_share] Access GRANTED');

// Check file upload
if (!isset($_FILES['file']) || $_FILES['file']['error'] != UPLOAD_ERR_OK) {
    error_log('[upload_to_share] File upload error: ' . (isset($_FILES['file']) ? $_FILES['file']['error'] : 'no file'));
    http_response_code(400);
    exit('No se proporciono archivo o hubo error en la carga');
}

$uploadedFile = $_FILES['file'];
$fileName = $uploadedFile['name'];
$tmpPath = $uploadedFile['tmp_name'];

error_log('[upload_to_share] File uploaded: ' . $fileName);

// Validate file type
$ext = strtolower(pathinfo($fileName, PATHINFO_EXTENSION));
if (!in_array($ext, array('pdf', 'txt'))) {
    http_response_code(400);
    exit('Solo se permiten archivos PDF y TXT');
}

// Sanitize filename - remove problematic characters for MySQL UTF-8
try {
    $baseName = pathinfo($fileName, PATHINFO_FILENAME);
    // Remove characters that can cause MySQL encoding issues
    $baseName = preg_replace('/[^\p{L}\p{N}\s_\-\.]/u', '', $baseName);
    // Also remove control characters and non-UTF8
    $baseName = preg_replace('/[\x00-\x1F\x7F]/u', '', $baseName);
    $baseName = mb_convert_encoding($baseName, 'UTF-8', 'UTF-8');
    $sanitizedName = sanitizeName($baseName);
    if (empty($sanitizedName)) {
        $sanitizedName = 'documento_' . time();
    }
    $finalFileName = $sanitizedName . '.' . $ext;
} catch (Throwable $e) {
    error_log('[upload_to_share] Filename sanitization failed: ' . $e->getMessage());
    // Fallback to a generic name
    $finalFileName = 'documento_' . time() . '.' . $ext;
}

error_log('[upload_to_share] Sanitized filename: ' . $finalFileName);

try {
    // Read file content
    $fileBytes = file_get_contents($tmpPath);
    if ($fileBytes === false) {
        throw new Exception('No se pudo leer el archivo temporal');
    }

    $fileSize = strlen($fileBytes);
    $displayName = pathinfo($finalFileName, PATHINFO_FILENAME);

    // Extract text content - sanitize for MySQL UTF-8
    $textContent = '';
    if ($ext === 'pdf') {
        try {
            require_once __DIR__ . '/../vendor/autoload.php';
            $parser = new \Smalot\PdfParser\Parser();
            $pdf = $parser->parseFile($tmpPath);
            $textContent = $pdf->getText();
            // Sanitize text content for MySQL
            $textContent = mb_convert_encoding($textContent, 'UTF-8', 'UTF-8');
            $textContent = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $textContent);
        } catch (Throwable $e) {
            error_log('[upload_to_share] PDF parsing failed: ' . $e->getMessage());
            $textContent = '';
        }
    } else {
        // For TXT files, read as-is but sanitize
        $textContent = $fileBytes;
        $textContent = mb_convert_encoding($textContent, 'UTF-8', 'UTF-8');
        $textContent = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $textContent);
    }

    // Determine file_rel_path - get directory path from tree
    // Build path by traversing up the tree
    $pathParts = array();
    $currentId = $directoryId;
    
    while ($currentId !== null) {
        $stmt = $pdo->prepare('SELECT id, parent_id, name FROM directories WHERE id = ?');
        $stmt->execute([$currentId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) break;
        
        array_unshift($pathParts, $row['name']); // Add to beginning
        $currentId = $row['parent_id'];
    }
    
    $dirPath = implode('/', $pathParts);
    error_log('[upload_to_share] Built dirPath by traversal: ' . $dirPath);

    $fileRelPath = $dirPath ? ($dirPath . '/' . $finalFileName) : $finalFileName;

    error_log('[upload_to_share] file_rel_path=' . $fileRelPath);

    // Insert document into database
    $docStmt = $pdo->prepare('
        INSERT INTO documents (
            user_id,
            directory_id,
            original_filename,
            display_name,
            stored_filename,
            file_rel_path,
            mime_type,
            size_bytes,
            text_content
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ');

    $mimeType = $ext === 'pdf' ? 'application/pdf' : 'text/plain';
    $docStmt->execute(array(
        (int)$user['id'],
        $directoryId,
        $fileName,
        $displayName,
        $finalFileName,
        $fileRelPath,
        $mimeType,
        $fileSize,
        $textContent
    ));

    $documentId = (int)$pdo->lastInsertId();

    error_log('[upload_to_share] Document inserted: id=' . $documentId);

    // Save actual file to filesystem
    $absDir = absPathForUser((int)$user['id'], $dirPath);
    if (!is_dir($absDir)) {
        mkdir($absDir, 0777, true);
    }

    $absPath = $absDir . DIRECTORY_SEPARATOR . $finalFileName;
    file_put_contents($absPath, $fileBytes);

    error_log('[upload_to_share] File saved to: ' . $absPath);

    http_response_code(201);
    echo json_encode(array(
        'success' => true,
        'document_id' => $documentId,
        'display_name' => $displayName,
        'file_rel_path' => $fileRelPath,
        'file_name' => $finalFileName,
        'size' => $fileSize,
        'message' => 'Archivo subido correctamente'
    ));

} catch (Throwable $e) {
    error_log('[upload_to_share] Error: ' . $e->getMessage());
    http_response_code(500);
    exit('Error al procesar archivo: ' . $e->getMessage());
}
