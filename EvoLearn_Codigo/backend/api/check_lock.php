<?php
/**
 * Check lock status for a resource
 * GET /api/check_lock.php?type=directory&id=123
 * or GET /api/check_lock.php?type=document&id=456
 * 
 * Returns lock information if resource is locked
 */

declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo);

$type = isset($_GET['type']) ? trim($_GET['type']) : '';
$id = isset($_GET['id']) ? (int)$_GET['id'] : 0;

if (!in_array($type, ['directory', 'document'])) {
    jsonResponse(400, ['error' => 'type debe ser directory o document']);
}

if ($id <= 0) {
    jsonResponse(400, ['error' => 'id es requerido']);
}

try {
    if ($type === 'directory') {
        $lock = getDirectoryLock($pdo, $id);
    } else {
        $lock = getDocumentLock($pdo, $id);
    }
    
    if ($lock === null) {
        jsonResponse(200, [
            'locked' => false,
            'message' => 'Recurso disponible'
        ]);
    }
    
    $isOwnLock = (int)$lock['locked_by'] === (int)$user['id'];
    
    jsonResponse(200, [
        'locked' => true,
        'is_own_lock' => $isOwnLock,
        'locked_by' => $lock['locked_by_name'],
        'locked_by_email' => $lock['locked_by_email'],
        'lock_type' => $lock['lock_type'],
        'locked_at' => $lock['locked_at'],
        'expires_at' => $lock['expires_at']
    ]);
    
} catch (Exception $e) {
    log_error('Error checking lock', ['error' => $e->getMessage(), 'type' => $type, 'id' => $id]);
    jsonResponse(500, ['error' => 'Error al verificar estado de bloqueo']);
}
