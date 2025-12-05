<?php
require_once __DIR__ . '/../includes/bootstrap.php';

$pdo = getPDO();
$stmt = $pdo->query("SELECT id, file_path, file_rel_path FROM summary_jobs WHERE id = 52");

foreach ($stmt as $row) {
    echo "Job " . $row['id'] . ":\n";
    echo "  file_path: " . $row['file_path'] . "\n";
    echo "  file_rel_path: " . $row['file_rel_path'] . "\n";
    echo "  exists: " . (file_exists($row['file_path']) ? 'YES' : 'NO') . "\n";
}
?>
