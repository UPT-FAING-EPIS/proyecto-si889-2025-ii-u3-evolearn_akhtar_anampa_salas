<?php
require_once __DIR__ . '/../includes/bootstrap.php';

$pdo = getPDO();
echo "=== directory_shares schema ===\n";
$stmt = $pdo->query('DESCRIBE directory_shares');
foreach ($stmt as $row) {
    echo $row['Field'] . ' (' . $row['Type'] . ')' . PHP_EOL;
}

echo "\n=== directory_share_users schema ===\n";
$stmt = $pdo->query('DESCRIBE directory_share_users');
foreach ($stmt as $row) {
    echo $row['Field'] . ' (' . $row['Type'] . ')' . PHP_EOL;
}
?>
