/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET NAMES utf8 */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

CREATE DATABASE IF NOT EXISTS `estudiafacil` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;
USE `estudiafacil`;

CREATE TABLE IF NOT EXISTS `ai_results` (
  `id` int NOT NULL AUTO_INCREMENT,
  `document_id` int NOT NULL,
  `prompt` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `response_json` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_ai_results_document_id` (`document_id`),
  CONSTRAINT `ai_results_ibfk_1` FOREIGN KEY (`document_id`) REFERENCES `documents` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `directories` (
  `id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `parent_id` int DEFAULT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `color_hex` varchar(7) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '#1565C0',
  `position` int NOT NULL DEFAULT '0',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `cloud_managed` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indica si el directorio está gestionado en la nube (1) o solo local (0)',
  `cloud_directory_id` int DEFAULT NULL COMMENT 'ID del directorio en la nube si fue sincronizado',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_dir_name_per_parent` (`user_id`,`parent_id`,`name`),
  KEY `idx_dir_parent` (`parent_id`),
  KEY `idx_dir_user` (`user_id`),
  KEY `idx_directories_cloud` (`cloud_managed`,`cloud_directory_id`),
  CONSTRAINT `directories_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `directories_ibfk_2` FOREIGN KEY (`parent_id`) REFERENCES `directories` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `directory_events` (
  `id` int NOT NULL AUTO_INCREMENT,
  `share_id` int DEFAULT NULL COMMENT 'Share relacionado (si aplica)',
  `directory_id` int DEFAULT NULL COMMENT 'Directorio afectado',
  `document_id` int DEFAULT NULL COMMENT 'Documento afectado (si aplica)',
  `user_id` int NOT NULL COMMENT 'Usuario que ejecutó la acción',
  `event_type` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Tipo: file_added, file_removed, moved, permission_changed, user_added, user_removed, etc.',
  `details` json DEFAULT NULL COMMENT 'Detalles adicionales del evento en formato JSON',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `document_id` (`document_id`),
  KEY `idx_events_share` (`share_id`),
  KEY `idx_events_directory` (`directory_id`),
  KEY `idx_events_user` (`user_id`),
  KEY `idx_events_type` (`event_type`),
  KEY `idx_events_created` (`created_at`),
  KEY `idx_events_share_created` (`share_id`,`created_at`),
  CONSTRAINT `directory_events_ibfk_1` FOREIGN KEY (`share_id`) REFERENCES `directory_shares` (`id`) ON DELETE SET NULL,
  CONSTRAINT `directory_events_ibfk_2` FOREIGN KEY (`directory_id`) REFERENCES `directories` (`id`) ON DELETE SET NULL,
  CONSTRAINT `directory_events_ibfk_3` FOREIGN KEY (`document_id`) REFERENCES `documents` (`id`) ON DELETE SET NULL,
  CONSTRAINT `directory_events_ibfk_4` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Registro de eventos y cambios para auditoría e historial';

CREATE TABLE IF NOT EXISTS `directory_shares` (
  `id` int NOT NULL AUTO_INCREMENT,
  `directory_root_id` int NOT NULL COMMENT 'Directorio raíz que se comparte',
  `owner_user_id` int NOT NULL COMMENT 'Usuario propietario del share',
  `name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Nombre descriptivo del share (opcional)',
  `description` text COLLATE utf8mb4_unicode_ci COMMENT 'Descripción del share',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_shares_root` (`directory_root_id`),
  KEY `idx_shares_owner` (`owner_user_id`),
  KEY `idx_shares_created` (`created_at`),
  CONSTRAINT `directory_shares_ibfk_1` FOREIGN KEY (`directory_root_id`) REFERENCES `directories` (`id`) ON DELETE CASCADE,
  CONSTRAINT `directory_shares_ibfk_2` FOREIGN KEY (`owner_user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Comparticiones de directorios creadas por usuarios';

CREATE TABLE IF NOT EXISTS `directory_share_nodes` (
  `id` int NOT NULL AUTO_INCREMENT,
  `share_id` int NOT NULL COMMENT 'ID del share al que pertenece',
  `directory_id` int NOT NULL COMMENT 'Directorio incluido en el share',
  `include_subtree` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Si incluye subcarpetas (1) o solo este nivel (0)',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_share_directory` (`share_id`,`directory_id`),
  KEY `idx_share_nodes_share` (`share_id`),
  KEY `idx_share_nodes_directory` (`directory_id`),
  CONSTRAINT `directory_share_nodes_ibfk_1` FOREIGN KEY (`share_id`) REFERENCES `directory_shares` (`id`) ON DELETE CASCADE,
  CONSTRAINT `directory_share_nodes_ibfk_2` FOREIGN KEY (`directory_id`) REFERENCES `directories` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Nodos (carpetas) seleccionados dentro de cada share';

CREATE TABLE IF NOT EXISTS `directory_share_users` (
  `id` int NOT NULL AUTO_INCREMENT,
  `share_id` int NOT NULL COMMENT 'ID del share',
  `user_id` int NOT NULL COMMENT 'Usuario invitado',
  `role` enum('viewer','editor') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'viewer' COMMENT 'viewer: solo lectura, editor: puede modificar',
  `invited_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `accepted_at` datetime DEFAULT NULL COMMENT 'Cuando el usuario aceptó la invitación',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_share_user` (`share_id`,`user_id`),
  KEY `idx_share_users_share` (`share_id`),
  KEY `idx_share_users_user` (`user_id`),
  KEY `idx_share_users_role` (`role`),
  CONSTRAINT `directory_share_users_ibfk_1` FOREIGN KEY (`share_id`) REFERENCES `directory_shares` (`id`) ON DELETE CASCADE,
  CONSTRAINT `directory_share_users_ibfk_2` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Usuarios con acceso a cada share y sus roles';

CREATE TABLE IF NOT EXISTS `documents` (
  `id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `directory_id` int DEFAULT NULL,
  `original_filename` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `display_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `stored_filename` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `file_rel_path` varchar(1024) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `mime_type` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `size_bytes` int NOT NULL,
  `text_content` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `model_used` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'llama3',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_documents_user_id` (`user_id`),
  KEY `idx_documents_directory_id` (`directory_id`),
  KEY `idx_documents_file_rel_path` (`file_rel_path`(255)),
  KEY `idx_documents_created_at` (`created_at`),
  CONSTRAINT `documents_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `documents_ibfk_2` FOREIGN KEY (`directory_id`) REFERENCES `directories` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=18 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `document_locks` (
  `id` int NOT NULL AUTO_INCREMENT,
  `document_id` int NOT NULL,
  `locked_by` int NOT NULL,
  `lock_type` varchar(50) DEFAULT 'editing',
  `expires_at` datetime NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_doc_lock` (`document_id`),
  KEY `idx_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS `flashcards` (
  `id` int NOT NULL AUTO_INCREMENT,
  `topic_id` int NOT NULL,
  `question` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `answer` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `position` int NOT NULL DEFAULT '0',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_flashcards_topic_id` (`topic_id`),
  KEY `idx_flashcards_position` (`position`),
  CONSTRAINT `flashcards_ibfk_1` FOREIGN KEY (`topic_id`) REFERENCES `topics` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `summary_jobs` (
  `id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `file_path` varchar(1024) COLLATE utf8mb4_unicode_ci NOT NULL,
  `file_rel_path` varchar(1024) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `analysis_type` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `model` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('pending','processing','completed','failed','canceled') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `progress` int NOT NULL DEFAULT '0',
  `summary_text` longtext COLLATE utf8mb4_unicode_ci,
  `error_message` text COLLATE utf8mb4_unicode_ci,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_summary_jobs_status` (`status`),
  KEY `idx_summary_jobs_user_id` (`user_id`),
  KEY `idx_summary_jobs_user_path_status` (`user_id`,`file_rel_path`(255),`status`),
  CONSTRAINT `summary_jobs_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=29 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `topics` (
  `id` int NOT NULL AUTO_INCREMENT,
  `document_id` int NOT NULL,
  `title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `summary` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `position` int NOT NULL DEFAULT '0',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_topics_document_id` (`document_id`),
  KEY `idx_topics_position` (`position`),
  CONSTRAINT `topics_ibfk_1` FOREIGN KEY (`document_id`) REFERENCES `documents` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `users` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password_hash` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `auth_token` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `token_expires_at` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_courses` (
  `id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `tema` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `nombre_curso` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `duracion_horas` int NOT NULL DEFAULT '0',
  `url` varchar(1024) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_user_course` (`user_id`,`url`(255)),
  KEY `idx_user_courses_user_id` (`user_id`),
  KEY `idx_user_courses_tema` (`tema`(100)),
  KEY `idx_user_courses_created_at` (`created_at`),
  CONSTRAINT `user_courses_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=35 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!40103 SET TIME_ZONE=IFNULL(@OLD_TIME_ZONE, 'system') */;
/*!40101 SET SQL_MODE=IFNULL(@OLD_SQL_MODE, '') */;
/*!40014 SET FOREIGN_KEY_CHECKS=IFNULL(@OLD_FOREIGN_KEY_CHECKS, 1) */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40111 SET SQL_NOTES=IFNULL(@OLD_SQL_NOTES, 1) */;
