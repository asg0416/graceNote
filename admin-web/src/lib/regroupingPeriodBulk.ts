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

type PeriodUpdateBounds = {
    min?: string | null;
    startMax?: string | null;
    endMax?: string | null;
};

export function applyBulkMemberPeriods<T extends MemberWithPeriod>(
    members: T[],
    memberIds: string[],
    updates: BulkPeriodUpdate,
    bounds: PeriodUpdateBounds = {}
): T[] {
    const targetIds = new Set(memberIds);

    return members.map(member => {
        if (!targetIds.has(member.id)) return member;

        const clampedUpdates = clampPeriodUpdate(updates, {
            min: member.recommended_starts_week_date ?? bounds.min,
            startMax: bounds.startMax ?? member.recommended_ends_week_date ?? bounds.endMax,
            endMax: member.recommended_ends_week_date ?? bounds.endMax,
        });

        return {
            ...member,
            ...clampedUpdates,
        };
    });
}

export function clampDateToRange(value: string, min?: string | null, max?: string | null) {
    if (min && value < min) return min;
    if (max && value > max) return max;
    return value;
}

export function clampPeriodUpdate(
    updates: BulkPeriodUpdate,
    bounds: PeriodUpdateBounds
): BulkPeriodUpdate {
    return {
        ...(updates.starts_week_date ? {
            starts_week_date: clampDateToRange(
                updates.starts_week_date,
                bounds.min,
                bounds.startMax ?? bounds.endMax
            ),
        } : {}),
        ...(updates.ends_week_date ? {
            ends_week_date: clampDateToRange(
                updates.ends_week_date,
                bounds.min,
                bounds.endMax
            ),
        } : {}),
    };
}
