<?php
declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/db.php';
require_once '../includes/auth.php';
require_once __DIR__ . '/../includes/fs.php';
require_once __DIR__ . '/../includes/permissions.php';
require_once __DIR__ . '/../includes/locks.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonResponse(405, ['error' => 'Method not allowed']);

$pdo = getPDO();
$user = requireAuth($pdo);

$data = json_decode(file_get_contents('php://input'), true) ?? $_POST;
$summary = trim($data['summary'] ?? '');
$fileName = trim($data['file_name'] ?? '');
$documentId = isset($data['document_id']) ? (int)$data['document_id'] : null;

if ($summary === '' || $fileName === '') {
    jsonResponse(400, ['error' => 'summary y file_name son requeridos']);
}

// Cloud mode: save for cloud-managed documents
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
    
    // Save summary to FS (same location as PDF)
    $pdfRelPath = $docInfo['file_rel_path'];
    $dirRel = normalizeRelativePath(dirname($pdfRelPath));
    $dirAbs = absPathForUser((int)$user['id'], $dirRel);
    
    $summaryFileName = 'Resumen_' . sanitizeName($fileName) . '.txt';
    $summaryPath = $dirAbs . DIRECTORY_SEPARATOR . $summaryFileName;
    
    if (!@file_put_contents($summaryPath, $summary)) {
        jsonResponse(500, ['error' => 'No se pudo guardar el resumen']);
    }
    
    $summaryRelPath = normalizeRelativePath(($dirRel !== '' ? ($dirRel . '/') : '') . $summaryFileName);
    
    // Release document lock
    if ($docInfo['cloud_managed']) {
        releaseDocumentLock($pdo, $documentId, (int)$user['id']);
        
        // Log event
        logDirectoryEvent($pdo, (int)$user['id'], 'summary_updated', null, (int)$docInfo['directory_id'], $documentId, [
            'document_name' => $docInfo['display_name'],
            'summary_length' => strlen($summary)
        ]);
    }
    
    jsonResponse(200, [
        'success' => true,
        'mode' => 'cloud',
        'summary_path' => $summaryRelPath,
        'document_id' => $documentId
    ]);
}

// FS mode only
$pathRel = normalizeRelativePath((string)($data['path'] ?? ''));

if ($pathRel === '') {
    jsonResponse(400, ['error' => 'path es requerido']);
}

// Obtener la ruta del directorio padre
$dirRel = normalizeRelativePath(dirname($pathRel));
$dirAbs = absPathForUser((int)$user['id'], $dirRel);

// Crear el archivo de resumen
$summaryFileName = 'Resumen_' . sanitizeName($fileName) . '.txt';
$summaryPath = $dirAbs . DIRECTORY_SEPARATOR . $summaryFileName;

if (!@file_put_contents($summaryPath, $summary)) {
    jsonResponse(500, ['error' => 'No se pudo guardar el resumen']);
}

$summaryRelPath = normalizeRelativePath(($dirRel !== '' ? ($dirRel . '/') : '') . $summaryFileName);

jsonResponse(200, [
    'success' => true, 
    'mode' => 'fs',
    'summary_path' => $summaryRelPath
]);