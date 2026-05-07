export type AttendanceRosterMember = {
  directoryMemberId: string;
  personId: string;
  fullName: string;
  groupId?: string | null;
  groupName?: string | null;
  role?: string | null;
  spouseName?: string | null;
  familyName?: string | null;
  startsAt?: string | null;
  endsAt?: string | null;
};

export type AttendanceRecordForMetrics = {
  directoryMemberId: string;
  status?: string | null;
};

export type WeekAttendanceMetrics = {
  totalPeople: number;
  presentPeople: number;
  absentPeople: number;
  rate: number | null;
  isNoMeetingDay: boolean;
};

const dateOnly = (value?: string | null) => value?.slice(0, 10) || null;

export const isRosterMemberActiveOnWeek = (
  member: AttendanceRosterMember,
  weekDate: string
) => {
  const startsAt = dateOnly(member.startsAt);
  const endsAt = dateOnly(member.endsAt);
  const week = dateOnly(weekDate);

  if (!week) return false;
  if (startsAt && startsAt > week) return false;
  if (endsAt && endsAt < week) return false;
  return true;
};

export const getActiveRosterForWeek = (
  roster: AttendanceRosterMember[],
  weekDate: string
) => roster.filter((member) => isRosterMemberActiveOnWeek(member, weekDate));

export const calculateWeekAttendanceMetrics = ({
  weekDate,
  roster,
  attendance,
  noMeetingDates = new Set<string>(),
}: {
  weekDate: string;
  roster: AttendanceRosterMember[];
  attendance: AttendanceRecordForMetrics[];
  noMeetingDates?: Set<string>;
}): WeekAttendanceMetrics => {
  const week = dateOnly(weekDate) || weekDate;
  const isNoMeetingDay = noMeetingDates.has(week);

  if (isNoMeetingDay) {
    return {
      totalPeople: 0,
      presentPeople: 0,
      absentPeople: 0,
      rate: null,
      isNoMeetingDay,
    };
  }

  const activeRoster = getActiveRosterForWeek(roster, week);
  const directoryToPerson = new Map(
    roster.map((member) => [member.directoryMemberId, member.personId])
  );
  const activePeople = new Set(activeRoster.map((member) => member.personId));
  const presentPeople = new Set<string>();

  attendance.forEach((record) => {
    const personId = directoryToPerson.get(record.directoryMemberId);
    if (!personId) return;

    // Historical Phase 2 starts_at can be later than old attendance snapshots.
    // A recorded attendance row is still evidence that the person was part of that week's denominator.
    activePeople.add(personId);

    if (record.status === 'present' || record.status === 'late') {
      presentPeople.add(personId);
    }
  });

  const totalPeople = activePeople.size;
  const presentCount = presentPeople.size;

  return {
    totalPeople,
    presentPeople: presentCount,
    absentPeople: Math.max(totalPeople - presentCount, 0),
    rate: totalPeople > 0 ? Math.round((presentCount / totalPeople) * 100) : null,
    isNoMeetingDay,
  };
};

export const getFamilySortKey = (member: AttendanceRosterMember) => {
  if (member.familyName) return `family:${member.familyName}`;
  if (member.spouseName) {
    return `spouse:${[member.fullName, member.spouseName].sort().join('_')}`;
  }
  return `person:${member.fullName}`;
};

export const sortRosterForDisplay = (members: AttendanceRosterMember[]) => {
  return [...members].sort((a, b) => {
    const groupDiff = (a.groupName || '').localeCompare(b.groupName || '');
    if (groupDiff !== 0) return groupDiff;

    const familyDiff = getFamilySortKey(a).localeCompare(getFamilySortKey(b));
    if (familyDiff !== 0) return familyDiff;

    return a.fullName.localeCompare(b.fullName);
  });
};
