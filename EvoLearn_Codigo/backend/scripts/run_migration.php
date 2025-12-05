<?php
/**
 * Script para ejecutar una migración SQL individual
 * Uso: php run_migration.php migrations/20251101_initial_schema.sql
 */

declare(strict_types=1);

if ($argc < 2) {
    echo "Uso: php run_migration.php <archivo.sql>\n";
    exit(1);
}

$sqlFile = $argv[1];

if (!file_exists($sqlFile)) {
    echo "ERROR: Archivo no encontrado: $sqlFile\n";
    exit(1);
}

require_once __DIR__ . '/../includes/bootstrap.php';

try {
    $pdo = getPDO();
    $sql = file_get_contents($sqlFile);
    
    echo "Ejecutando migración: " . basename($sqlFile) . "\n";
    
    // Dividir por ; para ejecutar múltiples statements
    // Filtrar comentarios y líneas vacías
    $statements = array_filter(
        array_map('trim', explode(';', $sql)),
        function($s) { 
            return !empty($s) && !preg_match('/^\s*--/', $s); 
        }
    );
    
    $pdo->beginTransaction();
    $count = 0;
    
    foreach ($statements as $stmt) {
        $stmt = trim($stmt);
        if (!empty($stmt)) {
            try {
                $pdo->exec($stmt);
                $count++;
            } catch (PDOException $e) {
                // Si es un error de "ya existe", continuar
                if (strpos($e->getMessage(), 'already exists') !== false ||
                    strpos($e->getMessage(), 'Duplicate') !== false) {
                    echo "  [SKIP] " . substr($stmt, 0, 50) . "... (ya existe)\n";
                    continue;
                }
                throw $e;
            }
        }
    }
    
    $pdo->commit();
    
    echo "SUCCESS: $count statements ejecutados\n";
    exit(0);
    
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    echo "ERROR: " . $e->getMessage() . "\n";
    echo "Archivo: " . $e->getFile() . "\n";
    echo "Línea: " . $e->getLine() . "\n";
    exit(1);
}
