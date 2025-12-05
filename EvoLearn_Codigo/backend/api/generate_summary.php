<?php
declare(strict_types=1);
require_once 'cors.php';
require_once __DIR__ . '/../includes/bootstrap.php';
require_once __DIR__ . '/../includes/locks.php';

// === IMMEDIATE LOGGING FOR DIAGNOSIS ===
$diagLog = __DIR__ . '/../logs/generate_summary_diag.log';
$timestamp = date('Y-m-d H:i:s');
$method = $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN';
$authHeader = $_SERVER['HTTP_AUTHORIZATION'] ?? 'MISSING';
$contentType = $_SERVER['CONTENT_TYPE'] ?? 'UNKNOWN';
error_log("[$timestamp] [generate_summary] METHOD=$method AUTH=$authHeader CONTENT_TYPE=$contentType");
@file_put_contents($diagLog, "[$timestamp] METHOD=$method AUTH=$authHeader CONTENT_TYPE=$contentType\n", FILE_APPEND);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error_log('[generate_summary] Rejecting non-POST request');
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
try {
    $user = requireAuth($pdo);
    @file_put_contents($diagLog, "[$timestamp] Auth OK, user_id={$user['id']}\n", FILE_APPEND);
} catch (Throwable $authErr) {
    error_log('[generate_summary] AUTH FAILED: ' . $authErr->getMessage());
    @file_put_contents($diagLog, "[$timestamp] Auth FAILED: {$authErr->getMessage()}\n", FILE_APPEND);
    throw $authErr;
}

// Debugging: log incoming headers and uploaded files to help diagnose
error_log('[generate_summary] Incoming headers: ' . print_r(getallheaders(), true));
error_log('[generate_summary] _FILES: ' . print_r($_FILES, true));
error_log('[generate_summary] _POST: ' . print_r($_POST, true));
// Log raw input length (may be large for multipart, but helps diagnosis)
$raw = @file_get_contents('php://input');
error_log('[generate_summary] raw input length: ' . ($raw !== false ? strlen($raw) : 'n/a'));

// Parse incoming data (both multipart and JSON)
$data = json_decode($raw, true) ?? $_POST ?? [];
$documentId = isset($data['document_id']) ? (int)$data['document_id'] : null;
$analysisType = (string)($data['analysis_type'] ?? 'summary_fast');
$clientModel = trim((string)($data['model'] ?? ''));

error_log('[generate_summary] parsed $data: ' . json_encode($data));
error_log('[generate_summary] documentId=' . ($documentId ?? 'NULL'));

// --- CLOUD MODE: Receive document_id and analysis type ---
$pdfFile = null;
$originalFileName = null;
$processingDir = null;
$storedFilePath = null;

if ($documentId !== null && $documentId > 0) {
    error_log('[generate_summary] CLOUD MODE: document_id=' . $documentId);
    // Skip file validation - this is cloud mode with document_id
} else {
    error_log('[generate_summary] FS MODE: no document_id, checking for PDF file');
    // --- FS MODE: Require PDF file upload ---
    $pdfFile = $_FILES['pdf'] ?? null;
    if (!$pdfFile) {
        error_log('[generate_summary] ERROR: No PDF file found');
        jsonResponse(400, ['error' => 'Se requiere un archivo PDF en el campo "pdf" o un document_id.']);
    }

    // If there was an upload error, return a helpful message and log the code
    if (!isset($pdfFile['error']) || $pdfFile['error'] !== UPLOAD_ERR_OK) {
        $errCode = isset($pdfFile['error']) ? (int)$pdfFile['error'] : -1;
        $errorMessages = [
            UPLOAD_ERR_INI_SIZE => 'El archivo excede upload_max_filesize en php.ini.',
            UPLOAD_ERR_FORM_SIZE => 'El archivo excede MAX_FILE_SIZE en el formulario HTML.',
            UPLOAD_ERR_PARTIAL => 'El archivo se subió parcialmente.',
            UPLOAD_ERR_NO_FILE => 'No se seleccionó ningún archivo.',
            UPLOAD_ERR_NO_TMP_DIR => 'Falta el directorio temporal en el servidor.',
            UPLOAD_ERR_CANT_WRITE => 'Error al escribir el archivo en disco.',
            UPLOAD_ERR_EXTENSION => 'Una extensión PHP detuvo la subida del archivo.',
        ];
        $msg = $errorMessages[$errCode] ?? 'Error desconocido al subir el archivo.';
        log_error('Upload validation failed', ['error_code' => $errCode, 'msg' => $msg, 'file_info' => $pdfFile]);
        // If the error is INI_SIZE or FORM_SIZE, return 413 Payload Too Large
        if (in_array($errCode, [UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE], true)) {
            jsonResponse(413, ['error' => $msg, 'code' => $errCode]);
        }
        jsonResponse(400, ['error' => $msg, 'code' => $errCode]);
    }

    // Validar tamaño del archivo (máximo 50MB)
    $maxFileSize = 50 * 1024 * 1024;
    if ($pdfFile['size'] > $maxFileSize) {
        log_error('PDF file too large', ['file' => $pdfFile['name'], 'size' => $pdfFile['size'], 'max' => $maxFileSize]);
        jsonResponse(413, ['error' => 'El archivo PDF es demasiado grande. Máximo permitido: 50MB.']);
    }
    
    // FS mode setup
    $originalFileName = $pdfFile['name'];
        $processingDir = __DIR__ . DIRECTORY_SEPARATOR . '..' . DIRECTORY_SEPARATOR . 'uploads' . DIRECTORY_SEPARATOR . 'processing_queue';
    if (!is_dir($processingDir)) {
        if (!mkdir($processingDir, 0777, true)) {
            log_error('Failed to create processing directory', ['path' => $processingDir]);
            jsonResponse(500, ['error' => 'Error interno del servidor al preparar el archivo para el análisis.']);
        }
    }
}

