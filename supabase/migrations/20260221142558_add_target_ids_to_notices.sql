ALTER TABLE "public"."notices"
ADD COLUMN IF NOT EXISTS "target_church_ids" uuid[] DEFAULT '{}'::uuid[],
ADD COLUMN IF NOT EXISTS "target_department_ids" uuid[] DEFAULT '{}'::uuid[];
