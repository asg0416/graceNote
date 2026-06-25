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
  status?: string | null;
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

export type WeekAttendanceTargetDetails = {
  targetPersonIds: Set<string>;
  activeWindowPersonIds: Set<string>;
  snapshotPersonIds: Set<string>;
  backfilledPersonIds: Set<string>;
  usedRetroactiveBackfill: boolean;
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
  if (member.status === 'inactive' && !endsAt) return false;
  if (startsAt && startsAt > week) return false;
  if (endsAt && endsAt < week) return false;
  return true;
};

export const getActiveRosterForWeek = (
  roster: AttendanceRosterMember[],
  weekDate: string
) => roster.filter((member) => isRosterMemberActiveOnWeek(member, weekDate));

export const getCurrentActiveRoster = (roster: AttendanceRosterMember[]) => {
  return roster.filter((member) => member.status !== 'inactive' && !dateOnly(member.endsAt));
};

export const getWeekAttendanceTargetDetails = ({
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
}): WeekAttendanceTargetDetails => {
  const week = dateOnly(weekDate) || weekDate;
  const isNoMeetingDay = noMeetingDates.has(week);
  const emptyDetails = {
    targetPersonIds: new Set<string>(),
    activeWindowPersonIds: new Set<string>(),
    snapshotPersonIds: new Set<string>(),
    backfilledPersonIds: new Set<string>(),
    usedRetroactiveBackfill: false,
    isNoMeetingDay,
  };

  if (isNoMeetingDay) return emptyDetails;

  const activeRoster = getActiveRosterForWeek(roster, week);
  const directoryToPerson = new Map(
    roster.map((member) => [member.directoryMemberId, member.personId])
  );
  const activeWindowPersonIds = new Set(activeRoster.map((member) => member.personId));
  const snapshotPersonIds = new Set<string>();

  attendance.forEach((record) => {
    const personId = directoryToPerson.get(record.directoryMemberId);
    if (personId) snapshotPersonIds.add(personId);
  });

  const targetPersonIds = new Set(activeWindowPersonIds);
  const backfilledPersonIds = new Set<string>();

  if (
    backfillMode === 'current-active' &&
    snapshotPersonIds.size > 0 &&
    activeWindowPersonIds.size === 0
  ) {
    snapshotPersonIds.forEach((personId) => {
      targetPersonIds.add(personId);
    });

    getCurrentActiveRoster(roster).forEach((member) => {
      if (!targetPersonIds.has(member.personId)) {
        backfilledPersonIds.add(member.personId);
      }
      targetPersonIds.add(member.personId);
    });
  }

  return {
    targetPersonIds,
    activeWindowPersonIds,
    snapshotPersonIds,
    backfilledPersonIds,
    usedRetroactiveBackfill: backfilledPersonIds.size > 0,
    isNoMeetingDay,
  };
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

  const targetDetails = getWeekAttendanceTargetDetails({
    weekDate,
    roster,
    attendance,
    noMeetingDates,
    backfillMode,
  });
  const activePeople = targetDetails.targetPersonIds;
  const presentSnapshotPeople = new Set<string>();
  const directoryToPerson = new Map(
    roster.map((member) => [member.directoryMemberId, member.personId])
  );

  attendance.forEach((record) => {
    const personId = directoryToPerson.get(record.directoryMemberId);
    if (!personId) return;

    if (record.status === 'present' || record.status === 'late') {
      presentSnapshotPeople.add(personId);
    }
  });

  const totalPeople = activePeople.size;
  const presentCount = Array.from(presentSnapshotPeople)
    .filter((personId) => activePeople.has(personId))
    .length;

  return {
    totalPeople,
    presentPeople: presentCount,
    absentPeople: Math.max(totalPeople - presentCount, 0),
    rate: totalPeople > 0 ? Math.round((presentCount / totalPeople) * 100) : null,
    isNoMeetingDay,
    activeWindowPeople: targetDetails.activeWindowPersonIds.size,
    snapshotPeople: targetDetails.snapshotPersonIds.size,
    backfilledPeople: targetDetails.backfilledPersonIds.size,
    usedRetroactiveBackfill: targetDetails.usedRetroactiveBackfill,
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

  details.push(`선택 주차 조편성 대상 ${metrics.activeWindowPeople}명`);

  if (metrics.usedRetroactiveBackfill) {
    details.push(`과거 입력 보정으로 현재 명부 ${metrics.backfilledPeople}명 추가 반영`);
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
