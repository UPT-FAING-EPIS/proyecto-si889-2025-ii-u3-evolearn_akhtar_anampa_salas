<?php
declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo);
$data = json_decode(file_get_contents('php://input'), true) ?? $_POST;

$shareId = (int)($data['share_id'] ?? 0);

if ($shareId <= 0) {
    jsonResponse(400, ['error' => 'share_id requerido']);
}

// Verificar que el share existe y el usuario es el owner
$stmt = $pdo->prepare('SELECT id, name, owner_user_id FROM directory_shares WHERE id = ?');
$stmt->execute([$shareId]);
$share = $stmt->fetch();

if (!$share) {
    jsonResponse(404, ['error' => 'Share no encontrado']);
}

if ((int)$share['owner_user_id'] !== (int)$user['id']) {
    jsonResponse(403, ['error' => 'Solo el propietario puede desmigrar el share']);
}

try {
    $pdo->beginTransaction();

    // 1. Get root directory from share
    $stmt = $pdo->prepare('SELECT directory_root_id FROM directory_shares WHERE id = ?');
    $stmt->execute([$shareId]);
    $rootDirId = $stmt->fetchColumn();

    if (!$rootDirId) {
        throw new Exception('No se encontró el directorio raíz del share');
    }

    // 2. Get all cloud directories in this share (starting from root)
    $stmt = $pdo->prepare('
        SELECT d.id, d.parent_id, d.name, d.color_hex, d.user_id
        FROM directories d
        WHERE d.id = ? AND d.cloud_managed = 1
    ');
    $stmt->execute([$rootDirId]);
    $rootDir = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$rootDir) {
        throw new Exception('El directorio raíz no existe o no es cloud');
    }

    // Map cloud directory IDs to new FS directory IDs
    $dirMapping = [];
    $dirsToProcess = [$rootDir];
    $processedDirs = [];

    // Function to recursively get children
    $getChildren = function($parentId) use ($pdo) {
        $stmt = $pdo->prepare('
            SELECT id, parent_id, name, color_hex, user_id
            FROM directories
            WHERE parent_id = ? AND cloud_managed = 1
        ');
        $stmt->execute([$parentId]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    };

    // Process directories in hierarchical order
    while (!empty($dirsToProcess)) {
        $dir = array_shift($dirsToProcess);
        
        // Determine parent FS ID
        $parentFsId = null;
        if ($dir['parent_id']) {
            $parentFsId = $dirMapping[$dir['parent_id']] ?? null;
        }

        // Create FS directory
        $insertDir = $pdo->prepare('
            INSERT INTO directories (user_id, parent_id, name, color_hex, cloud_managed)
            VALUES (?, ?, ?, ?, 0)
        ');
        $insertDir->execute([
            $user['id'],
            $parentFsId,
            $dir['name'],
            $dir['color_hex']
        ]);
        $newFsId = (int)$pdo->lastInsertId();
        $dirMapping[$dir['id']] = $newFsId;
        $processedDirs[] = $dir['id'];

        // Copy documents from cloud dir to FS dir
        $docStmt = $pdo->prepare('
            SELECT id, display_name, original_filename, file_path, size_bytes, summary_text, summary_date
            FROM documents
            WHERE directory_id = ?
        ');
        $docStmt->execute([$dir['id']]);
        $docs = $docStmt->fetchAll(PDO::FETCH_ASSOC);

        foreach ($docs as $doc) {
            $insertDoc = $pdo->prepare('
                INSERT INTO documents (
                    directory_id, display_name, original_filename, 
                    file_path, size_bytes, summary_text, summary_date
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ');
            $insertDoc->execute([
                $newFsId,
                $doc['display_name'],
                $doc['original_filename'],
                $doc['file_path'],
                $doc['size_bytes'],
                $doc['summary_text'],
                $doc['summary_date']
            ]);
        }

        // Add children to process queue
        $children = $getChildren($dir['id']);
        foreach ($children as $child) {
            $dirsToProcess[] = $child;
        }
    }

    // 3. Delete cloud directories and their documents (in reverse order to handle foreign keys)
    foreach (array_reverse($processedDirs) as $cloudDirId) {
        // Delete documents first
        $delDocs = $pdo->prepare('DELETE FROM documents WHERE directory_id = ?');
        $delDocs->execute([$cloudDirId]);
        
        // Delete directory
        $delDir = $pdo->prepare('DELETE FROM directories WHERE id = ?');
        $delDir->execute([$cloudDirId]);
    }

    // 4. Delete all users from share
    $delUsers = $pdo->prepare('DELETE FROM directory_share_users WHERE share_id = ?');
    $delUsers->execute([$shareId]);

    // 5. Delete share events
    $delEvents = $pdo->prepare('DELETE FROM directory_events WHERE share_id = ?');
    $delEvents->execute([$shareId]);

    // 6. Delete share locks
    $delLocks = $pdo->prepare('DELETE FROM directory_locks WHERE share_id = ?');
    $delLocks->execute([$shareId]);

    // 7. Delete share nodes
    $delNodes = $pdo->prepare('DELETE FROM directory_share_nodes WHERE share_id = ?');
    $delNodes->execute([$shareId]);

    // 8. Delete the share itself
    $delShare = $pdo->prepare('DELETE FROM directory_shares WHERE id = ?');
    $delShare->execute([$shareId]);

    $pdo->commit();

    jsonResponse(200, [
        'success' => true,
        'message' => 'Share convertido a local. Todos los archivos fueron copiados al sistema de archivos local y el share fue eliminado de la base de datos.',
        'share_id' => $shareId,
        'directories_copied' => count($dirMapping),
    ]);

} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    
    // Log error for debugging
    log_error('Error al convertir share a local', [
        'share_id' => $shareId,
        'user_id' => $user['id'],
        'error' => $e->getMessage(),
        'trace' => $e->getTraceAsString()
    ]);
    
    jsonResponse(500, [
        'error' => 'Error al convertir share a local',
        'details' => $e->getMessage()
    ]);
}
