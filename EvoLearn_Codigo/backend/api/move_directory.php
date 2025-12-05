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
$isVip = isVip($pdo, $user);

$data = json_decode(file_get_contents('php://input'), true) ?? $_POST;

// FS-only branch (always use FS mode now since VIP is removed)
$pathRel = normalizeRelativePath((string)($data['path'] ?? ''));
$newParentRel = normalizeRelativePath((string)($data['new_parent_path'] ?? ''));

// Validar que se proporcione el path
if ($pathRel === '') {
    jsonResponse(400, ['error' => 'Se requiere el path de la carpeta a mover']);
}

if ($pathRel !== '') {
    $srcAbs = absPathForUser((int)$user['id'], $pathRel);
    if (!is_dir($srcAbs)) {
        jsonResponse(404, ['error' => 'Carpeta no encontrada']);
    }
    
    // Para la raíz, newParentRel será string vacío, lo cual es válido
    $destParentAbs = absPathForUser((int)$user['id'], $newParentRel);
    
    // Asegurar que el directorio padre destino existe (si es raíz, ya existe)
    if (!is_dir($destParentAbs)) {
        if (!mkdir($destParentAbs, 0777, true)) {
            jsonResponse(500, ['error' => 'No se pudo crear el directorio destino']);
        }
    }
    
    // Verificar que no se está intentando mover dentro de sí mismo
    $srcName = basename($srcAbs);
    $destPath = $newParentRel !== '' ? ($newParentRel . '/' . $srcName) : $srcName;
    if ($destPath === $pathRel) {
        jsonResponse(400, ['error' => 'No puedes mover la carpeta a su misma ubicación']);
    }
    
    // Verificar que no se está intentando mover dentro de un subdirectorio
    if ($newParentRel !== '' && strpos($newParentRel, $pathRel) === 0) {
        jsonResponse(400, ['error' => 'No puedes mover una carpeta dentro de sí misma o de sus subcarpetas']);
    }
    
    $targetAbs = uniqueChildPath($destParentAbs, $srcName, false);
    if (!@rename($srcAbs, $targetAbs)) {
        jsonResponse(500, ['error' => 'No se pudo mover la carpeta. Verifica permisos.']);
    }
    
    $finalRel = normalizeRelativePath(($newParentRel !== '' ? ($newParentRel . '/') : '') . basename($targetAbs));
    jsonResponse(200, ['success' => true, 'mode' => 'fs', 'fs_path' => $finalRel]);
}

// VIP: DB + FS espejo
$id = (int)($data['id'] ?? 0);
$newParent = isset($data['new_parent_id']) ? (int)$data['new_parent_id'] : null;

if ($id <= 0) jsonResponse(400, ['error' => 'id requerido']);
$dir = $pdo->prepare('SELECT id, user_id, parent_id, name, cloud_managed FROM directories WHERE id = ?');
$dir->execute([$id]);
$src = $dir->fetch();
if (!$src) jsonResponse(404, ['error' => 'Directorio no encontrado']);

// Check permissions on source
if ($src['cloud_managed']) {
    requireDirectoryPermission($pdo, (int)$user['id'], $id, 'edit');
    // Acquire lock for moving
    requireDirectoryLock($pdo, $id, (int)$user['id'], 'moving');
} else {
    if ((int)$src['user_id'] !== (int)$user['id']) {
        jsonResponse(403, ['error' => 'No tienes permisos sobre este directorio']);
    }
}

if ($newParent !== null) {
    if ($newParent === $id) jsonResponse(400, ['error' => 'No puedes mover un directorio dentro de sí mismo']);
    $chk = $pdo->prepare('SELECT id, user_id, cloud_managed FROM directories WHERE id = ?');
    $chk->execute([$newParent]);
    $parent = $chk->fetch();
    if (!$parent) jsonResponse(400, ['error' => 'new_parent_id inválido']);
    
    // Check permissions on target
    if ($parent['cloud_managed']) {
        requireDirectoryPermission($pdo, (int)$user['id'], $newParent, 'edit');
    } else {
        if ((int)$parent['user_id'] !== (int)$user['id']) {
            jsonResponse(403, ['error' => 'No tienes permisos sobre el directorio destino']);
        }
    }
}

try {
    $pdo->beginTransaction();
    
    $upd = $pdo->prepare('UPDATE directories SET parent_id = ? WHERE id = ?');
    $upd->execute([$newParent, $id]);
    
    // Log event if cloud-managed
    if ($src['cloud_managed'] || ($newParent && $parent['cloud_managed'])) {
        logDirectoryEvent($pdo, (int)$user['id'], 'directory_moved', null, $newParent, null, [
            'directory_name' => $src['name'],
            'from_parent_id' => $src['parent_id']
        ]);
    }
    
    $pdo->commit();
    
    // Release lock
    if ($src['cloud_managed']) {
        releaseDirectoryLock($pdo, $id, (int)$user['id']);
    }
} catch (PDOException $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    jsonResponse(500, ['error' => 'Database error: ' . $e->getMessage()]);
}

// mover FS espejo
$oldParentRel = dbRelativePathFromId($pdo, (int)$user['id'], (int)$src['parent_id']);
$srcAbs = absPathForUser((int)$user['id'], normalizeRelativePath(($oldParentRel !== '' ? ($oldParentRel . '/') : '') . sanitizeName((string)$src['name'])));
$newParentRel = dbRelativePathFromId($pdo, (int)$user['id'], $newParent);
$destParentAbs = absPathForUser((int)$user['id'], $newParentRel);
if (!is_dir($destParentAbs)) mkdir($destParentAbs, 0777, true);
$targetAbs = $destParentAbs . DIRECTORY_SEPARATOR . sanitizeName((string)$src['name']);
if (is_dir($srcAbs)) @rename($srcAbs, $targetAbs);
$finalRel = normalizeRelativePath(($newParentRel !== '' ? ($newParentRel . '/') : '') . basename($targetAbs));
jsonResponse(200, ['success' => true, 'mode' => 'vip', 'fs_path' => $finalRel]);