<?php
require_once 'includes/db.php';

$pdo = getPDO();

// Ver job exitoso
$stmt = $pdo->prepare('SELECT id, file_rel_path FROM summary_jobs WHERE id = 65');
$stmt->execute();
$job = $stmt->fetch(PDO::FETCH_ASSOC);

if ($job) {
    echo "Job 65 file: {$job['file_rel_path']}\n";
    $path = __DIR__ . '/' . $job['file_rel_path'];
    echo "Full path: $path\n";
    echo "Exists: " . (file_exists($path) ? "YES" : "NO") . "\n";
    echo "Size: " . filesize($path) . " bytes\n";
}
?>
