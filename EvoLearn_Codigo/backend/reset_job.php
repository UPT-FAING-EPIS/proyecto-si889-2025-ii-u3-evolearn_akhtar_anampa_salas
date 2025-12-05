<?php
require_once 'includes/db.php';

$pdo = getPDO();
$stmt = $pdo->prepare('UPDATE summary_jobs SET status = ?, progress = 0, error_message = NULL WHERE id = ?');
$stmt->execute(['pending', 66]);
echo "Job 66 reset to pending\n";
?>
