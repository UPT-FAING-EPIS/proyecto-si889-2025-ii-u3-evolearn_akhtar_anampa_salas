<?php
// Script para ejecutar database.sql en la BD remota
require_once __DIR__ . '/includes/db.php';

try {
    $pdo = getPDO();
    $sql = file_get_contents(__DIR__ . '/database.sql');
    
    // Dividir por `;` y ejecutar cada statement
    $statements = array_filter(array_map('trim', explode(';', $sql)));
    
    $successCount = 0;
    $errorCount = 0;
    
    foreach ($statements as $statement) {
        if (!empty($statement) && !preg_match('/^--/', $statement)) {  // Skip comments
            try {
                $pdo->exec($statement);
                $successCount++;
                echo "✓ " . substr(preg_replace('/\s+/', ' ', $statement), 0, 70) . "...\n";
            } catch (Exception $e) {
                $msg = $e->getMessage();
                // Ignorar errores de base de datos/tablas existentes
                if (strpos($msg, 'already exists') !== false || strpos($msg, '1007') !== false) {
                    echo "⊘ Skipped (already exists): " . substr($statement, 0, 50) . "...\n";
                } else {
                    $errorCount++;
                    echo "✗ Failed: " . substr($statement, 0, 50) . "...\n";
                    echo "  Error: " . $msg . "\n";
                }
            }
        }
    }
    
    echo "\n========================================\n";
    echo "✓ Successful: $successCount\n";
    echo "✗ Failed: $errorCount\n";
    echo "========================================\n";
    
    if ($errorCount === 0) {
        echo "✓ Database setup completed!\n";
    }
    
} catch (Exception $e) {
    echo "✗ Critical Error: " . $e->getMessage() . "\n";
    exit(1);
}
