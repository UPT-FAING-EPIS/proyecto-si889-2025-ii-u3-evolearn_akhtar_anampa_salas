<?php
require_once __DIR__ . '/../includes/db.php';

echo "=== VERIFICANDO ESTRUCTURA DE TABLA directory_shares ===\n\n";

try {
    $pdo = getPDO();
    
    // Verificar si la tabla existe
    $stmt = $pdo->query("SHOW TABLES LIKE 'directory_shares'");
    if ($stmt->rowCount() === 0) {
        echo "✗ La tabla 'directory_shares' NO EXISTE\n";
        echo "   Necesitas ejecutar la migración 20251118_add_sharing_system.sql\n";
        exit(1);
    }
    
    echo "✓ La tabla 'directory_shares' existe\n\n";
    
    // Mostrar estructura de la tabla
    echo "=== ESTRUCTURA DE LA TABLA ===\n";
    $stmt = $pdo->query("DESCRIBE directory_shares");
    $columns = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    foreach ($columns as $col) {
        $null = $col['Null'] === 'NO' ? 'NOT NULL' : 'NULL';
        $default = $col['Default'] ? "DEFAULT {$col['Default']}" : '';
        echo sprintf("%-20s %-15s %-10s %s\n", 
            $col['Field'], 
            $col['Type'], 
            $null,
            $default
        );
    }
    
    echo "\n=== VERIFICACIÓN ===\n";
    
    $requiredColumns = ['directory_root_id', 'owner_user_id', 'name', 'description'];
    foreach ($requiredColumns as $colName) {
        $found = false;
        foreach ($columns as $col) {
            if ($col['Field'] === $colName) {
                $found = true;
                echo "✓ $colName\n";
                break;
            }
        }
        if (!$found) {
            echo "✗ $colName (FALTA)\n";
        }
    }
    
} catch (PDOException $e) {
    echo "✗ Error: " . $e->getMessage() . "\n";
    exit(1);
}
