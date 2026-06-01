type MemberWithPeriod = {
    id: string;
    starts_week_date?: string | null;
    ends_week_date?: string | null;
    recommended_starts_week_date?: string | null;
    recommended_ends_week_date?: string | null;
};

type BulkPeriodUpdate = {
    starts_week_date?: string | null;
    ends_week_date?: string | null;
};

export function applyBulkMemberPeriods<T extends MemberWithPeriod>(
    members: T[],
    memberIds: string[],
    updates: BulkPeriodUpdate
): T[] {
    const targetIds = new Set(memberIds);

    return members.map(member => {
        if (!targetIds.has(member.id)) return member;

        return {
            ...member,
            ...(updates.starts_week_date ? {
                starts_week_date: clampDateToRange(
                    updates.starts_week_date,
                    member.recommended_starts_week_date,
                    member.recommended_ends_week_date
                ),
            } : {}),
            ...(updates.ends_week_date ? {
                ends_week_date: clampDateToRange(
                    updates.ends_week_date,
                    member.recommended_starts_week_date,
                    member.recommended_ends_week_date
                ),
            } : {}),
        };
    });
}

export function clampDateToRange(value: string, min?: string | null, max?: string | null) {
    if (min && value < min) return min;
    if (max && value > max) return max;
    return value;
}
