-- Migration: Add file_rel_path column and composite index
-- Date: 2025-11-13
-- Description: Adds relative file path tracking and optimizes queries with composite index

-- Add file_rel_path column if it doesn't exist
ALTER TABLE summary_jobs 
ADD COLUMN IF NOT EXISTS file_rel_path VARCHAR(1024) NULL AFTER file_path;

-- Create composite index for efficient querying by user, path, and status
CREATE INDEX IF NOT EXISTS idx_summary_jobs_user_path_status 
ON summary_jobs (user_id, file_rel_path(255), status);
