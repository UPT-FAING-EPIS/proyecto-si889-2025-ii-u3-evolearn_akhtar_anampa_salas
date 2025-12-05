-- Migration: Add summary_jobs table for async processing
-- Date: 2025-11-10
-- Description: Creates summary_jobs table to handle background summary generation

CREATE TABLE IF NOT EXISTS summary_jobs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  file_path VARCHAR(1024) NOT NULL,
  analysis_type VARCHAR(50) NOT NULL,
  model VARCHAR(50) NOT NULL,
  status ENUM('pending', 'processing', 'completed', 'failed') NOT NULL DEFAULT 'pending',
  progress INT NOT NULL DEFAULT 0,
  summary_text LONGTEXT NULL,
  error_message TEXT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_summary_jobs_status (status),
  INDEX idx_summary_jobs_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
