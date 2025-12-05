<?php
// Simple migration to add file_rel_path to summary_jobs and create composite index
// Usage: php backend/scripts/migrations/20251113_add_file_rel_path.php

declare(strict_types=1);
require_once __DIR__ . '/../../includes/bootstrap.php';

$pdo = getPDO();

function columnExists(PDO $pdo, string $table, string $column): bool {
    $stmt = $pdo->prepare("SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?");
    $stmt->execute([$table, $column]);
    return (int)$stmt->fetchColumn() > 0;
}

function indexExists(PDO $pdo, string $table, string $index): bool {
    $stmt = $pdo->prepare("SHOW INDEX FROM `{$table}` WHERE Key_name = ?");
    $stmt->execute([$index]);
    return (bool)$stmt->fetch(PDO::FETCH_ASSOC);
}

try {
    $pdo->beginTransaction();

    if (!columnExists($pdo, 'summary_jobs', 'file_rel_path')) {
        $pdo->exec("ALTER TABLE summary_jobs ADD COLUMN file_rel_path VARCHAR(1024) NULL AFTER file_path");
        echo "Added column summary_jobs.file_rel_path\n";
    } else {
        echo "Column summary_jobs.file_rel_path already exists\n";
    }

    // Create composite index for user_id, file_rel_path, status (with prefix for long varchar)
    if (!indexExists($pdo, 'summary_jobs', 'idx_summary_jobs_user_path_status')) {
        $pdo->exec("CREATE INDEX idx_summary_jobs_user_path_status ON summary_jobs (user_id, file_rel_path(255), status)");
        echo "Created index idx_summary_jobs_user_path_status\n";
    } else {
        echo "Index idx_summary_jobs_user_path_status already exists\n";
    }

    $pdo->commit();
    echo "Migration completed successfully.\n";
} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    fwrite(STDERR, "Migration failed: " . $e->getMessage() . "\n");
    exit(1);
}
