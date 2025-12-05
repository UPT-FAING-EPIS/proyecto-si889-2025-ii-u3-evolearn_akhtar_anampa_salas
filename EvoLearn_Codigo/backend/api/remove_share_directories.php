<?php
/**
 * Remove directories from share (unshare subdirectories)
 * POST /api/remove_share_directories.php
 * 
 * Body:
 * {
 *   "share_id": 123,
 *   "directory_ids": [45, 67, 89]
 * }
 * 
 * Only owner can remove directories from share
 */

declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo);

$input = json_decode(file_get_contents('php://input'), true);

$shareId = isset($input['share_id']) ? (int)$input['share_id'] : null;
$directoryIds = $input['directory_ids'] ?? null;

if ($shareId === null) {
    jsonResponse(400, ['error' => 'share_id es requerido']);
}

if (!is_array($directoryIds) || empty($directoryIds)) {
    jsonResponse(400, ['error' => 'directory_ids debe ser un array no vacío']);
}

// Verify ownership
$stmt = $pdo->prepare('
    SELECT id, owner_user_id, name, directory_root_id
    FROM directory_shares
    WHERE id = ?
');
$stmt->execute([$shareId]);
$share = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$share) {
    jsonResponse(404, ['error' => 'Share no encontrado']);
}

if ((int)$share['owner_user_id'] !== (int)$user['id']) {
    jsonResponse(403, ['error' => 'Solo el propietario puede modificar el share']);
}

try {
    $pdo->beginTransaction();

    // Verify all directories belong to this share and are not the root
    $placeholders = str_repeat('?,', count($directoryIds) - 1) . '?';
    $stmt = $pdo->prepare("
        SELECT dsn.directory_id
        FROM directory_share_nodes dsn
        WHERE dsn.share_id = ? 
          AND dsn.directory_id IN ($placeholders)
          AND dsn.directory_id != ?
    ");
    $params = array_merge([$shareId], $directoryIds, [(int)$share['directory_root_id']]);
    $stmt->execute($params);
    $validIds = $stmt->fetchAll(PDO::FETCH_COLUMN);

    if (empty($validIds)) {
        $pdo->rollBack();
        jsonResponse(400, ['error' => 'No se encontraron subdirectorios válidos para remover']);
    }

    if (count($validIds) !== count($directoryIds)) {
        $pdo->rollBack();
        jsonResponse(400, ['error' => 'Algunos directorios no pertenecen al share o incluyen el directorio raíz']);
    }

    // Remove directories from share_nodes
    $placeholders = str_repeat('?,', count($validIds) - 1) . '?';
    $stmt = $pdo->prepare("
        DELETE FROM directory_share_nodes
        WHERE share_id = ? AND directory_id IN ($placeholders)
    ");
    $stmt->execute(array_merge([$shareId], $validIds));

    $removedCount = $stmt->rowCount();

    // Log event
    $stmt = $pdo->prepare('
        INSERT INTO directory_events (share_id, directory_id, user_id, event_type, details)
        VALUES (?, ?, ?, ?, ?)
    ');
    $stmt->execute([
        $shareId,
        (int)$share['directory_root_id'],
        $user['id'],
        'directories_removed',
        json_encode([
            'removed_count' => $removedCount,
            'directory_ids' => $validIds
        ])
    ]);

    $pdo->commit();

    log_info('Directories removed from share', [
        'share_id' => $shareId,
        'directory_ids' => $validIds,
        'count' => $removedCount
    ]);

    jsonResponse(200, [
        'ok' => true,
        'removed_count' => $removedCount,
        'message' => "$removedCount " . ($removedCount === 1 ? 'directorio removido' : 'directorios removidos')
    ]);

} catch (PDOException $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    log_error('DB error removing directories from share', ['error' => $e->getMessage()]);
    jsonResponse(500, ['error' => 'Error de base de datos']);
}
