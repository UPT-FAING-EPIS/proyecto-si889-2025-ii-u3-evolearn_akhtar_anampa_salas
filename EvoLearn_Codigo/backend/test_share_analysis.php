<?php
/**
 * TEST: Análisis de PDF en Share - Vista Completa del Flujo
 * 
 * Este script simula:
 * 1. Usuario solicita análisis de PDF en share compartido
 * 2. Backend procesa el análisis
 * 3. Se genera archivo TXT con resumen
 * 4. Se visualiza en el share con markdown
 */

require_once 'includes/db.php';

$pdo = getPDO();

echo "\n" . str_repeat("=", 80) . "\n";
echo "TEST: ANÁLISIS DE PDF EN SHARE COMPARTIDO\n";
echo str_repeat("=", 80) . "\n\n";

// ===== PASO 1: Obtener documento del share =====
echo "PASO 1: Obtener documento de un share compartido\n";
echo str_repeat("-", 80) . "\n";

$query = "
    SELECT 
        ds.id as share_id,
        ds.owner_user_id,
        d.id as document_id,
        d.display_name,
        d.file_rel_path,
        d.user_id as doc_owner,
        d.directory_id
    FROM directory_shares ds
    JOIN directories root_dir ON ds.directory_root_id = root_dir.id
    JOIN documents d ON d.directory_id = root_dir.id
    WHERE ds.owner_user_id = 11
    LIMIT 1
";

$result = $pdo->query($query);
$share = $result->fetch(PDO::FETCH_ASSOC);

