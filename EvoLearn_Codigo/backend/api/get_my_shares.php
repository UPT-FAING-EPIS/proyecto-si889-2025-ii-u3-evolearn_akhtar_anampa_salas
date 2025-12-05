<?php
/**
 * Get all shares (owned + invited)
 * GET /api/get_my_shares.php
 * 
 * Returns two lists:
 * - owned_shares: Shares created by me
 * - invited_shares: Shares where I'm a member (viewer/editor)
 */

declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo);
$userId = (int)$user['id'];

try {
    // Get owned shares
    $ownedStmt = $pdo->prepare('
        SELECT 
            ds.id,
            ds.name,
            ds.created_at,
            COUNT(DISTINCT dsu.user_id) as member_count,
            COUNT(DISTINCT dsn.directory_id) as directory_count
        FROM directory_shares ds
        LEFT JOIN directory_share_users dsu ON ds.id = dsu.share_id
        LEFT JOIN directory_share_nodes dsn ON ds.id = dsn.share_id
        WHERE ds.owner_user_id = ?
        GROUP BY ds.id
        ORDER BY ds.created_at DESC
    ');
    $ownedStmt->execute([$userId]);
    $ownedShares = $ownedStmt->fetchAll(PDO::FETCH_ASSOC);
    
    // Get root directories and shared users for each owned share
    foreach ($ownedShares as &$share) {
        $dirStmt = $pdo->prepare('
            SELECT d.id, d.name, d.color_hex
            FROM directory_share_nodes dsn
            JOIN directories d ON dsn.directory_id = d.id
            WHERE dsn.share_id = ? AND d.parent_id IS NULL
            LIMIT 1
        ');
        $dirStmt->execute([$share['id']]);
        $root = $dirStmt->fetch(PDO::FETCH_ASSOC);
        // Guarantee a null instead of boolean false for missing root directory
        $share['root_directory'] = $root ?: null;
        
        // Get shared users
        $usersStmt = $pdo->prepare('
            SELECT u.id, u.name, u.email, dsu.role, dsu.invited_at, dsu.accepted_at
            FROM directory_share_users dsu
            JOIN users u ON dsu.user_id = u.id
            WHERE dsu.share_id = ?
            ORDER BY dsu.invited_at DESC
        ');
        $usersStmt->execute([$share['id']]);
        $share['shared_users'] = $usersStmt->fetchAll(PDO::FETCH_ASSOC);
        
        $share['role'] = 'owner';
    }
    
    // Get invited shares (where user is a member)
    $invitedStmt = $pdo->prepare('
        SELECT 
            ds.id,
            ds.name,
            ds.created_at,
            dsu.role,
            u.name as owner_name,
            u.email as owner_email,
            COUNT(DISTINCT dsu2.user_id) as member_count
        FROM directory_share_users dsu
        JOIN directory_shares ds ON dsu.share_id = ds.id
        JOIN users u ON ds.owner_user_id = u.id
        LEFT JOIN directory_share_users dsu2 ON ds.id = dsu2.share_id
        WHERE dsu.user_id = ?
        GROUP BY ds.id, dsu.role
        ORDER BY ds.created_at DESC
    ');
    $invitedStmt->execute([$userId]);
    $invitedShares = $invitedStmt->fetchAll(PDO::FETCH_ASSOC);
    
    // Get root directories for invited shares
    foreach ($invitedShares as &$share) {
        $dirStmt = $pdo->prepare('
            SELECT d.id, d.name, d.color_hex
            FROM directory_share_nodes dsn
            JOIN directories d ON dsn.directory_id = d.id
            WHERE dsn.share_id = ? AND d.parent_id IS NULL
            LIMIT 1
        ');
        $dirStmt->execute([$share['id']]);
        $root = $dirStmt->fetch(PDO::FETCH_ASSOC);
        $share['root_directory'] = $root ?: null;
    }
    
    jsonResponse(200, [
        'owned_shares' => $ownedShares,
        'invited_shares' => $invitedShares,
        'total_owned' => count($ownedShares),
        'total_invited' => count($invitedShares)
    ]);
    
} catch (PDOException $e) {
    log_error('Error fetching shares', ['error' => $e->getMessage()]);
    jsonResponse(500, ['error' => 'Error al obtener compartidos']);
}
