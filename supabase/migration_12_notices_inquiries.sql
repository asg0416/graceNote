-- Migration 12: 공지사항, 문의하기 및 프로필 사진 기능 추가

-- 1. 프로필 테이블에 아바타 URL 추가
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE public.member_directory ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- 2. 공지사항 (Notices) 테이블 생성
CREATE TABLE IF NOT EXISTS public.notices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    church_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    department_id UUID REFERENCES public.departments(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT DEFAULT 'general', -- 'general', 'event', 'urgent' 등
    is_global BOOLEAN DEFAULT false, -- 전체 공지 여부
    target_role TEXT DEFAULT 'all', -- 'all', 'leader', 'admin' 등
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. 문의하기 (Inquiries) 테이블 생성
CREATE TABLE IF NOT EXISTS public.inquiries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT DEFAULT 'bug', -- 'bug', 'question', 'suggestion', 'other'
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'replied', 'closed')),
    user_last_read_at TIMESTAMPTZ,
    admin_last_read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. 문의 답변 (Inquiry Responses) 테이블 생성
CREATE TABLE IF NOT EXISTS public.inquiry_responses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    inquiry_id UUID REFERENCES public.inquiries(id) ON DELETE CASCADE,
    admin_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. RLS 정책 설정

-- 모든 테이블 RLS 활성화
ALTER TABLE public.notices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_responses ENABLE ROW LEVEL SECURITY;

-- [Notices Policies]
CREATE POLICY "Anyone can view notices" ON public.notices
    FOR SELECT TO authenticated USING (
        is_global = true OR 
        church_id = (SELECT church_id FROM public.profiles WHERE id = auth.uid()) OR
        public.check_is_master()
    );

CREATE POLICY "Masters and Admins can manage notices" ON public.notices
    FOR ALL TO authenticated USING (
        public.check_is_master() OR 
        public.is_admin_approved(church_id)
    );

-- [Inquiries Policies]
CREATE POLICY "Users can view and manage own inquiries" ON public.inquiries
    FOR ALL TO authenticated USING (
        user_id = auth.uid() OR public.check_is_master()
    ) WITH CHECK (
        user_id = auth.uid() OR public.check_is_master()
    );

CREATE POLICY "Admins can view all inquiries for their church" ON public.inquiries
    FOR SELECT TO authenticated USING (
        public.is_admin_approved((SELECT church_id FROM public.profiles WHERE id = inquiries.user_id))
    );

-- [Inquiry Responses Policies]
CREATE POLICY "Users can view responses to their inquiries" ON public.inquiry_responses
    FOR SELECT TO authenticated USING (
        EXISTS (
            SELECT 1 FROM public.inquiries i 
            WHERE i.id = inquiry_responses.inquiry_id 
            AND (i.user_id = auth.uid() OR public.check_is_master())
        )
    );

CREATE POLICY "Admins can manage responses" ON public.inquiry_responses
    FOR ALL TO authenticated USING (
        public.check_is_master() OR public.is_admin_approved()
    );

-- 6. 트리거: 문의 답변 시 상태 변경
CREATE OR REPLACE FUNCTION public.handle_inquiry_response()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.inquiries 
    SET status = 'replied', updated_at = NOW()
    WHERE id = NEW.inquiry_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_inquiry_response_added
    AFTER INSERT ON public.inquiry_responses
    FOR EACH ROW EXECUTE FUNCTION public.handle_inquiry_response();

-- 7. Storage Bucket 설정 (수동 또는 CLI로 수행해야 할 수 있음)
-- 이 부분은 주석으로 남겨둡니다. 
-- 'avatars' 버킷을 public으로 생성하고 정책을 설정해야 합니다.
