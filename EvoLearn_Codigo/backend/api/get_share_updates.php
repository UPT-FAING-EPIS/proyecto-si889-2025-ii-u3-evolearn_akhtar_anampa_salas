<?php
/**
 * Check if a share has been updated since a given timestamp (polling endpoint)
 * GET /api/get_share_updates.php?share_id=6&since=2025-11-24T09:00:00Z
 * 
 * Returns:
 * {
 *   "has_updates": true/false,
 *   "server_time": "2025-11-24T09:14:23Z"
 * }
 */

declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo, false); // Non-JSON responses for polling

$shareId = isset($_GET['share_id']) ? (int)$_GET['share_id'] : 0;
$since = isset($_GET['since']) ? trim($_GET['since']) : null;

if ($shareId <= 0) {
    jsonResponse(400, ['error' => 'share_id es requerido']);
}

// Verify user has access to this share
$accessStmt = $pdo->prepare('
    SELECT 1 FROM directory_shares ds
    WHERE ds.id = ? AND (
        ds.owner_user_id = ? OR
        EXISTS (SELECT 1 FROM directory_share_users WHERE share_id = ds.id AND user_id = ?)
    )
');
$accessStmt->execute([$shareId, (int)$user['id'], (int)$user['id']]);

if (!$accessStmt->fetch()) {
    jsonResponse(403, ['error' => 'No tienes acceso a este share']);
}

try {
    // Get current server time in ISO 8601 format
    $serverTime = gmdate('Y-m-d\TH:i:s\Z');

    // If no since timestamp provided, always return has_updates = true
    if (!$since) {
        jsonResponse(200, [
            'has_updates' => true,
            'server_time' => $serverTime,
        ]);
    }

    // Convert since timestamp to a datetime for comparison
    try {
        $sinceDateTime = new DateTime($since, new DateTimeZone('UTC'));
        $sinceStr = $sinceDateTime->format('Y-m-d H:i:s');
    } catch (Exception $parseEx) {
        jsonResponse(400, ['error' => 'Invalid since timestamp format']);
    }

    // Check for updates in the share:
    // 1. New/updated documents
    $docStmt = $pdo->prepare('
        SELECT COUNT(*) as count
        FROM documents d
        WHERE d.directory_id IN (
            SELECT dsn.directory_id
            FROM directory_share_nodes dsn
            WHERE dsn.share_id = ?
        )
        AND (d.created_at > ? OR d.updated_at > ?)
    ');
    $docStmt->execute([$shareId, $sinceStr, $sinceStr]);
    $docCount = (int)$docStmt->fetchColumn();

    // 2. Updated directories
    $dirStmt = $pdo->prepare('
        SELECT COUNT(*) as count
        FROM directories d
        WHERE d.id IN (
            SELECT dsn.directory_id
            FROM directory_share_nodes dsn
            WHERE dsn.share_id = ?
        )
        AND (d.created_at > ? OR d.updated_at > ?)
    ');
    $dirStmt->execute([$shareId, $sinceStr, $sinceStr]);
    $dirCount = (int)$dirStmt->fetchColumn();

    // 3. User role changes in share
    $userStmt = $pdo->prepare('
        SELECT COUNT(*) as count
        FROM directory_share_users dsu
        WHERE dsu.share_id = ?
        AND dsu.invited_at > ?
    ');
    $userStmt->execute([$shareId, $sinceStr]);
    $userCount = (int)$userStmt->fetchColumn();

    $hasUpdates = ($docCount + $dirCount + $userCount) > 0;

    jsonResponse(200, [
        'has_updates' => $hasUpdates,
        'server_time' => $serverTime,
    ]);
    
} catch (PDOException $e) {
    log_error('Error fetching share updates', ['error' => $e->getMessage(), 'share_id' => $shareId]);
    jsonResponse(500, ['error' => 'Error al obtener actualizaciones']);
}
