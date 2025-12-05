-- Migration: Add profile image column to users table
-- Description: Adds support for user profile pictures
-- Created: 2025-11-18

-- Add profile_image_path column to users table
ALTER TABLE users ADD COLUMN profile_image_path VARCHAR(512) NULL 
  COMMENT 'Path to user profile image file' AFTER password_hash;

-- Add index for future profile lookups
ALTER TABLE users ADD INDEX idx_users_profile_image (profile_image_path);

-- Optional: Add last_image_update timestamp to track when image was last changed
ALTER TABLE users ADD COLUMN profile_image_updated_at DATETIME NULL 
  COMMENT 'Timestamp of last profile image update' AFTER profile_image_path;

-- Verification query to confirm columns were added:
-- SELECT id, name, email, profile_image_path, profile_image_updated_at FROM users LIMIT 1;
