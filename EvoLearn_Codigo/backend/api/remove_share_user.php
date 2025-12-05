<?php
/**
 * Remove user from share
 * POST /api/remove_share_user.php
 * 
 * Body:
 * {
 *   "share_id": 123,
 *   "user_id": 45
 * }
 * 
 * Only owner can remove users
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
$targetUserId = isset($input['user_id']) ? (int)$input['user_id'] : null;

if ($shareId === null) {
    jsonResponse(400, ['error' => 'share_id es requerido']);
}

if ($targetUserId === null) {
    jsonResponse(400, ['error' => 'user_id es requerido']);
}

// Verify ownership
$stmt = $pdo->prepare('
    SELECT id, owner_user_id, name
    FROM directory_shares
    WHERE id = ?
');
$stmt->execute([$shareId]);
$share = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$share) {
    jsonResponse(404, ['error' => 'Share no encontrado']);
}

if ((int)$share['owner_user_id'] !== (int)$user['id']) {
    jsonResponse(403, ['error' => 'Solo el propietario puede eliminar usuarios']);
}

// Get target user info
$stmt = $pdo->prepare('SELECT id, name, email FROM users WHERE id = ?');
$stmt->execute([$targetUserId]);
$targetUser = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$targetUser) {
    jsonResponse(404, ['error' => 'Usuario no encontrado']);
}

try {
    $pdo->beginTransaction();

    // Check if user exists in share
    $stmt = $pdo->prepare('
        SELECT id, role 
        FROM directory_share_users 
        WHERE share_id = ? AND user_id = ?
    ');
    $stmt->execute([$shareId, $targetUserId]);
    $existing = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$existing) {
        $pdo->rollBack();
        jsonResponse(404, ['error' => 'Usuario no está en este share']);
    }

    // Delete user from share
    $stmt = $pdo->prepare('
        DELETE FROM directory_share_users 
        WHERE id = ?
    ');
    $stmt->execute([$existing['id']]);

    // Log event
    $stmt = $pdo->prepare('
        INSERT INTO directory_events (share_id, user_id, event_type, details)
        VALUES (?, ?, ?, ?)
    ');
    $stmt->execute([
        $shareId,
        $user['id'],
        'user_removed',
        json_encode([
            'target_user_id' => $targetUserId,
            'target_user_name' => $targetUser['name'],
            'target_user_email' => $targetUser['email']
        ])
    ]);

    $pdo->commit();

    log_info('User removed from share', [
        'share_id' => $shareId,
        'target_user_id' => $targetUserId
    ]);

    jsonResponse(200, [
        'ok' => true,
        'message' => 'Usuario eliminado del share exitosamente'
    ]);

} catch (PDOException $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    log_error('DB error removing user from share', ['error' => $e->getMessage()]);
    jsonResponse(500, ['error' => 'Error de base de datos']);
}
