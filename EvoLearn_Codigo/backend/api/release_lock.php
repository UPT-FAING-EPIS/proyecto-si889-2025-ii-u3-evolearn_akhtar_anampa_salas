<?php
/**
 * Release a lock manually
 * POST /api/release_lock.php
 * Body: { "type": "directory", "id": 123 }
 * 
 * Allows user to release their own locks
 */

declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';
require_once __DIR__ . '/../includes/locks.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo);

$data = json_decode(file_get_contents('php://input'), true) ?? $_POST;
$type = isset($data['type']) ? trim($data['type']) : '';
$id = isset($data['id']) ? (int)$data['id'] : 0;

if (!in_array($type, ['directory', 'document'])) {
    jsonResponse(400, ['error' => 'type debe ser directory o document']);
}

if ($id <= 0) {
    jsonResponse(400, ['error' => 'id es requerido']);
}

try {
    if ($type === 'directory') {
        $released = releaseDirectoryLock($pdo, $id, (int)$user['id']);
    } else {
        $released = releaseDocumentLock($pdo, $id, (int)$user['id']);
    }
    
    if ($released) {
        jsonResponse(200, [
            'success' => true,
            'message' => 'Bloqueo liberado exitosamente'
        ]);
    } else {
        jsonResponse(404, [
            'error' => 'No se encontró un bloqueo activo para este recurso'
        ]);
    }
    
} catch (Exception $e) {
    log_error('Error releasing lock', ['error' => $e->getMessage(), 'type' => $type, 'id' => $id]);
    jsonResponse(500, ['error' => 'Error al liberar bloqueo']);
}
