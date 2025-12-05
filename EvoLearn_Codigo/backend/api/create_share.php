<?php
/**
 * Create a new share
 * POST /api/create_share.php
 * 
 * Body JSON:
 * {
 *   "directory_root_id": 123,
 *   "name": "Compartir Examenes", // optional
 *   "description": "...", // optional
 *   "nodes": [
 *     { "directory_id": 123, "include_subtree": true },
 *     { "directory_id": 124, "include_subtree": false }
 *   ]
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
$directoryRootId = (int)($input['directory_root_id'] ?? 0);
$name = trim($input['name'] ?? '');
$description = trim($input['description'] ?? '');
$nodes = $input['nodes'] ?? [];

if ($directoryRootId <= 0) {
    jsonResponse(400, ['error' => 'directory_root_id is required']);
}

if (!is_array($nodes) || empty($nodes)) {
    jsonResponse(400, ['error' => 'nodes array is required and cannot be empty']);
}

try {
    $pdo->beginTransaction();
    
    // Verify that directory_root_id exists and belongs to current user
    $stmt = $pdo->prepare('
        SELECT id, name, user_id 
        FROM directories 
        WHERE id = ?
    ');
    $stmt->execute([$directoryRootId]);
    $rootDir = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$rootDir) {
        $pdo->rollBack();
        jsonResponse(404, ['error' => 'Directory not found']);
    }
    
    if ((int)$rootDir['user_id'] !== (int)$currentUser['id']) {
        $pdo->rollBack();
        jsonResponse(403, ['error' => 'You do not own this directory']);
    }
    
    // Create the share
    $stmt = $pdo->prepare('
        INSERT INTO directory_shares (directory_root_id, owner_user_id, name, description)
        VALUES (?, ?, ?, ?)
    ');
    $stmt->execute([
        $directoryRootId,
        $currentUser['id'],
        $name ?: null,
        $description ?: null
    ]);
    
    $shareId = (int)$pdo->lastInsertId();
    
    // Insert share nodes
    $stmtNode = $pdo->prepare('
        INSERT INTO directory_share_nodes (share_id, directory_id, include_subtree)
        VALUES (?, ?, ?)
    ');
    
    $insertedNodes = 0;
    foreach ($nodes as $node) {
        $dirId = (int)($node['directory_id'] ?? 0);
        $includeSubtree = !empty($node['include_subtree']);
        
        if ($dirId <= 0) {
            continue; // Skip invalid nodes
        }
        
        // Verify directory exists and belongs to user
        $stmt = $pdo->prepare('SELECT id FROM directories WHERE id = ? AND user_id = ?');
        $stmt->execute([$dirId, $currentUser['id']]);
        if (!$stmt->fetch()) {
            continue; // Skip directories that don't exist or don't belong to user
        }
        
        $stmtNode->execute([$shareId, $dirId, $includeSubtree ? 1 : 0]);
        $insertedNodes++;
    }
    
    if ($insertedNodes === 0) {
        $pdo->rollBack();
        jsonResponse(400, ['error' => 'No valid nodes were provided']);
    }
    
    // Log event
    $stmt = $pdo->prepare('
        INSERT INTO directory_events (share_id, directory_id, user_id, event_type, details)
        VALUES (?, ?, ?, ?, ?)
    ');
    $stmt->execute([
        $shareId,
        $directoryRootId,
        $currentUser['id'],
        'share_created',
        json_encode([
            'share_name' => $name ?: $rootDir['name'],
            'nodes_count' => $insertedNodes
        ])
    ]);
    
    $pdo->commit();
    
    log_info('Share created', [
        'share_id' => $shareId,
        'root_dir' => $directoryRootId,
        'nodes' => $insertedNodes
    ]);
    
    jsonResponse(201, [
        'ok' => true,
        'share_id' => $shareId,
        'nodes_created' => $insertedNodes
    ]);
    
} catch (PDOException $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    log_error('DB error creating share', ['error' => $e->getMessage()]);
    jsonResponse(500, ['error' => 'Database error']);
}
