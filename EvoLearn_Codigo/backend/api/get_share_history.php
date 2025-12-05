<?php
/**
 * Get complete history for a share
 * GET /api/get_share_history.php?share_id=X&limit=50&offset=0
 * 
 * Returns paginated event history for a share
 */

declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo);

$shareId = isset($_GET['share_id']) ? (int)$_GET['share_id'] : 0;
$limit = isset($_GET['limit']) ? min((int)$_GET['limit'], 100) : 50;
$offset = isset($_GET['offset']) ? (int)$_GET['offset'] : 0;

if ($shareId <= 0) {
    jsonResponse(400, ['error' => 'share_id es requerido']);
}

// Verify user has access to this share
$accessStmt = $pdo->prepare('
    SELECT ds.name, ds.owner_user_id
    FROM directory_shares ds
    WHERE ds.id = ? AND (
        ds.owner_user_id = ? OR
        EXISTS (SELECT 1 FROM directory_share_users WHERE share_id = ds.id AND user_id = ?)
    )
');
$accessStmt->execute([$shareId, (int)$user['id'], (int)$user['id']]);
$shareInfo = $accessStmt->fetch();

if (!$shareInfo) {
    jsonResponse(403, ['error' => 'No tienes acceso a este share']);
}

try {
    // Get total event count
    $countStmt = $pdo->prepare('SELECT COUNT(*) FROM directory_events WHERE share_id = ?');
    $countStmt->execute([$shareId]);
    $totalEvents = (int)$countStmt->fetchColumn();
    
    // Get paginated events
    $eventsStmt = $pdo->prepare('
        SELECT 
            de.id,
            de.user_id,
            de.event_type,
            de.share_id,
            de.directory_id,
            de.document_id,
            de.details,
            de.created_at,
            u.name as user_name,
            u.email as user_email,
            d.name as directory_name,
            doc.display_name as document_name
        FROM directory_events de
        JOIN users u ON de.user_id = u.id
        LEFT JOIN directories d ON de.directory_id = d.id
        LEFT JOIN documents doc ON de.document_id = doc.id
        WHERE de.share_id = ?
        ORDER BY de.created_at DESC
        LIMIT ? OFFSET ?
    ');
    $eventsStmt->execute([$shareId, $limit, $offset]);
    $events = $eventsStmt->fetchAll(PDO::FETCH_ASSOC);
    
    // Decode JSON details and format timestamps
    foreach ($events as &$event) {
        if ($event['details']) {
            $event['details'] = json_decode($event['details'], true);
        }
        // Format created_at to ISO8601
        $event['created_at_iso'] = date('c', strtotime($event['created_at']));
    }
    
    jsonResponse(200, [
        'share_name' => $shareInfo['name'],
        'is_owner' => (int)$shareInfo['owner_user_id'] === (int)$user['id'],
        'events' => $events,
        'total_events' => $totalEvents,
        'limit' => $limit,
        'offset' => $offset,
        'has_more' => ($offset + $limit) < $totalEvents
    ]);
    
} catch (PDOException $e) {
    log_error('Error fetching share history', ['error' => $e->getMessage(), 'share_id' => $shareId]);
    jsonResponse(500, ['error' => 'Error al obtener historial']);
}
