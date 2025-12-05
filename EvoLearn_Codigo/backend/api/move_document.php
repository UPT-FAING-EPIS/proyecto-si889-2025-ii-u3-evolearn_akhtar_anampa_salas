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

error_log('[move_document] Received data: ' . json_encode($data));

// Check if this is a cloud-managed document move (document_id provided)
$docId = isset($data['document_id']) ? (int)$data['document_id'] : 0;
$targetDir = isset($data['target_directory_id']) ? (int)$data['target_directory_id'] : null;

// If document_id is provided, use cloud mode
if ($docId > 0) {
    error_log('[move_document] Cloud mode: docId=' . $docId . ', targetDir=' . ($targetDir ?? 'null'));
    
    $doc = $pdo->prepare('
        SELECT d.id, d.user_id, d.directory_id, d.display_name, d.file_rel_path, dir.cloud_managed
        FROM documents d
        LEFT JOIN directories dir ON d.directory_id = dir.id
        WHERE d.id = ?
    ');
    $doc->execute([$docId]);
    $d = $doc->fetch(PDO::FETCH_ASSOC);
    
    if (!$d) {
        jsonResponse(404, ['error' => 'Documento no encontrado']);
    }

    // Check permissions on source
    if ($d['cloud_managed']) {
        try {
            requireDocumentPermission($pdo, (int)$user['id'], $docId);
        } catch (Throwable $e) {
            error_log('[move_document] Permission error: ' . $e->getMessage());
            jsonResponse(403, ['error' => 'No tienes permisos sobre este documento']);
        }
    } else {
        if ((int)$d['user_id'] !== (int)$user['id']) {
            jsonResponse(403, ['error' => 'No tienes permisos sobre este documento']);
        }
    }

    // Check permissions on target directory
    $dir = null;
    if ($targetDir !== null) {
        $chk = $pdo->prepare('SELECT id, user_id, name, cloud_managed FROM directories WHERE id = ?');
        $chk->execute([$targetDir]);
        $dir = $chk->fetch(PDO::FETCH_ASSOC);
        if (!$dir) {
            jsonResponse(400, ['error' => 'target_directory_id inválido']);
        }
        
        if ($dir['cloud_managed']) {
            try {
                requireDirectoryPermission($pdo, (int)$user['id'], $targetDir, 'edit');
            } catch (Throwable $e) {
                error_log('[move_document] Target directory permission error: ' . $e->getMessage());
                jsonResponse(403, ['error' => 'No tienes permisos sobre el directorio destino']);
            }
        } else {
            if ((int)$dir['user_id'] !== (int)$user['id']) {
                jsonResponse(403, ['error' => 'No tienes permisos sobre el directorio destino']);
            }
        }
    }

    try {
        $pdo->beginTransaction();
        
        // Build new file_rel_path
        $newParentPath = '';
        if ($targetDir !== null) {
            $newParentPath = dbRelativePathFromId($pdo, (int)$user['id'], $targetDir);
        }
        $fileName = basename($d['file_rel_path']);
        $newFileRelPath = $newParentPath !== '' ? ($newParentPath . '/' . $fileName) : $fileName;
        
        $upd = $pdo->prepare('UPDATE documents SET directory_id = ?, file_rel_path = ? WHERE id = ?');
        $upd->execute([$targetDir, $newFileRelPath, $docId]);
        
        // Log event if cloud-managed
        if ($d['cloud_managed'] || ($dir && $dir['cloud_managed'])) {
            logDirectoryEvent($pdo, (int)$user['id'], 'document_moved', null, $targetDir, $docId, [
                'document_name' => $d['display_name'],
                'from_directory_id' => $d['directory_id']
            ]);
        }
        
        $pdo->commit();
        
        // Also move the physical file
        $oldAbs = absPathForUser((int)$user['id'], $d['file_rel_path']);
        $newParentAbs = absPathForUser((int)$user['id'], $newParentPath);
        
        if (!is_dir($newParentAbs)) {
            mkdir($newParentAbs, 0777, true);
        }
        
        $targetAbs = $newParentAbs . DIRECTORY_SEPARATOR . $fileName;
        if (is_file($oldAbs) && $oldAbs !== $targetAbs) {
            @rename($oldAbs, $targetAbs);
        }
        
        jsonResponse(200, ['success' => true, 'mode' => 'cloud', 'file_rel_path' => $newFileRelPath]);
        
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('[move_document] Database error: ' . $e->getMessage());
        jsonResponse(500, ['error' => 'Database error: ' . $e->getMessage()]);
    }
}

// FS-only branch (path provided instead of document_id)
$pathRel = normalizeRelativePath((string)($data['path'] ?? ''));
$newParentRel = normalizeRelativePath((string)($data['new_parent_path'] ?? ''));

// Validar que se proporcione el path para modo FS
if ($pathRel === '') {
    jsonResponse(400, ['error' => 'Se requiere document_id o path del documento a mover']);
}

$abs = absPathForUser((int)$user['id'], $pathRel);
if (!is_file($abs)) {
    jsonResponse(404, ['error' => 'Documento no encontrado']);
}

// Para la raíz, newParentRel será string vacío, lo cual es válido
$destParentAbs = absPathForUser((int)$user['id'], $newParentRel);

// Asegurar que el directorio padre destino existe (si es raíz, ya existe)
if (!is_dir($destParentAbs)) {
    if (!mkdir($destParentAbs, 0777, true)) {
        jsonResponse(500, ['error' => 'No se pudo crear el directorio destino']);
    }
}

// Verificar que no se está intentando mover a la misma ubicación
$fileName = basename($abs);
$destPath = $newParentRel !== '' ? ($newParentRel . '/' . $fileName) : $fileName;
if ($destPath === $pathRel) {
    jsonResponse(400, ['error' => 'El documento ya está en esa ubicación']);
}

$ext = '.' . strtolower(pathinfo($abs, PATHINFO_EXTENSION));
$base = basename($abs, $ext);
$targetAbs = uniqueChildPath($destParentAbs, $base, true, $ext);

if (!@rename($abs, $targetAbs)) {
    jsonResponse(500, ['error' => 'No se pudo mover el documento. Verifica permisos.']);
}

$finalRel = normalizeRelativePath(($newParentRel !== '' ? ($newParentRel . '/') : '') . basename($targetAbs));
jsonResponse(200, ['success' => true, 'mode' => 'fs', 'fs_path' => $finalRel]);
