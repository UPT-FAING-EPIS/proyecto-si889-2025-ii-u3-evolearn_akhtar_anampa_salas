<?php
/**
 * Migration: Add sharing system tables and columns
 * Date: 2025-11-18
 * Description: Adds complete sharing system with directory_shares, share_nodes, share_users, and events
 */

declare(strict_types=1);
require_once __DIR__ . '/../../includes/bootstrap.php';

$pdo = getPDO();

echo "Ejecutando migración: Add Sharing System\n";
echo "========================================\n\n";

try {
    $pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
    $pdo->setAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, true);
    
    // ============================================
    // 1. Add cloud management columns to directories
    // ============================================
    
    echo "1. Agregando columnas cloud a directories...\n";
    
    // Check if cloud_managed exists
    $stmt = $pdo->query("SHOW COLUMNS FROM directories LIKE 'cloud_managed'");
    if (!$stmt->fetch()) {
        $pdo->exec("ALTER TABLE directories ADD COLUMN cloud_managed TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Indica si el directorio está gestionado en la nube (1) o solo local (0)'");
        echo "   ✓ Columna cloud_managed creada\n";
    } else {
        echo "   - Columna cloud_managed ya existe\n";
    }
    
    // Check if cloud_directory_id exists
    $stmt = $pdo->query("SHOW COLUMNS FROM directories LIKE 'cloud_directory_id'");
    if (!$stmt->fetch()) {
        $pdo->exec("ALTER TABLE directories ADD COLUMN cloud_directory_id INT NULL COMMENT 'ID del directorio en la nube si fue sincronizado'");
        echo "   ✓ Columna cloud_directory_id creada\n";
    } else {
        echo "   - Columna cloud_directory_id ya existe\n";
    }
    
    // Check if index exists
    $stmt = $pdo->query("SHOW INDEX FROM directories WHERE Key_name = 'idx_directories_cloud'");
    if (!$stmt->fetch()) {
        $pdo->exec("ALTER TABLE directories ADD INDEX idx_directories_cloud (cloud_managed, cloud_directory_id)");
        echo "   ✓ Índice idx_directories_cloud creado\n";
    } else {
        echo "   - Índice idx_directories_cloud ya existe\n";
    }
    
    echo "\n";
    
    // ============================================
    // 2. Directory Shares
    // ============================================
    
    echo "2. Creando tabla directory_shares...\n";
    
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS directory_shares (
          id INT AUTO_INCREMENT PRIMARY KEY,
          directory_root_id INT NOT NULL COMMENT 'Directorio raíz que se comparte',
          owner_user_id INT NOT NULL COMMENT 'Usuario propietario del share',
          name VARCHAR(255) NULL COMMENT 'Nombre descriptivo del share (opcional)',
          description TEXT NULL COMMENT 'Descripción del share',
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          
          FOREIGN KEY (directory_root_id) REFERENCES directories(id) ON DELETE CASCADE,
          FOREIGN KEY (owner_user_id) REFERENCES users(id) ON DELETE CASCADE,
          
          INDEX idx_shares_root (directory_root_id),
          INDEX idx_shares_owner (owner_user_id),
          INDEX idx_shares_created (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        COMMENT='Comparticiones de directorios creadas por usuarios'
    ");
    echo "   ✓ Tabla directory_shares creada\n\n";
    
    // ============================================
    // 3. Directory Share Nodes
    // ============================================
    
    echo "3. Creando tabla directory_share_nodes...\n";
    
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS directory_share_nodes (
          id INT AUTO_INCREMENT PRIMARY KEY,
          share_id INT NOT NULL COMMENT 'ID del share al que pertenece',
          directory_id INT NOT NULL COMMENT 'Directorio incluido en el share',
          include_subtree TINYINT(1) NOT NULL DEFAULT 1 
            COMMENT 'Si incluye subcarpetas (1) o solo este nivel (0)',
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          
          FOREIGN KEY (share_id) REFERENCES directory_shares(id) ON DELETE CASCADE,
          FOREIGN KEY (directory_id) REFERENCES directories(id) ON DELETE CASCADE,
          
          UNIQUE KEY uniq_share_directory (share_id, directory_id),
          INDEX idx_share_nodes_share (share_id),
          INDEX idx_share_nodes_directory (directory_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        COMMENT='Nodos (carpetas) seleccionados dentro de cada share'
    ");
    echo "   ✓ Tabla directory_share_nodes creada\n\n";
    
    // ============================================
    // 4. Directory Share Users
    // ============================================
    
    echo "4. Creando tabla directory_share_users...\n";
    
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS directory_share_users (
          id INT AUTO_INCREMENT PRIMARY KEY,
          share_id INT NOT NULL COMMENT 'ID del share',
          user_id INT NOT NULL COMMENT 'Usuario invitado',
          role ENUM('viewer', 'editor') NOT NULL DEFAULT 'viewer'
            COMMENT 'viewer: solo lectura, editor: puede modificar',
          invited_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          accepted_at DATETIME NULL COMMENT 'Cuando el usuario aceptó la invitación',
          
          FOREIGN KEY (share_id) REFERENCES directory_shares(id) ON DELETE CASCADE,
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
          
          UNIQUE KEY uniq_share_user (share_id, user_id),
          INDEX idx_share_users_share (share_id),
          INDEX idx_share_users_user (user_id),
          INDEX idx_share_users_role (role)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        COMMENT='Usuarios con acceso a cada share y sus roles'
    ");
    echo "   ✓ Tabla directory_share_users creada\n\n";
    
    // ============================================
    // 5. Directory Events
    // ============================================
    
    echo "5. Creando tabla directory_events...\n";
    
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS directory_events (
          id INT AUTO_INCREMENT PRIMARY KEY,
          share_id INT NULL COMMENT 'Share relacionado (si aplica)',
          directory_id INT NULL COMMENT 'Directorio afectado',
          document_id INT NULL COMMENT 'Documento afectado (si aplica)',
          user_id INT NOT NULL COMMENT 'Usuario que ejecutó la acción',
          event_type VARCHAR(50) NOT NULL 
            COMMENT 'Tipo: file_added, file_removed, moved, permission_changed, user_added, user_removed, etc.',
          details JSON NULL COMMENT 'Detalles adicionales del evento en formato JSON',
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          
          FOREIGN KEY (share_id) REFERENCES directory_shares(id) ON DELETE SET NULL,
          FOREIGN KEY (directory_id) REFERENCES directories(id) ON DELETE SET NULL,
          FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE SET NULL,
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
          
          INDEX idx_events_share (share_id),
          INDEX idx_events_directory (directory_id),
          INDEX idx_events_user (user_id),
          INDEX idx_events_type (event_type),
          INDEX idx_events_created (created_at),
          INDEX idx_events_share_created (share_id, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        COMMENT='Registro de eventos y cambios para auditoría e historial'
    ");
    echo "   ✓ Tabla directory_events creada\n\n";
    
    echo "========================================\n";
    echo "Migración completada exitosamente!\n";
    echo "========================================\n";
    
    exit(0);
    
} catch (Throwable $e) {
    echo "\nERROR: " . $e->getMessage() . "\n";
    echo "Archivo: " . $e->getFile() . "\n";
    echo "Línea: " . $e->getLine() . "\n";
    exit(1);
}
