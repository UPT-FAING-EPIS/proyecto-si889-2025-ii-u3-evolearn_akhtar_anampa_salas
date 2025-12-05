<?php
/**
 * Locking system for concurrent editing control
 * Prevents conflicts when multiple users edit shared resources
 */

declare(strict_types=1);

/**
 * Try to acquire a lock on a directory
 * @param PDO $pdo Database connection
 * @param int $directoryId Directory to lock
 * @param int $userId User requesting the lock
 * @param string $lockType Type of lock (editing, moving, deleting)
 * @param int $ttl Time-to-live in seconds (default: 300 = 5 minutes)
 * @return bool True if lock acquired, false if already locked by someone else
 */
function acquireDirectoryLock(PDO $pdo, int $directoryId, int $userId, string $lockType = 'editing', int $ttl = 300): bool {
    // Clean expired locks first
    cleanExpiredLocks($pdo);
    
    // Check if already locked by someone else
    $stmt = $pdo->prepare('
        SELECT locked_by, lock_type 
        FROM directory_locks 
        WHERE directory_id = ? AND expires_at > NOW()
    ');
    $stmt->execute([$directoryId]);
    $existing = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($existing) {
        // If locked by the same user, refresh the lock
        if ((int)$existing['locked_by'] === $userId) {
            $refresh = $pdo->prepare('
                UPDATE directory_locks 
                SET expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND),
                    lock_type = ?
                WHERE directory_id = ? AND locked_by = ?
            ');
            $refresh->execute([$ttl, $lockType, $directoryId, $userId]);
            return true;
        }
        // Locked by another user
        return false;
    }
    
    // Acquire new lock
    try {
        $expiresAt = date('Y-m-d H:i:s', time() + $ttl);
        $insert = $pdo->prepare('
            INSERT INTO directory_locks (directory_id, locked_by, lock_type, expires_at)
            VALUES (?, ?, ?, ?)
        ');
        $insert->execute([$directoryId, $userId, $lockType, $expiresAt]);
        return true;
    } catch (PDOException $e) {
        // Race condition: another lock was created
        return false;
    }
}

/**
 * Release a directory lock
 */
function releaseDirectoryLock(PDO $pdo, int $directoryId, int $userId): bool {
    $stmt = $pdo->prepare('
        DELETE FROM directory_locks 
        WHERE directory_id = ? AND locked_by = ?
    ');
    $stmt->execute([$directoryId, $userId]);
    return $stmt->rowCount() > 0;
}

/**
 * Check if a directory is locked and get lock info
 * @return array|null Lock info or null if not locked
 */
function getDirectoryLock(PDO $pdo, int $directoryId): ?array {
    cleanExpiredLocks($pdo);
    
    $stmt = $pdo->prepare('
        SELECT dl.*, u.name as locked_by_name, u.email as locked_by_email
        FROM directory_locks dl
        JOIN users u ON dl.locked_by = u.id
        WHERE dl.directory_id = ? AND dl.expires_at > NOW()
    ');
    $stmt->execute([$directoryId]);
    $lock = $stmt->fetch(PDO::FETCH_ASSOC);
    
    return $lock ?: null;
}

/**
 * Acquire document lock
 */
function acquireDocumentLock(PDO $pdo, int $documentId, int $userId, string $lockType = 'editing', int $ttl = 300): bool {
    cleanExpiredLocks($pdo);
    
    $stmt = $pdo->prepare('
        SELECT locked_by 
        FROM document_locks 
        WHERE document_id = ? AND expires_at > NOW()
    ');
    $stmt->execute([$documentId]);
    $existing = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($existing) {
        if ((int)$existing['locked_by'] === $userId) {
            $refresh = $pdo->prepare('
                UPDATE document_locks 
                SET expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND),
                    lock_type = ?
                WHERE document_id = ? AND locked_by = ?
            ');
            $refresh->execute([$ttl, $lockType, $documentId, $userId]);
            return true;
        }
        return false;
    }
    
    try {
        $expiresAt = date('Y-m-d H:i:s', time() + $ttl);
        $insert = $pdo->prepare('
            INSERT INTO document_locks (document_id, locked_by, lock_type, expires_at)
            VALUES (?, ?, ?, ?)
        ');
        $insert->execute([$documentId, $userId, $lockType, $expiresAt]);
        return true;
    } catch (PDOException $e) {
        return false;
    }
}

/**
 * Release document lock
 */
function releaseDocumentLock(PDO $pdo, int $documentId, int $userId): bool {
    $stmt = $pdo->prepare('
        DELETE FROM document_locks 
        WHERE document_id = ? AND locked_by = ?
    ');
    $stmt->execute([$documentId, $userId]);
    return $stmt->rowCount() > 0;
}

/**
 * Get document lock info
 */
function getDocumentLock(PDO $pdo, int $documentId): ?array {
    cleanExpiredLocks($pdo);
    
    $stmt = $pdo->prepare('
        SELECT dl.*, u.name as locked_by_name, u.email as locked_by_email
        FROM document_locks dl
        JOIN users u ON dl.locked_by = u.id
        WHERE dl.document_id = ? AND dl.expires_at > NOW()
    ');
    $stmt->execute([$documentId]);
    $lock = $stmt->fetch(PDO::FETCH_ASSOC);
    
    return $lock ?: null;
}

/**
 * Clean expired locks (called automatically by other functions)
 */
function cleanExpiredLocks(PDO $pdo): void {
    static $lastClean = 0;
    $now = time();
    
    // Only clean every 30 seconds to avoid excessive queries
    if ($now - $lastClean < 30) {
        return;
    }
    
    $pdo->exec('DELETE FROM directory_locks WHERE expires_at <= NOW()');
    $pdo->exec('DELETE FROM document_locks WHERE expires_at <= NOW()');
    
    $lastClean = $now;
}

/**
 * Require lock or throw 423 error
 */
function requireDirectoryLock(PDO $pdo, int $directoryId, int $userId, string $lockType = 'editing'): void {
    if (!acquireDirectoryLock($pdo, $directoryId, $userId, $lockType)) {
        $lock = getDirectoryLock($pdo, $directoryId);
        http_response_code(423); // Locked
        header('Content-Type: application/json');
        echo json_encode([
            'error' => 'Este directorio está siendo editado por otro usuario',
            'locked_by' => $lock['locked_by_name'] ?? 'Desconocido',
            'lock_type' => $lock['lock_type'] ?? 'editing',
            'code' => 'RESOURCE_LOCKED'
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }
}

/**
 * Require document lock or throw 423 error
 */
function requireDocumentLock(PDO $pdo, int $documentId, int $userId, string $lockType = 'editing'): void {
    if (!acquireDocumentLock($pdo, $documentId, $userId, $lockType)) {
        $lock = getDocumentLock($pdo, $documentId);
        http_response_code(423);
        header('Content-Type: application/json');
        echo json_encode([
            'error' => 'Este documento está siendo editado por otro usuario',
            'locked_by' => $lock['locked_by_name'] ?? 'Desconocido',
            'lock_type' => $lock['lock_type'] ?? 'editing',
            'code' => 'RESOURCE_LOCKED'
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }
}
