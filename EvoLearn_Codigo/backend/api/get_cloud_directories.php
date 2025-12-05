<?php
/**
 * Get cloud directories for shared view
 * GET /api/get_cloud_directories.php?share_id=X
 * 
 * Returns directory tree for a specific share
 * Used in "Compartidos" section of frontend
 */

declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo);

$shareId = isset($_GET['share_id']) ? (int)$_GET['share_id'] : null;

if ($shareId === null) {
    jsonResponse(400, ['error' => 'share_id es requerido']);
}

// Verify access to share
$accessStmt = $pdo->prepare('
    SELECT 
        ds.id,
        ds.owner_user_id,
        ds.name,
        dsu.role,
        u.name as owner_name
    FROM directory_shares ds
    LEFT JOIN directory_share_users dsu ON ds.id = dsu.share_id AND dsu.user_id = ?
    LEFT JOIN users u ON ds.owner_user_id = u.id
    WHERE ds.id = ? AND (ds.owner_user_id = ? OR dsu.user_id IS NOT NULL)
');
$accessStmt->execute([(int)$user['id'], $shareId, (int)$user['id']]);
$shareInfo = $accessStmt->fetch(PDO::FETCH_ASSOC);

if (!$shareInfo) {
    jsonResponse(403, ['error' => 'No tienes acceso a este share']);
}

// Determine user role
$isOwner = (int)$shareInfo['owner_user_id'] === (int)$user['id'];
$role = $isOwner ? 'owner' : ($shareInfo['role'] ?? 'viewer');

try {
    // Get root directories for this share
    $rootStmt = $pdo->prepare('
        SELECT DISTINCT
            d.id,
            d.user_id,
            d.parent_id,
            d.name,
            d.color_hex,
            d.cloud_managed,
            dsn.include_subtree
        FROM directory_share_nodes dsn
        JOIN directories d ON dsn.directory_id = d.id
        WHERE dsn.share_id = ?
        ORDER BY d.name
    ');
    $rootStmt->execute([$shareId]);
    $roots = $rootStmt->fetchAll(PDO::FETCH_ASSOC);
    
    // Recursive function to build tree
    // Limited depth to prevent huge responses that PHP dev server can't handle
    $maxDepth = 2;
    $buildTree = function($parentId, $includeSubtree, $currentDepth = 0) use ($pdo, $shareId, &$buildTree, $maxDepth) {
        // Stop recursion at max depth
        if ($currentDepth >= $maxDepth) {
            return [];
        }
        
        $stmt = $pdo->prepare('
            SELECT 
                d.id,
                d.user_id,
                d.parent_id,
                d.name,
                d.color_hex,
                d.cloud_managed
            FROM directories d
            WHERE d.parent_id = ? AND d.cloud_managed = 1
            ORDER BY d.name
        ');
        $stmt->execute([$parentId]);
        $children = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        foreach ($children as &$child) {
            // Get documents in this directory
            $docStmt = $pdo->prepare('
                SELECT 
                    id,
                    display_name,
                    original_filename,
                    size_bytes,
                    created_at,
                    file_rel_path,
                    mime_type
                FROM documents
                WHERE directory_id = ?
                ORDER BY display_name
            ');
            $docStmt->execute([$child['id']]);
            $docs = $docStmt->fetchAll(PDO::FETCH_ASSOC);
            
            // Add type field based on mime_type
            foreach ($docs as &$doc) {
                if (strpos($doc['mime_type'] ?? '', 'text/plain') !== false) {
                    $doc['type'] = 'summary';
                } else {
                    $doc['type'] = 'pdf';
                }
            }
            
            $child['documents'] = $docs;
            
            // Get subdirectories if include_subtree and haven't reached max depth
            if ($includeSubtree && $currentDepth < $maxDepth - 1) {
                $child['subdirectories'] = $buildTree($child['id'], true, $currentDepth + 1);
            } else {
                $child['subdirectories'] = [];
            }
        }
        
        return $children;
    };
    
    // Build tree for each root
    $directories = [];
    foreach ($roots as &$root) {
        // Get documents in root
        $docStmt = $pdo->prepare('
            SELECT 
                id,
                display_name,
                original_filename,
                size_bytes,
                created_at,
                file_rel_path,
                mime_type
            FROM documents
            WHERE directory_id = ?
            ORDER BY display_name
        ');
        $docStmt->execute([$root['id']]);
        $docs = $docStmt->fetchAll(PDO::FETCH_ASSOC);
        
        // Add type field based on mime_type
        foreach ($docs as &$doc) {
            if (strpos($doc['mime_type'] ?? '', 'text/plain') !== false) {
                $doc['type'] = 'summary';
            } else {
                $doc['type'] = 'pdf';
            }
        }
        
        $root['documents'] = $docs;
        
        // Get subdirectories
        if ($root['include_subtree']) {
            $root['subdirectories'] = $buildTree($root['id'], true, 1);
        } else {
            $root['subdirectories'] = [];
        }
        
        $directories[] = $root;
    }
    
    // Ensure response is not too large
    $response = [
        'share_id' => $shareId,
        'share_name' => $shareInfo['name'],
        'owner_name' => $shareInfo['owner_name'],
        'your_role' => $role,
        'directories' => $directories
    ];
    
    $json = json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    $jsonSize = strlen($json);
    
    // Log response size for debugging
    log_info('Cloud directories response', [
        'share_id' => $shareId,
        'response_size_bytes' => $jsonSize,
        'directories_count' => count($directories)
    ]);
    
    // If response is large, we may need to chunk it
    // PHP dev server has issues with large responses
    if ($jsonSize > 1000000) {
        log_info('Large cloud directories response', [
            'share_id' => $shareId,
            'size_bytes' => $jsonSize
        ]);
    }
    
    http_response_code(200);
    header('Content-Type: application/json; charset=utf-8');
    header('Content-Length: ' . $jsonSize);
    header('Connection: close');
    
    // Flush output buffer and send response
    ob_end_clean();
    echo $json;
    flush();
    exit;
    
} catch (PDOException $e) {
    log_error('Error fetching cloud directories', ['error' => $e->getMessage(), 'share_id' => $shareId]);
    jsonResponse(500, ['error' => 'Error al obtener directorios']);
}
