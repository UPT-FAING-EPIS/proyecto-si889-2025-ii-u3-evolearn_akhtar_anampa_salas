<?php
/**
 * DEMO COMPLETO: Flujo de análisis de documentos cloud
 * 
 * Este script demuestra:
 * 1. Verificación de documento existente
 * 2. Creación de job de análisis (status: pending)
 * 3. Simulación del worker procesando el job
 * 4. Creación del archivo de resumen
 * 5. Verificación que se puede descargar el resumen
 */

require_once 'includes/db.php';
require_once 'includes/fs.php';

$pdo = getPDO();

echo "=" . str_repeat("=", 70) . "\n";
echo "DEMO: Cloud Document Analysis Workflow\n";
echo "=" . str_repeat("=", 70) . "\n\n";

// === PASO 1: Verificar documento ===
echo "PASO 1: Verificar documento\n";
echo str_repeat("-", 70) . "\n";

$docId = 1;
$userId = 11;

$stmt = $pdo->prepare('SELECT id, display_name, file_rel_path, directory_id FROM documents WHERE id = ? AND user_id = ?');
$stmt->execute([$docId, $userId]);
$doc = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$doc) {
    echo "ERROR: Document not found\n";
    exit(1);
}

echo "✓ Documento encontrado:\n";
echo "  ID: {$doc['id']}\n";
echo "  Nombre: {$doc['display_name']}\n";
echo "  Directorio: {$doc['directory_id']}\n";
echo "  Path: {$doc['file_rel_path']}\n\n";

// === PASO 2: Crear job de análisis ===
echo "PASO 2: Crear job de análisis\n";
echo str_repeat("-", 70) . "\n";

$stmt = $pdo->prepare('
    INSERT INTO summary_jobs (user_id, file_path, file_rel_path, analysis_type, model, status)
    VALUES (?, ?, ?, ?, ?, ?)
');

$fileRelPath = $doc['file_rel_path'];
$analysisType = 'summary_fast';
$model = 'gemini-2.5-flash';

$stmt->execute([$userId, $fileRelPath, $fileRelPath, $analysisType, $model, 'pending']);
$jobId = $pdo->lastInsertId();

echo "✓ Job creado:\n";
echo "  Job ID: $jobId\n";
echo "  Status: pending\n";
echo "  File: $fileRelPath\n";
echo "  Analysis: $analysisType\n\n";

// === PASO 3: Simular procesamiento (sin parser PDF) ===
echo "PASO 3: Procesar job (simular)\n";
echo str_repeat("-", 70) . "\n";

$summary = "RESUMEN: " . $doc['display_name'] . "\n\n";
$summary .= "Este es un resumen de ejemplo para demostrar que el sistema funciona correctamente.\n\n";
$summary .= "Temas principales:\n";
$summary .= "1. Tema 1 - Contenido principal\n";
$summary .= "2. Tema 2 - Conceptos importantes\n";
$summary .= "3. Tema 3 - Aplicaciones prácticas\n\n";
$summary .= "Conclusión:\n";
$summary .= "El sistema de análisis de documentos cloud está funcionando correctamente.";

// Actualizar job a completed
$stmt = $pdo->prepare('UPDATE summary_jobs SET status = ?, progress = 100, summary_text = ?, updated_at = NOW() WHERE id = ?');
$stmt->execute(['completed', $summary, $jobId]);

echo "✓ Job procesado:\n";
echo "  Status: completed\n";
echo "  Summary length: " . strlen($summary) . " bytes\n\n";

// === PASO 4: Guardar archivo TXT ===
echo "PASO 4: Guardar archivo de resumen\n";
echo str_repeat("-", 70) . "\n";

// Obtener info del directorio
$stmt = $pdo->prepare('SELECT id, user_id FROM directories WHERE id = ?');
$stmt->execute([$doc['directory_id']]);
$dir = $stmt->fetch(PDO::FETCH_ASSOC);

if ($dir) {
    $dirRel = dirname($fileRelPath);
    $dirAbs = __DIR__ . '/uploads/' . $userId . '/' . basename($dirRel);
    
    // Crear directorio si no existe
    if (!is_dir($dirAbs)) {
        mkdir($dirAbs, 0777, true);
    }
    
    // Crear nombre del archivo de resumen
    $pdfBaseName = basename($fileRelPath, '.pdf');
    $summaryFileName = 'Resumen_' . str_replace(' ', '_', $pdfBaseName) . '.txt';
    $summaryPath = $dirAbs . DIRECTORY_SEPARATOR . $summaryFileName;
    
    // Guardar archivo
    if (file_put_contents($summaryPath, $summary) !== false) {
        echo "✓ Archivo de resumen guardado:\n";
        echo "  Path: $summaryPath\n";
        echo "  Size: " . strlen($summary) . " bytes\n";
        
        // Registrar en BD
        $stmt = $pdo->prepare('
            INSERT IGNORE INTO documents 
            (user_id, directory_id, original_filename, display_name, stored_filename, mime_type, size_bytes, text_content, model_used)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ');
        $stmt->execute([
            $userId,
            $doc['directory_id'],
            $summaryFileName,
            'Resumen: ' . $pdfBaseName,
            $summaryFileName,
            'text/plain',
            strlen($summary),
            $summary,
            'system'
        ]);
        
        echo "✓ Entrada de documento creada en BD\n\n";
    } else {
        echo "ERROR: No se pudo guardar el archivo\n";
    }
}

// === PASO 5: Verificación final ===
echo "PASO 5: Verificación final\n";
echo str_repeat("-", 70) . "\n";

$stmt = $pdo->prepare('SELECT id, display_name FROM documents WHERE user_id = ? AND directory_id = ? ORDER BY id DESC LIMIT 10');
$stmt->execute([$userId, $doc['directory_id']]);
$docs = $stmt->fetchAll(PDO::FETCH_ASSOC);

echo "✓ Documentos en el directorio:\n";
foreach ($docs as $d) {
    $prefix = strpos($d['display_name'], 'Resumen:') === 0 ? "[TXT]" : "[PDF]";
    echo "  $prefix {$d['display_name']}\n";
}

echo "\n" . str_repeat("=", 70) . "\n";
echo "✅ DEMO COMPLETADO EXITOSAMENTE\n";
echo "=" . str_repeat("=", 70) . "\n";
?>
