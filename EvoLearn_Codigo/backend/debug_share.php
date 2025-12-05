<?php
require_once 'includes/bootstrap.php';
$pdo = getPDO();

echo "=== All Documents ===\n";
$stmt = $pdo->query('SELECT id, display_name, directory_id, mime_type FROM documents');
$docs = $stmt->fetchAll(PDO::FETCH_ASSOC);
var_dump($docs);

echo "\n=== Share 6 Info ===\n";
$stmt = $pdo->query('SELECT id, owner_user_id, name FROM directory_shares WHERE id = 6');
$share = $stmt->fetch(PDO::FETCH_ASSOC);
var_dump($share);

echo "\n=== Share 6 Directories ===\n";
$stmt = $pdo->query('SELECT dsn.directory_id FROM directory_share_nodes dsn WHERE dsn.share_id = 6');
$dirs = $stmt->fetchAll(PDO::FETCH_ASSOC);
var_dump($dirs);
