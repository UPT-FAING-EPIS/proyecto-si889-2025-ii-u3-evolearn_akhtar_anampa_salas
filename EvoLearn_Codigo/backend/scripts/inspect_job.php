<?php
require_once __DIR__ . '/../includes/db.php';

$id = isset($argv[1]) ? (int)$argv[1] : 0;
if ($id <= 0) {
    echo "Usage: php inspect_job.php <job_id>\n";
    exit(1);
}
try {
    $pdo = getPDO();
    $stmt = $pdo->prepare('SELECT id, status, progress, file_path, file_rel_path, error_message, analysis_type, model, created_at, updated_at FROM summary_jobs WHERE id = ?');
    $stmt->execute([$id]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        echo "Job not found: $id\n";
        exit(2);
    }
    echo json_encode($row, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";
} catch (Throwable $e) {
    echo "Error: " . $e->getMessage() . "\n";
    exit(3);
}