$pathRel = normalizeRelativePath((string)($data['path'] ?? ''));

// Fix: If pathRel includes the filename (common from frontend), extract just the directory part
// Frontend may send "folder/subfolder/file.pdf" when it should send just "folder/subfolder"
if ($pathRel && $originalFileName && basename($pathRel) === $originalFileName) {
    // pathRel ends with the same filename, remove it
    $pathRel = dirname($pathRel);
    if ($pathRel === '.') {
        $pathRel = ''; // Root directory
    }
}

// Cloud mode: check permissions and acquire lock
if ($documentId !== null && $documentId > 0) {
    $docStmt = $pdo->prepare('
        SELECT d.id, d.user_id, d.directory_id, d.display_name, d.file_rel_path, dir.cloud_managed
        FROM documents d
        LEFT JOIN directories dir ON d.directory_id = dir.id
        WHERE d.id = ?
    ');
    $docStmt->execute([$documentId]);
    $docInfo = $docStmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$docInfo) {
        jsonResponse(404, ['error' => 'Documento no encontrado']);
    }
    
    // Check permissions
    if ($docInfo['cloud_managed']) {
        try {
            requireDocumentPermission($pdo, (int)$user['id'], $documentId);
        } catch (Throwable $permErr) {
            error_log('[generate_summary] Permission denied: ' . $permErr->getMessage());
            jsonResponse(403, ['error' => 'No tienes permisos para generar resumen de este documento']);
        }
        
        // Try to acquire lock for summarizing, but don't fail if lock table doesn't exist
        try {
            requireDocumentLock($pdo, $documentId, (int)$user['id'], 'summarizing');
        } catch (Throwable $lockErr) {
            error_log('[generate_summary] Lock error (continuing anyway): ' . $lockErr->getMessage());
            // Continue without lock - lock tables might not exist
        }
    } else {
        if ((int)$docInfo['user_id'] !== (int)$user['id']) {
            jsonResponse(403, ['error' => 'No tienes permisos para generar resumen de este documento']);
        }
    }
    
    $fullRelPath = $docInfo['file_rel_path'];
} else {
    // FS mode
    $fullRelPath = ($pathRel ? $pathRel . '/' : '') . $originalFileName;
}

// --- Strong dedup: reuse existing job for same user + file_rel_path + analysis_type ---
try {
    $stmt = $pdo->prepare(
        "SELECT id FROM summary_jobs WHERE user_id = ? AND file_rel_path = ? AND analysis_type = ? AND status IN ('pending','processing') ORDER BY id DESC LIMIT 1"
    );
    $stmt->execute([$user['id'], $fullRelPath, $analysisType]);
    $existing = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($existing && isset($existing['id'])) {
        // Reuse the existing job and do not enqueue a new file
        jsonResponse(202, [
            'success' => true,
            'message' => 'La tarea ya existe. Reutilizando job en curso.',
            'job_id' => (int)$existing['id'],
        ]);
    }
} catch (Throwable $e) {
    log_error('Dedup lookup failed', ['error' => $e->getMessage(), 'file_rel_path' => $fullRelPath]);
}

