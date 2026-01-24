-- GraceNote Security Fix: Church Isolation & Master Access
-- 목적: 모든 테이블에 대해 교회 단위 데이터 격리(Isolation)를 강화하고 마스터 계정의 전역 접근 권한을 보장함.

DO $$
DECLARE
    pol RECORD;
BEGIN
    -- 1. 기존 RLS 정책 삭제 (중복 방지)
    FOR pol IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);
    END LOOP;
END $$;

-- ============================================
-- 핵심 유틸리티 함수 강화 (안정성 확보)
-- ============================================

-- 내 교회 ID를 안전하게 가져오는 함수 (RLS 무한 재귀 방지용)
CREATE OR REPLACE FUNCTION public.get_my_church_id()
RETURNS UUID AS $$
BEGIN
  RETURN (SELECT church_id FROM public.profiles WHERE id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 특정 교회의 유저인지 확인
CREATE OR REPLACE FUNCTION public.is_in_church(target_church_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND (church_id = target_church_id OR is_master = true)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- RLS (Row Level Security) 정책 재정의
-- ============================================

-- [Profiles]
-- 본인 정보는 ALL, 같은 교회의 다른 유저는 SELECT, 마스터는 ALL
CREATE POLICY "Profiles self all" ON public.profiles FOR ALL TO authenticated USING (auth.uid() = id OR public.check_is_master()) WITH CHECK (auth.uid() = id OR public.check_is_master());
CREATE POLICY "Profiles church select" ON public.profiles FOR SELECT TO authenticated USING (church_id = public.get_my_church_id() OR public.check_is_master());

-- [Churches]
-- 조회는 인증된 유저 전체(가입 시 필요), 관리는 마스터 전용
CREATE POLICY "Churches select all" ON public.churches FOR SELECT TO authenticated USING (true);
CREATE POLICY "Churches master manage" ON public.churches FOR ALL TO authenticated USING (public.check_is_master());

-- [Departments / Groups / Families]
-- 조회 및 관리는 해당 교회 유저/관리자 또는 마스터 전용
CREATE POLICY "Depts church isolation" ON public.departments FOR SELECT TO authenticated USING (church_id = public.get_my_church_id() OR public.check_is_master());
CREATE POLICY "Depts admin manage" ON public.departments FOR ALL TO authenticated USING (public.is_admin_approved(church_id) OR public.check_is_master());

CREATE POLICY "Groups church isolation" ON public.groups FOR SELECT TO authenticated USING (church_id = public.get_my_church_id() OR public.check_is_master());
CREATE POLICY "Groups admin manage" ON public.groups FOR ALL TO authenticated USING (public.is_admin_approved(church_id) OR public.check_is_master());

CREATE POLICY "Families church isolation" ON public.families FOR SELECT TO authenticated USING (church_id = public.get_my_church_id() OR public.check_is_master());
CREATE POLICY "Families admin manage" ON public.families FOR ALL TO authenticated USING (public.is_admin_approved(church_id) OR public.check_is_master());

-- [Group Members]
-- 같은 교회의 멤버십만 조회 가능
CREATE POLICY "Membership church isolation" ON public.group_members FOR SELECT TO authenticated 
USING (EXISTS (SELECT 1 FROM public.groups g WHERE g.id = group_members.group_id AND (g.church_id = public.get_my_church_id() OR public.check_is_master())));

CREATE POLICY "Membership self manage" ON public.group_members FOR ALL TO authenticated 
USING (profile_id = auth.uid() OR public.check_is_master());

CREATE POLICY "Membership admin manage" ON public.group_members FOR ALL TO authenticated 
USING (EXISTS (SELECT 1 FROM public.groups g WHERE g.id = group_members.group_id AND (public.is_admin_approved(g.church_id) OR public.check_is_master())));

-- [Weeks / Attendance / Prayer Entries]
-- 교회 단위로 조회 및 수정 제한
CREATE POLICY "Weeks church isolation" ON public.weeks FOR SELECT TO authenticated USING (church_id = public.get_my_church_id() OR public.check_is_master());
CREATE POLICY "Weeks admin manage" ON public.weeks FOR ALL TO authenticated USING (public.is_admin_approved(church_id) OR public.check_is_master());

CREATE POLICY "Attendance church isolation" ON public.attendance FOR SELECT TO authenticated 
USING (EXISTS (SELECT 1 FROM public.weeks w WHERE w.id = attendance.week_id AND (w.church_id = public.get_my_church_id() OR public.check_is_master())));

CREATE POLICY "Attendance manage" ON public.attendance FOR ALL TO authenticated 
USING (public.is_admin_approved() OR public.is_leader() OR public.check_is_master());

CREATE POLICY "Prayers church isolation" ON public.prayer_entries FOR SELECT TO authenticated 
USING (EXISTS (SELECT 1 FROM public.weeks w WHERE w.id = prayer_entries.week_id AND (w.church_id = public.get_my_church_id() OR public.check_is_master())));

CREATE POLICY "Prayers self/admin manage" ON public.prayer_entries FOR ALL TO authenticated 
USING (member_id = auth.uid() OR public.is_admin_approved() OR public.is_leader() OR public.check_is_master());

-- [Member Directory]
CREATE POLICY "Directory church isolation" ON public.member_directory FOR SELECT TO authenticated 
USING (church_id = public.get_my_church_id() OR public.check_is_master());

CREATE POLICY "Directory admin manage" ON public.member_directory FOR ALL TO authenticated 
USING (public.is_admin_approved(church_id) OR public.check_is_master());

-- [Notices]
CREATE POLICY "Notices church isolation" ON public.notices FOR SELECT TO authenticated 
USING (is_global = true OR church_id = public.get_my_church_id() OR public.check_is_master());

CREATE POLICY "Notices admin manage" ON public.notices FOR ALL TO authenticated 
USING (public.is_admin_approved(church_id) OR public.check_is_master());

-- [Notice Reads]
CREATE POLICY "Notice reads self manage" ON public.notice_reads FOR ALL TO authenticated 
USING (user_id = auth.uid() OR public.check_is_master()) WITH CHECK (user_id = auth.uid() OR public.check_is_master());

-- [Inquiries]
CREATE POLICY "Inquiries self/master" ON public.inquiries FOR ALL TO authenticated 
USING (user_id = auth.uid() OR public.check_is_master());

CREATE POLICY "Inquiry responses self/master" ON public.inquiry_responses FOR SELECT TO authenticated 
USING (EXISTS (SELECT 1 FROM public.inquiries i WHERE i.id = inquiry_responses.inquiry_id AND (i.user_id = auth.uid() OR public.check_is_master())));

CREATE POLICY "Inquiry responses master all" ON public.inquiry_responses FOR ALL TO authenticated 
USING (public.check_is_master());

-- [Interactions]
CREATE POLICY "Interactions self" ON public.prayer_interactions FOR ALL TO authenticated 
USING (profile_id = auth.uid() OR public.check_is_master());

-- [Phone Verifications]
CREATE POLICY "Phone verifications manage" ON public.phone_verifications FOR ALL TO authenticated 
USING (true) WITH CHECK (true);

-- [Debug Logs]
CREATE POLICY "Debug logs master manage" ON public.debug_logs FOR ALL TO authenticated 
USING (public.check_is_master());

-- [Newsletters]
CREATE POLICY "Newsletters select all" ON public.newsletters FOR SELECT TO authenticated 
USING (true);
