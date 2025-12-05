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
$docId = isset($data['document_id']) ? (int)$data['document_id'] : 0;

// Database mode (cloud-managed documents)
if ($docId > 0) {
    $stmt = $pdo->prepare('
        SELECT d.id, d.user_id, d.directory_id, d.display_name, dir.cloud_managed
        FROM documents d
        LEFT JOIN directories dir ON d.directory_id = dir.id
        WHERE d.id = ?
    ');
    $stmt->execute([$docId]);
    $doc = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$doc) jsonResponse(404, ['error' => 'Documento no encontrado']);
    
    // Check permissions
    if ($doc['cloud_managed']) {
        try {
            requireDocumentPermission($pdo, (int)$user['id'], $docId);
        } catch (Throwable $e) {
            error_log('[delete_document] Permission error: ' . $e->getMessage());
            jsonResponse(403, ['error' => 'No tienes permisos sobre este documento']);
        }
        // Try to acquire lock, but don't fail if lock system has issues
        try {
            requireDocumentLock($pdo, $docId, (int)$user['id'], 'editing');
        } catch (Throwable $e) {
            error_log('[delete_document] Lock error (continuing): ' . $e->getMessage());
            // Continue without lock
        }
    } else {
        if ((int)$doc['user_id'] !== (int)$user['id']) {
            jsonResponse(403, ['error' => 'No tienes permisos sobre este documento']);
        }
    }
    
    try {
        $pdo->beginTransaction();
        
        // Log event if cloud-managed
        if ($doc['cloud_managed']) {
            logDirectoryEvent($pdo, (int)$user['id'], 'document_deleted', null, (int)$doc['directory_id'], $docId, [
                'document_name' => $doc['display_name']
            ]);
        }
        
        $del = $pdo->prepare('DELETE FROM documents WHERE id = ?');
        $del->execute([$docId]);
        
        $pdo->commit();
        
        jsonResponse(200, ['success' => true, 'mode' => 'cloud']);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        jsonResponse(500, ['error' => 'Database error: ' . $e->getMessage()]);
    }
}

// FS mode: aceptar 'path' o 'summary_path' (compatibilidad)
$pathRel = normalizeRelativePath((string)($data['path'] ?? $data['summary_path'] ?? ''));
if ($pathRel === '') jsonResponse(400, ['error' => 'Path o document_id requerido']);

$abs = absPathForUser((int)$user['id'], $pathRel);
if (!is_file($abs)) jsonResponse(404, ['error' => 'Documento no encontrado']);

@unlink($abs);

// Si es un archivo de resumen, eliminar también su JSON de cursos
$fileName = basename($pathRel);
if (str_starts_with($fileName, 'Resumen_') && str_ends_with($fileName, '.txt')) {
    $courseFileName = substr($fileName, 0, -4) . '.cursos.json';
    $courseAbs = dirname($abs) . DIRECTORY_SEPARATOR . $courseFileName;
    if (is_file($courseAbs)) @unlink($courseAbs);
}

jsonResponse(200, ['success' => true, 'mode' => 'fs']);
