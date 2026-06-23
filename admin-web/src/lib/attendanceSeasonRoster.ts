export type SeasonPlanGroup = {
  id: string;
  sourceGroupId?: string | null;
  name?: string | null;
  startsWeekDate?: string | null;
  endsWeekDate?: string | null;
  planStatus?: string | null;
  sortOrder?: number | null;
};

export type SeasonPlanAssignment = {
  id: string;
  planGroupId?: string | null;
  personId?: string | null;
  sourceMemberDirectoryId?: string | null;
  role?: string | null;
  startsWeekDate?: string | null;
  endsWeekDate?: string | null;
  sortOrder?: number | null;
};

export type SeasonPlanDirectoryMember = {
  id: string;
  full_name?: string | null;
  person_id?: string | null;
  group_id?: string | null;
  group_name?: string | null;
  group_member_id?: string | null;
  role_in_group?: string | null;
  family_name?: string | null;
  spouse_name?: string | null;
  children_info?: string | null;
  starts_at?: string | null;
  ends_at?: string | null;
  is_active?: boolean | null;
  [key: string]: unknown;
};

export type SeasonPlanAttendanceRosterInput = {
  weekDate: string;
  planGroups: SeasonPlanGroup[];
  assignments: SeasonPlanAssignment[];
  directoryMembers: SeasonPlanDirectoryMember[];
};

const dateOnly = (value?: string | null) => value?.slice(0, 10) || null;

const isDateInPeriod = (
  weekDate: string,
  startsAt?: string | null,
  endsAt?: string | null
) => {
  const week = dateOnly(weekDate);
  if (!week) return false;

  const starts = dateOnly(startsAt);
  const ends = dateOnly(endsAt);

  return (!starts || starts <= week) && (!ends || ends >= week);
};

const maxDateText = (...values: Array<string | null | undefined>) => (
  values
    .map(dateOnly)
    .filter((value): value is string => Boolean(value))
    .sort((a, b) => b.localeCompare(a))[0] || null
);

const minDateText = (...values: Array<string | null | undefined>) => (
  values
    .map(dateOnly)
    .filter((value): value is string => Boolean(value))
    .sort((a, b) => a.localeCompare(b))[0] || null
);

export const buildSeasonPlanAttendanceRoster = ({
  weekDate,
  planGroups,
  assignments,
  directoryMembers,
}: SeasonPlanAttendanceRosterInput): SeasonPlanDirectoryMember[] => {
  const activePlanGroupById = new Map(
    planGroups
      .filter((group) => isDateInPeriod(weekDate, group.startsWeekDate, group.endsWeekDate))
      .map((group) => [group.id, group])
  );
  const planGroupOrderByKey = new Map<string, number>();
  planGroups.forEach((group, index) => {
    const order = group.sortOrder ?? index;
    planGroupOrderByKey.set(group.id, order);
    if (group.sourceGroupId) planGroupOrderByKey.set(group.sourceGroupId, order);
    if (group.name) planGroupOrderByKey.set(group.name, order);
  });

  if (activePlanGroupById.size === 0) return [];

  const directoryById = new Map(directoryMembers.map((member) => [member.id, member]));
  const directoryByPersonId = new Map<string, SeasonPlanDirectoryMember>();
  directoryMembers.forEach((member) => {
    const personId = member.person_id;
    if (!personId || directoryByPersonId.has(personId)) return;
    directoryByPersonId.set(personId, member);
  });

  const rosterByGroupPerson = new Map<string, SeasonPlanDirectoryMember>();

  assignments
    .filter((assignment) => assignment.planGroupId && activePlanGroupById.has(assignment.planGroupId))
    .filter((assignment) => isDateInPeriod(weekDate, assignment.startsWeekDate, assignment.endsWeekDate))
    .forEach((assignment) => {
      const planGroup = activePlanGroupById.get(assignment.planGroupId as string);
      if (!planGroup) return;

      const directory = assignment.sourceMemberDirectoryId
        ? directoryById.get(assignment.sourceMemberDirectoryId)
        : undefined;
      const personId = assignment.personId || directory?.person_id || null;
      const fallbackDirectory = personId ? directoryByPersonId.get(personId) : undefined;
      const sourceDirectory = directory || fallbackDirectory;

      if (!personId || !sourceDirectory) return;

      const startsAt = maxDateText(planGroup.startsWeekDate, assignment.startsWeekDate);
      const endsAt = minDateText(planGroup.endsWeekDate, assignment.endsWeekDate);
      if (startsAt && endsAt && startsAt > endsAt) return;

      const groupId = planGroup.sourceGroupId || null;
      const groupKey = groupId || planGroup.id;
      const rosterMember: SeasonPlanDirectoryMember = {
        ...sourceDirectory,
        id: sourceDirectory.id,
        person_id: personId,
        group_id: groupId,
        group_name: planGroup.name || sourceDirectory.group_name || null,
        role_in_group: assignment.role || sourceDirectory.role_in_group || 'member',
        group_member_id: null,
        starts_at: startsAt,
        ends_at: endsAt,
        membership_status: 'active',
        phase2_membership_source: 'regrouping_plan_assignments',
      };
      const rosterKey = `${groupKey}::${personId}`;
      const previous = rosterByGroupPerson.get(rosterKey);
      if (!previous || (previous.role_in_group !== 'leader' && rosterMember.role_in_group === 'leader')) {
        rosterByGroupPerson.set(rosterKey, rosterMember);
      }
    });

  return Array.from(rosterByGroupPerson.values()).sort((left, right) => {
    const leftOrder = planGroupOrderByKey.get(left.group_id || left.group_name || '') ?? 9999;
    const rightOrder = planGroupOrderByKey.get(right.group_id || right.group_name || '') ?? 9999;
    if (leftOrder !== rightOrder) return leftOrder - rightOrder;
    return String(left.full_name || '').localeCompare(String(right.full_name || ''));
  });
};
