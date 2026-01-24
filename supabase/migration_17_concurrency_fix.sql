-- GraceNote Robustness Fix: Prayer Interaction Atomicity
-- 목적: prayer_interactions 테이블의 변화에 따라 prayer_entries의 together_count를 자동으로 업데이트하여 동시성 문제를 해결함.

-- 1. 트리거 함수 정의
CREATE OR REPLACE FUNCTION public.handle_prayer_interaction_count()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        IF (NEW.interaction_type = 'pray') THEN
            UPDATE public.prayer_entries
            SET together_count = COALESCE(together_count, 0) + 1
            WHERE id = NEW.prayer_id;
        END IF;
    ELSIF (TG_OP = 'DELETE') THEN
        IF (OLD.interaction_type = 'pray') THEN
            UPDATE public.prayer_entries
            SET together_count = GREATEST(COALESCE(together_count, 0) - 1, 0)
            WHERE id = OLD.prayer_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. 트리거 적용
DROP TRIGGER IF EXISTS on_prayer_interaction_changed ON public.prayer_interactions;
CREATE TRIGGER on_prayer_interaction_changed
AFTER INSERT OR DELETE ON public.prayer_interactions
FOR EACH ROW EXECUTE FUNCTION public.handle_prayer_interaction_count();

-- 3. 기존 수동 업데이트용 RPC 무력화 또는 안내 (선택)
-- 기존 앱 코드에서 RPC를 호출하더라도 트리거가 중복으로 작동하지 않도록 주의해야 함.
-- 가장 안전한 방법은 앱 로직에서 RPC 호출을 제거하도록 가이드하고, 
-- 과도기적으로는 RPC 함수 내용을 비우는 방법이 있음.
