<?php
declare(strict_types=1);
require_once 'cors.php';
require_once __DIR__ . '/../includes/db.php';
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/logger.php';
require_once __DIR__ . '/../vendor/autoload.php'; // smalot/pdfparser
require_once __DIR__ . '/../includes/fs.php';
require_once __DIR__ . '/../includes/permissions.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo);

// Check if uploading to a specific directory (cloud mode)
$directoryId = isset($_POST['directory_id']) ? (int)$_POST['directory_id'] : null;
if ($directoryId !== null && $directoryId > 0) {
    // Verify directory exists and check permissions
    $stmt = $pdo->prepare('SELECT id, user_id, cloud_managed FROM directories WHERE id = ?');
    $stmt->execute([$directoryId]);
    $dir = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$dir) {
        jsonResponse(404, ['error' => 'Directory not found']);
    }
    
    // Check permissions
    if ($dir['cloud_managed']) {
        requireDirectoryPermission($pdo, (int)$user['id'], $directoryId, 'edit');
    } else {
        if ((int)$dir['user_id'] !== (int)$user['id']) {
            jsonResponse(403, ['error' => 'No tienes permisos para subir archivos a este directorio']);
        }
    }
}

// Leer ruta relativa (FS mode only)
$relativePath = normalizeRelativePath((string)($_POST['relative_path'] ?? ''));

// Validate upload
if (!isset($_FILES['pdf'])) {
    jsonResponse(400, ['error' => 'Missing file field "pdf"']);
}

$file = $_FILES['pdf'];
if ($file['error'] !== UPLOAD_ERR_OK) {
    $errorMessages = [
        UPLOAD_ERR_INI_SIZE => 'El archivo excede el tamaño máximo permitido por el servidor',
        UPLOAD_ERR_FORM_SIZE => 'El archivo excede el tamaño máximo permitido',
        UPLOAD_ERR_PARTIAL => 'El archivo se subió parcialmente',
        UPLOAD_ERR_NO_FILE => 'No se seleccionó ningún archivo',
        UPLOAD_ERR_NO_TMP_DIR => 'Falta el directorio temporal',
        UPLOAD_ERR_CANT_WRITE => 'Error al escribir el archivo en disco',
        UPLOAD_ERR_EXTENSION => 'Una extensión PHP detuvo la subida del archivo',
    ];
    $errorMsg = $errorMessages[$file['error']] ?? 'Error desconocido al subir el archivo';
    jsonResponse(400, ['error' => $errorMsg, 'code' => $file['error']]);
}

// Validar tamaño del archivo (máximo 50MB)
$maxFileSize = 50 * 1024 * 1024; // 50MB
if ($file['size'] > $maxFileSize) {
    jsonResponse(413, ['error' => 'El archivo PDF es demasiado grande. Máximo permitido: 50MB']);
}

$finfo = finfo_open(FILEINFO_MIME_TYPE);
$mime = finfo_file($finfo, $file['tmp_name']);
finfo_close($finfo);
if ($mime !== 'application/pdf') {
    jsonResponse(400, ['error' => 'Only PDF files are allowed', 'mime' => $mime]);
}

$uploadDir = __DIR__ . DIRECTORY_SEPARATOR . '..' . DIRECTORY_SEPARATOR . 'uploads';
if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0777, true);
}
$originalName = basename($file['name']);
$storedName = sprintf('%s_%s.pdf', date('YmdHis'), bin2hex(random_bytes(6)));
$targetPath = $uploadDir . DIRECTORY_SEPARATOR . $storedName;
if (!move_uploaded_file($file['tmp_name'], $targetPath)) {
    jsonResponse(500, ['error' => 'Failed to store file']);
}

// Parse PDF text (solo para preview, no se usa para resumen)
try {
    $parser = new \Smalot\PdfParser\Parser();
    $pdf = $parser->parseFile($targetPath);
    $text = $pdf->getText();
    // Limitar a 40k para preview (el resumen se genera desde el archivo completo)
    $text = mb_substr($text, 0, 40000, 'UTF-8');
} catch (Throwable $e) {
    // No fallar la subida si el parsing falla, solo no tendremos preview
    $text = '';
    log_error('PDF parsing failed during upload', ['file' => $originalName, 'error' => $e->getMessage()]);
}

// Guardar copia física bajo el root del usuario (FS mode)
$displayName = $originalName;
$baseRel = $relativePath;
$baseAbs = absPathForUser((int)$user['id'], $baseRel);
if (!is_dir($baseAbs)) mkdir($baseAbs, 0777, true);
$fsCopyAbs = uniqueChildPath($baseAbs, sanitizeName(pathinfo($displayName, PATHINFO_FILENAME)), true, '.pdf');
@copy($targetPath, $fsCopyAbs);
$fsCopyRel = normalizeRelativePath(($baseRel !== '' ? ($baseRel . '/') : '') . basename($fsCopyAbs));

// Save to database if uploading to cloud directory
$documentId = null;
if ($directoryId !== null && $dir['cloud_managed']) {
    try {
        $pdo->beginTransaction();
        
        $insertDoc = $pdo->prepare('
            INSERT INTO documents (user_id, directory_id, original_filename, display_name, stored_filename, file_rel_path, mime_type, size_bytes, text_content, model_used)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ');
        $insertDoc->execute([
            (int)$user['id'],
            $directoryId,
            $originalName,
            $originalName,
            $storedName,
            $fsCopyRel,
            'application/pdf',
            $file['size'],
            $text,
            'llama3'
        ]);
        $documentId = (int)$pdo->lastInsertId();
        
        // Log event
        logDirectoryEvent($pdo, (int)$user['id'], 'document_uploaded', null, $directoryId, $documentId, [
            'document_name' => $originalName,
            'file_size' => $file['size']
        ]);
        
        $pdo->commit();
    } catch (Exception $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        jsonResponse(500, ['error' => 'Failed to save document to database: ' . $e->getMessage()]);
    }
}

jsonResponse(200, [
    'success' => true,
    'document_id' => $documentId,
    'mode' => $directoryId ? 'cloud' : 'fs',
    'fs_path' => $fsCopyRel,
    'ai_preview' => ['text_length' => strlen($text)]
]);