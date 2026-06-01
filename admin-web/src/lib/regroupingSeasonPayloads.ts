export const isUuid = (value: unknown) =>
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

const getDateText = (value: unknown) =>
    typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;

export const buildRegroupingSeasonGroupsPayload = (groups: Array<Record<string, unknown>>) =>
    groups.map((group, index) => {
        const id = typeof group.id === 'string' ? group.id : null;
        const planGroupId = typeof group.plan_group_id === 'string' && isUuid(group.plan_group_id)
            ? group.plan_group_id
            : null;
        const sourceGroupId = typeof group.source_group_id === 'string' && isUuid(group.source_group_id)
            ? group.source_group_id
            : !planGroupId && isUuid(id)
                ? id
                : null;

        return {
            id,
            plan_group_id: planGroupId,
            source_group_id: sourceGroupId,
            name: String(group.name || ''),
            color_hex: typeof group.color_hex === 'string' && group.color_hex ? group.color_hex : null,
            sort_order: index,
            leader_person_id: typeof group.leader_person_id === 'string' && isUuid(group.leader_person_id)
                ? group.leader_person_id
                : null,
            starts_week_date: getDateText(group.starts_week_date),
            ends_week_date: getDateText(group.ends_week_date),
            plan_status: group.plan_status === 'ended' ? 'ended' : 'active',
            is_new_member_group: Boolean(group.is_new_member_group),
            climbing_threshold: group.is_new_member_group
                ? Number(group.climbing_threshold || 4)
                : null,
        };
    });

export const buildRegroupingSeasonAssignmentsPayload = (members: Array<Record<string, unknown>>) =>
    members
        .map((member, index) => {
            const personId = typeof member.person_id === 'string' && isUuid(member.person_id)
                ? member.person_id
                : typeof member.phase2_person_id === 'string' && isUuid(member.phase2_person_id)
                    ? member.phase2_person_id
                    : null;

            if (!personId) return null;

            const groupId = typeof member.group_id === 'string' && member.group_id ? member.group_id : null;
            const role = typeof member.role_in_group === 'string' && member.role_in_group
                ? member.role_in_group
                : typeof member.role === 'string' && member.role
                    ? member.role
                    : 'member';

            return {
                group_id: groupId,
                plan_group_id: null,
                person_id: personId,
                role_in_group: role,
                sort_order: index,
                source_membership_id: typeof member.phase2_membership_id === 'string' && isUuid(member.phase2_membership_id)
                    ? member.phase2_membership_id
                    : typeof member.membership_id === 'string' && isUuid(member.membership_id)
                        ? member.membership_id
                        : null,
                source_member_directory_id: typeof member.source_member_directory_id === 'string' && isUuid(member.source_member_directory_id)
                    ? member.source_member_directory_id
                    : typeof member.id === 'string' && isUuid(member.id)
                        ? member.id
                        : null,
                starts_week_date: getDateText(member.starts_week_date),
                ends_week_date: getDateText(member.ends_week_date),
            };
        })
        .filter((assignment): assignment is NonNullable<typeof assignment> => assignment !== null);

const getNestedRecord = (value: unknown) => {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
    return value as Record<string, unknown>;
};

const getText = (...values: unknown[]) => {
    for (const value of values) {
        if (typeof value === 'string' && value.trim()) return value;
    }
    return '';
};

export const mapRegroupingSeasonDraftToBoard = ({
    planGroups,
    assignments,
}: {
    planGroups: Array<Record<string, unknown>>;
    assignments: Array<Record<string, unknown>>;
}) => {
    const groups = [...planGroups]
        .sort((left, right) => Number(left.sort_order || 0) - Number(right.sort_order || 0))
        .map(group => {
            const id = String(group.id || '');
            const sourceGroup = getNestedRecord(group.source_group);
            return {
                id,
                plan_group_id: id,
                source_group_id: typeof group.source_group_id === 'string' ? group.source_group_id : null,
                name: String(group.name || ''),
                color_hex: typeof group.color_hex === 'string' && group.color_hex ? group.color_hex : '#4f46e5',
                sort_order: Number(group.sort_order || 0),
                starts_week_date: getDateText(group.starts_week_date),
                ends_week_date: getDateText(group.ends_week_date),
                plan_status: group.plan_status === 'ended' ? 'ended' : 'active',
                is_new_member_group: Boolean(group.is_new_member_group ?? sourceGroup.is_new_member_group),
                climbing_threshold: group.climbing_threshold ?? sourceGroup.climbing_threshold ?? null,
            };
        });

    const members = [...assignments]
        .sort((left, right) => Number(left.sort_order || 0) - Number(right.sort_order || 0))
        .map(assignment => {
            const person = getNestedRecord(assignment.people);
            const directory = getNestedRecord(assignment.member_directory);
            const sourceMembership = getNestedRecord(assignment.source_membership);
            const sourceMembershipGroup = getNestedRecord(sourceMembership.group);
            const sourceDirectoryId = typeof assignment.source_member_directory_id === 'string'
                ? assignment.source_member_directory_id
                : null;

            return {
                id: `season-${String(assignment.id || '')}`,
                season_assignment_id: String(assignment.id || ''),
                full_name: getText(directory.full_name, person.display_name, '이름 없음'),
                phone: getText(directory.phone, person.normalized_phone),
                group_id: typeof assignment.plan_group_id === 'string' ? assignment.plan_group_id : null,
                role_in_group: typeof assignment.role_in_group === 'string' ? assignment.role_in_group : 'member',
                family_name: getText(directory.family_name) || null,
                spouse_name: getText(directory.spouse_name) || null,
                children_info: getText(directory.children_info) || null,
                birth_date: getText(directory.birth_date) || null,
                wedding_anniversary: getText(directory.wedding_anniversary) || null,
                notes: getText(directory.notes) || null,
                avatar_url: getText(directory.avatar_url) || null,
                profile_id: getText(directory.profile_id) || null,
                person_id: String(assignment.person_id || ''),
                phase2_person_id: String(assignment.person_id || ''),
                phase2_membership_id: typeof assignment.source_membership_id === 'string' ? assignment.source_membership_id : null,
                source_membership_group_id: typeof sourceMembership.group_id === 'string' ? sourceMembership.group_id : null,
                source_membership_group_name: getText(sourceMembershipGroup.name) || null,
                source_member_directory_id: sourceDirectoryId,
                starts_week_date: getDateText(assignment.starts_week_date),
                ends_week_date: getDateText(assignment.ends_week_date),
            };
        });

    return { groups, members };
};
