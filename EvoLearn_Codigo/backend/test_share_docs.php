<?php
require_once 'includes/bootstrap.php';

$pdo = getPDO();

// Test: Get documents for share 6
echo "=== Testing get_cloud_directories for share 6 ===\n\n";

$stmt = $pdo->prepare('
    SELECT d.id, d.display_name, d.mime_type, d.file_rel_path
    FROM documents d
    JOIN directory_share_nodes dsn ON d.directory_id = dsn.directory_id
    WHERE dsn.share_id = 6
    LIMIT 10
');
$stmt->execute();
$docs = $stmt->fetchAll(PDO::FETCH_ASSOC);

echo json_encode($docs, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
