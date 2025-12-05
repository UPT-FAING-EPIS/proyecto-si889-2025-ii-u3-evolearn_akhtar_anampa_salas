<?php
/**
 * List users in a share
 * GET /api/list_share_users.php?share_id=42
 */

declare(strict_types=1);
require_once __DIR__ . '/../includes/bootstrap.php';

header('Content-Type: application/json');

$pdo = getPDO();
$currentUser = requireAuth($pdo);

// Validate share_id parameter
$shareId = (int)($_GET['share_id'] ?? 0);

if ($shareId <= 0) {
    jsonResponse(400, ['error' => 'share_id parameter required']);
}

try {
    // Verify share exists
    $stmt = $pdo->prepare('
        SELECT id, owner_user_id, directory_root_id, name, description, created_at
        FROM directory_shares 
        WHERE id = ?
    ');
    $stmt->execute([$shareId]);
    $share = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$share) {
        jsonResponse(404, ['error' => 'Share not found']);
    }
    
    $isOwner = ((int)$share['owner_user_id'] === (int)$currentUser['id']);
    
    // Check if current user has access to this share (is owner or is a member)
    if (!$isOwner) {
        $stmt = $pdo->prepare('
            SELECT id FROM directory_share_users 
            WHERE share_id = ? AND user_id = ?
        ');
        $stmt->execute([$shareId, $currentUser['id']]);
        if (!$stmt->fetch()) {
            jsonResponse(403, ['error' => 'You do not have access to this share']);
        }
    }
    
    // Get owner info
    $stmt = $pdo->prepare('
        SELECT id, name, email 
        FROM users 
        WHERE id = ?
    ');
    $stmt->execute([$share['owner_user_id']]);
    $owner = $stmt->fetch(PDO::FETCH_ASSOC);
    
    // Get list of users in the share
    $stmt = $pdo->prepare('
        SELECT 
            dsu.id,
            dsu.user_id,
            dsu.role,
            dsu.invited_at,
            dsu.accepted_at,
            u.name,
            u.email
        FROM directory_share_users dsu
        JOIN users u ON u.id = dsu.user_id
        WHERE dsu.share_id = ?
        ORDER BY dsu.invited_at DESC
    ');
    $stmt->execute([$shareId]);
    $shareUsers = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    // Format users
    $users = [];
    foreach ($shareUsers as $su) {
        $users[] = [
            'share_user_id' => (int)$su['id'],
            'user_id' => (int)$su['user_id'],
            'name' => $su['name'],
            'email' => $su['email'],
            'role' => $su['role'],
            'invited_at' => $su['invited_at'],
            'accepted_at' => $su['accepted_at'],
        ];
    }
    
    jsonResponse(200, [
        'ok' => true,
        'share' => [
            'id' => (int)$share['id'],
            'name' => $share['name'],
            'description' => $share['description'],
            'directory_root_id' => (int)$share['directory_root_id'],
            'created_at' => $share['created_at'],
            'owner' => [
                'id' => (int)$owner['id'],
                'name' => $owner['name'],
                'email' => $owner['email'],
            ],
            'is_owner' => $isOwner,
        ],
        'users' => $users,
        'total_users' => count($users),
    ]);
    
} catch (PDOException $e) {
    log_error('DB error listing share users', ['error' => $e->getMessage()]);
    jsonResponse(500, ['error' => 'Database error']);
}
