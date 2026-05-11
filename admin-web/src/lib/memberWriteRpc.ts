/* eslint-disable @typescript-eslint/no-explicit-any */

export type MemberWritePayload = {
    id?: string | null;
    church_id?: string | null;
    department_id?: string | null;
    full_name?: string | null;
    phone?: string | null;
    group_name?: string | null;
    role_in_group?: string | null;
    family_name?: string | null;
    spouse_name?: string | null;
    children_info?: string | null;
    birth_date?: string | null;
    wedding_anniversary?: string | null;
    notes?: string | null;
    avatar_url?: string | null;
    profile_id?: string | null;
    person_id?: string | null;
    is_active?: boolean | null;
};

type RpcClientLike = {
    rpc: (
        functionName: string,
        args?: Record<string, unknown>
    ) => PromiseLike<{ data: any; error: { message?: string } | null }>;
};

export const upsertMemberPersonMembership = async (
    supabase: RpcClientLike,
    payload: MemberWritePayload
) => {
    const { data, error } = await supabase.rpc('upsert_member_person_membership', {
        p_member_directory_id: payload.id || null,
        p_church_id: payload.church_id || null,
        p_department_id: payload.department_id || null,
        p_full_name: payload.full_name || null,
        p_phone: payload.phone || null,
        p_group_name: payload.group_name || null,
        p_role_in_group: payload.role_in_group || 'member',
        p_family_name: payload.family_name || null,
        p_spouse_name: payload.spouse_name || null,
        p_children_info: payload.children_info || null,
        p_birth_date: payload.birth_date || null,
        p_wedding_anniversary: payload.wedding_anniversary || null,
        p_notes: payload.notes || null,
        p_avatar_url: payload.avatar_url || null,
        p_profile_id: payload.profile_id || null,
        p_person_id: payload.person_id || null,
        p_is_active: payload.is_active !== false,
    });

    if (error) {
        throw new Error(error.message || '성도 저장 RPC 실행에 실패했습니다.');
    }

    if (!data?.id) {
        throw new Error('성도 저장 RPC가 저장된 성도 ID를 반환하지 않았습니다.');
    }

    return data;
};
