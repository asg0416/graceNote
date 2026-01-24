-- GraceNote Performance Fix: Database Indices
-- 목적: 주요 테이블의 외래키 및 자주 사용되는 필터 컬럼에 인덱스를 추가하여 대량 데이터 처리 성능을 개선함.

-- 1. Profiles & Churches
CREATE INDEX IF NOT EXISTS idx_profiles_church_id ON public.profiles(church_id);
CREATE INDEX IF NOT EXISTS idx_profiles_department_id ON public.profiles(department_id);

-- 2. Member Directory
CREATE INDEX IF NOT EXISTS idx_member_directory_church_id ON public.member_directory(church_id);
CREATE INDEX IF NOT EXISTS idx_member_directory_department_id ON public.member_directory(department_id);
CREATE INDEX IF NOT EXISTS idx_member_directory_group_name ON public.member_directory(group_name);
CREATE INDEX IF NOT EXISTS idx_member_directory_is_active ON public.member_directory(is_active);

-- 3. Weeks & Attendance
CREATE INDEX IF NOT EXISTS idx_weeks_church_id ON public.weeks(church_id);
CREATE INDEX IF NOT EXISTS idx_weeks_week_date ON public.weeks(week_date);
CREATE INDEX IF NOT EXISTS idx_attendance_week_id ON public.attendance(week_id);
CREATE INDEX IF NOT EXISTS idx_attendance_directory_member_id ON public.attendance(directory_member_id);

-- 4. Prayer Entries
CREATE INDEX IF NOT EXISTS idx_prayer_entries_week_id ON public.prayer_entries(week_id);
CREATE INDEX IF NOT EXISTS idx_prayer_entries_directory_member_id ON public.prayer_entries(directory_member_id);
CREATE INDEX IF NOT EXISTS idx_prayer_entries_status ON public.prayer_entries(status);

-- 5. Interactions
CREATE INDEX IF NOT EXISTS idx_prayer_interactions_prayer_id ON public.prayer_interactions(prayer_id);
CREATE INDEX IF NOT EXISTS idx_prayer_interactions_profile_id ON public.prayer_interactions(profile_id);
