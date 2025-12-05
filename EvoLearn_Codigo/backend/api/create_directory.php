<?php
declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/db.php';
require_once '../includes/auth.php';
require_once __DIR__ . '/../includes/fs.php';
require_once __DIR__ . '/../includes/permissions.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonResponse(405, ['error' => 'Method not allowed']);

$pdo = getPDO();
$user = requireAuth($pdo);

$data = json_decode(file_get_contents('php://input'), true) ?? $_POST;
$name = trim($data['name'] ?? '');
$color = strtoupper(trim($data['color_hex'] ?? '#1565C0'));
$parentPath = normalizeRelativePath((string)($data['parent_path'] ?? $data['parent'] ?? ''));
$parentId = isset($data['parent_id']) ? (int)$data['parent_id'] : null;

if ($name === '') jsonResponse(400, ['error' => 'Nombre requerido']);
if (!preg_match('/^#[0-9A-F]{6}$/', $color)) $color = '#1565C0';

// Cloud mode: create in database with permission checks
if ($parentId !== null && $parentId > 0) {
    $stmt = $pdo->prepare('SELECT id, user_id, cloud_managed FROM directories WHERE id = ?');
    $stmt->execute([$parentId]);
    $parent = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$parent) {
        jsonResponse(404, ['error' => 'Parent directory not found']);
    }
    
    // Check permissions
    if ($parent['cloud_managed']) {
        requireDirectoryPermission($pdo, (int)$user['id'], $parentId, 'edit');
    } else {
        if ((int)$parent['user_id'] !== (int)$user['id']) {
            jsonResponse(403, ['error' => 'No tienes permisos para crear directorios aquí']);
        }
    }
    
    try {
        $pdo->beginTransaction();
        
        $ins = $pdo->prepare('INSERT INTO directories (user_id, parent_id, name, color_hex, cloud_managed) VALUES (?, ?, ?, ?, ?)');
        $ins->execute([(int)$user['id'], $parentId, $name, $color, $parent['cloud_managed'] ? 1 : 0]);
        $newId = (int)$pdo->lastInsertId();
        
        // Log event if parent is cloud-managed
        if ($parent['cloud_managed']) {
            logDirectoryEvent($pdo, (int)$user['id'], 'directory_created', null, $parentId, null, [
                'directory_name' => $name,
                'directory_id' => $newId
            ]);
        }
        
        $pdo->commit();
        
        jsonResponse(201, [
            'success' => true,
            'mode' => 'cloud',
            'directory_id' => $newId,
            'name' => $name,
            'color' => $color
        ]);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        if (str_contains($e->getMessage(), 'uniq_dir_name_per_parent')) {
            jsonResponse(409, ['error' => 'Ya existe un directorio con ese nombre']);
        }
        jsonResponse(500, ['error' => 'Database error: ' . $e->getMessage()]);
    }
}

// FS mode only - crear solo en FS
$baseAbs = absPathForUser((int)$user['id'], $parentPath);
if (!is_dir($baseAbs)) mkdir($baseAbs, 0777, true);
$targetAbs = uniqueChildPath($baseAbs, sanitizeName($name), false);
if (!mkdir($targetAbs, 0777, true)) {
    jsonResponse(500, ['error' => 'No se pudo crear la carpeta física']);
}
writeDirMeta($targetAbs, ['color' => $color]);
$rel = normalizeRelativePath(($parentPath !== '' ? ($parentPath . '/') : '') . basename($targetAbs));
jsonResponse(201, ['success' => true, 'mode' => 'fs', 'fs_path' => $rel]);