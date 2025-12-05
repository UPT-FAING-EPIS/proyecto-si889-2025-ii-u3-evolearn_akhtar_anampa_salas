<?php
/**
 * Permissions system for shared directories
 * 
 * Provides functions to check if a user has permission to perform actions
 * on directories and documents based on sharing configuration.
 */

declare(strict_types=1);

/**
 * Check if a directory is cloud-managed (shared)
 */
function isCloudManaged(PDO $pdo, int $directoryId): bool {
    $stmt = $pdo->prepare('SELECT cloud_managed FROM directories WHERE id = ?');
    $stmt->execute([$directoryId]);
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    return $result ? (bool)$result['cloud_managed'] : false;
}

/**
 * Check if user has permission to perform action on a directory
 * 
 * @param PDO $pdo Database connection
 * @param int $userId User attempting the action
 * @param int $directoryId Directory being accessed
 * @param string $requiredPermission 'view' or 'edit'
 * @return bool True if user has permission
 */
function hasDirectoryPermission(PDO $pdo, int $userId, int $directoryId, string $requiredPermission = 'view'): bool {
    // 1. Check if directory is local (cloud_managed = 0)
    $stmt = $pdo->prepare('
        SELECT user_id, cloud_managed 
        FROM directories 
        WHERE id = ?
    ');
    $stmt->execute([$directoryId]);
    $dir = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$dir) {
        return false; // Directory doesn't exist
    }
    
    // If local directory, only owner has access
    if (!$dir['cloud_managed']) {
        return (int)$dir['user_id'] === $userId;
    }
    
    // 2. Directory is cloud-managed, check shares
    // First check if user is the owner
    if ((int)$dir['user_id'] === $userId) {
        return true; // Owner has full access
    }
    
    // 3. Check if directory is included in any share where user is a member
    // Need to find shares that include this directory (directly or via include_subtree)
    $stmt = $pdo->prepare('
        SELECT dsu.role, dsn.include_subtree, dsn.directory_id
        FROM directory_share_users dsu
        JOIN directory_shares ds ON ds.id = dsu.share_id
        JOIN directory_share_nodes dsn ON dsn.share_id = ds.id
        WHERE dsu.user_id = ?
    ');
    $stmt->execute([$userId]);
    $shareAccess = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    foreach ($shareAccess as $access) {
        $nodeId = (int)$access['directory_id'];
        $includeSubtree = (bool)$access['include_subtree'];
        
        // Check if this node matches or is an ancestor
        if ($nodeId === $directoryId) {
            // Direct match
            if ($requiredPermission === 'view') {
                return true; // Both viewer and editor can view
            }
            return $access['role'] === 'editor'; // Only editor can edit
        }
        
        // Check if directoryId is a descendant of nodeId (if include_subtree)
        if ($includeSubtree && isDescendantOf($pdo, $directoryId, $nodeId)) {
            if ($requiredPermission === 'view') {
                return true;
            }
            return $access['role'] === 'editor';
        }
    }
    
    return false;
}

/**
 * Check if directoryId is a descendant of ancestorId
 */
function isDescendantOf(PDO $pdo, int $directoryId, int $ancestorId): bool {
    $currentId = $directoryId;
    $maxDepth = 50; // Prevent infinite loops
    
    while ($currentId && $maxDepth-- > 0) {
        $stmt = $pdo->prepare('SELECT parent_id FROM directories WHERE id = ?');
        $stmt->execute([$currentId]);
        $result = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$result) {
            return false;
        }
        
        $parentId = $result['parent_id'] ? (int)$result['parent_id'] : null;
        
        if ($parentId === $ancestorId) {
            return true;
        }
        
        $currentId = $parentId;
    }
    
    return false;
}

/**
 * Check if user can edit a document
 */
function canEditDocument(PDO $pdo, int $userId, int $documentId): bool {
    $stmt = $pdo->prepare('
        SELECT user_id, directory_id 
        FROM documents 
        WHERE id = ?
    ');
    $stmt->execute([$documentId]);
    $doc = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$doc) {
        return false;
    }
    
    // If user owns the document
    if ((int)$doc['user_id'] === $userId) {
        return true;
    }
    
    // Check directory permissions if document is in a directory
    if ($doc['directory_id']) {
        return hasDirectoryPermission($pdo, $userId, (int)$doc['directory_id'], 'edit');
    }
    
    return false;
}

/**
 * Require permission or fail with 403
 * 
 * @throws Will call jsonResponse(403) and exit if permission denied
 */
function requireDirectoryPermission(PDO $pdo, int $userId, int $directoryId, string $requiredPermission = 'edit'): void {
    if (!hasDirectoryPermission($pdo, $userId, $directoryId, $requiredPermission)) {
        log_warning('Permission denied', [
            'user_id' => $userId,
            'directory_id' => $directoryId,
            'required' => $requiredPermission
        ]);
        jsonResponse(403, ['error' => 'You do not have permission to perform this action']);
    }
}

/**
 * Require document edit permission or fail with 403
 */
function requireDocumentPermission(PDO $pdo, int $userId, int $documentId): void {
    if (!canEditDocument($pdo, $userId, $documentId)) {
        log_warning('Document permission denied', [
            'user_id' => $userId,
            'document_id' => $documentId
        ]);
        jsonResponse(403, ['error' => 'You do not have permission to edit this document']);
    }
}

/**
 * Log an event to directory_events table
 */
function logDirectoryEvent(
    PDO $pdo,
    int $userId,
    string $eventType,
    ?int $shareId = null,
    ?int $directoryId = null,
    ?int $documentId = null,
    ?array $details = null
): void {
    try {
        $stmt = $pdo->prepare('
            INSERT INTO directory_events 
            (share_id, directory_id, document_id, user_id, event_type, details)
            VALUES (?, ?, ?, ?, ?, ?)
        ');
        $stmt->execute([
            $shareId,
            $directoryId,
            $documentId,
            $userId,
            $eventType,
            $details ? json_encode($details) : null
        ]);
    } catch (PDOException $e) {
        log_error('Failed to log directory event', [
            'error' => $e->getMessage(),
            'event_type' => $eventType
        ]);
    }
}
