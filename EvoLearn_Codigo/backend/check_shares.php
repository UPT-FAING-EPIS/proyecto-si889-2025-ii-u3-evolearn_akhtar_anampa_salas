<?php
require_once 'includes/db.php';

$pdo = getPDO();

echo "Shares activos en el sistema:\n\n";

$query = "
    SELECT 
        ds.id,
        ds.owner_user_id,
        ds.name,
        root_dir.id as dir_id,
        root_dir.name as dir_name,
        COUNT(d.id) as doc_count
    FROM directory_shares ds
    JOIN directories root_dir ON ds.directory_root_id = root_dir.id
    LEFT JOIN documents d ON d.directory_id = root_dir.id
    GROUP BY ds.id
";

$result = $pdo->query($query);
$shares = $result->fetchAll(PDO::FETCH_ASSOC);

foreach ($shares as $share) {
    echo "Share ID {$share['id']}:\n";
    echo "  Owner: User {$share['owner_user_id']}\n";
    echo "  Name: {$share['name']}\n";
    echo "  Directory: {$share['dir_name']} (ID: {$share['dir_id']})\n";
    echo "  Documentos: {$share['doc_count']}\n\n";
}
?>
