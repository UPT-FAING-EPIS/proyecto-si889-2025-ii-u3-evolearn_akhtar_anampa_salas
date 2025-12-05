<?php
// Verificar que las tablas existen
require_once __DIR__ . '/includes/db.php';

try {
    $pdo = getPDO();
    
    // Obtener lista de tablas
    $stmt = $pdo->query("SHOW TABLES");
    $tables = $stmt->fetchAll(PDO::FETCH_COLUMN);
    
    echo "Tablas en la base de datos:\n";
    echo "================================\n";
    foreach ($tables as $table) {
        echo "✓ " . $table . "\n";
    }
    
    echo "\n================================\n";
    echo "Total: " . count($tables) . " tablas\n";
    
    // Verificar estructura de user_courses
    if (in_array('user_courses', $tables)) {
        echo "\n✓ Tabla 'user_courses' existe!\n";
        echo "Estructura:\n";
        
        $stmt = $pdo->query("DESCRIBE user_courses");
        $columns = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        foreach ($columns as $col) {
            echo "  - {$col['Field']}: {$col['Type']}";
            if ($col['Key']) echo " [" . $col['Key'] . "]";
            echo "\n";
        }
    } else {
        echo "\n✗ Tabla 'user_courses' NO existe!\n";
    }
    
} catch (Exception $e) {
    echo "✗ Error: " . $e->getMessage() . "\n";
    exit(1);
}
