<?php
/**
 * Quick migration script - Add file_rel_path column to documents
 */
require_once __DIR__ . '/includes/db.php';

try {
    $pdo = getPDO();
    
    // Check if column already exists
    $checkStmt = $pdo->query("SHOW COLUMNS FROM documents LIKE 'file_rel_path'");
    if ($checkStmt->rowCount() > 0) {
        echo "✅ Columna file_rel_path ya existe en la tabla documents\n";
        exit(0);
    }
    
    // Add column
    $pdo->exec("ALTER TABLE documents ADD COLUMN file_rel_path VARCHAR(1024) NULL AFTER stored_filename");
    echo "✅ Columna file_rel_path agregada exitosamente\n";
    
    // Add index
    $pdo->exec("ALTER TABLE documents ADD INDEX idx_documents_file_rel_path (file_rel_path(255))");
    echo "✅ Índice agregado exitosamente\n";
    
    // Verify
    $checkStmt = $pdo->query("SHOW COLUMNS FROM documents WHERE Field = 'file_rel_path'");
    if ($checkStmt->rowCount() > 0) {
        $col = $checkStmt->fetch(PDO::FETCH_ASSOC);
        echo "\n✅ MIGRACIÓN COMPLETADA\n";
        echo "Columna: " . $col['Field'] . "\n";
        echo "Tipo: " . $col['Type'] . "\n";
        echo "Permite NULL: " . $col['Null'] . "\n";
    }
    
} catch (PDOException $e) {
    echo "❌ Error: " . $e->getMessage() . "\n";
    exit(1);
}
?>
