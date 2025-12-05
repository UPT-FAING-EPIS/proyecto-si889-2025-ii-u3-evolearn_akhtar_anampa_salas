<?php
/**
 * Script para verificar el estado del esquema de la base de datos
 */

declare(strict_types=1);
require_once __DIR__ . '/../includes/bootstrap.php';

$pdo = getPDO();

echo "========================================\n";
echo "  Verificación del esquema actual\n";
echo "========================================\n\n";

// 1. Listar todas las tablas
echo "📋 Tablas existentes:\n";
$stmt = $pdo->query("SHOW TABLES");
$tables = $stmt->fetchAll(PDO::FETCH_COLUMN);
foreach ($tables as $table) {
    echo "  ✓ $table\n";
}

echo "\n";

// 2. Verificar estructura de summary_jobs (tabla clave para migraciones)
if (in_array('summary_jobs', $tables)) {
    echo "📊 Estructura de summary_jobs:\n";
    $stmt = $pdo->query("DESCRIBE summary_jobs");
    $columns = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    foreach ($columns as $col) {
        $nullable = $col['Null'] === 'YES' ? 'NULL' : 'NOT NULL';
        $default = $col['Default'] ? "DEFAULT {$col['Default']}" : '';
        echo sprintf("  %-20s %-30s %s %s\n", 
            $col['Field'], 
            $col['Type'], 
            $nullable,
            $default
        );
    }
    
    echo "\n📑 Índices de summary_jobs:\n";
    $stmt = $pdo->query("SHOW INDEX FROM summary_jobs");
    $indexes = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $uniqueIndexes = [];
    foreach ($indexes as $idx) {
        $key = $idx['Key_name'];
        if (!isset($uniqueIndexes[$key])) {
            $uniqueIndexes[$key] = [];
        }
        $uniqueIndexes[$key][] = $idx['Column_name'];
    }
    
    foreach ($uniqueIndexes as $name => $cols) {
        echo "  ✓ $name: " . implode(', ', $cols) . "\n";
    }
}

echo "\n";

// 3. Verificar enum de status
echo "🔍 Valores ENUM de summary_jobs.status:\n";
$stmt = $pdo->query("SHOW COLUMNS FROM summary_jobs LIKE 'status'");
$statusCol = $stmt->fetch(PDO::FETCH_ASSOC);
if ($statusCol) {
    echo "  " . $statusCol['Type'] . "\n";
    
    // Verificar si incluye 'canceled'
    if (strpos($statusCol['Type'], 'canceled') !== false) {
        echo "  ✓ Estado 'canceled' disponible\n";
    } else {
        echo "  ✗ Estado 'canceled' NO disponible\n";
    }
}

echo "\n";

// 4. Contar registros
echo "📈 Registros en tablas principales:\n";
$mainTables = ['users', 'directories', 'documents', 'summary_jobs'];
foreach ($mainTables as $table) {
    if (in_array($table, $tables)) {
        $stmt = $pdo->query("SELECT COUNT(*) FROM $table");
        $count = $stmt->fetchColumn();
        echo "  $table: $count registros\n";
    }
}

echo "\n";

// 5. Verificar columna file_rel_path
if (in_array('summary_jobs', $tables)) {
    $stmt = $pdo->query("SHOW COLUMNS FROM summary_jobs LIKE 'file_rel_path'");
    $col = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($col) {
        echo "✓ Columna file_rel_path existe\n";
    } else {
        echo "✗ Columna file_rel_path NO existe\n";
    }
}

echo "\n========================================\n";
echo "  Verificación completada\n";
echo "========================================\n";
