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

export type AttendanceRosterBackfillMode = 'none' | 'current-active';

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
  activeWindowPeople: number;
  snapshotPeople: number;
  backfilledPeople: number;
  usedRetroactiveBackfill: boolean;
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

export const getCurrentActiveRoster = (roster: AttendanceRosterMember[]) => {
  return roster.filter((member) => !dateOnly(member.endsAt));
};

export const calculateWeekAttendanceMetrics = ({
  weekDate,
  roster,
  attendance,
  noMeetingDates = new Set<string>(),
  backfillMode = 'none',
}: {
  weekDate: string;
  roster: AttendanceRosterMember[];
  attendance: AttendanceRecordForMetrics[];
  noMeetingDates?: Set<string>;
  backfillMode?: AttendanceRosterBackfillMode;
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
      activeWindowPeople: 0,
      snapshotPeople: 0,
      backfilledPeople: 0,
      usedRetroactiveBackfill: false,
    };
  }

  const activeRoster = getActiveRosterForWeek(roster, week);
  const directoryToPerson = new Map(
    roster.map((member) => [member.directoryMemberId, member.personId])
  );
  const activePeople = new Set(activeRoster.map((member) => member.personId));
  const presentPeople = new Set<string>();
  const snapshotPeople = new Set<string>();

  attendance.forEach((record) => {
    const personId = directoryToPerson.get(record.directoryMemberId);
    if (!personId) return;

    // Historical Phase 2 starts_at can be later than old attendance snapshots.
    // A recorded attendance row is still evidence that the person was part of that week's denominator.
    activePeople.add(personId);
    snapshotPeople.add(personId);

    if (record.status === 'present' || record.status === 'late') {
      presentPeople.add(personId);
    }
  });

  const activeWindowPeople = new Set(activeRoster.map((member) => member.personId));
  let usedRetroactiveBackfill = false;
  let backfilledPeople = 0;

  if (
    backfillMode === 'current-active' &&
    snapshotPeople.size > 0 &&
    activeWindowPeople.size < activePeople.size
  ) {
    const beforeBackfill = activePeople.size;
    getCurrentActiveRoster(roster).forEach((member) => {
      activePeople.add(member.personId);
    });
    backfilledPeople = Math.max(activePeople.size - beforeBackfill, 0);
    usedRetroactiveBackfill = backfilledPeople > 0;
  }

  const totalPeople = activePeople.size;
  const presentCount = presentPeople.size;

  return {
    totalPeople,
    presentPeople: presentCount,
    absentPeople: Math.max(totalPeople - presentCount, 0),
    rate: totalPeople > 0 ? Math.round((presentCount / totalPeople) * 100) : null,
    isNoMeetingDay,
    activeWindowPeople: activeWindowPeople.size,
    snapshotPeople: snapshotPeople.size,
    backfilledPeople,
    usedRetroactiveBackfill,
  };
};

export const buildAttendanceTargetExplanation = (
  metrics: WeekAttendanceMetrics
) => {
  const details: string[] = [];

  if (metrics.isNoMeetingDay) {
    details.push('모임없는날로 출석률 계산에서 제외했습니다.');
    return details;
  }

  details.push(`주차 기준 active person ${metrics.activeWindowPeople}명`);

  if (metrics.snapshotPeople > 0) {
    details.push(`출석 기록에 포함된 person ${metrics.snapshotPeople}명`);
  }

  if (metrics.usedRetroactiveBackfill) {
    details.push(`과거 입력 보정으로 현재 active roster ${metrics.backfilledPeople}명 추가 반영`);
  }

  return details;
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
