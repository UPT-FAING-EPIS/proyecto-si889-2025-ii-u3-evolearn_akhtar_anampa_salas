<?php
require_once 'includes/db.php';

$pdo = getPDO();

echo "📋 Verificando job creado...\n\n";

// Ver el job que se acaba de crear
$query = "SELECT id, user_id, file_path, file_rel_path, analysis_type, model, status, created_at
         FROM summary_jobs
         WHERE id = 66";

$result = $pdo->query($query);
$job = $result->fetch(PDO::FETCH_ASSOC);

if ($job) {
    echo "✓ Job ID: {$job['id']}\n";
    echo "  User ID: {$job['user_id']}\n";
    echo "  File path: {$job['file_path']}\n";
    echo "  File rel path: {$job['file_rel_path']}\n";
    echo "  Analysis type: {$job['analysis_type']}\n";
    echo "  Model: {$job['model']}\n";
    echo "  Status: {$job['status']}\n";
    echo "  Created: {$job['created_at']}\n";
    
    // Verificar que el archivo existe
    echo "\n📂 Verificando archivo:\n";
    $filePath = __DIR__ . '/' . $job['file_rel_path'];
    $exists = file_exists($filePath);
    echo "  Ruta: {$filePath}\n";
    echo "  Existe: " . ($exists ? "✓ SÍ" : "✗ NO") . "\n";
    
    if ($exists) {
        $size = filesize($filePath);
        echo "  Tamaño: " . ($size / 1024) . " KB\n";
    }
} else {
    echo "✗ Job no encontrado\n";
}

// Ver documentos relacionados
echo "\n📄 Documento relacionado:\n";
$docQuery = "SELECT id, display_name, user_id, directory_id, file_rel_path
            FROM documents
            WHERE id = 1";

$docResult = $pdo->query($docQuery);
$doc = $docResult->fetch(PDO::FETCH_ASSOC);

if ($doc) {
    echo "  ID: {$doc['id']}\n";
    echo "  Nombre: {$doc['display_name']}\n";
    echo "  User ID: {$doc['user_id']}\n";
    echo "  Dir ID: {$doc['directory_id']}\n";
    echo "  File rel path: {$doc['file_rel_path']}\n";
}
?>
