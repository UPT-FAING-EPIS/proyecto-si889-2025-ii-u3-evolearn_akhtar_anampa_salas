<?php
/**
 * Migration: add 'canceled' status to summary_jobs.status enum
 */
declare(strict_types=1);

require_once __DIR__ . '/../../includes/bootstrap.php';

$pdo = getPDO();

try {
    // Check current enum definition
    $stmt = $pdo->query("SHOW COLUMNS FROM summary_jobs LIKE 'status'");
    $col = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$col) {
        echo "Column 'status' not found on summary_jobs.\n";
        exit(1);
    }

    $type = $col['Type'] ?? '';
    if (strpos($type, "'canceled'") !== false) {
        echo "Enum already includes 'canceled'. Nothing to do.\n";
        exit(0);
    }

    echo "Altering column 'status' to include 'canceled'...\n";
    $pdo->exec("ALTER TABLE summary_jobs MODIFY COLUMN status ENUM('pending','processing','completed','failed','canceled') NOT NULL DEFAULT 'pending'");

    echo "Migration completed successfully.\n";
    exit(0);

} catch (Throwable $e) {
    echo "Migration failed: " . $e->getMessage() . "\n";
    exit(1);
}
