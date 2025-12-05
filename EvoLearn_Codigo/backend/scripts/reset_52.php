<?php
require_once __DIR__ . '/../includes/bootstrap.php';

$pdo = getPDO();
$stmt = $pdo->prepare('UPDATE summary_jobs SET status = ? WHERE id = 52');
$stmt->execute(['pending']);
echo "Job 52 reset to pending\n";
?>
