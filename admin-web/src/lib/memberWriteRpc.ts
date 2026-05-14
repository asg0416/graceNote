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

export const setMemberDirectoryActiveStatus = async (
    supabase: RpcClientLike,
    memberDirectoryId: string,
    isActive: boolean
) => {
    const { data, error } = await supabase.rpc('set_member_directory_active_status', {
        p_member_directory_id: memberDirectoryId,
        p_is_active: isActive,
    });

    if (error) {
        throw new Error(error.message || '성도 활성 상태 변경 RPC 실행에 실패했습니다.');
    }

    if (!data?.id) {
        throw new Error('성도 활성 상태 변경 RPC가 저장된 성도 ID를 반환하지 않았습니다.');
    }

    return data;
};

export const setPersonDepartmentActiveStatus = async (
    supabase: RpcClientLike,
    payload: {
        personId: string;
        churchId: string;
        departmentId: string;
        isActive: boolean;
        restoreGroupIds?: string[];
    }
) => {
    const { data, error } = payload.isActive && payload.restoreGroupIds
        ? await supabase.rpc('restore_person_department_affiliation', {
            p_person_id: payload.personId,
            p_church_id: payload.churchId,
            p_department_id: payload.departmentId,
            p_group_ids: payload.restoreGroupIds,
        })
        : await supabase.rpc('set_person_department_active_status', {
            p_person_id: payload.personId,
            p_church_id: payload.churchId,
            p_department_id: payload.departmentId,
            p_is_active: payload.isActive,
        });

    if (error) {
        throw new Error(error.message || '부서 소속 활성 상태 변경 RPC 실행에 실패했습니다.');
    }

    return Array.isArray(data)
        ? data.map((row) => row.member_directory_id).filter(Boolean)
        : [];
};

export const saveRegroupingMemberships = async (
    supabase: RpcClientLike,
    payload: {
        churchId: string;
        departmentId: string;
        groups: Array<Record<string, unknown>>;
        assignments: Array<Record<string, unknown>>;
    }
) => {
    const { data, error } = await supabase.rpc('save_regrouping_memberships', {
        p_church_id: payload.churchId,
        p_department_id: payload.departmentId,
        p_groups: payload.groups,
        p_assignments: payload.assignments,
    });

    if (error) {
        throw new Error(error.message || '조편성 저장 RPC 실행에 실패했습니다.');
    }

    return Array.isArray(data)
        ? data.map((row) => row.member_directory_id).filter(Boolean)
        : [];
};

export const renameMemberDirectoryGroupAssignments = async (
    supabase: RpcClientLike,
    payload: {
        churchId: string;
        departmentId: string;
        oldGroupName: string;
        newGroupName: string;
    }
) => {
    const { data, error } = await supabase.rpc('rename_member_directory_group_assignments', {
        p_church_id: payload.churchId,
        p_department_id: payload.departmentId,
        p_old_group_name: payload.oldGroupName,
        p_new_group_name: payload.newGroupName,
    });

    if (error) {
        throw new Error(error.message || '조 이름 변경 동기화 RPC 실행에 실패했습니다.');
    }

    return typeof data === 'number' ? data : 0;
};
