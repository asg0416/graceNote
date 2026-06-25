export type AttendanceDisplayGroup = {
  id: string;
  name: string;
};

export type AttendanceWeekGroupNameSource = {
  groupId?: string | null;
  groupName?: string | null;
};

const normalizeGroupName = (groupName?: string | null) => {
  const trimmed = groupName?.trim();
  if (!trimmed || trimmed === '조 없음') return null;
  return trimmed;
};

export const applyAttendanceWeekGroupDisplayNames = <T extends AttendanceDisplayGroup>(
  groups: T[],
  sources: AttendanceWeekGroupNameSource[]
): T[] => {
  const displayNameByGroupId = new Map<string, string>();

  sources.forEach((source) => {
    if (!source.groupId || displayNameByGroupId.has(source.groupId)) return;
    const displayName = normalizeGroupName(source.groupName);
    if (!displayName) return;
    displayNameByGroupId.set(source.groupId, displayName);
  });

  return groups.map((group) => {
    const displayName = displayNameByGroupId.get(group.id);
    if (!displayName || displayName === group.name) return group;
    return {
      ...group,
      name: displayName,
    };
  });
};
