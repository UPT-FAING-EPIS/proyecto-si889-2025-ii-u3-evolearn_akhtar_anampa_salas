<?php
/**
 * Ejecuta la migración del sistema de compartir
 */

require_once __DIR__ . '/../includes/db.php';

echo "=== EJECUTANDO MIGRACION: Sistema de Compartir ===\n\n";

try {
    $pdo = getPDO();
    
    // Leer el archivo de migración
    $sqlFile = __DIR__ . '/migrations/20251118_add_sharing_system.sql';
    
    if (!file_exists($sqlFile)) {
        die("Error: No se encontró el archivo de migración en: $sqlFile\n");
    }
    
    $sql = file_get_contents($sqlFile);
    
    echo "Leyendo migración desde: $sqlFile\n";
    echo "Ejecutando SQL...\n\n";
    
    // Ejecutar el SQL
    $pdo->exec($sql);
    
    echo "✓ Migración completada exitosamente!\n\n";
    
    // Verificar las tablas creadas
    echo "=== TABLAS CREADAS ===\n";
    $tables = ['directory_shares', 'directory_share_nodes', 'directory_share_users', 'directory_events'];
    
    foreach ($tables as $table) {
        $stmt = $pdo->query("SHOW TABLES LIKE '$table'");
        if ($stmt->rowCount() > 0) {
            echo "✓ $table\n";
        } else {
            echo "✗ $table (NO CREADA)\n";
        }
    }
    
    echo "\n=== VERIFICANDO COLUMNAS EN directories ===\n";
    $stmt = $pdo->query("SHOW COLUMNS FROM directories LIKE 'cloud_%'");
    $columns = $stmt->fetchAll();
    
    if (count($columns) > 0) {
        foreach ($columns as $col) {
            echo "✓ " . $col['Field'] . "\n";
        }
    } else {
        echo "✗ No se encontraron columnas cloud_*\n";
    }
    
    echo "\n¡Migración completada!\n";
    
} catch (PDOException $e) {
    echo "✗ Error al ejecutar la migración:\n";
    echo "  Código: " . $e->getCode() . "\n";
    echo "  Mensaje: " . $e->getMessage() . "\n";
    exit(1);
}
