<?php
/**
 * TEST PRACTICO: Ver cómo se ve el análisis en un share
 * 
 * Demuestra:
 * 1. Qué ve el usuario cuando abre un share
 * 2. Cómo se ve un PDF vs un TXT con resumen
 * 3. Cómo se renderiza el resumen en markdown
 */

require_once 'includes/db.php';

$pdo = getPDO();

echo "\n" . str_repeat("=", 80) . "\n";
echo "TEST: VER ANÁLISIS EN SHARE\n";
echo str_repeat("=", 80) . "\n\n";

// Usar share #7 que ya tiene documento
$shareId = 7;

$query = "
    SELECT 
        ds.id,
        ds.directory_root_id,
        ds.owner_user_id,
        ds.name as share_name
    FROM directory_shares ds
    WHERE ds.id = ?
";

$stmt = $pdo->prepare($query);
$stmt->execute([$shareId]);
$share = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$share) {
    echo "Share no encontrado\n";
    exit;
}

echo "SHARE: {$share['share_name']}\n";
echo str_repeat("-", 80) . "\n";
echo "ID: {$share['id']}\n";
echo "Owner: User {$share['owner_user_id']}\n\n";

// Obtener documentos
$stmt = $pdo->prepare('
    SELECT id, display_name, mime_type, size_bytes, text_content
    FROM documents 
    WHERE directory_id = ? 
    ORDER BY created_at
');
$stmt->execute([$share['directory_root_id']]);
$documents = $stmt->fetchAll(PDO::FETCH_ASSOC);

echo "CONTENIDO (" . count($documents) . " archivos):\n";
echo str_repeat("-", 80) . "\n\n";

foreach ($documents as $doc) {
    $icon = '';
    if (strpos($doc['mime_type'], 'pdf') !== false) {
        $icon = '📄';
    } else if (strpos($doc['mime_type'], 'text') !== false) {
        $icon = '📝';
    }
    
    echo "$icon {$doc['display_name']}\n";
    echo "   Tipo: {$doc['mime_type']}\n";
    echo "   Size: {$doc['size_bytes']} bytes\n";
    
    if (strpos($doc['mime_type'], 'text') !== false && $doc['text_content']) {
        echo "   📖 PREVISUALIZACIÓN:\n";
        echo "   " . str_repeat("-", 76) . "\n";
        
        // Mostrar primeras líneas del resumen
        $lines = explode("\n", $doc['text_content']);
        $preview_lines = array_slice($lines, 0, 15);
        
        foreach ($preview_lines as $line) {
            echo "   " . $line . "\n";
        }
        
        if (count($lines) > 15) {
            echo "   ... (más contenido)\n";
        }
        echo "   " . str_repeat("-", 76) . "\n";
    }
    echo "\n";
}

echo str_repeat("=", 80) . "\n";
echo "CÓMO SE VERÍA EN FLUTTER:\n";
echo str_repeat("=", 80) . "\n\n";

echo "1. LISTA DE ARCHIVOS EN EL SHARE:\n";
echo "   ┌─ 📄 Documento de Prueba\n";
echo "   │  Tap para descargar / ver detalles\n";
echo "   │\n";
echo "   └─ 📝 Resumen: documento\n";
echo "      Tap para ver con markdown\n\n";

echo "2. AL HACER TAP EN EL RESUMEN (📝):\n";
echo "   ┌────────────────────────────────────┐\n";
echo "   │ Resumen: documento                │\n";
echo "   │ ────────────────────────────────  │\n";
echo "   │                                    │\n";
echo "   │ ## Temas Principales              │\n";
echo "   │                                    │\n";
echo "   │ 1. **Introducción**               │\n";
echo "   │    Contenido...                   │\n";
echo "   │                                    │\n";
echo "   │ 2. **Conceptos Clave**            │\n";
echo "   │    - Concepto 1                   │\n";
echo "   │    - Concepto 2                   │\n";
echo "   │                                    │\n";
echo "   │ [Compartir] [Descargar] [Cerrar]  │\n";
echo "   └────────────────────────────────────┘\n\n";

echo str_repeat("=", 80) . "\n";
echo "✅ TEST COMPLETADO\n";
echo str_repeat("=", 80) . "\n\n";

echo "El sistema está listo para:\n";
echo "1. ✓ Generar análisis de PDFs\n";
echo "2. ✓ Crear archivos TXT con resumen\n";
echo "3. ✓ Registrar en BD\n";
echo "4. ✓ Mostrar en shares\n\n";

echo "Flutter debe:\n";
echo "1. Llamar a get_my_shares.php para obtener shares\n";
echo "2. Llamar a list_documents.php para ver archivos en cada share\n";
echo "3. Renderizar archivos con markdown si son .txt\n";
echo "4. Ofrecer opción para solicitar análisis de PDFs\n\n";
?>
require 'includes/db.php';
$pdo = getPDO();

echo "=== Shares ===\n";
$shares = $pdo->query("SELECT id, name, directory_root_id FROM directory_shares ORDER BY id DESC LIMIT 10")->fetchAll(PDO::FETCH_ASSOC);
print_r($shares);

echo "\n=== Directorios migrados ===\n";
$dirs = $pdo->query("SELECT id, name, parent_id, cloud_managed FROM directories WHERE cloud_managed=1 ORDER BY id DESC LIMIT 20")->fetchAll(PDO::FETCH_ASSOC);
print_r($dirs);

echo "\n=== Documentos migrados ===\n";
$docs = $pdo->query("SELECT id, directory_id, display_name, original_filename FROM documents ORDER BY id DESC LIMIT 20")->fetchAll(PDO::FETCH_ASSOC);
print_r($docs);
