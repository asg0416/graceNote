-- Update iam-images bucket to allow 20MB and mp4 videos

UPDATE storage.buckets
SET 
  file_size_limit = 20971520, -- 20MB
  allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif', 'video/mp4']
WHERE id = 'iam-images';
