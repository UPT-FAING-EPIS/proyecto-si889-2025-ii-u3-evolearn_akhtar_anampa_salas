<?php
require_once __DIR__ . '/../includes/bootstrap.php';

$pdo = getPDO();
$stmt = $pdo->prepare("UPDATE summary_jobs SET status = 'pending' WHERE id = 51");
$stmt->execute();
echo "Job 51 reset to pending\n";
?>
