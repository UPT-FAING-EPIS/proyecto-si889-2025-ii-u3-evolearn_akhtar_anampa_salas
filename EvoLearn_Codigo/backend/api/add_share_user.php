<?php
/**
 * Add user to a share
 * POST /api/add_share_user.php
 * 
 * Body JSON:
 * {
 *   "share_id": 42,
 *   "user_email": "juan@ejemplo.com", // optional if user_id provided
 *   "user_id": 5, // optional if user_email provided
 *   "role": "editor" // or "viewer"
 * }
 */

declare(strict_types=1);
require_once __DIR__ . '/../includes/bootstrap.php';

header('Content-Type: application/json');

$pdo = getPDO();
$currentUser = requireAuth($pdo);

// Parse JSON body
$input = json_decode(file_get_contents('php://input'), true);

if (!is_array($input)) {
    jsonResponse(400, ['error' => 'Invalid JSON']);
}

// Validate required fields
$shareId = (int)($input['share_id'] ?? 0);
$userEmail = trim($input['user_email'] ?? '');
$userId = (int)($input['user_id'] ?? 0);
$role = strtolower(trim($input['role'] ?? 'viewer'));

if ($shareId <= 0) {
    jsonResponse(400, ['error' => 'share_id is required']);
}

if (empty($userEmail) && $userId <= 0) {
    jsonResponse(400, ['error' => 'Either user_email or user_id is required']);
}

if (!in_array($role, ['viewer', 'editor'])) {
    jsonResponse(400, ['error' => 'role must be "viewer" or "editor"']);
}

try {
    $pdo->beginTransaction();
    
    // Verify share exists and current user is the owner
    $stmt = $pdo->prepare('
        SELECT id, owner_user_id, directory_root_id 
        FROM directory_shares 
        WHERE id = ?
    ');
    $stmt->execute([$shareId]);
    $share = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$share) {
        $pdo->rollBack();
        jsonResponse(404, ['error' => 'Share not found']);
    }
    
    if ((int)$share['owner_user_id'] !== (int)$currentUser['id']) {
        $pdo->rollBack();
        jsonResponse(403, ['error' => 'Only the owner can add users to this share']);
    }
    
    // Find user by email or ID
    $targetUser = null;
    if ($userId > 0) {
        $stmt = $pdo->prepare('SELECT id, name, email FROM users WHERE id = ?');
        $stmt->execute([$userId]);
        $targetUser = $stmt->fetch(PDO::FETCH_ASSOC);
    } elseif (!empty($userEmail)) {
        $stmt = $pdo->prepare('SELECT id, name, email FROM users WHERE email = ?');
        $stmt->execute([$userEmail]);
        $targetUser = $stmt->fetch(PDO::FETCH_ASSOC);
    }
    
    if (!$targetUser) {
        $pdo->rollBack();
        jsonResponse(404, ['error' => 'User not found']);
    }
    
    $targetUserId = (int)$targetUser['id'];
    
    // Prevent adding owner as user
    if ($targetUserId === (int)$currentUser['id']) {
        $pdo->rollBack();
        jsonResponse(400, ['error' => 'Cannot add yourself to the share']);
    }
    
    // Check if user is already in the share
    $stmt = $pdo->prepare('
        SELECT id, role 
        FROM directory_share_users 
        WHERE share_id = ? AND user_id = ?
    ');
    $stmt->execute([$shareId, $targetUserId]);
    $existing = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($existing) {
        // Update role if different
        if ($existing['role'] !== $role) {
            $stmt = $pdo->prepare('
                UPDATE directory_share_users 
                SET role = ? 
                WHERE id = ?
            ');
            $stmt->execute([$role, $existing['id']]);
            
            // Log event
            $stmt = $pdo->prepare('
                INSERT INTO directory_events (share_id, user_id, event_type, details)
                VALUES (?, ?, ?, ?)
            ');
            $stmt->execute([
                $shareId,
                $currentUser['id'],
                'permission_changed',
                json_encode([
                    'target_user_id' => $targetUserId,
                    'target_user_name' => $targetUser['name'],
                    'old_role' => $existing['role'],
                    'new_role' => $role
                ])
            ]);
            
            $pdo->commit();
            
            jsonResponse(200, [
                'ok' => true,
                'message' => 'User role updated',
                'share_user_id' => (int)$existing['id'],
                'role' => $role
            ]);
        } else {
            $pdo->rollBack();
            jsonResponse(409, ['error' => 'User already has this role in the share']);
        }
    }
    
    // Add user to share
    $stmt = $pdo->prepare('
        INSERT INTO directory_share_users (share_id, user_id, role)
        VALUES (?, ?, ?)
    ');
    $stmt->execute([$shareId, $targetUserId, $role]);
    
    $shareUserId = (int)$pdo->lastInsertId();
    
    // Log event
    $stmt = $pdo->prepare('
        INSERT INTO directory_events (share_id, directory_id, user_id, event_type, details)
        VALUES (?, ?, ?, ?, ?)
    ');
    $stmt->execute([
        $shareId,
        $share['directory_root_id'],
        $currentUser['id'],
        'user_added',
        json_encode([
            'target_user_id' => $targetUserId,
            'target_user_name' => $targetUser['name'],
            'target_user_email' => $targetUser['email'],
            'role' => $role
        ])
    ]);
    
    $pdo->commit();
    
    log_info('User added to share', [
        'share_id' => $shareId,
        'target_user_id' => $targetUserId,
        'role' => $role
    ]);
    
    jsonResponse(200, [
        'ok' => true,
        'share_user_id' => $shareUserId,
        'user' => [
            'id' => $targetUserId,
            'name' => $targetUser['name'],
            'email' => $targetUser['email'],
            'role' => $role
        ]
    ]);
    
} catch (PDOException $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    log_error('DB error adding user to share', ['error' => $e->getMessage()]);
    jsonResponse(500, ['error' => 'Database error']);
}
