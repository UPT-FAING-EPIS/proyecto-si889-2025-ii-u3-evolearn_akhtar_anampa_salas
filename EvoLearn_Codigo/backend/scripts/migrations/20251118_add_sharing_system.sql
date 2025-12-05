-- Migration: Add sharing system tables and columns
-- Date: 2025-11-18
-- Description: Adds complete sharing system with directory_shares, share_nodes, share_users, and events
-- Part of: Sharing Feature Plan v3

-- ============================================
-- 1. Add cloud management columns to directories
-- ============================================

-- Add cloud_managed column (skip if exists)
SET @column_exists = (
  SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
  WHERE TABLE_SCHEMA = DATABASE() 
  AND TABLE_NAME = 'directories' 
  AND COLUMN_NAME = 'cloud_managed'
);

SET @sql = IF(@column_exists = 0,
  "ALTER TABLE directories ADD COLUMN cloud_managed TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Indica si el directorio está gestionado en la nube (1) o solo local (0)'",
  "SELECT 'Column cloud_managed already exists' AS msg"
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add cloud_directory_id column (skip if exists)
SET @column_exists = (
  SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
  WHERE TABLE_SCHEMA = DATABASE() 
  AND TABLE_NAME = 'directories' 
  AND COLUMN_NAME = 'cloud_directory_id'
);

SET @sql = IF(@column_exists = 0,
  "ALTER TABLE directories ADD COLUMN cloud_directory_id INT NULL COMMENT 'ID del directorio en la nube si fue sincronizado'",
  "SELECT 'Column cloud_directory_id already exists' AS msg"
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add index (skip if exists)
SET @index_exists = (
  SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS 
  WHERE TABLE_SCHEMA = DATABASE() 
  AND TABLE_NAME = 'directories' 
  AND INDEX_NAME = 'idx_directories_cloud'
);

SET @sql = IF(@index_exists = 0,
  "ALTER TABLE directories ADD INDEX idx_directories_cloud (cloud_managed, cloud_directory_id)",
  "SELECT 'Index idx_directories_cloud already exists' AS msg"
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ============================================
-- 2. Directory Shares (compartir raíz)
-- ============================================

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
COMMENT='Comparticiones de directorios creadas por usuarios';

-- ============================================
-- 3. Directory Share Nodes (selección de carpetas)
-- ============================================

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
COMMENT='Nodos (carpetas) seleccionados dentro de cada share';

-- ============================================
-- 4. Directory Share Users (usuarios invitados)
-- ============================================

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
COMMENT='Usuarios con acceso a cada share y sus roles';

-- ============================================
-- 5. Directory Events (historial y auditoría)
-- ============================================

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
COMMENT='Registro de eventos y cambios para auditoría e historial';

-- ============================================
-- Notas de implementación:
-- ============================================
-- 
-- 1. cloud_managed permite diferenciar directorios locales vs cloud
-- 2. directory_share_nodes.include_subtree controla inclusión recursiva
-- 3. directory_share_users.role determina permisos (viewer/editor)
-- 4. directory_events registra todo para historial y sincronización
-- 5. Las FK con ON DELETE CASCADE aseguran limpieza automática
-- 6. Los índices optimizan queries frecuentes (listados, permisos)
--
-- Próximos pasos (Fase 2):
-- - Implementar endpoints: create_share, add_share_user, etc.
-- - Validar permisos en endpoints existentes (upload, move, delete)
-- - Frontend: sección Compartidos en Home
