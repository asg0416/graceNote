type RpcErrorLike = {
    message?: string;
};

type RpcResult<T> = {
    data: T | null;
    error: RpcErrorLike | null;
};

type RpcClientLike = {
    rpc: <T = unknown>(
        functionName: string,
        args?: Record<string, unknown>
    ) => PromiseLike<RpcResult<T>>;
};

const assertNoRpcError = (error: RpcErrorLike | null, fallbackMessage: string) => {
    if (error) {
        throw new Error(error.message || fallbackMessage);
    }
};

export const createRegroupingSeason = async (
    supabase: RpcClientLike,
    payload: {
        churchId: string;
        departmentId: string;
        title: string;
        effectiveWeekDate: string;
    }
) => {
    const { data, error } = await supabase.rpc<string>('create_regrouping_season', {
        p_church_id: payload.churchId,
        p_department_id: payload.departmentId,
        p_title: payload.title,
        p_effective_week_date: payload.effectiveWeekDate,
    });

    assertNoRpcError(error, '조편성 계획 생성에 실패했습니다.');
    if (!data) {
        throw new Error('조편성 계획 ID를 받지 못했습니다.');
    }

    return data;
};

export const saveRegroupingSeasonDraft = async (
    supabase: RpcClientLike,
    payload: {
        seasonId: string;
        groups: Array<Record<string, unknown>>;
        assignments: Array<Record<string, unknown>>;
    }
) => {
    const { data, error } = await supabase.rpc<Array<{
        plan_group_count: number;
        assignment_count: number;
    }>>('save_regrouping_season_draft', {
        p_season_id: payload.seasonId,
        p_groups: payload.groups,
        p_assignments: payload.assignments,
    });

    assertNoRpcError(error, '조편성 계획 저장에 실패했습니다.');

    const first = Array.isArray(data) ? data[0] : null;
    return {
        planGroupCount: first?.plan_group_count ?? 0,
        assignmentCount: first?.assignment_count ?? 0,
    };
};

export const applyRegroupingSeason = async (
    supabase: RpcClientLike,
    payload: { seasonId: string }
) => {
    const { data, error } = await supabase.rpc('apply_regrouping_season', {
        p_season_id: payload.seasonId,
    });

    assertNoRpcError(error, '조편성 계획 적용에 실패했습니다.');

    return data;
};
