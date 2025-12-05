-- Migration: Add 'canceled' status to summary_jobs
-- Date: 2025-11-13
-- Description: Extends the status enum to include 'canceled' option

ALTER TABLE summary_jobs 
MODIFY COLUMN status ENUM('pending', 'processing', 'completed', 'failed', 'canceled') 
NOT NULL DEFAULT 'pending';
