-- Migration: Add file_rel_path column to documents table
-- Date: 2025-11-22
-- Purpose: Store relative file path for cloud documents for use in process_summaries.php

ALTER TABLE documents
ADD COLUMN file_rel_path VARCHAR(1024) NULL AFTER stored_filename,
ADD INDEX idx_documents_file_rel_path (file_rel_path(255));
