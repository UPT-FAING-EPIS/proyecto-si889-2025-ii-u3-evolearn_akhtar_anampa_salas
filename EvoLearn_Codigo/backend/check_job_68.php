<?php
require_once 'includes/bootstrap.php';
$pdo = getPDO();

echo "=== Checking Job 68 ===\n";
$stmt = $pdo->query('SELECT * FROM summary_jobs WHERE id = 68');
$job = $stmt->fetch(PDO::FETCH_ASSOC);
echo json_encode($job, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n\n";

echo "=== All Pending Jobs ===\n";
$stmt = $pdo->query("SELECT id, status, document_id, analysis_type, created_at FROM summary_jobs WHERE status = 'pending' ORDER BY id DESC LIMIT 10");
$jobs = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo json_encode($jobs, JSON_PRETTY_PRINT) . "\n";