// --- Short-window rate limit (if still too many different requests) ---
try {
    $stmt = $pdo->prepare(
        "SELECT id FROM summary_jobs WHERE user_id = ? AND status IN ('pending','processing') AND created_at >= (NOW() - INTERVAL 5 SECOND) ORDER BY id DESC LIMIT 1"
    );
    $stmt->execute([$user['id']]);
    $recent = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($recent && isset($recent['id'])) {
        jsonResponse(429, [
            'error' => 'Demasiadas solicitudes de análisis. Intenta nuevamente en unos segundos.',
            'existing_job_id' => (int)$recent['id'],
        ]);
    }
} catch (Throwable $e) {
    log_error('Rate-limit check failed', ['error' => $e->getMessage()]);
}

// FS MODE: Move uploaded file to processing queue ---
if (isset($pdfFile)) {
    $storedFileName = sprintf('%s_%s.pdf', date('YmdHis'), bin2hex(random_bytes(8)));
    $storedFilePath = $processingDir . '/' . $storedFileName;

    if (!move_uploaded_file($pdfFile['tmp_name'], $storedFilePath)) {
        log_error('Failed to move uploaded file to processing queue', ['tmp' => $pdfFile['tmp_name'], 'dest' => $storedFilePath]);
        jsonResponse(500, ['error' => 'Error interno del servidor al guardar el archivo.']);
    }
} else {
    // Cloud mode - file is already in database, use file_rel_path as file_path
    $storedFilePath = $fullRelPath;
}

// --- Crear el Job en la base de datos ---
// Prefer modelos 2.5 en API v1; si el cliente no especifica o pide 1.5, forzar 2.5
if ($clientModel === '' || preg_match('/^gemini-1\.5/', $clientModel)) {
    $model = ($analysisType === 'summary_detailed') ? 'gemini-2.5-pro' : 'gemini-2.5-flash';
} else {
    $model = $clientModel;
}

// Usamos el path relativo para el job, que combina el path de la app y el nombre del archivo original

try {
    $diagLog = __DIR__ . '/../logs/generate_summary_diag.log';
    $timestamp = date('Y-m-d H:i:s');
    @file_put_contents($diagLog, "[$timestamp] About to INSERT job: user_id={$user['id']}, file_rel_path=$fullRelPath, analysis_type=$analysisType\n", FILE_APPEND);
    
    $stmt = $pdo->prepare(
        'INSERT INTO summary_jobs (user_id, file_path, file_rel_path, analysis_type, model, status) VALUES (?, ?, ?, ?, ?, ?)'
    );
    $stmt->execute([$user['id'], $storedFilePath, $fullRelPath, $analysisType, $model, 'pending']);
    $jobId = $pdo->lastInsertId();
    
    @file_put_contents($diagLog, "[$timestamp] INSERT SUCCESS, job_id=$jobId\n", FILE_APPEND);
} catch (Throwable $e) {
    log_error('Failed to create summary job in DB', ['error' => $e->getMessage()]);
    $diagLog = __DIR__ . '/../logs/generate_summary_diag.log';
    @file_put_contents($diagLog, "[" . date('Y-m-d H:i:s') . "] INSERT FAILED: {$e->getMessage()}\n", FILE_APPEND);
    // Si falla la BD, eliminar el archivo que movimos (FS mode only)
    if ($storedFilePath && is_file($storedFilePath)) {
        @unlink($storedFilePath);
    }
    jsonResponse(500, ['error' => 'Error interno del servidor al crear la tarea de análisis.']);
}

log_info('Summary job created', ['job_id' => $jobId, 'user_id' => $user['id'], 'file' => $fullRelPath]);

// --- Procesar el job en background sin bloquear la respuesta ---
$backendPath = __DIR__ . '/..';
$workerScript = $backendPath . '/cron/process_summaries.php';

// Usar proceso no-bloqueante para procesar el job
if (strtoupper(substr(PHP_OS, 0, 3)) === 'WIN') {
    // Windows
    $cmd = "start /B php \"$workerScript\" > nul 2>&1";
    pclose(popen($cmd, 'r'));
} else {
    // Linux/Mac
    $cmd = "php \"$workerScript\" > /dev/null 2>&1 &";
    shell_exec($cmd);
}

// --- Responder con el ID del Job ---
jsonResponse(202, [
    'success' => true,
    'message' => 'La tarea de análisis ha sido aceptada. Consulta el estado usando el job_id.',
    'job_id' => (int)$jobId,
]);
