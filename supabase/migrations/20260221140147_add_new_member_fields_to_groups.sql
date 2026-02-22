-- Add columns for new member groups and climbing thresholds

ALTER TABLE "public"."groups"
ADD COLUMN IF NOT EXISTS "is_new_member_group" boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS "climbing_threshold" integer DEFAULT 4;
