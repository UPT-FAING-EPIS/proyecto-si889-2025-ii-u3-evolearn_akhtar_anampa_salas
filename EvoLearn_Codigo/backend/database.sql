-- MySQL 8+ schema for EstudiaFácil (robust)

DROP DATABASE IF EXISTS estudiafacil;
CREATE DATABASE estudiafacil
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE estudiafacil;

-- Users
CREATE TABLE users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  auth_token VARCHAR(128) NULL,
  token_expires_at DATETIME NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Hierarchical directories per user
CREATE TABLE directories (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  parent_id INT NULL,
  name VARCHAR(255) NOT NULL,
  color_hex VARCHAR(7) NOT NULL DEFAULT '#1565C0', -- e.g. #1565C0
  position INT NOT NULL DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (parent_id) REFERENCES directories(id) ON DELETE CASCADE,
  UNIQUE KEY uniq_dir_name_per_parent (user_id, parent_id, name),
  INDEX idx_dir_parent (parent_id),
  INDEX idx_dir_user (user_id)
) ENGINE=InnoDB;

-- Documents uploaded by users
CREATE TABLE documents (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  directory_id INT NULL,
  original_filename VARCHAR(255) NOT NULL,
  display_name VARCHAR(255) NOT NULL,
  stored_filename VARCHAR(255) NOT NULL,
  file_rel_path VARCHAR(1024) NULL,
  mime_type VARCHAR(100) NOT NULL,
  size_bytes INT NOT NULL,
  text_content LONGTEXT NOT NULL,
  model_used VARCHAR(50) NOT NULL DEFAULT 'llama3',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (directory_id) REFERENCES directories(id) ON DELETE SET NULL,
  INDEX idx_documents_user_id (user_id),
  INDEX idx_documents_directory_id (directory_id),
  INDEX idx_documents_file_rel_path (file_rel_path(255)),
  INDEX idx_documents_created_at (created_at)
) ENGINE=InnoDB;

-- AI raw results, prompt + JSON payload returned
CREATE TABLE ai_results (
  id INT AUTO_INCREMENT PRIMARY KEY,
  document_id INT NOT NULL,
  prompt LONGTEXT NOT NULL,
  response_json LONGTEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE,
  INDEX idx_ai_results_document_id (document_id)
) ENGINE=InnoDB;

-- Topics derived from a document
CREATE TABLE topics (
  id INT AUTO_INCREMENT PRIMARY KEY,
  document_id INT NOT NULL,
  title VARCHAR(255) NOT NULL,
  summary TEXT NOT NULL,
  position INT NOT NULL DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE,
  INDEX idx_topics_document_id (document_id),
  INDEX idx_topics_position (position)
) ENGINE=InnoDB;

-- Flashcards linked to topics
CREATE TABLE flashcards (
  id INT AUTO_INCREMENT PRIMARY KEY,
  topic_id INT NOT NULL,
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  position INT NOT NULL DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE CASCADE,
  INDEX idx_flashcards_topic_id (topic_id),
  INDEX idx_flashcards_position (position)
) ENGINE=InnoDB;

-- Sample user (password: 123456)
INSERT INTO users (name, email, password_hash) VALUES
('Demo User', 'demo@estudiafacil.com', '$2y$10$beKgh5/Rlrq08uVWzzFgt.HPA65wPYirKEWBpYdMgPH2kxC3RHIXe');

-- Summary generation jobs (for async processing)
CREATE TABLE summary_jobs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  file_path VARCHAR(1024) NOT NULL,
  file_rel_path VARCHAR(1024) NULL,
  analysis_type VARCHAR(50) NOT NULL,
  model VARCHAR(50) NOT NULL,
  status ENUM('pending', 'processing', 'completed', 'failed', 'canceled') NOT NULL DEFAULT 'pending',
  progress INT NOT NULL DEFAULT 0,
  summary_text LONGTEXT NULL,
  error_message TEXT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_summary_jobs_status (status),
  INDEX idx_summary_jobs_user_id (user_id),
  INDEX idx_summary_jobs_user_path_status (user_id, file_rel_path(255), status)
) ENGINE=InnoDB;

-- User courses (cursos consultados por usuario)
CREATE TABLE user_courses (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  tema VARCHAR(255) NOT NULL,
  nombre_curso VARCHAR(255) NOT NULL,
  duracion_horas INT NOT NULL DEFAULT 0,
  url VARCHAR(1024) NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user_courses_user_id (user_id),
  INDEX idx_user_courses_tema (tema(100)),
  INDEX idx_user_courses_created_at (created_at),
  UNIQUE KEY uniq_user_course (user_id, url(255))
) ENGINE=InnoDB;