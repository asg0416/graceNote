-- Migration 12: Phone Verification System Support

-- 1. Ensure Profiles phone is unique
-- Note: If there are existing duplicates, this will fail. You may need to clean data first.
ALTER TABLE public.profiles ADD CONSTRAINT profiles_phone_key UNIQUE (phone);

-- 2. Ensure Member Directory phone is unique
ALTER TABLE public.member_directory ADD CONSTRAINT member_directory_phone_key UNIQUE (phone);

-- 3. Create Phone Verifications table for Custom OTP
CREATE TABLE IF NOT EXISTS public.phone_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone TEXT NOT NULL,
    code TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(phone)
);

-- RLS for phone_verifications
ALTER TABLE public.phone_verifications ENABLE ROW LEVEL SECURITY;

-- Policy: Only service role can access (Edge Functions)
-- We do not add public policies because verification should happen via trusted Edge Functions.
