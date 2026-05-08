export type SnapshotAttendanceStatus = 'present' | 'late' | 'absent' | 'unknown';

export type AttendanceRosterSnapshotMember = {
  id: string;
  snapshotId: string;
  personId: string;
  displayName: string;
  groupId?: string | null;
  groupName?: string | null;
  role?: string | null;
  attendanceStatus: SnapshotAttendanceStatus;
  included: boolean;
  source?: string | null;
};

export type SnapshotAttendanceMetrics = {
  totalPeople: number;
  presentPeople: number;
  absentPeople: number;
  rate: number | null;
};

export type SnapshotGroupDisplay = {
  groupId: string | null;
  groupName: string;
  totalPeople: number;
  presentPeople: number;
  members: AttendanceRosterSnapshotMember[];
};

type SupabaseErrorLike = {
  message?: string;
};

type RpcClientLike = {
  rpc: (
    functionName: string,
    args?: Record<string, unknown>
  ) => PromiseLike<{ data: unknown; error: SupabaseErrorLike | null }>;
};

type SnapshotMembersQuery = PromiseLike<{
  data: AttendanceRosterSnapshotMemberRow[] | null;
  error: SupabaseErrorLike | null;
}> & {
  order: (
    column: string,
    options?: { ascending?: boolean; nullsFirst?: boolean }
  ) => SnapshotMembersQuery;
};

type SnapshotMembersFilter = {
  eq: (column: string, value: string) => SnapshotMembersQuery;
};

type SnapshotMembersSelect = {
  select: (columns: string) => SnapshotMembersFilter;
};

type SnapshotMembersClientLike = {
  from: (table: 'attendance_roster_snapshot_members') => SnapshotMembersSelect;
};

type AttendanceRosterSnapshotMemberRow = {
  id: string;
  snapshot_id: string;
  person_id: string;
  display_name: string;
  group_id?: string | null;
  group_name?: string | null;
  role?: string | null;
  attendance_status?: string | null;
  included?: boolean | null;
  source?: string | null;
};

const isPresentStatus = (status: SnapshotAttendanceStatus) => (
  status === 'present' || status === 'late'
);

const normalizeSnapshotStatus = (
  status?: string | null
): SnapshotAttendanceStatus => {
  if (status === 'present' || status === 'late' || status === 'absent') {
    return status;
  }

  return 'unknown';
};

export const mapSnapshotMemberRow = (
  row: AttendanceRosterSnapshotMemberRow
): AttendanceRosterSnapshotMember => ({
  id: row.id,
  snapshotId: row.snapshot_id,
  personId: row.person_id,
  displayName: row.display_name,
  groupId: row.group_id,
  groupName: row.group_name,
  role: row.role,
  attendanceStatus: normalizeSnapshotStatus(row.attendance_status),
  included: row.included !== false,
  source: row.source,
});

export const calculateSnapshotMetrics = (
  members: AttendanceRosterSnapshotMember[]
): SnapshotAttendanceMetrics => {
  const includedMembers = members.filter((member) => member.included);
  const totalPeople = includedMembers.length;
  const presentPeople = includedMembers
    .filter((member) => isPresentStatus(member.attendanceStatus))
    .length;

  return {
    totalPeople,
    presentPeople,
    absentPeople: Math.max(totalPeople - presentPeople, 0),
    rate: totalPeople > 0 ? Math.round((presentPeople / totalPeople) * 100) : null,
  };
};

export const groupSnapshotMembersForDisplay = (
  members: AttendanceRosterSnapshotMember[]
): SnapshotGroupDisplay[] => {
  const groups = new Map<string, SnapshotGroupDisplay>();

  members.forEach((member) => {
    const key = member.groupId || '__unassigned__';
    const group = groups.get(key) || {
      groupId: member.groupId || null,
      groupName: member.groupName || '미편성',
      totalPeople: 0,
      presentPeople: 0,
      members: [],
    };

    group.members.push(member);
    if (member.included) {
      group.totalPeople += 1;
      if (isPresentStatus(member.attendanceStatus)) {
        group.presentPeople += 1;
      }
    }

    groups.set(key, group);
  });

  return Array.from(groups.values())
    .map((group) => ({
      ...group,
      members: [...group.members].sort((a, b) => (
        a.displayName.localeCompare(b.displayName)
      )),
    }))
    .sort((a, b) => a.groupName.localeCompare(b.groupName));
};

export const ensureAttendanceRosterSnapshot = async (
  client: RpcClientLike,
  departmentId: string,
  weekId: string
) => {
  const { data, error } = await client.rpc('ensure_attendance_roster_snapshot', {
    p_department_id: departmentId,
    p_week_id: weekId,
  });

  if (error) {
    throw new Error(error.message || '출석 대상 snapshot 생성에 실패했습니다.');
  }

  if (typeof data !== 'string') {
    throw new Error('출석 대상 snapshot ID를 받지 못했습니다.');
  }

  return data;
};

export const fetchAttendanceRosterSnapshotMembers = async (
  client: SnapshotMembersClientLike,
  snapshotId: string
) => {
  const { data, error } = await client
    .from('attendance_roster_snapshot_members')
    .select(`
      id,
      snapshot_id,
      person_id,
      display_name,
      group_id,
      group_name,
      role,
      attendance_status,
      included,
      source
    `)
    .eq('snapshot_id', snapshotId)
    .order('group_name', { ascending: true, nullsFirst: false })
    .order('display_name', { ascending: true });

  if (error) {
    throw new Error(error.message || '출석 대상 snapshot 구성원을 불러오지 못했습니다.');
  }

  return (data || []).map(mapSnapshotMemberRow);
};
