export const isUuid = (value: unknown) =>
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

export const buildRegroupingSeasonGroupsPayload = (groups: Array<Record<string, unknown>>) =>
    groups.map((group, index) => {
        const id = typeof group.id === 'string' ? group.id : null;
        const planGroupId = typeof group.plan_group_id === 'string' && isUuid(group.plan_group_id)
            ? group.plan_group_id
            : null;
        const sourceGroupId = typeof group.source_group_id === 'string' && isUuid(group.source_group_id)
            ? group.source_group_id
            : isUuid(id)
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
                source_member_directory_id: typeof member.id === 'string' && isUuid(member.id)
                    ? member.id
                    : null,
            };
        })
        .filter((assignment): assignment is NonNullable<typeof assignment> => assignment !== null);
