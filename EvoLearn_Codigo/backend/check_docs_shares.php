<?php
require_once 'includes/db.php';

$pdo = getPDO();

echo "Verificando todos los shares y documentos de user 11...\n\n";

// Obtener todos los shares del user 11
$query = "SELECT ds.id, ds.directory_root_id, d.id as dir_id, d.name
         FROM directory_shares ds
         JOIN directories d ON ds.directory_root_id = d.id
         WHERE ds.owner_user_id = 11";

$result = $pdo->query($query);
$shares = $result->fetchAll(PDO::FETCH_ASSOC);

echo "Shares creados por user 11: " . count($shares) . "\n\n";

foreach ($shares as $share) {
    echo "Share ID {$share['id']}: Directorio '{$share['name']}' (dir_id: {$share['dir_id']})\n";
    
    // Ver documentos en este directorio
    $query = "SELECT id, display_name, file_rel_path
             FROM documents
             WHERE directory_id = ?";
    $stmt = $pdo->prepare($query);
    $stmt->execute([$share['dir_id']]);
    $docs = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    echo "  Documentos: " . count($docs) . "\n";
    foreach ($docs as $doc) {
        echo "    - ID {$doc['id']}: {$doc['display_name']} (path: {$doc['file_rel_path']})\n";
    }
    echo "\n";
}

// También obtener documentos de user 11 en todos sus directorios
echo str_repeat("=", 50) . "\n\n";
echo "Todos los documentos de user 11 en sus directorios:\n\n";

$query = "SELECT d.id, d.display_name, d.directory_id, d.file_rel_path, dir.name as dir_name
         FROM documents d
         LEFT JOIN directories dir ON d.directory_id = dir.id
         WHERE d.user_id = 11
         ORDER BY d.directory_id, d.display_name";

$result = $pdo->query($query);
$allDocs = $result->fetchAll(PDO::FETCH_ASSOC);

$currentDir = null;
foreach ($allDocs as $doc) {
    if ($doc['directory_id'] != $currentDir) {
        $currentDir = $doc['directory_id'];
        echo "Directorio {$currentDir} ({$doc['dir_name']}):\n";
    }
    
    $fileExists = file_exists(__DIR__ . '/' . $doc['file_rel_path']);
    $status = $fileExists ? "EXISTS" : "MISSING";
    echo "  - {$doc['display_name']} [{$status}] (path: {$doc['file_rel_path']})\n";
}
?>