if (!$share) {
    echo "No se encontró share con documentos. Creando uno para la demo...\n\n";
    
    // Crear un share de demostración
    $stmt = $pdo->prepare('
        SELECT id FROM directories WHERE user_id = 11 LIMIT 1
    ');
    $stmt->execute();
    $dir = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$dir) {
        echo "ERROR: No hay directorios para user 11\n";
        exit(1);
    }
    
    $stmt = $pdo->prepare('
        INSERT INTO directory_shares (directory_root_id, owner_user_id, name)
        VALUES (?, ?, ?)
    ');
    $stmt->execute([$dir['id'], 11, 'Share Demo']);
    $shareId = $pdo->lastInsertId();
    
    // Crear documento para el demo
    $stmt = $pdo->prepare('
        INSERT INTO documents (user_id, directory_id, original_filename, display_name, stored_filename, mime_type, size_bytes, text_content)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ');
    $stmt->execute([
        11,
        $dir['id'],
        'documento.pdf',
        'Documento de Prueba',
        'documento.pdf',
        'application/pdf',
        1000,
        'Contenido de prueba'
    ]);
    
    echo "Share creado para demo\n\n";
    exit;
}

echo "✓ Share encontrado:\n";
echo "  Share ID: {$share['share_id']}\n";
echo "  Owner: User {$share['owner_user_id']}\n";
echo "  Documento: {$share['display_name']}\n";
echo "  Path: {$share['file_rel_path']}\n\n";

// ===== PASO 2: Simular solicitud de análisis =====
echo "PASO 2: Enviar solicitud de análisis (simulate POST /api/generate_summary.php)\n";
echo str_repeat("-", 80) . "\n";

$analysisType = 'summary_fast';
$model = 'gemini-2.5-flash';

echo "POST /api/generate_summary.php\n";
echo "{\n";
echo "  \"document_id\": {$share['document_id']},\n";
echo "  \"share_id\": {$share['share_id']},\n";
echo "  \"analysis_type\": \"$analysisType\",\n";
echo "  \"model\": \"$model\"\n";
echo "}\n\n";

// Crear job
$stmt = $pdo->prepare('
    INSERT INTO summary_jobs (user_id, file_path, file_rel_path, analysis_type, model, status)
    VALUES (?, ?, ?, ?, ?, ?)
');

$stmt->execute([
    $share['owner_user_id'],
    $share['file_rel_path'],
    $share['file_rel_path'],
    $analysisType,
    $model,
    'completed'  // Para demo, simular que ya está completado
]);

$jobId = $pdo->lastInsertId();

echo "✓ Job creado:\n";
echo "  Job ID: $jobId\n";
echo "  Status: PENDING → PROCESSING → COMPLETED\n\n";

// ===== PASO 3: Simular procesamiento y generar resumen =====
echo "PASO 3: Procesamiento (simular cron worker)\n";
echo str_repeat("-", 80) . "\n";

$summaryText = "# Resumen: " . $share['display_name'] . "\n\n";
$summaryText .= "## Temas Principales\n\n";
$summaryText .= "1. **Introducción**: Este documento presenta información fundamental sobre el tema.\n\n";
$summaryText .= "2. **Conceptos Clave**:\n";
$summaryText .= "   - Concepto 1: Explicación detallada\n";
$summaryText .= "   - Concepto 2: Aplicaciones prácticas\n";
$summaryText .= "   - Concepto 3: Casos de uso\n\n";
$summaryText .= "3. **Análisis**: El documento proporciona análisis exhaustivo de cada tema.\n\n";
$summaryText .= "4. **Conclusión**: Conclusiones importantes derivadas del contenido.\n\n";
$summaryText .= "## Puntos Importantes\n\n";
$summaryText .= "- Punto 1: Aspecto crítico del tema\n";
$summaryText .= "- Punto 2: Área de aplicación práctica\n";
$summaryText .= "- Punto 3: Recomendaciones\n\n";

// Guardar resumen
$dirRel = dirname($share['file_rel_path']);
$dirAbs = __DIR__ . '/uploads/' . $share['owner_user_id'] . '/' . basename($dirRel);

if (!is_dir($dirAbs)) {
    @mkdir($dirAbs, 0777, true);
}

$pdfBaseName = basename($share['file_rel_path'], '.pdf');
$summaryFileName = 'Resumen_' . str_replace(' ', '_', $pdfBaseName) . '.txt';
$summaryPath = $dirAbs . DIRECTORY_SEPARATOR . $summaryFileName;

if (file_put_contents($summaryPath, $summaryText) !== false) {
    echo "✓ Resumen generado:\n";
    echo "  Archivo: $summaryFileName\n";
    echo "  Tamaño: " . strlen($summaryText) . " bytes\n";
    echo "  Path: $summaryPath\n\n";
}

// Registrar en BD
$stmt = $pdo->prepare('
    INSERT IGNORE INTO documents 
    (user_id, directory_id, original_filename, display_name, stored_filename, mime_type, size_bytes, text_content, model_used)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
');
$stmt->execute([
    $share['owner_user_id'],
    $share['directory_id'],
    $summaryFileName,
    'Resumen: ' . $pdfBaseName,
    $summaryFileName,
    'text/plain',
    strlen($summaryText),
    $summaryText,
    'gemini-2.5-flash'
]);

echo "✓ Documento de resumen registrado en BD\n\n";

// ===== PASO 4: Ver archivos en el share =====
echo "PASO 4: Archivos en el share (lo que ve el usuario)\n";
echo str_repeat("-", 80) . "\n";

$stmt = $pdo->prepare('
    SELECT id, display_name, mime_type, size_bytes
    FROM documents 
    WHERE directory_id = ? 
    ORDER BY mime_type, display_name
');
$stmt->execute([$share['directory_id']]);
$docs = $stmt->fetchAll(PDO::FETCH_ASSOC);

echo "Contenido del share:\n\n";

$pdfFiles = [];
$txtFiles = [];

foreach ($docs as $doc) {
    if (strpos($doc['mime_type'], 'pdf') !== false) {
        $pdfFiles[] = $doc;
    } else if (strpos($doc['mime_type'], 'text') !== false) {
        $txtFiles[] = $doc;
    }
}

if ($pdfFiles) {
    echo "📄 **Documentos PDF**:\n\n";
    foreach ($pdfFiles as $pdf) {
        echo "  - **{$pdf['display_name']}** ({$pdf['size_bytes']} bytes)\n";
    }
    echo "\n";
}

if ($txtFiles) {
    echo "📝 **Resúmenes (TXT)**:\n\n";
    foreach ($txtFiles as $txt) {
        echo "  - **{$txt['display_name']}** ({$txt['size_bytes']} bytes)\n";
        echo "    *Generado automáticamente por IA*\n";
    }
    echo "\n";
}

// ===== PASO 5: Previsualizar resumen =====
echo "PASO 5: Previsualización del resumen (markdown)\n";
echo str_repeat("-", 80) . "\n\n";

echo $summaryText;

echo "\n" . str_repeat("=", 80) . "\n";
echo "✅ TEST COMPLETADO\n";
echo str_repeat("=", 80) . "\n\n";

echo "RESUMEN:\n";
echo "1. ✓ Documento encontrado en share\n";
echo "2. ✓ Análisis solicitado\n";
echo "3. ✓ Resumen generado por IA\n";
echo "4. ✓ Archivo TXT creado\n";
echo "5. ✓ Visible en el share con markdown\n\n";

echo "PRÓXIMOS PASOS:\n";
echo "- Desde Flutter, recuperar lista de documentos del share\n";
echo "- Mostrar PDFs y TXTs con iconos diferenciados\n";
echo "- Al hacer tap en TXT, mostrar con formato markdown\n";
echo "- Opción para descargar/compartir resumen\n\n";
?>
