<?php
// Script to apply migration: add_profile_image.sql
// This script adds profile image columns to users table

// Conexión directa a MySQL
try {
    $pdo = new PDO(
        'mysql:host=161.132.49.24;dbname=estudiafacil;charset=utf8mb4',
        'php_user',
        'psswdphp8877'
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    echo "❌ ERROR de conexión a base de datos:\n";
    echo $e->getMessage() . "\n";
    exit(1);
}

try {
    echo "Iniciando migration: add_profile_image.sql\n";
    echo "===============================================\n\n";

    // SQL statements to execute
    $statements = [
        "ALTER TABLE users ADD COLUMN profile_image_path VARCHAR(512) NULL 
          COMMENT 'Path to user profile image file' AFTER password_hash",
        
        "ALTER TABLE users ADD COLUMN profile_image_updated_at DATETIME NULL 
          COMMENT 'Timestamp of last profile image update' AFTER profile_image_path",
        
        "ALTER TABLE users ADD INDEX idx_users_profile_image (profile_image_path)"
    ];

    foreach ($statements as $index => $sql) {
        echo "Ejecutando statement " . ($index + 1) . " de " . count($statements) . "...\n";
        
        try {
            $pdo->exec($sql);
            echo "✓ Completado exitosamente\n\n";
        } catch (PDOException $e) {
            // Check if the column already exists (common error on re-run)
            if (strpos($e->getMessage(), 'Duplicate column name') !== false) {
                echo "⚠ Columna ya existe (probablemente ya fue aplicada)\n\n";
            } else {
                throw $e;
            }
        }
    }

    echo "===============================================\n";
    echo "Verificando estructura de tabla users...\n\n";

    // Verify the columns exist
    $result = $pdo->query("DESCRIBE users");
    $columns = $result->fetchAll(PDO::FETCH_ASSOC);

    $profileImagePath = false;
    $profileImageUpdatedAt = false;

    foreach ($columns as $col) {
        if ($col['Field'] === 'profile_image_path') {
            $profileImagePath = true;
            echo "✓ Columna 'profile_image_path' encontrada\n";
            echo "  Tipo: " . $col['Type'] . "\n";
            echo "  Nullable: " . ($col['Null'] === 'YES' ? 'SÍ' : 'NO') . "\n\n";
        }
        if ($col['Field'] === 'profile_image_updated_at') {
            $profileImageUpdatedAt = true;
            echo "✓ Columna 'profile_image_updated_at' encontrada\n";
            echo "  Tipo: " . $col['Type'] . "\n";
            echo "  Nullable: " . ($col['Null'] === 'YES' ? 'SÍ' : 'NO') . "\n\n";
        }
    }

    if ($profileImagePath && $profileImageUpdatedAt) {
        echo "===============================================\n";
        echo "✅ MIGRATION COMPLETADA EXITOSAMENTE\n";
        echo "===============================================\n";
        echo "\nLas columnas de foto de perfil han sido agregadas a la tabla 'users':\n";
        echo "- profile_image_path: Almacena la ruta del archivo de imagen\n";
        echo "- profile_image_updated_at: Almacena la fecha de última actualización\n";
    } else {
        echo "⚠ ERROR: No se encontraron todas las columnas esperadas\n";
        if (!$profileImagePath) echo "  - Falta: profile_image_path\n";
        if (!$profileImageUpdatedAt) echo "  - Falta: profile_image_updated_at\n";
        exit(1);
    }

} catch (Exception $e) {
    echo "❌ ERROR durante la migration:\n";
    echo $e->getMessage() . "\n";
    exit(1);
}
?>
