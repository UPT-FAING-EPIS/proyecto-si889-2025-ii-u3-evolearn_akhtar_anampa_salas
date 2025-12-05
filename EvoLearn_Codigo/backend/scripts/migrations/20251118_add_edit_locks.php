<?php
/**
 * Migration: Add edit locks table for concurrent editing control
 * Created: 2025-11-18
 */

require_once __DIR__ . '/../../includes/db.php';

try {
    $pdo = getPDO();
    echo "Starting migration: Add edit locks table...\n";
    
    // Create directory_locks table for concurrent editing control
    $createLocks = "
    CREATE TABLE IF NOT EXISTS directory_locks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        directory_id INT NOT NULL,
        locked_by INT NOT NULL,
        lock_type ENUM('editing', 'moving', 'deleting') NOT NULL DEFAULT 'editing',
        locked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP NULL,
        FOREIGN KEY (directory_id) REFERENCES directories(id) ON DELETE CASCADE,
        FOREIGN KEY (locked_by) REFERENCES users(id) ON DELETE CASCADE,
        INDEX idx_directory_lock (directory_id),
        INDEX idx_lock_expiry (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ";
    
    $pdo->exec($createLocks);
    echo "✓ Created directory_locks table\n";
    
    // Create document_locks table
    $createDocLocks = "
    CREATE TABLE IF NOT EXISTS document_locks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        document_id INT NOT NULL,
        locked_by INT NOT NULL,
        lock_type ENUM('editing', 'moving', 'summarizing') NOT NULL DEFAULT 'editing',
        locked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP NULL,
        FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE,
        FOREIGN KEY (locked_by) REFERENCES users(id) ON DELETE CASCADE,
        INDEX idx_document_lock (document_id),
        INDEX idx_lock_expiry (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ";
    
    $pdo->exec($createDocLocks);
    echo "✓ Created document_locks table\n";
    
    echo "✅ Migration completed successfully!\n";
    
} catch (Exception $e) {
    echo "❌ Migration failed: " . $e->getMessage() . "\n";
    exit(1);
}
