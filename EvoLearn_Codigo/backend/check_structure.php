<?php
require_once 'includes/db.php';

$pdo = getPDO();

echo "🔍 Verificando estructura de shares para user 11...\n\n";

// Ver qué tablas existen
$query = "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'estudiafacil' ORDER BY TABLE_NAME";
$result = $pdo->query($query);
$tables = $result->fetchAll(PDO::FETCH_COLUMN);

echo "Tablas en la BD:\n";
foreach ($tables as $table) {
    echo "  - $table\n";
}

echo "\n" . str_repeat("=", 50) . "\n\n";

// Probar diferentes queries
echo "🔎 Buscando información de shares de user 11...\n\n";

// Query 1: Ver si hay registros en directory_shares
try {
    $query = "SELECT * FROM directory_shares WHERE directory_id IN (
              SELECT id FROM directories WHERE user_id = 11) LIMIT 1";
    $result = $pdo->query($query);
    $row = $result->fetch(PDO::FETCH_ASSOC);
    
    if ($row) {
        echo "✓ Found directory_share record:\n";
        print_r($row);
    } else {
        echo "✗ No directory_shares found\n";
    }
} catch (Exception $e) {
    echo "✗ Error querying directory_shares: " . $e->getMessage() . "\n";
}

echo "\n";

// Query 2: Ver documentos directos del user
try {
    $query = "SELECT d.id, d.display_name, d.user_id, d.directory_id, d.file_rel_path
             FROM documents d
             WHERE d.user_id = 11 LIMIT 5";
    $result = $pdo->query($query);
    $docs = $result->fetchAll(PDO::FETCH_ASSOC);
    
    echo "Documentos de user 11: " . count($docs) . "\n";
    foreach ($docs as $doc) {
        echo "  ID {$doc['id']}: {$doc['display_name']} (path: {$doc['file_rel_path']})\n";
    }
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

echo "\n";

// Query 3: Ver directorios
try {
    $query = "SELECT id, name FROM directories WHERE user_id = 11";
    $result = $pdo->query($query);
    $dirs = $result->fetchAll(PDO::FETCH_ASSOC);
    
    echo "Directorios de user 11: " . count($dirs) . "\n";
    foreach ($dirs as $dir) {
        echo "  ID {$dir['id']}: {$dir['name']}\n";
    }
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
