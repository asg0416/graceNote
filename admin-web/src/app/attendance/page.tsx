'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Loader2,
    Calendar,
    Download,
    ChevronDown,
    CheckCircle2,
    XCircle,
    AlertCircle,
    Users,
    Church as ChurchIcon,
    Layers,
    Trophy,
    HeartPulse,
    TrendingUp,
    ChevronLeft,
    ChevronRight,
    Filter,
    BarChart3,
    CalendarDays
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Modal } from '@/components/Modal';
import {
    calculateSnapshotMetrics,
    addSnapshotMember,
    ensureAttendanceRosterSnapshot,
    fetchAttendanceRosterSnapshotMembers,
    loadGroupRosterIntoSnapshot,
    loadMissingGroupRostersIntoSnapshot,
    setSnapshotMemberIncluded,
    setSnapshotMemberStatus,
    type AttendanceRosterSnapshotMembersClient,
    type AttendanceRosterSnapshotRpcClient,
    type AttendanceRosterSnapshotMember,
    type SnapshotAttendanceStatus,
    type SnapshotAttendanceMetrics,
} from '@/lib/attendanceRosterSnapshots';
import * as XLSX from 'xlsx';

type AttendanceDirectoryMember = {
    id: string;
    full_name?: string | null;
    group_id?: string | null;
    group_name?: string | null;
    group_member_id?: string | null;
    person_id?: string | null;
    phase2_membership_source?: string | null;
    role_in_group?: string | null;
    family_name?: string | null;
    spouse_name?: string | null;
    children_info?: string | null;
    starts_at?: string | null;
    ends_at?: string | null;
    is_active?: boolean | null;
    [key: string]: unknown;
};

type AttendanceDashboardItem = {
    id: string;
    snapshotMemberId?: string | null;
    personId?: string | null;
    name: string;
    department: string;
    group: string;
    role: string;
    status: string;
    updatedAt: string | null;
    spouseName?: string | null;
    familyName?: string | null;
    included?: boolean;
    submittedStatus?: SnapshotAttendanceStatus | null;
    hasSubmissionConflict?: boolean;
    reason?: string | null;
};

type AttendanceGroupRow = {
    id: string;
    name: string;
    created_at?: string | null;
};

type SnapshotAddCandidate = {
    personId: string;
    name: string;
    groupName?: string | null;
    scopeLabel: string;
};

type ExportAttendancePerson = {
    name: string;
    role: string;
    groupName: string;
    spouseName?: string | null;
    familyName?: string | null;
    weeks: Map<string, AttendanceRosterSnapshotMember>;
};

type Phase2AttendanceMembership = {
    person_id: string | null;
    role: string | null;
    status?: string | null;
    legacy_member_directory_id: string | null;
    legacy_group_member_id: string | null;
    starts_at?: string | null;
    ends_at?: string | null;
    groups?: {
        id?: string | null;
        name?: string | null;
    } | null;
};

const SUBMISSION_CONFLICT_KEEP_ADMIN_REASON = 'admin attendance dashboard keep admin over submitted attendance';

type AttendanceStatusRow = {
    status?: string | null;
};

type AttendanceRow = AttendanceStatusRow & {
    directory_member_id: string;
    group_id?: string | null;
    updated_at?: string | null;
    groups?: {
        id?: string | null;
        name?: string | null;
    } | null;
};

type WeekRow = {
    id: string;
    week_date: string;
};

type ProfileRow = {
    id: string;
    full_name?: string | null;
    role?: string | null;
    admin_status?: string | null;
    is_master?: boolean | null;
    church_id?: string | null;
    department_id?: string | null;
};

type ChurchRow = {
    id: string;
    name: string;
};

type DepartmentRow = {
    id: string;
    name: string;
    church_id?: string | null;
};

type GroupStat = {
    name: string;
    present: number;
    total: number;
};

type WeeklyTrendDatum = {
    id: string;
    date: string;
    present: number;
    total: number;
    rate: number | null;
    isNoMeetingDay: boolean;
    hasError?: boolean;
};

type InsightPersonReport = {
    id: string;
    directoryMemberId?: string | null;
    full_name: string;
    group_name: string;
    presentWeekIds: Set<string>;
    totalWeekIds: Set<string>;
    rate: number;
    presentCount: number;
    consecutiveAbsences: boolean;
    totalWeeks: number;
};

type InsightGroupRanking = {
    name: string;
    presentSum: number;
    totalAttCount: number;
    rate: number;
    weekCount: number;
    dataWeekCount: number;
    averagePresent: number;
    averageTarget: number;
};

type InsightSubmissionRiskGroup = {
    id: string;
    name: string;
    expectedWeeks: number;
    submittedWeeks: number;
    missedWeeks: number;
    missedWeekLabels: string[];
    averageTarget: number;
    riskRate: number;
};

type SupabaseErrorLike = {
    message?: string;
    code?: string;
    details?: string;
    hint?: string;
};

const buildQueryError = (label: string, error: unknown) => {
    const supabaseError = error as SupabaseErrorLike | null | undefined;
    const parts = [
        supabaseError?.message,
        supabaseError?.code ? `code=${supabaseError.code}` : null,
        supabaseError?.details ? `details=${supabaseError.details}` : null,
        supabaseError?.hint ? `hint=${supabaseError.hint}` : null,
    ].filter(Boolean);

    return new Error(`${label}: ${parts.join(' / ') || 'unknown error'}`);
};

const fetchMembershipRoster = async (
    departmentId: string
): Promise<AttendanceDirectoryMember[]> => {
    try {
        const membershipQuery = supabase
            .from('memberships')
            .select(`
                person_id,
                role,
                status,
                legacy_member_directory_id,
                legacy_group_member_id,
                starts_at,
                ends_at,
                groups!group_id(id, name)
            `)
            .eq('department_id', departmentId)
            .not('legacy_member_directory_id', 'is', null);

        const { data: memberships, error: membershipError } = await membershipQuery;

        if (membershipError) throw buildQueryError('memberships roster query failed', membershipError);
        if (!memberships || memberships.length === 0) return [];

        const typedMemberships = memberships as Phase2AttendanceMembership[];
        const directoryIds = Array.from(new Set(
            typedMemberships
                .map((membership) => membership.legacy_member_directory_id)
                .filter(Boolean)
        ));

        if (directoryIds.length === 0) return [];

        const { data: directoryRows, error: directoryError } = await supabase
            .from('member_directory')
            .select('*')
            .in('id', directoryIds)
            .eq('is_active', true);

        if (directoryError) throw buildQueryError('member_directory roster query failed', directoryError);

        const directoryById = new Map<string, AttendanceDirectoryMember>(
            ((directoryRows || []) as AttendanceDirectoryMember[]).map((directory) => [directory.id, directory])
        );

        return typedMemberships
            .reduce<AttendanceDirectoryMember[]>((roster, membership) => {
                if (!membership.legacy_member_directory_id) return roster;
                const directory = directoryById.get(membership.legacy_member_directory_id);
                if (!directory) return roster;

                roster.push({
                    ...directory,
                    group_id: membership.groups?.id || directory.group_id,
                    group_name: membership.groups?.name || directory.group_name,
                    role_in_group: membership.role || directory.role_in_group,
                    group_member_id: membership.legacy_group_member_id,
                    person_id: membership.person_id,
                    membership_status: membership.status,
                    starts_at: membership.starts_at,
                    ends_at: membership.ends_at,
                    phase2_membership_source: 'memberships'
                });
                return roster;
            }, []);
    } catch (error) {
        console.warn('Attendance Phase 2 roster read failed. Falling back to legacy member_directory.', error);
        return [];
    }
};

const fetchAttendanceRoster = async (
    departmentId: string
): Promise<AttendanceDirectoryMember[]> => {
    const phase2Roster = await fetchMembershipRoster(departmentId);
    if (phase2Roster.length > 0) return phase2Roster;

    const { data, error } = await supabase
        .from('member_directory')
        .select('*')
        .eq('department_id', departmentId)
        .eq('is_active', true);

    if (error) throw buildQueryError('legacy attendance roster query failed', error);
    return (data || []) as AttendanceDirectoryMember[];
};

const getAttendanceItemFamilyKey = (item: AttendanceDashboardItem) => {
    if (item.familyName) return `family:${item.familyName}`;
    if (item.spouseName) return `spouse:${[item.name, item.spouseName].sort().join('_')}`;
    return `person:${item.name}`;
};

const sortAttendanceItemsForDisplay = (
    items: AttendanceDashboardItem[],
    groupOrder = new Map<string, number>()
) => {
    return [...items].sort((a, b) => {
        const aGroupOrder = groupOrder.get(a.group) ?? 9999;
        const bGroupOrder = groupOrder.get(b.group) ?? 9999;
        const groupOrderDiff = aGroupOrder - bGroupOrder;
        if (groupOrderDiff !== 0) return groupOrderDiff;

        const groupDiff = a.group.localeCompare(b.group);
        if (groupDiff !== 0) return groupDiff;

        const familyDiff = getAttendanceItemFamilyKey(a).localeCompare(getAttendanceItemFamilyKey(b));
        if (familyDiff !== 0) return familyDiff;

        return a.name.localeCompare(b.name);
    });
};

const applyAttendanceRowsToSnapshotMembers = (
    snapshotMembers: AttendanceRosterSnapshotMember[],
    attendanceRows: AttendanceRow[]
) => {
    const attendanceByDirectoryId = new Map(
        attendanceRows.map((row) => [row.directory_member_id, row])
    );

    return snapshotMembers.map((member) => {
        const attendance = member.legacyMemberDirectoryId
            ? attendanceByDirectoryId.get(member.legacyMemberDirectoryId)
            : undefined;

        return {
            ...member,
            attendanceStatus: member.attendanceStatus === 'unknown' && (
                attendance?.status === 'present' || attendance?.status === 'late' || attendance?.status === 'absent'
            )
                ? attendance.status
                : member.attendanceStatus,
        };
    });
};

const normalizeSubmittedAttendanceStatus = (
    status?: string | null
): SnapshotAttendanceStatus | null => {
    if (status === 'present' || status === 'late' || status === 'absent') {
        return status;
    }

    return null;
};

const getCompactAttendanceLabel = (status?: SnapshotAttendanceStatus | null) => {
    switch (status) {
        case 'present':
            return '출석';
        case 'late':
            return '지각';
        case 'absent':
            return '결석';
        default:
            return '미확인';
    }
};

const getExportAttendanceMark = (status?: SnapshotAttendanceStatus | null) => {
    switch (status) {
        case 'present':
            return 'O';
        case 'late':
            return 'L';
        case 'absent':
        case 'unknown':
            return 'X';
        default:
            return '-';
    }
};

const mergeExportAttendanceStatus = (
    current: SnapshotAttendanceStatus,
    incoming: SnapshotAttendanceStatus
): SnapshotAttendanceStatus => {
    if (current === 'present' || incoming === 'present') return 'present';
    if (current === 'late' || incoming === 'late') return 'late';
    return 'absent';
};

const formatSnapshotMemberNames = (
    members: AttendanceRosterSnapshotMember[],
    personIds: Set<string>,
    limit = 5
) => {
    const names = Array.from(new Set(members
        .filter((member) => personIds.has(member.personId))
        .map((member) => member.displayName)
    )).filter(Boolean);

    if (names.length <= limit) return names.join(', ');
    return `${names.slice(0, limit).join(', ')} 외 ${names.length - limit}명`;
};

const formatShortWeekDate = (date: string) => {
    const [, month, day] = date.split('-');
    return month && day ? `${Number(month)}/${Number(day)}` : date;
};

const getSnapshotMembersForWeek = async (
    departmentId: string,
    weekId: string
) => {
    const snapshotRpcClient = supabase as unknown as AttendanceRosterSnapshotRpcClient;
    const snapshotMembersClient = supabase as unknown as AttendanceRosterSnapshotMembersClient;
    const snapshotId = await ensureAttendanceRosterSnapshot(snapshotRpcClient, departmentId, weekId);
    const snapshotMembers = await fetchAttendanceRosterSnapshotMembers(snapshotMembersClient, snapshotId);

    const { data: departmentGroups, error: departmentGroupsError } = await supabase
        .from('groups')
        .select('id')
        .eq('department_id', departmentId);

    if (departmentGroupsError) {
        throw buildQueryError('attendance department groups query failed', departmentGroupsError);
    }

    const departmentGroupIds = ((departmentGroups || []) as { id: string }[]).map((group) => group.id);
    if (departmentGroupIds.length === 0) {
        return {
            snapshotId,
            snapshotMembers,
            snapshotMembersWithAttendance: snapshotMembers,
            attendanceRows: [],
        };
    }

    const { data: attendance, error } = await supabase
        .from('attendance')
        .select('*')
        .eq('week_id', weekId)
        .in('group_id', departmentGroupIds);

    if (error) throw buildQueryError('attendance rows query failed', error);

    return {
        snapshotId,
        snapshotMembers,
        snapshotMembersWithAttendance: applyAttendanceRowsToSnapshotMembers(snapshotMembers, (attendance || []) as AttendanceRow[]),
        attendanceRows: (attendance || []) as AttendanceRow[],
    };
};

export default function AttendancePage() {
    const [loading, setLoading] = useState(true);
    const [profile, setProfile] = useState<ProfileRow | null>(null);

    // Selection States
    const [churches, setChurches] = useState<ChurchRow[]>([]);
    const [selectedChurchId, setSelectedChurchId] = useState<string>('');
    const [departments, setDepartments] = useState<DepartmentRow[]>([]);
    const [selectedDeptId, setSelectedDeptId] = useState<string>('');
    const [weeks, setWeeks] = useState<WeekRow[]>([]);
    const [selectedWeekId, setSelectedWeekId] = useState<string>('');

    // Data States
    const [attendanceData, setAttendanceData] = useState<AttendanceDashboardItem[]>([]);
    const [groupStats, setGroupStats] = useState<GroupStat[]>([]);
    const [selectedWeekMetrics, setSelectedWeekMetrics] = useState<SnapshotAttendanceMetrics | null>(null);
    const [targetExplanation, setTargetExplanation] = useState<string[]>([]);
    const [snapshotEditLoadingId, setSnapshotEditLoadingId] = useState<string | null>(null);
    const [ignoredSubmissionConflictKeys, setIgnoredSubmissionConflictKeys] = useState<Set<string>>(new Set());
    const [selectedWeekNoMeetingReason, setSelectedWeekNoMeetingReason] = useState<string | null>(null);
    const [selectedWeekHasSubmittedAttendance, setSelectedWeekHasSubmittedAttendance] = useState(false);
    const [isNoMeetingMutationLoading, setIsNoMeetingMutationLoading] = useState(false);
    const [attendanceView, setAttendanceView] = useState<'weekly' | 'insights'>('weekly');

    // Stats View States
    const [statsPeriod, setStatsPeriod] = useState<'quarter' | 'year'>('quarter');
    const [hallOfFame, setHallOfFame] = useState<InsightPersonReport[]>([]);
    const [careList, setCareList] = useState<InsightPersonReport[]>([]);

    const [selectedYear, setSelectedYear] = useState<number>(new Date().getFullYear());
    const [selectedMonth, setSelectedMonth] = useState<number>(new Date().getMonth() + 1);
    const [weeklyTrendData, setWeeklyTrendData] = useState<WeeklyTrendDatum[]>([]);
    const [isTrendLoading, setIsTrendLoading] = useState(false);
    const [attendanceSnapshotVersion, setAttendanceSnapshotVersion] = useState(0);

    // Insight Report Specific States (Independent)
    const [insightYear, setInsightYear] = useState<number>(new Date().getFullYear());
    const [insightQuarter, setInsightQuarter] = useState<number>(Math.floor(new Date().getMonth() / 3) + 1);
    const [groupRankings, setGroupRankings] = useState<InsightGroupRanking[]>([]);
    const [submissionRiskGroups, setSubmissionRiskGroups] = useState<InsightSubmissionRiskGroup[]>([]);

    // Hall of Fame & Care List Filter Settings
    const [hallOfFameTarget] = useState<'rate' | 'count'>('rate');
    const [hallOfFameValue, setHallOfFameValue] = useState<number>(80);
    const [careTarget] = useState<'rate' | 'consecutive'>('consecutive');
    const [careValue] = useState<number>(3); // 3 weeks or 30%

    // Detail View Toggle
    const [isDetailExpanded, setIsDetailExpanded] = useState(false);

    // Export States
    const [isExportModalOpen, setIsExportModalOpen] = useState(false);
    const [startYear, setStartYear] = useState(new Date().getFullYear());
    const [startMonth, setStartMonth] = useState(1);
    const [endYear, setEndYear] = useState(new Date().getFullYear());
    const [endMonth, setEndMonth] = useState(new Date().getMonth() + 1);
    const [isExportLoading, setIsExportLoading] = useState(false);
    const [, setIsInsightsLoading] = useState(false);
    const [currentSnapshotId, setCurrentSnapshotId] = useState<string | null>(null);
    const [attendanceGroups, setAttendanceGroups] = useState<AttendanceGroupRow[]>([]);
    const [isAddSnapshotMemberModalOpen, setIsAddSnapshotMemberModalOpen] = useState(false);
    const [addSnapshotGroupId, setAddSnapshotGroupId] = useState<string | null>(null);
    const [addSnapshotSearch, setAddSnapshotSearch] = useState('');
    const [addSnapshotCandidates, setAddSnapshotCandidates] = useState<SnapshotAddCandidate[]>([]);
    const router = useRouter();

    useEffect(() => {
        const checkUser = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                router.push('/login');
                return;
            }

            const { data } = await supabase
                .from('profiles')
                .select('id, full_name, role, admin_status, is_master, church_id, department_id')
                .eq('id', session.user.id)
                .single();

            const isAuthorized = data && (data.is_master || (data.role === 'admin' && data.admin_status === 'approved'));

            if (!isAuthorized) {
                await supabase.auth.signOut();
                router.push('/login?error=unauthorized');
                return;
            }

            setProfile(data);

            // Master: Load Churches, Admin: Set Church and Load Departments
            if (data.is_master) {
                const { data: churchList } = await supabase.from('churches').select('*').order('name');
                setChurches(churchList || []);
                if (churchList && churchList.length > 0) {
                    setSelectedChurchId(churchList[0].id);
                }
            } else {
                setSelectedChurchId(data.church_id);
            }

            setLoading(false);
        };

        checkUser();
    }, [router]);

    // Handle Church Change
    useEffect(() => {
        if (selectedChurchId) {
            const fetchData = async () => {
                // 1. Load Departments
                let deptQuery = supabase
                    .from('departments')
                    .select('*')
                    .eq('church_id', selectedChurchId)
                    .eq('is_active', true);

                if (profile?.department_id) {
                    deptQuery = deptQuery.eq('id', profile.department_id);
                }

                const { data: deptList } = await deptQuery.order('name');
                setDepartments(deptList || []);

                if (profile?.department_id) {
                    setSelectedDeptId(profile.department_id);
                } else if (deptList && deptList.length > 0) {
                    setSelectedDeptId(deptList[0].id);
                } else {
                    setSelectedDeptId('');
                }

                // 2. Load Weeks - Remove setWeeks here to avoid conflict with monthly filter
                const { data: weekList } = await supabase
                    .from('weeks')
                    .select('*')
                    .eq('church_id', selectedChurchId)
                    .eq('is_active', true)
                    .order('week_date', { ascending: false });

                const sortedWeeks = weekList || [];
                // setWeeks(sortedWeeks); // Conflicted with monthly filter

                if (sortedWeeks.length > 0) {
                    // Group by Month for Tabs (if needed in future, but not used now)
                    /*
                    const groups: any = {};
                    sortedWeeks.forEach(w => {
                        const m = w.week_date.substring(0, 7); 
                        if (!groups[m]) groups[m] = [];
                        groups[m].push(w);
                    });
                    const mList = Object.keys(groups).sort().reverse();
                    setMonthWeeks(mList.map(m => ({ month: m, weeks: groups[m].reverse() })));
                    */

                    // Initial Selection: Latest Week
                    if (!selectedWeekId) {
                        setSelectedWeekId(sortedWeeks[0].id);
                    }
                } else {
                    setSelectedWeekId('');
                }
            };
            fetchData();
        }
    }, [selectedChurchId]);

    // Handle Dept/Year/Month Change -> Update Weeks and Trend
    useEffect(() => {
        if (selectedChurchId && selectedDeptId) {
            const fetchTrendAndWeeks = async () => {
                setIsTrendLoading(true);
                try {
                    // 1. Fetch weeks for the selected year/month
                    const startOfMonth = `${selectedYear}-${selectedMonth.toString().padStart(2, '0')}-01`;
                    const lastDay = new Date(selectedYear, selectedMonth, 0).getDate();
                    const endOfMonth = `${selectedYear}-${selectedMonth.toString().padStart(2, '0')}-${lastDay.toString().padStart(2, '0')}`;

                    const { data: monthWeeksList, error: monthWeeksError } = await supabase
                        .from('weeks')
                        .select('*')
                        .eq('church_id', selectedChurchId)
                        .eq('is_active', true)
                        .gte('week_date', startOfMonth)
                        .lte('week_date', endOfMonth)
                        .order('week_date', { ascending: true });

                    if (monthWeeksError) throw buildQueryError('attendance month weeks query failed', monthWeeksError);

                    const monthWeeks = monthWeeksList || [];
                    setWeeks(monthWeeks);
                    if (monthWeeks.length > 0) {
                        setSelectedWeekId((currentWeekId) => (
                            currentWeekId && monthWeeks.some((week) => week.id === currentWeekId)
                                ? currentWeekId
                                : monthWeeks[monthWeeks.length - 1].id
                        ));
                    } else {
                        setSelectedWeekId('');
                    }

                    // 2. Fetch Weekly Trend (Last 5 weeks for the vertical chart)
                    const { data: trendWeeks, error: trendWeeksError } = await supabase
                        .from('weeks')
                        .select('id, week_date')
                        .eq('church_id', selectedChurchId)
                        .eq('is_active', true)
                        .gte('week_date', startOfMonth)
                        .lte('week_date', endOfMonth)
                        .order('week_date', { ascending: true });

                    if (trendWeeksError) throw buildQueryError('attendance trend weeks query failed', trendWeeksError);

                    const { data: monthNoMeetingDays, error: noMeetingDaysError } = await supabase
                        .from('no_meeting_days')
                        .select('week_date')
                        .eq('department_id', selectedDeptId)
                        .gte('week_date', startOfMonth)
                        .lte('week_date', endOfMonth);

                    if (noMeetingDaysError) throw buildQueryError('attendance no-meeting days query failed', noMeetingDaysError);

                    const monthNoMeetingDateSet = new Set<string>(
                        ((monthNoMeetingDays || []) as { week_date: string }[]).map((day) => day.week_date)
                    );

                    if (trendWeeks && trendWeeks.length > 0) {
                        const trendData = await Promise.all(trendWeeks.map(async (w) => {
                            try {
                                const isNoMeetingDay = monthNoMeetingDateSet.has(w.week_date);
                                const { snapshotMembersWithAttendance } = await getSnapshotMembersForWeek(
                                    selectedDeptId,
                                    w.id
                                );
                                const metrics = isNoMeetingDay
                                    ? { totalPeople: 0, presentPeople: 0, absentPeople: 0, rate: null }
                                    : calculateSnapshotMetrics(snapshotMembersWithAttendance);

                                return {
                                    id: w.id,
                                    date: w.week_date.substring(5), // MM-DD
                                    present: metrics.presentPeople,
                                    total: metrics.totalPeople,
                                    rate: metrics.rate,
                                    isNoMeetingDay,
                                    hasError: false,
                                };
                            } catch (error) {
                                console.error(`Attendance trend week failed (${w.week_date}):`, error);
                                return {
                                    id: w.id,
                                    date: w.week_date.substring(5),
                                    present: 0,
                                    total: 0,
                                    rate: null,
                                    isNoMeetingDay: false,
                                    hasError: true,
                                };
                            }
                        }));
                        setWeeklyTrendData(trendData);
                    } else {
                        setWeeklyTrendData([]);
                    }
                } catch (error) {
                    console.error('Attendance trend fetch error:', error);
                    setWeeklyTrendData([]);
                } finally {
                    setIsTrendLoading(false);
                }
            };
            fetchTrendAndWeeks();
        }
    }, [selectedChurchId, selectedDeptId, selectedYear, selectedMonth, attendanceSnapshotVersion]);

    const prevMonth = () => {
        if (selectedMonth === 1) {
            setSelectedYear(prev => prev - 1);
            setSelectedMonth(12);
        } else {
            setSelectedMonth(prev => prev - 1);
        }
    };

    const nextMonth = () => {
        const now = new Date();
        const nowYear = now.getFullYear();
        const nowMonth = now.getMonth() + 1;
        if (selectedYear === nowYear && selectedMonth === nowMonth) return;

        if (selectedMonth === 12) {
            setSelectedYear(prev => prev + 1);
            setSelectedMonth(1);
        } else {
            setSelectedMonth(prev => prev + 1);
        }
    };

    // Handle Week Change
    useEffect(() => {
        if (selectedWeekId) {
            fetchAttendance();
        } else {
            setAttendanceData([]);
            setGroupStats([]);
            setSelectedWeekNoMeetingReason(null);
            setSelectedWeekHasSubmittedAttendance(false);
        }
    }, [selectedWeekId]);

    const fetchAttendance = async () => {
        if (!selectedDeptId || !selectedWeekId) return;

        try {
            const selectedWeek = weeks.find((week) => week.id === selectedWeekId) as WeekRow | undefined;
            if (!selectedWeek) return;

            // 1. Ensure explicit week+department roster snapshot.
            const {
                snapshotId,
                snapshotMembers,
                snapshotMembersWithAttendance,
                attendanceRows,
            } = await getSnapshotMembersForWeek(selectedDeptId, selectedWeekId);
            setCurrentSnapshotId(snapshotId);

            const { data: selectedNoMeetingDays, error: selectedNoMeetingDaysError } = await supabase
                .from('no_meeting_days')
                .select('week_date, reason')
                .eq('department_id', selectedDeptId)
                .eq('week_date', selectedWeek.week_date);

            if (selectedNoMeetingDaysError) {
                throw buildQueryError('selected week no-meeting query failed', selectedNoMeetingDaysError);
            }

            const selectedNoMeetingDateSet = new Set<string>(
                ((selectedNoMeetingDays || []) as { week_date: string }[]).map((day) => day.week_date)
            );
            const selectedNoMeetingDay = ((selectedNoMeetingDays || []) as { week_date: string; reason?: string | null }[])[0];

            const isNoMeetingDay = selectedNoMeetingDateSet.has(selectedWeek.week_date);
            setSelectedWeekNoMeetingReason(isNoMeetingDay ? selectedNoMeetingDay?.reason || '' : null);
            setSelectedWeekHasSubmittedAttendance(attendanceRows.length > 0);
            const rawSnapshotMemberById = new Map(
                snapshotMembers.map((member) => [member.id, member])
            );
            const submittedAttendanceByDirectoryId = new Map(
                attendanceRows
                    .filter((row) => row.directory_member_id)
                    .map((row) => [row.directory_member_id, normalizeSubmittedAttendanceStatus(row.status)])
            );
            const metrics = isNoMeetingDay
                ? {
                    totalPeople: 0,
                    presentPeople: 0,
                    absentPeople: 0,
                    rate: null,
                }
                : calculateSnapshotMetrics(snapshotMembersWithAttendance);
            setSelectedWeekMetrics(metrics);
            const selectedTargetPersonIds = new Set(
                snapshotMembersWithAttendance
                    .filter((member) => member.included)
                    .map((member) => member.personId)
            );
            const explanation: string[] = [];

            const previousWeek = [...weeks]
                .filter((week) => week.week_date < selectedWeek.week_date)
                .sort((a, b) => b.week_date.localeCompare(a.week_date))[0] as WeekRow | undefined;

            if (previousWeek) {
                const { snapshotMembers: previousSnapshotMembers } = await getSnapshotMembersForWeek(
                    selectedDeptId,
                    previousWeek.id
                );
                const previousTargetPersonIds = new Set(
                    previousSnapshotMembers
                        .filter((member) => member.included)
                        .map((member) => member.personId)
                );

                const addedPeople = new Set(
                    Array.from(selectedTargetPersonIds)
                        .filter((personId) => !previousTargetPersonIds.has(personId))
                );
                const removedPeople = new Set(
                    Array.from(previousTargetPersonIds)
                        .filter((personId) => !selectedTargetPersonIds.has(personId))
                );

                if (addedPeople.size > 0) {
                    explanation.push(`전주 대비 추가 ${addedPeople.size}명: ${formatSnapshotMemberNames(snapshotMembersWithAttendance, addedPeople)}`);
                }
                if (removedPeople.size > 0) {
                    explanation.push(`전주 대비 제외 ${removedPeople.size}명: ${formatSnapshotMemberNames(previousSnapshotMembers, removedPeople)}`);
                }
            }
            setTargetExplanation(explanation);

            // 3. Merge & Reconstruct Data
            // 부서 내 전체 조 목록 조회 (미제출 조 표시용)
            const { data: deptGroups, error: deptGroupsError } = await supabase
                .from('groups')
                .select('id, name, created_at')
                .eq('department_id', selectedDeptId)
                .eq('is_active', true)
                .order('created_at', { ascending: true })
                .order('name', { ascending: true });
            if (deptGroupsError) throw buildQueryError('attendance active groups query failed', deptGroupsError);
            const orderedGroups = ((deptGroups || []) as AttendanceGroupRow[]);
            const groupOrder = new Map(orderedGroups.map((group, index) => [group.name, index]));
            setAttendanceGroups(orderedGroups);

            const rosterForFamilySort = await fetchAttendanceRoster(selectedDeptId);
            const familySortByPersonId = new Map(
                rosterForFamilySort
                    .filter((member) => member.person_id)
                    .map((member) => [
                        String(member.person_id),
                        {
                            spouseName: member.spouse_name || null,
                            familyName: member.family_name || null,
                        },
                    ])
            );

            const finalMerged = sortAttendanceItemsForDisplay(
                snapshotMembersWithAttendance
                    .filter((member) => (
                        member.included ||
                        Boolean(
                            member.legacyMemberDirectoryId &&
                            submittedAttendanceByDirectoryId.has(member.legacyMemberDirectoryId)
                        )
                    ))
                    .map((member) => {
                        const familySort = familySortByPersonId.get(member.personId);
                        const submittedStatus = member.legacyMemberDirectoryId
                            ? submittedAttendanceByDirectoryId.get(member.legacyMemberDirectoryId) || null
                            : null;
                        const rawSnapshotStatus = rawSnapshotMemberById.get(member.id)?.attendanceStatus || 'unknown';
                        const isExcludedButSubmitted = member.included === false && Boolean(submittedStatus);
                        const isSubmittedConflictResolved = member.reason === SUBMISSION_CONFLICT_KEEP_ADMIN_REASON;
                        const hasSubmissionConflict = Boolean(
                            !isSubmittedConflictResolved &&
                            (
                                isExcludedButSubmitted ||
                                (
                                    submittedStatus &&
                                    rawSnapshotStatus !== 'unknown' &&
                                    rawSnapshotStatus !== submittedStatus
                                )
                            )
                        );

                        return {
                            id: member.legacyMemberDirectoryId || member.id,
                            snapshotMemberId: member.id,
                            personId: member.personId,
                            name: member.displayName || '이름 없음',
                            department: departments.find(d => d.id === selectedDeptId)?.name || '부서 없음',
                            group: member.groupName || '미편성',
                            role: member.role || 'member',
                            status: member.attendanceStatus === 'unknown' ? 'absent' : member.attendanceStatus,
                            updatedAt: null,
                            spouseName: familySort?.spouseName || null,
                            familyName: familySort?.familyName || null,
                            included: member.included,
                            submittedStatus,
                            hasSubmissionConflict,
                            reason: member.reason,
                        };
                    }),
                groupOrder
            );
            setAttendanceData(finalMerged);

            // 4. Calculate Group Stats (All Groups in Dept)
            const groupsMap = new Map<string, { name: string; total: number; present: number }>();
            // 먼저 부서 내 모든 조를 0으로 초기화
            orderedGroups.forEach(g => {
                groupsMap.set(g.name, { name: g.name, total: 0, present: 0 });
            });

            finalMerged.forEach(item => {
                if (!groupsMap.has(item.group)) {
                    groupsMap.set(item.group, { name: item.group, total: 0, present: 0 });
                }
                const g = groupsMap.get(item.group);
                if (!g) return;
                if (item.included === false) return;
                g.total++;
                if (item.status === 'present' || item.status === 'late') g.present++;
            });

            const stats = Array.from(groupsMap.values());
            setGroupStats(stats.sort((a, b) => {
                const aOrder = groupOrder.get(a.name) ?? 9999;
                const bOrder = groupOrder.get(b.name) ?? 9999;
                if (aOrder !== bOrder) return aOrder - bOrder;
                return a.name.localeCompare(b.name);
            }));

            fetchInsights();
        } catch (err) {
            console.error('Attendance Fetch Error:', err);
        }
    };

    const updateSnapshotMemberStatus = async (
        snapshotMemberId: string,
        status: SnapshotAttendanceStatus
    ) => {
        try {
            setSnapshotEditLoadingId(snapshotMemberId);
            await setSnapshotMemberStatus(
                supabase as unknown as AttendanceRosterSnapshotRpcClient,
                snapshotMemberId,
                status,
                'admin attendance dashboard edit'
            );
            setAttendanceSnapshotVersion((value) => value + 1);
            await fetchAttendance();
        } catch (err) {
            console.error('Snapshot status update error:', err);
            alert(err instanceof Error ? err.message : '출석 상태 수정 중 오류가 발생했습니다.');
        } finally {
            setSnapshotEditLoadingId(null);
        }
    };

    const excludeSnapshotMember = async (snapshotMemberId: string, name: string) => {
        if (!confirm(`${name} 성도를 이 주차 출석 대상에서 제외할까요? 성도 명부에서는 삭제되지 않습니다.`)) {
            return;
        }

        try {
            setSnapshotEditLoadingId(snapshotMemberId);
            await setSnapshotMemberIncluded(
                supabase as unknown as AttendanceRosterSnapshotRpcClient,
                snapshotMemberId,
                false,
                'admin attendance dashboard exclude'
            );
            setAttendanceSnapshotVersion((value) => value + 1);
            await fetchAttendance();
        } catch (err) {
            console.error('Snapshot exclude error:', err);
            alert(err instanceof Error ? err.message : '출석 대상 제외 중 오류가 발생했습니다.');
        } finally {
            setSnapshotEditLoadingId(null);
        }
    };

    const restoreSnapshotMemberWithSubmittedStatus = async (member: AttendanceDashboardItem) => {
        if (!member.snapshotMemberId || !member.submittedStatus) return;

        try {
            setSnapshotEditLoadingId(member.snapshotMemberId);
            await setSnapshotMemberIncluded(
                supabase as unknown as AttendanceRosterSnapshotRpcClient,
                member.snapshotMemberId,
                true,
                'admin attendance dashboard restore submitted member'
            );
            await setSnapshotMemberStatus(
                supabase as unknown as AttendanceRosterSnapshotRpcClient,
                member.snapshotMemberId,
                member.submittedStatus,
                'admin attendance dashboard apply submitted status'
            );
            setAttendanceSnapshotVersion((value) => value + 1);
            await fetchAttendance();
        } catch (err) {
            console.error('Snapshot restore submitted member error:', err);
            alert(err instanceof Error ? err.message : '조장 제출값 적용 중 오류가 발생했습니다.');
        } finally {
            setSnapshotEditLoadingId(null);
        }
    };

    const applySubmittedStatusesForGroup = async (
        groupName: string,
        members: AttendanceDashboardItem[]
    ) => {
        const targets = members.filter((member) => member.snapshotMemberId && member.submittedStatus);
        if (targets.length === 0) return;
        if (!confirm(`${groupName} 조의 조장 제출 출석부를 관리자 확정값으로 적용할까요?`)) return;

        const loadingKey = `group-submission:${groupName}`;
        try {
            setSnapshotEditLoadingId(loadingKey);
            for (const member of targets) {
                if (!member.snapshotMemberId || !member.submittedStatus) continue;

                if (member.included === false) {
                    await setSnapshotMemberIncluded(
                        supabase as unknown as AttendanceRosterSnapshotRpcClient,
                        member.snapshotMemberId,
                        true,
                        'admin attendance dashboard restore group submitted member'
                    );
                }

                await setSnapshotMemberStatus(
                    supabase as unknown as AttendanceRosterSnapshotRpcClient,
                    member.snapshotMemberId,
                    member.submittedStatus,
                    'admin attendance dashboard apply group submitted status'
                );
            }
            setAttendanceSnapshotVersion((value) => value + 1);
            await fetchAttendance();
        } catch (err) {
            console.error('Apply group submitted statuses error:', err);
            alert(err instanceof Error ? err.message : '조장 제출 출석부 적용 중 오류가 발생했습니다.');
        } finally {
            setSnapshotEditLoadingId(null);
        }
    };

    const mergeSubmittedStatusesForGroup = async (
        groupName: string,
        members: AttendanceDashboardItem[]
    ) => {
        const excludedSubmittedTargets = members
            .filter((member) => member.included === false)
            .filter((member) => member.snapshotMemberId && member.submittedStatus);
        const keepAdminTargets = members
            .filter((member) => member.included !== false)
            .filter((member) => member.hasSubmissionConflict && member.snapshotMemberId);
        if (excludedSubmittedTargets.length === 0 && keepAdminTargets.length === 0) {
            alert('병합할 조장 제출 변경사항이 없습니다.');
            return;
        }
        if (!confirm(`${groupName} 조에서 조장이 제출한 새 인원은 추가하고, 기존 관리자 수정값은 유지할까요?`)) return;

        const loadingKey = `group-submission:${groupName}`;
        try {
            setSnapshotEditLoadingId(loadingKey);
            for (const member of excludedSubmittedTargets) {
                if (!member.snapshotMemberId || !member.submittedStatus) continue;
                await setSnapshotMemberIncluded(
                    supabase as unknown as AttendanceRosterSnapshotRpcClient,
                    member.snapshotMemberId,
                    true,
                    'admin attendance dashboard merge submitted member'
                );
                await setSnapshotMemberStatus(
                    supabase as unknown as AttendanceRosterSnapshotRpcClient,
                    member.snapshotMemberId,
                    member.submittedStatus,
                    'admin attendance dashboard merge submitted status'
                );
            }
            for (const member of keepAdminTargets) {
                if (!member.snapshotMemberId) continue;
                await setSnapshotMemberStatus(
                    supabase as unknown as AttendanceRosterSnapshotRpcClient,
                    member.snapshotMemberId,
                    (member.status as SnapshotAttendanceStatus) || 'absent',
                    SUBMISSION_CONFLICT_KEEP_ADMIN_REASON
                );
            }
            setAttendanceSnapshotVersion((value) => value + 1);
            await fetchAttendance();
        } catch (err) {
            console.error('Merge group submitted statuses error:', err);
            alert(err instanceof Error ? err.message : '조장 제출 출석부 병합 중 오류가 발생했습니다.');
        } finally {
            setSnapshotEditLoadingId(null);
        }
    };

    const getSubmissionConflictKey = (groupName: string) => `${selectedWeekId}:${groupName}`;

    const keepAdminAttendanceForGroup = (groupName: string) => {
        const targets = attendanceData
            .filter((member) => member.group === groupName)
            .filter((member) => member.hasSubmissionConflict)
            .filter((member) => member.snapshotMemberId);

        if (targets.length === 0) return;
        if (!confirm(`${groupName} 조는 현재 관리자 화면을 확정하고 조장 제출본을 무시할까요?`)) return;

        const loadingKey = `group-submission:${groupName}`;
        const persistKeepAdminChoice = async () => {
            try {
                setSnapshotEditLoadingId(loadingKey);
                for (const member of targets) {
                    if (!member.snapshotMemberId) continue;

                    if (member.included === false) {
                        await setSnapshotMemberIncluded(
                            supabase as unknown as AttendanceRosterSnapshotRpcClient,
                            member.snapshotMemberId,
                            false,
                            SUBMISSION_CONFLICT_KEEP_ADMIN_REASON
                        );
                    } else {
                        await setSnapshotMemberStatus(
                            supabase as unknown as AttendanceRosterSnapshotRpcClient,
                            member.snapshotMemberId,
                            (member.status as SnapshotAttendanceStatus) || 'absent',
                            SUBMISSION_CONFLICT_KEEP_ADMIN_REASON
                        );
                    }
                }
                setIgnoredSubmissionConflictKeys((previous) => {
                    const next = new Set(previous);
                    next.add(getSubmissionConflictKey(groupName));
                    return next;
                });
                setAttendanceSnapshotVersion((value) => value + 1);
                await fetchAttendance();
            } catch (err) {
                console.error('Keep admin attendance conflict resolution error:', err);
                alert(err instanceof Error ? err.message : '관리자 화면 유지 처리 중 오류가 발생했습니다.');
            } finally {
                setSnapshotEditLoadingId(null);
            }
        };

        void persistKeepAdminChoice();
    };

    const refreshAttendanceDashboard = async () => {
        setAttendanceSnapshotVersion((value) => value + 1);
        await fetchAttendance();
    };

    const markSelectedWeekAsNoMeetingDay = async () => {
        if (!selectedDeptId || !selectedWeekId) return;

        const selectedWeek = weeks.find((week) => week.id === selectedWeekId) as WeekRow | undefined;
        if (!selectedWeek) return;

        const reason = window.prompt('모임없는 날 사유를 입력하세요.', '모임 없음');
        if (reason === null) return;

        try {
            setIsNoMeetingMutationLoading(true);
            const { error } = await supabase
                .from('no_meeting_days')
                .upsert({
                    department_id: selectedDeptId,
                    week_date: selectedWeek.week_date,
                    reason: reason.trim() || '모임 없음',
                    created_by: profile?.id || null,
                }, {
                    onConflict: 'department_id,week_date',
                });

            if (error) throw error;

            await refreshAttendanceDashboard();
        } catch (err) {
            console.error('No meeting day set error:', err);
            alert(err instanceof Error ? err.message : '모임없는 날 지정 중 오류가 발생했습니다.');
        } finally {
            setIsNoMeetingMutationLoading(false);
        }
    };

    const cancelSelectedWeekNoMeetingDay = async () => {
        if (!selectedDeptId || !selectedWeekId) return;

        const selectedWeek = weeks.find((week) => week.id === selectedWeekId) as WeekRow | undefined;
        if (!selectedWeek) return;
        if (!confirm('이 주차의 모임없는 날 지정을 취소할까요?')) return;

        try {
            setIsNoMeetingMutationLoading(true);
            const { error } = await supabase
                .from('no_meeting_days')
                .delete()
                .eq('department_id', selectedDeptId)
                .eq('week_date', selectedWeek.week_date);

            if (error) throw error;

            await refreshAttendanceDashboard();
        } catch (err) {
            console.error('No meeting day cancel error:', err);
            alert(err instanceof Error ? err.message : '모임없는 날 지정 취소 중 오류가 발생했습니다.');
        } finally {
            setIsNoMeetingMutationLoading(false);
        }
    };

    const toggleSnapshotMemberAttendance = async (member: AttendanceDashboardItem) => {
        if (!member.snapshotMemberId) return;
        if (member.included === false && member.submittedStatus) {
            await restoreSnapshotMemberWithSubmittedStatus(member);
            return;
        }
        await updateSnapshotMemberStatus(
            member.snapshotMemberId,
            member.status === 'present' || member.status === 'late' ? 'absent' : 'present'
        );
    };

    const openAddSnapshotMemberModal = async (groupId: string | null) => {
        if (!selectedDeptId || !selectedChurchId) return;
        setAddSnapshotGroupId(groupId);
        setAddSnapshotSearch('');

        const roster = await fetchAttendanceRoster(selectedDeptId);
        const candidatesByPerson = new Map<string, SnapshotAddCandidate>();

        roster
            .filter((member) => member.person_id)
            .forEach((member) => {
                const personId = String(member.person_id);
                if (candidatesByPerson.has(personId)) return;

                candidatesByPerson.set(personId, {
                    personId,
                    name: member.full_name || '이름 없음',
                    groupName: member.group_name,
                    scopeLabel: '현재 부서',
                });
            });

        const { data: churchPeople, error: churchPeopleError } = await supabase
            .from('people')
            .select('id, display_name')
            .eq('church_id', selectedChurchId)
            .order('display_name', { ascending: true });

        if (churchPeopleError) throw churchPeopleError;

        (churchPeople || []).forEach((person) => {
            const personId = String(person.id);
            if (candidatesByPerson.has(personId)) return;

            candidatesByPerson.set(personId, {
                personId,
                name: person.display_name || '이름 없음',
                groupName: null,
                scopeLabel: '같은 교회 / 현재 부서 소속 아님',
            });
        });

        const candidates = Array.from(candidatesByPerson.values())
            .sort((a, b) => a.name.localeCompare(b.name));

        setAddSnapshotCandidates(candidates);
        setIsAddSnapshotMemberModalOpen(true);
    };

    const addPersonToCurrentSnapshot = async (candidate: SnapshotAddCandidate) => {
        if (!currentSnapshotId) return;

        try {
            await addSnapshotMember(
                supabase as unknown as AttendanceRosterSnapshotRpcClient,
                {
                    snapshotId: currentSnapshotId,
                    personId: candidate.personId,
                    groupId: addSnapshotGroupId,
                    reason: 'admin attendance dashboard add',
                }
            );
            setAttendanceSnapshotVersion((value) => value + 1);
            setIsAddSnapshotMemberModalOpen(false);
            await fetchAttendance();
        } catch (err) {
            console.error('Snapshot add member error:', err);
            alert(err instanceof Error ? err.message : '출석 대상 추가 중 오류가 발생했습니다.');
        }
    };

    const loadGroupRoster = async (groupId: string, groupName: string) => {
        if (!currentSnapshotId) return;
        if (!confirm(`${groupName} 현재 조명단을 이 주차 snapshot에 불러올까요?`)) return;

        try {
            const count = await loadGroupRosterIntoSnapshot(
                supabase as unknown as AttendanceRosterSnapshotRpcClient,
                currentSnapshotId,
                groupId
            );
            setAttendanceSnapshotVersion((value) => value + 1);
            await fetchAttendance();
            alert(`${count}명의 조명단을 snapshot에 반영했습니다.`);
        } catch (err) {
            console.error('Load group roster error:', err);
            alert(err instanceof Error ? err.message : '조명단 불러오기 중 오류가 발생했습니다.');
        }
    };

    const loadMissingGroupRosters = async () => {
        if (!currentSnapshotId) return;
        if (!confirm('이 주차에 출석 대상이 비어 있는 조들의 현재 조명단을 한 번에 불러올까요?')) return;

        try {
            const count = await loadMissingGroupRostersIntoSnapshot(
                supabase as unknown as AttendanceRosterSnapshotRpcClient,
                currentSnapshotId
            );
            setAttendanceSnapshotVersion((value) => value + 1);
            await fetchAttendance();
            alert(`${count}명의 미제출 조명단을 snapshot에 반영했습니다.`);
        } catch (err) {
            console.error('Load missing group rosters error:', err);
            alert(err instanceof Error ? err.message : '미제출 조명단 불러오기 중 오류가 발생했습니다.');
        }
    };

    const fetchInsights = async () => {
        if (!selectedChurchId || !selectedDeptId) return;
        setIsInsightsLoading(true);
        try {
            let startDate = `${insightYear}-01-01`;
            let endDate = `${insightYear}-12-31`;

            if (statsPeriod === 'quarter') {
                const qStartMonth = (insightQuarter - 1) * 3 + 1;
                const qEndMonth = insightQuarter * 3;
                startDate = `${insightYear}-${qStartMonth.toString().padStart(2, '0')}-01`;
                const lastDayOfQuarter = new Date(insightYear, qEndMonth, 0).getDate();
                endDate = `${insightYear}-${qEndMonth.toString().padStart(2, '0')}-${lastDayOfQuarter.toString().padStart(2, '0')}`;
            }

            // Fetch weeks in the period
            const { data: periodWeeks, error: periodWeeksError } = await supabase
                .from('weeks')
                .select('*')
                .eq('church_id', selectedChurchId)
                .eq('is_active', true)
                .gte('week_date', startDate)
                .lte('week_date', endDate)
                .order('week_date', { ascending: false });

            if (periodWeeksError) throw buildQueryError('attendance insight weeks query failed', periodWeeksError);

            if (!periodWeeks || periodWeeks.length === 0) {
                setHallOfFame([]);
                setCareList([]);
                setGroupRankings([]);
                setSubmissionRiskGroups([]);
                return;
            }

            const noMeetingDateSet = new Set<string>();
            const { data: noMeetingDaysForInsight, error: noMeetingDaysForInsightError } = await supabase
                .from('no_meeting_days')
                .select('week_date')
                .eq('department_id', selectedDeptId)
                .gte('week_date', startDate)
                .lte('week_date', endDate);
            if (noMeetingDaysForInsightError) {
                throw buildQueryError('attendance insight no-meeting query failed', noMeetingDaysForInsightError);
            }
            ((noMeetingDaysForInsight || []) as { week_date: string }[]).forEach((day) => {
                noMeetingDateSet.add(day.week_date);
            });

            const meetingWeeks = (periodWeeks as WeekRow[]).filter((week) => !noMeetingDateSet.has(week.week_date));

            const reportByPerson = new Map<string, InsightPersonReport>();
            const groupTotals = new Map<string, { name: string; presentSum: number; totalAttCount: number; weekIds: Set<string> }>();
            const submissionRiskByGroup = new Map<string, {
                id: string;
                name: string;
                expectedWeeks: number;
                submittedWeeks: number;
                missedWeekLabels: string[];
                targetPeopleSum: number;
            }>();

            const ensurePersonReport = (member: AttendanceRosterSnapshotMember) => {
                const existing = reportByPerson.get(member.personId);
                if (existing) {
                    if (!existing.directoryMemberId && member.legacyMemberDirectoryId) {
                        existing.directoryMemberId = member.legacyMemberDirectoryId;
                    }
                    if (existing.group_name === '조 없음' && member.groupName) {
                        existing.group_name = member.groupName;
                    }
                    return existing;
                }

                const report: InsightPersonReport = {
                    id: member.personId,
                    directoryMemberId: member.legacyMemberDirectoryId,
                    full_name: member.displayName || '이름 없음',
                    group_name: member.groupName || '조 없음',
                    presentWeekIds: new Set<string>(),
                    totalWeekIds: new Set<string>(),
                    rate: 0,
                    presentCount: 0,
                    consecutiveAbsences: false,
                    totalWeeks: 0,
                };
                reportByPerson.set(member.personId, report);
                return report;
            };

            for (const week of meetingWeeks) {
                const { snapshotMembersWithAttendance, attendanceRows } = await getSnapshotMembersForWeek(selectedDeptId, week.id);
                const includedMembers = snapshotMembersWithAttendance.filter((member) => member.included);
                const weekMembersByPerson = new Map<string, AttendanceRosterSnapshotMember[]>();
                const weekMembersByGroupAndPerson = new Map<string, AttendanceRosterSnapshotMember[]>();
                const submittedGroupIds = new Set(
                    attendanceRows
                        .map((row) => row.group_id)
                        .filter((groupId): groupId is string => Boolean(groupId))
                );
                const targetPeopleByGroup = new Map<string, {
                    id: string;
                    name: string;
                    personIds: Set<string>;
                }>();

                includedMembers.forEach((member) => {
                    if (!member.personId) return;
                    weekMembersByPerson.set(member.personId, [...(weekMembersByPerson.get(member.personId) || []), member]);

                    const groupName = member.groupName || '조 없음';
                    const groupPersonKey = `${groupName}::${member.personId}`;
                    weekMembersByGroupAndPerson.set(groupPersonKey, [
                        ...(weekMembersByGroupAndPerson.get(groupPersonKey) || []),
                        member,
                    ]);

                    if (member.groupId && groupName && groupName !== '조 없음') {
                        const groupTarget = targetPeopleByGroup.get(member.groupId) || {
                            id: member.groupId,
                            name: groupName,
                            personIds: new Set<string>(),
                        };
                        groupTarget.personIds.add(member.personId);
                        targetPeopleByGroup.set(member.groupId, groupTarget);
                    }
                });

                targetPeopleByGroup.forEach((groupTarget) => {
                    const existing = submissionRiskByGroup.get(groupTarget.id) || {
                        id: groupTarget.id,
                        name: groupTarget.name,
                        expectedWeeks: 0,
                        submittedWeeks: 0,
                        missedWeekLabels: [],
                        targetPeopleSum: 0,
                    };
                    existing.expectedWeeks += 1;
                    existing.targetPeopleSum += groupTarget.personIds.size;
                    if (submittedGroupIds.has(groupTarget.id)) {
                        existing.submittedWeeks += 1;
                    } else {
                        existing.missedWeekLabels.push(formatShortWeekDate(week.week_date));
                    }
                    submissionRiskByGroup.set(groupTarget.id, existing);
                });

                weekMembersByPerson.forEach((membersForPerson) => {
                    const displayMember = membersForPerson.find((member) => member.legacyMemberDirectoryId) || membersForPerson[0];
                    const report = ensurePersonReport(displayMember);
                    report.totalWeekIds.add(week.id);
                    if (membersForPerson.some((member) => member.attendanceStatus === 'present' || member.attendanceStatus === 'late')) {
                        report.presentWeekIds.add(week.id);
                    }

                });

                weekMembersByGroupAndPerson.forEach((membersForGroupPerson) => {
                    const displayMember = membersForGroupPerson[0];
                    const groupName = displayMember.groupName || '조 없음';
                    if (!groupName || groupName === '조 없음') return;

                    const group = groupTotals.get(groupName) || {
                        name: groupName,
                        presentSum: 0,
                        totalAttCount: 0,
                        weekIds: new Set<string>(),
                    };
                    group.weekIds.add(week.id);
                    group.totalAttCount += 1;
                    if (membersForGroupPerson.some((member) => member.attendanceStatus === 'present' || member.attendanceStatus === 'late')) {
                        group.presentSum += 1;
                    }
                    groupTotals.set(groupName, group);
                });
            }

            const commonTotalWeeks = meetingWeeks.length;
            const report = Array.from(reportByPerson.values()).map((personReport) => {
                const totalWeeks = commonTotalWeeks;
                const presentCount = personReport.presentWeekIds.size;
                const rate = totalWeeks > 0 ? (presentCount / totalWeeks) * 100 : 0;
                const last3Weeks = meetingWeeks.slice(0, 3);
                const consecutiveAbsences = last3Weeks.length >= 3 && last3Weeks.every((week) => (
                    !personReport.presentWeekIds.has(week.id)
                ));

                return {
                    ...personReport,
                    presentCount,
                    rate,
                    consecutiveAbsences,
                    totalWeeks,
                };
            });

            setHallOfFame(report.filter(r =>
                hallOfFameTarget === 'rate' ? r.rate >= hallOfFameValue : r.presentCount >= hallOfFameValue
            ).sort((a, b) => b.rate - a.rate));

            setCareList(report.filter(r => {
                if (careTarget === 'consecutive') return r.consecutiveAbsences;
                return r.rate <= careValue;
            }).sort((a, b) => a.rate - b.rate));

            const rankings = Array.from(groupTotals.values())
                .map((g) => {
                    const weekCount = Math.max(1, commonTotalWeeks);
                    const dataWeekCount = g.weekIds.size;
                    return {
                        name: g.name,
                        presentSum: g.presentSum,
                        totalAttCount: g.totalAttCount,
                        weekCount,
                        dataWeekCount,
                        averagePresent: g.presentSum / weekCount,
                        averageTarget: g.totalAttCount / weekCount,
                        rate: g.totalAttCount > 0 ? (g.presentSum / g.totalAttCount) * 100 : 0
                    };
                })
                .filter(g => g.name && g.name !== '조 없음')
                .sort((a, b) => b.rate - a.rate);

            setGroupRankings(rankings);
            setSubmissionRiskGroups(Array.from(submissionRiskByGroup.values())
                .map((group) => {
                    const missedWeeks = group.expectedWeeks - group.submittedWeeks;
                    return {
                        id: group.id,
                        name: group.name,
                        expectedWeeks: group.expectedWeeks,
                        submittedWeeks: group.submittedWeeks,
                        missedWeeks,
                        missedWeekLabels: group.missedWeekLabels,
                        averageTarget: group.expectedWeeks > 0 ? group.targetPeopleSum / group.expectedWeeks : 0,
                        riskRate: group.expectedWeeks > 0 ? (missedWeeks / group.expectedWeeks) * 100 : 0,
                    };
                })
                .filter((group) => group.expectedWeeks >= 2 && group.missedWeeks >= 2)
                .sort((a, b) => {
                    const missedDiff = b.missedWeeks - a.missedWeeks;
                    if (missedDiff !== 0) return missedDiff;
                    return b.riskRate - a.riskRate;
                }));

        } catch (err) {
            console.error('Insights Error:', err);
            setHallOfFame([]);
            setCareList([]);
            setGroupRankings([]);
            setSubmissionRiskGroups([]);
        } finally {
            setIsInsightsLoading(false);
        }
    };

    useEffect(() => {
        fetchInsights();
    }, [statsPeriod, selectedDeptId, insightYear, insightQuarter, hallOfFameTarget, hallOfFameValue, careTarget, careValue]);

    const downloadRangeExcel = async () => {
        setIsExportLoading(true);
        try {
            // 1. Get all weeks in target range
            const startStr = `${startYear}-${startMonth.toString().padStart(2, '0')}-01`;
            const lastDay = new Date(endYear, endMonth, 0).getDate();
            const endStr = `${endYear}-${endMonth.toString().padStart(2, '0')}-${lastDay.toString().padStart(2, '0')}`;

            const { data: rangeWeeks } = await supabase
                .from('weeks')
                .select('*')
                .eq('church_id', selectedChurchId)
                .eq('is_active', true)
                .gte('week_date', startStr)
                .lte('week_date', endStr)
                .order('week_date', { ascending: true });

            if (!rangeWeeks || rangeWeeks.length === 0) {
                alert('해당 기간에 등록된 주차 정보가 없습니다.');
                return;
            }

            // 2. 해당 기간의 모임없는 날 조회
            const { data: noMeetingDays } = await supabase
                .from('no_meeting_days')
                .select('week_date, reason')
                .eq('department_id', selectedDeptId)
                .gte('week_date', startStr)
                .lte('week_date', endStr);

            const noMeetingDateSet = new Set<string>(
                ((noMeetingDays || []) as { week_date: string }[]).map((day) => day.week_date)
            );

            const { data: exportGroups } = await supabase
                .from('groups')
                .select('id, name, created_at')
                .eq('department_id', selectedDeptId)
                .order('created_at', { ascending: true })
                .order('name', { ascending: true });

            const exportGroupOrder = new Map(
                ((exportGroups || []) as AttendanceGroupRow[])
                    .map((group, index) => [group.name, index])
            );
            const rosterForFamilySort = await fetchAttendanceRoster(selectedDeptId);
            const familySortByPersonId = new Map(
                rosterForFamilySort
                    .filter((member) => member.person_id)
                    .map((member) => [
                        String(member.person_id),
                        {
                            spouseName: member.spouse_name || null,
                            familyName: member.family_name || null,
                        },
                    ])
            );

            const snapshotMembersByWeekId = new Map<string, AttendanceRosterSnapshotMember[]>();
            const peopleById = new Map<string, ExportAttendancePerson>();

            for (const week of rangeWeeks as WeekRow[]) {
                if (noMeetingDateSet.has(week.week_date)) {
                    snapshotMembersByWeekId.set(week.id, []);
                    continue;
                }

                const { snapshotMembersWithAttendance } = await getSnapshotMembersForWeek(
                    selectedDeptId,
                    week.id
                );
                const includedMembers = snapshotMembersWithAttendance
                    .filter((member) => member.included);
                snapshotMembersByWeekId.set(week.id, includedMembers);

                includedMembers.forEach((member) => {
                    const familySort = familySortByPersonId.get(member.personId);
                    const existing = peopleById.get(member.personId) || {
                        name: member.displayName || '이름 없음',
                        role: member.role || '성도',
                        groupName: member.groupName || '조 없음',
                        spouseName: familySort?.spouseName || null,
                        familyName: familySort?.familyName || null,
                        weeks: new Map<string, AttendanceRosterSnapshotMember>(),
                    };

                    const existingWeekMember = existing.weeks.get(week.id);
                    if (existingWeekMember) {
                        existing.weeks.set(week.id, {
                            ...existingWeekMember,
                            attendanceStatus: mergeExportAttendanceStatus(
                                existingWeekMember.attendanceStatus,
                                member.attendanceStatus
                            ),
                        });
                    } else {
                        existing.weeks.set(week.id, member);
                    }
                    if (member.groupName && existing.groupName === '조 없음') {
                        existing.groupName = member.groupName;
                    }
                    if (member.role && existing.role === '성도') {
                        existing.role = member.role;
                    }
                    if (!existing.spouseName && familySort?.spouseName) {
                        existing.spouseName = familySort.spouseName;
                    }
                    if (!existing.familyName && familySort?.familyName) {
                        existing.familyName = familySort.familyName;
                    }

                    peopleById.set(member.personId, existing);
                });
            }

            const exportPeople = Array.from(peopleById.values())
                .sort((a, b) => {
                    const aGroupOrder = exportGroupOrder.get(a.groupName) ?? 9999;
                    const bGroupOrder = exportGroupOrder.get(b.groupName) ?? 9999;
                    if (aGroupOrder !== bGroupOrder) return aGroupOrder - bGroupOrder;

                    const groupDiff = a.groupName.localeCompare(b.groupName);
                    if (groupDiff !== 0) return groupDiff;

                    const familyDiff = getAttendanceItemFamilyKey({
                        id: a.name,
                        name: a.name,
                        department: '',
                        group: a.groupName,
                        role: a.role,
                        status: '',
                        updatedAt: null,
                        spouseName: a.spouseName,
                        familyName: a.familyName,
                    }).localeCompare(getAttendanceItemFamilyKey({
                        id: b.name,
                        name: b.name,
                        department: '',
                        group: b.groupName,
                        role: b.role,
                        status: '',
                        updatedAt: null,
                        spouseName: b.spouseName,
                        familyName: b.familyName,
                    }));
                    if (familyDiff !== 0) return familyDiff;

                    return a.name.localeCompare(b.name);
                });

            if (exportPeople.length === 0) {
                alert('해당 기간에 추출할 출석 대상 snapshot이 없습니다.');
                return;
            }

            const exportData = exportPeople.map(person => {
                const activeMeetingWeeks = (rangeWeeks as WeekRow[]).filter((week) =>
                    !noMeetingDateSet.has(week.week_date) && person.weeks.has(week.id)
                );
                const row: Record<string, string> = {
                    '조': person.groupName || '조 없음',
                    '이름': person.name,
                    '역할': person.role || '성도'
                };

                (rangeWeeks as WeekRow[]).forEach((w) => {
                    if (noMeetingDateSet.has(w.week_date)) {
                        row[w.week_date] = '모임없음';
                    } else if (!person.weeks.has(w.id)) {
                        row[w.week_date] = '-';
                    } else {
                        const snapshotMember = person.weeks.get(w.id);
                        row[w.week_date] = getExportAttendanceMark(snapshotMember?.attendanceStatus);
                    }
                });

                const presentCount = activeMeetingWeeks.filter((week) => {
                    const status = person.weeks.get(week.id)?.attendanceStatus;
                    return status === 'present' || status === 'late';
                }).length;
                row['출석률'] = activeMeetingWeeks.length > 0
                    ? `${Math.round((presentCount / activeMeetingWeeks.length) * 100)}%`
                    : '-';

                return row;
            });

            const worksheet = XLSX.utils.json_to_sheet(exportData);
            const workbook = XLSX.utils.book_new();
            XLSX.utils.book_append_sheet(workbook, worksheet, `출석현황`);

            const title = `GraceNote_${startYear}${startMonth}_${endYear}${endMonth}_출석.xlsx`;
            XLSX.writeFile(workbook, title);
            setIsExportModalOpen(false);
        } catch (err) {
            console.error('Export Error:', err);
        } finally {
            setIsExportLoading(false);
        }
    };

    const downloadExcel = () => {
        setIsExportModalOpen(true);
    };

    const selectedChurchName = churches.find((church) => church.id === selectedChurchId)?.name || '교회 선택 필요';
    const selectedDepartmentName = departments.find((department) => department.id === selectedDeptId)?.name || '부서 선택 필요';
    const insightPeriodLabel = statsPeriod === 'quarter'
        ? `${insightYear}년 ${insightQuarter}분기`
        : `${insightYear}년`;

    return (
        <div className="space-y-8 sm:space-y-10 max-w-7xl mx-auto">
            {/* Header Area */}
            <header className="space-y-8 px-2">
                <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
                    <div className="flex items-center gap-4">
                        <div className="space-y-1">
                            <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">
                                출석 현황
                            </h1>
                            <p className="text-xs font-bold text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em]">Attendance Status</p>
                        </div>
                    </div>

                    <div className="inline-flex rounded-2xl border border-indigo-100 bg-indigo-50/70 p-1 shadow-sm dark:border-indigo-500/20 dark:bg-indigo-500/10">
                        <button
                            type="button"
                            onClick={() => setAttendanceView('weekly')}
                            className={cn(
                                "rounded-xl px-5 py-2.5 text-xs font-black transition-all",
                                attendanceView === 'weekly'
                                    ? "bg-white text-indigo-700 shadow-sm dark:bg-slate-950 dark:text-indigo-200"
                                    : "text-slate-400 hover:text-slate-700 dark:hover:text-slate-200"
                            )}
                        >
                            주차별 출석
                        </button>
                        <button
                            type="button"
                            onClick={() => setAttendanceView('insights')}
                            className={cn(
                                "rounded-xl px-5 py-2.5 text-xs font-black transition-all",
                                attendanceView === 'insights'
                                    ? "bg-white text-indigo-700 shadow-sm dark:bg-slate-950 dark:text-indigo-200"
                                    : "text-slate-400 hover:text-slate-700 dark:hover:text-slate-200"
                            )}
                        >
                            인사이트 리포트
                        </button>
                    </div>
                </div>
            </header>

            {/* Horizontal Filter Bar - Compact & Glassy */}
            {attendanceView === 'weekly' && (
            <div className="sticky top-20 z-[40] bg-white/70 dark:bg-[#0d1221]/70 backdrop-blur-2xl border border-slate-200/60 dark:border-slate-800/60 p-3 sm:p-4 rounded-2xl shadow-lg flex flex-wrap items-center gap-4">
                <div className="flex flex-wrap items-center gap-3 flex-1">
                    {profile?.is_master && (
                        <div className="relative group min-w-[160px]">
                            <select
                                value={selectedChurchId}
                                onChange={(e) => setSelectedChurchId(e.target.value)}
                                className="w-full pl-10 pr-10 py-2.5 bg-slate-50 dark:bg-slate-800/50 border border-slate-100 dark:border-slate-700/50 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 outline-none focus:ring-2 focus:ring-indigo-500/20 transition-all appearance-none cursor-pointer"
                            >
                                {churches.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                            </select>
                            <ChurchIcon className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                            <ChevronDown className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                        </div>
                    )}

                    <div className="relative group min-w-[160px]">
                        <select
                            value={selectedDeptId}
                            onChange={(e) => setSelectedDeptId(e.target.value)}
                            className="w-full pl-10 pr-10 py-2.5 bg-slate-50 dark:bg-slate-800/50 border border-slate-100 dark:border-slate-700/50 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 outline-none focus:ring-2 focus:ring-indigo-500/20 transition-all appearance-none cursor-pointer"
                        >
                            {departments.map(d => <option key={d.id} value={d.id}>{d.name}</option>)}
                        </select>
                        <Layers className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                        <ChevronDown className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                    </div>

                    <div className="h-6 w-px bg-slate-200 dark:bg-slate-800 mx-1 hidden sm:block" />

                    <div className="flex items-center gap-2">
                        <div className="relative group w-32">
                            <select
                                value={selectedYear}
                                onChange={(e) => setSelectedYear(parseInt(e.target.value))}
                                className="w-full pl-10 pr-10 py-2.5 bg-slate-50 dark:bg-slate-800/50 border border-slate-100 dark:border-slate-700/50 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 outline-none focus:ring-2 focus:ring-indigo-500/20 transition-all appearance-none cursor-pointer"
                            >
                                {[2024, 2025, 2026].map(y => <option key={y} value={y}>{y}년</option>)}
                            </select>
                            <CalendarDays className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                            <ChevronDown className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                        </div>

                        <div className="relative group w-28">
                            <select
                                value={selectedMonth}
                                onChange={(e) => setSelectedMonth(parseInt(e.target.value))}
                                className="w-full pl-10 pr-10 py-2.5 bg-slate-50 dark:bg-slate-800/50 border border-slate-100 dark:border-slate-700/50 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 outline-none focus:ring-2 focus:ring-indigo-500/20 transition-all appearance-none cursor-pointer"
                            >
                                {Array.from({ length: 12 }, (_, i) => i + 1).map(m => <option key={m} value={m}>{m}월</option>)}
                            </select>
                            <Calendar className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                            <ChevronDown className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                        </div>
                    </div>
                </div>

                <div className="flex items-center gap-2">
                    {weeks.length > 0 ? (
                        <div className="relative group min-w-[140px]">
                            <select
                                value={selectedWeekId}
                                onChange={(e) => setSelectedWeekId(e.target.value)}
                                className="w-full pl-10 pr-10 py-2.5 bg-indigo-600 text-white border-none rounded-2xl font-black text-xs outline-none focus:ring-2 focus:ring-indigo-500/40 transition-all appearance-none cursor-pointer"
                            >
                                {weeks.map((w, idx) => (
                                    <option key={w.id} value={w.id}>{idx + 1}주차 ({w.week_date.substring(5)})</option>
                                ))}
                            </select>
                            <Filter className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-white/40 dark:text-slate-400" />
                            <ChevronDown className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-white/40 dark:text-slate-400" />
                        </div>
                    ) : (
                        <div className="px-4 py-2 bg-slate-100 dark:bg-slate-800/50 rounded-2xl text-[10px] font-black text-slate-400">
                            기간 내 주차 정보 없음
                        </div>
                    )}
                </div>
            </div>
            )}

            {/* Quick Summary Stats Row */}
            {attendanceView === 'weekly' && (
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 px-1">
                <div className="bg-white dark:bg-slate-800/40 p-6 rounded-2xl border border-slate-100 dark:border-slate-800/50 shadow-sm flex items-center justify-between group hover:border-indigo-500/30 transition-all">
                    <div>
                        <p className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest mb-1">선택 주차 대상</p>
                        <h4 className="text-3xl font-black text-slate-900 dark:text-white tracking-tighter">{selectedWeekMetrics?.totalPeople ?? 0}</h4>
                    </div>
                    <div className="w-12 h-12 rounded-2xl bg-slate-50 dark:bg-slate-700/50 flex items-center justify-center text-slate-400 group-hover:bg-indigo-500 group-hover:text-white transition-all">
                        <Users className="w-6 h-6" />
                    </div>
                </div>
                <div className="bg-white dark:bg-slate-800/40 p-6 rounded-2xl border border-slate-100 dark:border-slate-800/50 shadow-sm flex items-center justify-between group hover:border-emerald-500/30 transition-all">
                    <div>
                        <p className="text-[10px] font-black text-emerald-600 dark:text-emerald-400 uppercase tracking-widest mb-1">금주 출석</p>
                        <h4 className="text-3xl font-black text-emerald-600 dark:text-emerald-400 tracking-tighter">
                            {selectedWeekMetrics?.presentPeople ?? 0}
                        </h4>
                    </div>
                    <div className="w-12 h-12 rounded-2xl bg-emerald-50 dark:bg-emerald-500/10 flex items-center justify-center text-emerald-500 group-hover:bg-emerald-500 group-hover:text-white transition-all">
                        <CheckCircle2 className="w-6 h-6" />
                    </div>
                </div>
                <div className="bg-white dark:bg-slate-800/40 p-6 rounded-2xl border border-slate-100 dark:border-slate-800/50 shadow-sm flex items-center justify-between group hover:border-rose-500/30 transition-all">
                    <div>
                        <p className="text-[10px] font-black text-rose-600 dark:text-rose-400 uppercase tracking-widest mb-1">금주 결석</p>
                        <h4 className="text-3xl font-black text-rose-600 dark:text-rose-400 tracking-tighter">
                            {selectedWeekMetrics?.absentPeople ?? 0}
                        </h4>
                    </div>
                    <div className="w-12 h-12 rounded-2xl bg-rose-50 dark:bg-rose-500/10 flex items-center justify-center text-rose-500 group-hover:bg-rose-500 group-hover:text-white transition-all">
                        <XCircle className="w-6 h-6" />
                    </div>
                </div>
                <div className="bg-indigo-600 p-6 rounded-2xl shadow-xl shadow-indigo-500/20 flex items-center justify-between group hover:scale-[1.02] transition-all">
                    <div>
                        <p className="text-[10px] font-black text-indigo-100/60 uppercase tracking-widest mb-1">선택 주차 출석률</p>
                        <h4 className="text-3xl font-black text-white tracking-tighter">
                            {selectedWeekMetrics?.rate === null || selectedWeekMetrics?.rate === undefined ? '-' : `${selectedWeekMetrics.rate}%`}
                        </h4>
                    </div>
                    <div className="w-12 h-12 rounded-2xl bg-white/10 flex items-center justify-center text-white">
                        <TrendingUp className="w-6 h-6" />
                    </div>
                </div>
            </div>
            )}

            <div className="grid grid-cols-1 xl:grid-cols-12 gap-8 mt-4 px-1">
                {/* Main Content Column (Left/Center) */}
                <div className={cn("space-y-8", attendanceView === 'insights' ? "hidden" : "xl:col-span-8")}>
                    {loading ? (
                        <div className="h-64 flex flex-col items-center justify-center bg-white dark:bg-slate-800/40 rounded-2xl border border-slate-100 dark:border-slate-800/50">
                            <Loader2 className="w-8 h-8 text-indigo-600 animate-spin" />
                            <p className="text-xs font-bold text-slate-400 mt-4 uppercase tracking-widest">데이터 동기화 중...</p>
                        </div>
                    ) : (
                        <>
                            <div className="bg-white dark:bg-slate-800/40 p-8 rounded-3xl border border-slate-100 dark:border-slate-800/50 shadow-sm space-y-8 relative overflow-hidden">
                                <div className="flex items-center justify-between relative z-10">
                                    <div className="flex items-center gap-2">
                                        <TrendingUp className="w-5 h-5 text-indigo-500" />
                                        <h3 className="text-xl font-black text-slate-900 dark:text-white tracking-tight">주차별 출석 변화</h3>
                                    </div>
                                    <div className="flex items-center gap-3">
                                        <div className="flex items-center gap-1 bg-slate-50 dark:bg-slate-900/50 p-1 rounded-xl border border-slate-100 dark:border-slate-800/50">
                                            <button
                                                onClick={prevMonth}
                                                className="p-1 px-2 hover:bg-white dark:hover:bg-slate-800 rounded-lg transition-all text-slate-400 hover:text-indigo-600"
                                                title="이전 달"
                                            >
                                                <ChevronLeft className="w-4 h-4" />
                                            </button>
                                            <button
                                                onClick={nextMonth}
                                                disabled={selectedYear === new Date().getFullYear() && selectedMonth === new Date().getMonth() + 1}
                                                className="p-1 px-2 hover:bg-white dark:hover:bg-slate-800 rounded-lg transition-all text-slate-400 hover:text-indigo-600 disabled:opacity-20 disabled:hover:text-slate-400"
                                                title="다음 달"
                                            >
                                                <ChevronRight className="w-4 h-4" />
                                            </button>
                                        </div>
                                        <p className="text-[10px] font-bold text-slate-400 uppercase tracking-widest hidden sm:block">Trend</p>
                                    </div>
                                </div>

                                <div className="relative mt-4 flex h-56 items-center justify-center">
                                    {isTrendLoading ? (
                                        <div className="flex flex-col items-center gap-3">
                                            <Loader2 className="w-8 h-8 text-indigo-500 animate-spin opacity-50" />
                                            <p className="text-[10px] font-black text-slate-400 animate-pulse uppercase tracking-widest">분석 중...</p>
                                        </div>
                                    ) : weeklyTrendData.length === 0 ? (
                                        <div className="flex flex-col items-center gap-2 opacity-40">
                                            <CalendarDays className="w-10 h-10 text-slate-400" />
                                            <p className="text-sm font-bold text-slate-500">선택한 월의 출석 데이터가 없습니다.</p>
                                        </div>
                                    ) : (
                                        <>
                                            {/* Y-Axis Scale & Grids */}
                                            <div className="absolute inset-x-0 top-0 bottom-8 flex flex-col justify-between pointer-events-none pr-2">
                                                {[100, 75, 50, 25, 0].map((tick) => (
                                                    <div key={tick} className="w-full flex items-center gap-3 group/grid">
                                                        <span className="text-[9px] font-black text-slate-300 dark:text-slate-600 w-6 text-right transition-colors group-hover/grid:text-indigo-400">{tick}%</span>
                                                        <div className="flex-1 h-[1px] bg-slate-100 dark:bg-slate-800/50 relative">
                                                            <div className="absolute inset-0 bg-indigo-500/10 opacity-0 group-hover/grid:opacity-100 transition-opacity" />
                                                        </div>
                                                    </div>
                                                ))}
                                            </div>

                                            <div className="absolute inset-x-0 top-0 bottom-0 flex justify-between gap-4 pl-10 pr-4">
                                                {weeklyTrendData.map((data, idx) => (
                                                    <div
                                                        key={idx}
                                                        className={cn(
                                                            "group grid flex-1 cursor-pointer grid-rows-[1fr_2rem] items-stretch justify-items-center transition-all",
                                                            selectedWeekId === data.id
                                                                ? "scale-[1.03]"
                                                                : "opacity-70 hover:opacity-100 hover:scale-[1.02]"
                                                        )}
                                                        onClick={() => setSelectedWeekId(data.id)}
                                                    >
                                                        <div className="relative row-start-1 h-full w-full">
                                                            {/* Bar BG */}
                                                            <div className={cn(
                                                                "absolute inset-y-0 left-1/2 w-3 -translate-x-1/2 rounded-full transition-colors sm:w-5",
                                                                data.hasError
                                                                    ? "bg-rose-100 ring-2 ring-rose-200/70 dark:bg-rose-900/30 dark:ring-rose-500/25"
                                                                    : selectedWeekId === data.id
                                                                    ? "bg-indigo-100 ring-2 ring-indigo-200/70 dark:bg-indigo-900/30 dark:ring-indigo-500/25"
                                                                    : "bg-slate-100 dark:bg-slate-800/50"
                                                            )} />
                                                            {/* Bar Fill */}
                                                            <div
                                                                className={cn(
                                                                    "absolute bottom-0 left-1/2 z-10 w-3 -translate-x-1/2 rounded-full transition-all duration-1000 ease-out sm:w-5",
                                                                    data.hasError
                                                                        ? "bg-rose-400/60 dark:bg-rose-500/60"
                                                                        : selectedWeekId === data.id
                                                                        ? "bg-indigo-700 dark:bg-indigo-400 shadow-[0_0_14px_rgba(79,70,229,0.35)]"
                                                                        : "bg-indigo-500/70 dark:bg-indigo-500/70 group-hover:bg-indigo-600"
                                                                )}
                                                                style={{ height: `${(data.present / (data.total || 1)) * 100}%` }}
                                                            >
                                                                <div className="absolute top-1.5 inset-x-0 h-1 bg-white/20 rounded-full mx-1" />
                                                                {/* Number Label */}
                                                                <div className={cn(
                                                                    "absolute left-1/2 -translate-x-1/2 text-[10px] font-black",
                                                                    selectedWeekId === data.id
                                                                        ? "-top-6 text-indigo-700 dark:text-indigo-300"
                                                                        : "-top-6 text-indigo-500 dark:text-indigo-400"
                                                                )}>
                                                                    {data.hasError ? '!' : data.present}
                                                                </div>
                                                                {/* Tooltip */}
                                                                <div className="absolute -top-10 left-1/2 -translate-x-1/2 opacity-0 group-hover:opacity-100 transition-all bg-slate-900 dark:bg-slate-700 text-white text-[10px] font-black px-2.5 py-1.5 rounded-xl z-20 whitespace-nowrap shadow-xl pointer-events-none">
                                                                    {data.hasError ? '계산 실패' : `${data.present}명 / ${data.total}명`}
                                                                </div>
                                                            </div>
                                                        </div>
                                                        <span className={cn(
                                                            "relative row-start-2 self-end rounded-full px-2 py-1 text-[10px] font-black transition-colors",
                                                            selectedWeekId === data.id
                                                                ? "bg-indigo-600 text-white shadow-sm dark:bg-indigo-400 dark:text-indigo-950"
                                                                : "text-slate-400 group-hover:text-indigo-600"
                                                        )}>
                                                            {selectedWeekId === data.id && (
                                                                <span className="absolute -top-1 left-1/2 h-1.5 w-1.5 -translate-x-1/2 rounded-full bg-indigo-600 ring-2 ring-white dark:bg-indigo-300 dark:ring-slate-900" />
                                                            )}
                                                            {data.date}
                                                        </span>
                                                    </div>
                                                ))}
                                            </div>
                                        </>
                                    )}
                                </div>
                            </div>

                            {/* Overall Progress - Segmented Bars */}
                            <div className="bg-white dark:bg-slate-800/40 p-8 rounded-3xl border border-slate-100 dark:border-slate-800/50 shadow-sm space-y-8">
                                <div className="flex items-center justify-between gap-3">
                                    <div className="flex items-center gap-2">
                                        <BarChart3 className="w-5 h-5 text-indigo-500" />
                                        <h3 className="text-xl font-black text-slate-900 dark:text-white tracking-tight">전체 조별 출석 현황</h3>
                                    </div>
                                    <div className="flex items-center gap-2">
                                        {isDetailExpanded && groupStats.some((group) => group.total === 0) && (
                                            <button
                                                type="button"
                                                onClick={loadMissingGroupRosters}
                                                className="rounded-xl bg-emerald-50 px-4 py-2 text-[11px] font-black text-emerald-600 transition-all hover:scale-105 hover:bg-emerald-100 dark:bg-emerald-500/10 dark:text-emerald-300"
                                            >
                                                미제출 조명단 한 번에 불러오기
                                            </button>
                                        )}
                                        <button
                                            onClick={() => setIsDetailExpanded(!isDetailExpanded)}
                                            className="text-[11px] font-black text-indigo-600 dark:text-indigo-400 hover:scale-105 transition-all bg-indigo-50 dark:bg-indigo-500/10 px-4 py-2 rounded-xl"
                                        >
                                            {isDetailExpanded ? '요약 보기' : '상세 명단 보기'}
                                        </button>
                                    </div>
                                </div>

                                <div className="space-y-6">
                                    {groupStats.length === 0 ? (
                                        <div className="flex flex-col items-center justify-center py-12 gap-3 opacity-40">
                                            <AlertCircle className="w-8 h-8 text-slate-400" />
                                            <p className="text-sm font-bold text-slate-500">선택된 주차의 출석 데이터가 없습니다.</p>
                                        </div>
                                    ) : isDetailExpanded ? (
                                        <div className="space-y-10">
                                            {groupStats.map(gs => {
                                                const groupMembers = attendanceData.filter(a => a.group === gs.name);
                                                const adminMembers = groupMembers.filter((member) => member.included !== false);
                                                const isSubmittedConflictIgnored = ignoredSubmissionConflictKeys.has(getSubmissionConflictKey(gs.name));
                                                const conflictMembers = isSubmittedConflictIgnored
                                                    ? []
                                                    : groupMembers.filter((member) => member.hasSubmissionConflict);
                                                const submittedMembers = groupMembers.filter((member) => (
                                                    member.submittedStatus ||
                                                    member.hasSubmissionConflict
                                                ));
                                                const groupConflictLoading = snapshotEditLoadingId === `group-submission:${gs.name}`;
                                                return (
                                                    <div key={gs.name} className="space-y-4">
                                                        <div className="flex items-center justify-between border-l-4 border-indigo-500 pl-4 py-1">
                                                            <div className="flex items-center gap-2">
                                                                <h4 className="font-black text-slate-900 dark:text-white uppercase tracking-tight">{gs.name}</h4>
                                                                {conflictMembers.length > 0 && (
                                                                    <span className="rounded-full bg-amber-50 px-2 py-0.5 text-[9px] font-black text-amber-600 dark:bg-amber-500/10 dark:text-amber-300">
                                                                        조장 제출 확인 필요 {conflictMembers.length}
                                                                    </span>
                                                                )}
                                                            </div>
                                                            <div className="text-[10px] font-bold text-slate-400">
                                                                출석: <span className="text-indigo-600">{gs.present}</span> / 전체: {gs.total}
                                                            </div>
                                                        </div>
                                                        <div className="flex flex-wrap gap-2">
                                                            {adminMembers.map(m => (
                                                                <button
                                                                    type="button"
                                                                    key={m.snapshotMemberId || m.id}
                                                                    onClick={() => toggleSnapshotMemberAttendance(m)}
                                                                    className={cn(
                                                                        "group/member relative px-3 py-1.5 rounded-xl border flex items-center gap-1.5 transition-all text-[11px] font-bold hover:-translate-y-0.5 hover:shadow-sm",
                                                                        m.status === 'present' || m.status === 'late'
                                                                            ? "bg-emerald-50 dark:bg-emerald-500/10 border-emerald-100 dark:border-emerald-500/20 text-emerald-600 dark:text-emerald-400"
                                                                            : "bg-slate-50 dark:bg-slate-800/30 border-slate-100 dark:border-slate-700/50 text-slate-400",
                                                                        m.hasSubmissionConflict && "ring-1 ring-amber-200"
                                                                    )}
                                                                >
                                                                    {m.status === 'present' || m.status === 'late' ? (
                                                                        <CheckCircle2 className="w-3 h-3" />
                                                                    ) : (
                                                                        <XCircle className="w-3 h-3" />
                                                                    )}
                                                                    <span>{m.name}</span>
                                                                    {m.hasSubmissionConflict && (
                                                                        <span className="h-1.5 w-1.5 rounded-full bg-amber-400" title="조장 제출값과 다름" />
                                                                    )}
                                                                    {m.snapshotMemberId && m.included !== false && (
                                                                        <span
                                                                            role="button"
                                                                            tabIndex={0}
                                                                            onClick={(event) => {
                                                                                event.stopPropagation();
                                                                                excludeSnapshotMember(m.snapshotMemberId!, m.name);
                                                                            }}
                                                                            onKeyDown={(event) => {
                                                                                if (event.key === 'Enter' || event.key === ' ') {
                                                                                    event.preventDefault();
                                                                                    event.stopPropagation();
                                                                                    excludeSnapshotMember(m.snapshotMemberId!, m.name);
                                                                                }
                                                                            }}
                                                                            className="absolute -right-1.5 -top-1.5 hidden h-4 w-4 items-center justify-center rounded-full bg-rose-500 text-[10px] font-black text-white shadow-sm group-hover/member:flex"
                                                                            title="이 주차 출석 대상에서 제외"
                                                                        >
                                                                            ×
                                                                        </span>
                                                                    )}
                                                                    {snapshotEditLoadingId === m.snapshotMemberId && (
                                                                        <span className="absolute inset-0 rounded-xl bg-white/60 dark:bg-slate-900/60" />
                                                                    )}
                                                                </button>
                                                            ))}
                                                            <button
                                                                type="button"
                                                                onClick={() => {
                                                                    const group = attendanceGroups.find((item) => item.name === gs.name);
                                                                    openAddSnapshotMemberModal(group?.id || null);
                                                                }}
                                                                className="px-3 py-1.5 rounded-xl border border-dashed border-indigo-200 bg-indigo-50/40 text-[11px] font-black text-indigo-600 hover:bg-indigo-50 dark:border-indigo-500/30 dark:bg-indigo-500/10 dark:text-indigo-300"
                                                            >
                                                                + 성도 추가
                                                            </button>
                                                            {adminMembers.length === 0 && (() => {
                                                                const group = attendanceGroups.find((item) => item.name === gs.name);
                                                                if (!group) return null;
                                                                return (
                                                                    <button
                                                                        type="button"
                                                                        onClick={() => loadGroupRoster(group.id, group.name)}
                                                                        className="px-3 py-1.5 rounded-xl border border-dashed border-emerald-200 bg-emerald-50/40 text-[11px] font-black text-emerald-600 hover:bg-emerald-50 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-300"
                                                                    >
                                                                        조명단 불러오기
                                                                    </button>
                                                                );
                                                            })()}
                                                        </div>
                                                        {conflictMembers.length > 0 && (
                                                            <div className="rounded-3xl border border-amber-100 bg-amber-50/60 p-4 shadow-sm dark:border-amber-500/20 dark:bg-amber-500/10">
                                                                <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
                                                                    <div className="space-y-1">
                                                                        <div className="flex flex-wrap items-center gap-2">
                                                                            <p className="text-sm font-black text-slate-900 dark:text-white">
                                                                                조장 제출본과 관리자 화면이 다릅니다
                                                                            </p>
                                                                            <span className="rounded-full bg-white px-2 py-0.5 text-[9px] font-black text-amber-700 shadow-sm ring-1 ring-amber-100 dark:bg-slate-950/60 dark:text-amber-200 dark:ring-amber-500/20">
                                                                                확인 필요 {conflictMembers.length}명
                                                                            </span>
                                                                        </div>
                                                                        <p className="text-[11px] font-bold text-slate-500 dark:text-slate-400">
                                                                            위 명단은 현재 관리자 화면입니다. 아래 조장 제출본을 보고 이 조의 출석부를 어떻게 처리할지 선택하세요.
                                                                        </p>
                                                                    </div>
                                                                    <div className="flex flex-wrap items-center gap-2">
                                                                        <button
                                                                            type="button"
                                                                            onClick={() => applySubmittedStatusesForGroup(gs.name, submittedMembers)}
                                                                            disabled={groupConflictLoading}
                                                                            className="rounded-2xl bg-slate-900 px-4 py-2 text-[11px] font-black text-white shadow-sm transition-all hover:-translate-y-0.5 hover:bg-slate-800 disabled:cursor-wait disabled:opacity-60 dark:bg-white dark:text-slate-950 dark:hover:bg-slate-100"
                                                                        >
                                                                            {groupConflictLoading ? '처리 중...' : '덮어쓰기'}
                                                                        </button>
                                                                        <button
                                                                            type="button"
                                                                            onClick={() => mergeSubmittedStatusesForGroup(gs.name, submittedMembers)}
                                                                            disabled={groupConflictLoading}
                                                                            className="rounded-2xl bg-white px-4 py-2 text-[11px] font-black text-indigo-600 shadow-sm ring-1 ring-indigo-100 transition-all hover:-translate-y-0.5 hover:bg-indigo-50 disabled:cursor-wait disabled:opacity-60 dark:bg-slate-950/70 dark:text-indigo-300 dark:ring-indigo-500/20"
                                                                        >
                                                                            병합하기
                                                                        </button>
                                                                        <button
                                                                            type="button"
                                                                            onClick={() => keepAdminAttendanceForGroup(gs.name)}
                                                                            className="rounded-2xl bg-white/80 px-4 py-2 text-[11px] font-black text-slate-500 shadow-sm ring-1 ring-slate-100 transition-all hover:-translate-y-0.5 hover:bg-white dark:bg-slate-950/50 dark:text-slate-300 dark:ring-slate-800"
                                                                        >
                                                                            관리자 화면 유지
                                                                        </button>
                                                                    </div>
                                                                </div>

                                                                <div className="rounded-2xl border border-white bg-white/90 p-4 dark:border-slate-800 dark:bg-slate-950/50">
                                                                    <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                                                                        <div>
                                                                            <p className="text-[11px] font-black text-slate-700 dark:text-slate-200">조장 제출본</p>
                                                                            <p className="mt-0.5 text-[10px] font-bold text-slate-400">
                                                                                앱에서 조장이 제출한 이 조의 출석부 전체입니다.
                                                                            </p>
                                                                        </div>
                                                                        <span className="rounded-full bg-slate-100 px-2.5 py-1 text-[10px] font-black text-slate-500 dark:bg-slate-800 dark:text-slate-300">
                                                                            {submittedMembers.length}명
                                                                        </span>
                                                                    </div>
                                                                    <div className="flex flex-wrap gap-1.5">
                                                                        {submittedMembers.map((member) => {
                                                                            const isSubmittedPresent = member.submittedStatus === 'present' || member.submittedStatus === 'late';
                                                                            return (
                                                                                <span
                                                                                    key={`submitted-${member.snapshotMemberId || member.id}`}
                                                                                    className={cn(
                                                                                        "inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-black",
                                                                                        isSubmittedPresent
                                                                                            ? "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-100 dark:bg-emerald-500/10 dark:text-emerald-300 dark:ring-emerald-500/20"
                                                                                            : "bg-slate-100 text-slate-500 ring-1 ring-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:ring-slate-700",
                                                                                        member.included === false && "ring-amber-300 dark:ring-amber-500/40"
                                                                                    )}
                                                                                >
                                                                                    {isSubmittedPresent ? (
                                                                                        <CheckCircle2 className="h-3 w-3" />
                                                                                    ) : (
                                                                                        <XCircle className="h-3 w-3" />
                                                                                    )}
                                                                                    {member.name}
                                                                                    <span className="text-[9px] opacity-60">
                                                                                        {getCompactAttendanceLabel(member.submittedStatus)}
                                                                                    </span>
                                                                                </span>
                                                                            );
                                                                        })}
                                                                    </div>
                                                                </div>

                                                                <div className="mt-3 grid gap-2 text-[10px] font-bold text-slate-500 dark:text-slate-400 md:grid-cols-3">
                                                                    <p><span className="font-black text-slate-700 dark:text-slate-200">덮어쓰기</span> 조장 제출본을 이 조의 관리자 확정값으로 적용</p>
                                                                    <p><span className="font-black text-slate-700 dark:text-slate-200">병합하기</span> 관리자 화면은 유지하고 조장이 제출한 추가 인원만 반영</p>
                                                                    <p><span className="font-black text-slate-700 dark:text-slate-200">관리자 화면 유지</span> 조장 제출본을 리포트에 반영하지 않음</p>
                                                                </div>
                                                            </div>
                                                        )}
                                                    </div>
                                                );
                                            })}
                                        </div>
                                    ) : (
                                        groupStats.map(gs => (
                                            <div key={gs.name} className="group/bar relative">
                                                <div className="flex items-end justify-between mb-3">
                                                    <span className="text-xs font-black text-slate-700 dark:text-slate-300 group-hover/bar:text-indigo-500 transition-colors uppercase tracking-widest flex items-center gap-2">
                                                        {gs.name}
                                                        {(gs.present / gs.total) >= 0.9 && <Trophy className="w-3.5 h-3.5 text-amber-500" />}
                                                    </span>
                                                    <span className="text-[10px] font-black text-slate-400 tracking-tight">
                                                        <span className="text-slate-900 dark:text-white text-sm mr-1">{gs.present}</span>/ {gs.total} 명 ({Math.round((gs.present / gs.total) * 100)}%)
                                                    </span>
                                                </div>
                                                <div className="flex gap-1 h-3">
                                                    {Array.from({ length: gs.total }).map((_, i) => (
                                                        <div
                                                            key={i}
                                                            className={cn(
                                                                "flex-1 rounded-sm transition-all duration-500",
                                                                i < gs.present
                                                                    ? ((gs.present / gs.total) > 0.8 ? "bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.3)]" :
                                                                        (gs.present / gs.total) > 0.5 ? "bg-indigo-500 shadow-[0_0_8px_rgba(99,102,241,0.3)]" :
                                                                            "bg-rose-500 shadow-[0_0_8px_rgba(244,63,94,0.3)]")
                                                                    : "bg-slate-100 dark:bg-slate-800/50"
                                                            )}
                                                        />
                                                    ))}
                                                </div>
                                            </div>
                                        ))
                                    )}
                                </div>
                            </div>
                        </>
                    )}
                </div>

	                {attendanceView === 'weekly' && (
	                    <aside className="xl:col-span-4 space-y-4">
	                        <div className="sticky top-40 space-y-4">
	                            <div className="rounded-3xl border border-indigo-100 bg-indigo-50/70 p-5 shadow-sm dark:border-indigo-500/20 dark:bg-indigo-500/10">
	                                <div className="mb-4 flex items-center justify-between">
	                                    <div>
	                                        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-indigo-500/70">리포트</p>
                                        <h3 className="mt-1 text-lg font-black text-slate-900 dark:text-white">리포트 추출</h3>
                                    </div>
                                    <Download className="h-5 w-5 text-indigo-500" />
                                </div>
                                <p className="mb-4 text-[11px] font-bold leading-5 text-slate-500 dark:text-slate-400">
                                    선택한 기간의 snapshot 기준 출석부를 엑셀로 생성합니다.
                                </p>
                                <button
                                    type="button"
                                    onClick={downloadExcel}
                                    className="w-full rounded-2xl bg-indigo-600 px-4 py-3 text-xs font-black text-white shadow-sm transition-all hover:bg-indigo-700 dark:bg-indigo-400 dark:text-indigo-950 dark:hover:bg-indigo-300"
                                >
	                                    기간 선택 후 다운로드
	                                </button>
	                            </div>

	                            <div className="rounded-3xl border border-slate-100 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900/60">
	                                <div className="mb-4 flex items-center gap-3">
	                                    <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-indigo-50 text-indigo-600 dark:bg-indigo-500/10 dark:text-indigo-300">
	                                        <AlertCircle className="h-5 w-5" />
	                                    </div>
	                                    <div>
	                                        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-slate-400">인원 변동</p>
	                                        <h3 className="mt-1 text-lg font-black text-slate-900 dark:text-white">지난 주와 달라진 출석 대상</h3>
	                                    </div>
	                                </div>

	                                {targetExplanation.length > 0 ? (
	                                    <div className="space-y-2">
	                                        {targetExplanation.map((item) => (
	                                            <div
	                                                key={item}
	                                                className="rounded-2xl bg-indigo-50 px-4 py-3 text-[11px] font-black leading-5 text-indigo-700 ring-1 ring-indigo-100 dark:bg-indigo-500/10 dark:text-indigo-200 dark:ring-indigo-500/20"
	                                            >
	                                                {item}
	                                            </div>
	                                        ))}
	                                    </div>
	                                ) : (
	                                    <div className="rounded-2xl bg-slate-50 px-4 py-4 text-[11px] font-bold leading-5 text-slate-500 dark:bg-slate-950/40 dark:text-slate-400">
	                                        이번 주 출석 대상은 지난 주와 동일합니다.
	                                    </div>
	                                )}
	                            </div>

	                            <div className="rounded-3xl border border-slate-100 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900/60">
	                                <div className="mb-4 flex items-center justify-between">
	                                    <div>
	                                        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-slate-400">모임 여부</p>
	                                        <h3 className="mt-1 text-lg font-black text-slate-900 dark:text-white">모임없는 날</h3>
	                                    </div>
	                                    <div className={cn(
	                                        "flex h-10 w-10 items-center justify-center rounded-2xl",
	                                        selectedWeekNoMeetingReason !== null
	                                            ? "bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-300"
	                                            : !selectedWeekHasSubmittedAttendance
	                                            ? "bg-amber-50 text-amber-600 dark:bg-amber-500/10 dark:text-amber-300"
	                                            : "bg-emerald-50 text-emerald-600 dark:bg-emerald-500/10 dark:text-emerald-300"
	                                    )}>
	                                        <CalendarDays className="h-5 w-5" />
	                                    </div>
	                                </div>

	                                <div className="rounded-2xl bg-slate-50 p-4 dark:bg-slate-950/40">
	                                    <p className="text-xs font-black text-slate-900 dark:text-white">
	                                        {selectedWeekNoMeetingReason !== null
	                                            ? '모임없는 날로 지정됨'
	                                            : selectedWeekHasSubmittedAttendance
	                                            ? '출석 기록이 있는 주차'
	                                            : '아직 출석 제출 없음'}
	                                    </p>
	                                    <p className="mt-1 text-[11px] font-bold leading-5 text-slate-500 dark:text-slate-400">
	                                        {selectedWeekNoMeetingReason !== null
	                                            ? `사유: ${selectedWeekNoMeetingReason || '모임 없음'}`
	                                            : selectedWeekHasSubmittedAttendance
	                                            ? '이미 출석 기록이 있어 모임없는 날로 바꿀 수 없습니다.'
	                                            : '실제 모임이 없었던 주차만 모임없는 날로 지정하세요.'}
	                                    </p>
	                                </div>

	                                <div className="mt-4">
	                                    {selectedWeekNoMeetingReason !== null ? (
	                                        <button
	                                            type="button"
	                                            onClick={cancelSelectedWeekNoMeetingDay}
	                                            disabled={isNoMeetingMutationLoading}
	                                            className="w-full rounded-2xl bg-white px-4 py-3 text-xs font-black text-slate-700 shadow-sm ring-1 ring-slate-200 transition-all hover:bg-slate-50 disabled:cursor-wait disabled:opacity-60 dark:bg-slate-950/50 dark:text-slate-200 dark:ring-slate-800 dark:hover:bg-slate-900"
	                                        >
	                                            {isNoMeetingMutationLoading ? '처리 중...' : '모임없는 날 지정 취소'}
	                                        </button>
	                                    ) : (
	                                        <button
	                                            type="button"
	                                            onClick={markSelectedWeekAsNoMeetingDay}
	                                            disabled={isNoMeetingMutationLoading || selectedWeekHasSubmittedAttendance}
	                                            className="w-full rounded-2xl bg-amber-500 px-4 py-3 text-xs font-black text-white shadow-sm transition-all hover:bg-amber-600 disabled:cursor-not-allowed disabled:bg-slate-200 disabled:text-slate-400 disabled:shadow-none dark:bg-amber-400 dark:text-amber-950 dark:hover:bg-amber-300 dark:disabled:bg-slate-800 dark:disabled:text-slate-500"
	                                        >
	                                            {isNoMeetingMutationLoading
	                                                ? '처리 중...'
	                                                : selectedWeekHasSubmittedAttendance
	                                                ? '출석 기록이 있어 지정 불가'
	                                                : '모임없는 날로 지정'}
	                                        </button>
	                                    )}
	                                </div>
	                            </div>
	                        </div>
	                    </aside>
	                )}

                {/* Sidebar Column (Right) */}
                <div className={cn("space-y-6", attendanceView === 'weekly' ? "hidden" : "xl:col-span-12")}>
                    <div className="relative overflow-hidden rounded-[2rem] border border-slate-100 bg-white p-8 shadow-sm dark:border-slate-800 dark:bg-slate-900/60">
                        <div className="absolute top-0 right-0 w-48 h-48 bg-indigo-500/5 rounded-full -mr-24 -mt-24 blur-3xl" />

                        <div className="relative mb-8 flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
                            <div>
                                <p className="text-[10px] font-black text-indigo-500 uppercase tracking-[0.2em]">Attendance Insights</p>
                                <h3 className="mt-1 text-2xl font-black tracking-tight text-slate-900 dark:text-white">인사이트 리포트</h3>
                                <p className="mt-2 max-w-2xl text-xs font-bold leading-5 text-slate-500 dark:text-slate-400">
                                    선택 기간 중 출석 대상이었던 실제 성도 기준으로 우수 출석, 조별 흐름, 돌봄 필요 대상을 요약합니다.
                                </p>
                                <div className="mt-4 flex flex-wrap items-center gap-2">
                                    <span className="inline-flex items-center gap-1.5 rounded-2xl bg-slate-50 px-3 py-2 text-[11px] font-black text-slate-600 ring-1 ring-slate-100 dark:bg-slate-950/40 dark:text-slate-300 dark:ring-slate-800">
                                        <ChurchIcon className="h-3.5 w-3.5 text-indigo-500" />
                                        {selectedChurchName}
                                    </span>
                                    <span className="inline-flex items-center gap-1.5 rounded-2xl bg-slate-50 px-3 py-2 text-[11px] font-black text-slate-600 ring-1 ring-slate-100 dark:bg-slate-950/40 dark:text-slate-300 dark:ring-slate-800">
                                        <Layers className="h-3.5 w-3.5 text-indigo-500" />
                                        {selectedDepartmentName}
                                    </span>
                                    <span className="inline-flex items-center gap-1.5 rounded-2xl bg-indigo-50 px-3 py-2 text-[11px] font-black text-indigo-700 ring-1 ring-indigo-100 dark:bg-indigo-500/10 dark:text-indigo-200 dark:ring-indigo-500/20">
                                        <CalendarDays className="h-3.5 w-3.5" />
                                        {insightPeriodLabel}
                                    </span>
                                </div>
                            </div>

                            <div className="flex shrink-0 flex-wrap items-center gap-2 lg:justify-end">
                                <div className="flex items-center gap-1 rounded-2xl border border-indigo-100 bg-indigo-50/70 p-1 shadow-sm dark:border-indigo-500/20 dark:bg-indigo-500/10">
                                    <button
                                        onClick={() => setStatsPeriod('quarter')}
                                        className={cn(
                                            "rounded-xl px-4 py-2 text-[10px] font-black transition-all",
                                            statsPeriod === 'quarter'
                                                ? "bg-white text-indigo-700 shadow-sm dark:bg-slate-950 dark:text-indigo-200"
                                                : "text-slate-400 hover:text-indigo-600 dark:hover:text-indigo-200"
                                        )}
                                    >
                                        분기
                                    </button>
                                    <button
                                        onClick={() => setStatsPeriod('year')}
                                        className={cn(
                                            "rounded-xl px-4 py-2 text-[10px] font-black transition-all",
                                            statsPeriod === 'year'
                                                ? "bg-white text-indigo-700 shadow-sm dark:bg-slate-950 dark:text-indigo-200"
                                                : "text-slate-400 hover:text-indigo-600 dark:hover:text-indigo-200"
                                        )}
                                    >
                                        년도
                                    </button>
                                </div>

                                <select
                                    value={insightYear}
                                    onChange={(e) => setInsightYear(parseInt(e.target.value))}
                                    className="rounded-2xl border border-slate-100 bg-slate-50 px-4 py-2.5 text-xs font-black text-slate-600 outline-none transition-all focus:ring-2 focus:ring-indigo-500/20 dark:border-slate-800 dark:bg-slate-800/50 dark:text-slate-300"
                                >
                                    {[2024, 2025, 2026].map(y => <option key={y} value={y}>{y}년</option>)}
                                </select>

                                {statsPeriod === 'quarter' && (
                                    <select
                                        value={insightQuarter}
                                        onChange={(e) => setInsightQuarter(parseInt(e.target.value))}
                                        className="rounded-2xl border border-slate-100 bg-slate-50 px-4 py-2.5 text-xs font-black text-slate-600 outline-none transition-all focus:ring-2 focus:ring-indigo-500/20 dark:border-slate-800 dark:bg-slate-800/50 dark:text-slate-300"
                                    >
                                        {[1, 2, 3, 4].map(q => <option key={q} value={q}>{q}분기</option>)}
                                    </select>
                                )}
                            </div>
                        </div>

                        <div className="relative mb-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
                            <div className="rounded-3xl border border-slate-100 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-950/30">
                                <div className="flex items-center justify-between">
                                    <p className="text-[10px] font-black uppercase tracking-[0.2em] text-slate-400">출석 우수</p>
                                    <Trophy className="h-4 w-4 text-amber-500" />
                                </div>
                                <p className="mt-3 text-3xl font-black text-slate-900 dark:text-white">{hallOfFame.length}</p>
                                <p className="mt-1 text-[11px] font-bold text-slate-500 dark:text-slate-400">{hallOfFameValue}% 이상 출석한 성도</p>
                            </div>
                            <div className="rounded-3xl border border-slate-100 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-950/30">
                                <div className="flex items-center justify-between">
                                    <p className="text-[10px] font-black uppercase tracking-[0.2em] text-slate-400">상위 조</p>
                                    <BarChart3 className="h-4 w-4 text-indigo-500" />
                                </div>
                                <p className="mt-3 truncate text-2xl font-black text-slate-900 dark:text-white">{groupRankings[0]?.name || '-'}</p>
                                <p className="mt-1 text-[11px] font-bold text-slate-500 dark:text-slate-400">
                                    {groupRankings[0] ? `${Math.round(groupRankings[0].rate)}% 평균 출석률` : '집계 데이터 없음'}
                                </p>
                            </div>
                            <div className="rounded-3xl border border-slate-100 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-950/30">
                                <div className="flex items-center justify-between">
                                    <p className="text-[10px] font-black uppercase tracking-[0.2em] text-slate-400">돌봄 필요</p>
                                    <HeartPulse className="h-4 w-4 text-rose-500" />
                                </div>
                                <p className="mt-3 text-3xl font-black text-slate-900 dark:text-white">{careList.length}</p>
                                <p className="mt-1 text-[11px] font-bold text-slate-500 dark:text-slate-400">최근 3회 연속 미출석 성도</p>
                            </div>
                            <div className="rounded-3xl border border-slate-100 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-950/30">
                                <div className="flex items-center justify-between">
                                    <p className="text-[10px] font-black uppercase tracking-[0.2em] text-slate-400">제출 점검</p>
                                    <AlertCircle className="h-4 w-4 text-orange-500" />
                                </div>
                                <p className="mt-3 text-3xl font-black text-slate-900 dark:text-white">{submissionRiskGroups.length}</p>
                                <p className="mt-1 text-[11px] font-bold text-slate-500 dark:text-slate-400">반복 미제출 조</p>
                            </div>
                        </div>

                        <div className={cn(
                            "relative gap-6",
                            attendanceView === 'insights' ? "grid grid-cols-1 xl:grid-cols-2" : "space-y-8"
                        )}>
                            {/* Hall of Fame - Compact */}
                            <div className="space-y-5 rounded-[2rem] border border-slate-100 bg-slate-50/60 p-5 dark:border-slate-800 dark:bg-slate-950/30">
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-2">
                                        <div className="w-9 h-9 rounded-2xl bg-amber-500/10 flex items-center justify-center">
                                            <Trophy className="w-3.5 h-3.5 text-amber-500" />
                                        </div>
                                        <div>
                                            <span className="text-sm font-black text-slate-900 dark:text-white">출석 우수자</span>
                                            <p className="text-[10px] font-bold text-slate-400">{hallOfFameValue}% 이상, 총 {hallOfFame.length}명</p>
                                        </div>
                                    </div>
                                    <div className="flex items-center gap-1.5 bg-slate-100 dark:bg-slate-800/50 p-1 rounded-xl">
                                        <button
                                            onClick={() => setHallOfFameValue(v => Math.max(0, v - 5))}
                                            className="w-6 h-6 flex items-center justify-center bg-white dark:bg-slate-700 rounded-lg text-slate-400 hover:text-indigo-600 transition-colors shadow-sm"
                                        >
                                            -
                                        </button>
                                        <span className="text-[10px] font-black text-slate-900 dark:text-white min-w-[32px] text-center">
                                            {hallOfFameTarget === 'rate' ? `${hallOfFameValue}%` : `${hallOfFameValue}회`}
                                        </span>
                                        <button
                                            onClick={() => setHallOfFameValue(v => Math.min(100, v + 5))}
                                            className="w-6 h-6 flex items-center justify-center bg-white dark:bg-slate-700 rounded-lg text-slate-400 hover:text-indigo-600 transition-colors shadow-sm"
                                        >
                                            +
                                        </button>
                                    </div>
                                </div>
                                <div className="max-h-[460px] space-y-3 overflow-y-auto pr-1">
                                    {hallOfFame.length > 0 ? (
                                        hallOfFame.map((member, idx) => (
                                            <div key={member.id} className="flex items-center justify-between rounded-3xl bg-white p-4 shadow-sm ring-1 ring-slate-100 transition-all hover:-translate-y-0.5 hover:ring-amber-200 dark:bg-slate-900/70 dark:ring-slate-800">
                                                <div className="flex items-center gap-4">
                                                    <div className="w-9 h-9 rounded-2xl bg-amber-500/10 flex items-center justify-center text-xs font-black text-amber-500">
                                                        {idx + 1}
                                                    </div>
                                                    <div>
                                                        <p className="text-xs font-black text-slate-900 dark:text-white">{member.full_name}</p>
                                                        <p className="text-[10px] font-bold text-slate-400">{member.group_name}</p>
                                                    </div>
                                                </div>
                                                <div className="text-right">
                                                    <p className="text-xs font-black text-amber-500">{Math.round(member.rate)}%</p>
                                                    <p className="text-[9px] font-bold text-slate-400">{member.presentCount}/{member.totalWeeks}주 출석</p>
                                                </div>
                                            </div>
                                        ))
                                    ) : (
                                        <div className="py-8 text-center bg-slate-50 dark:bg-slate-800/20 rounded-2xl border border-dashed border-slate-200 dark:border-slate-800">
                                            <p className="text-[10px] font-bold text-slate-400 uppercase tracking-tight">기준({hallOfFameTarget === 'rate' ? hallOfFameValue + '%' : hallOfFameValue + '회'}) 이상인 성도가 없습니다.</p>
                                        </div>
                                    )}
                                </div>
                            </div>

                            <div className={cn("h-px bg-slate-100 dark:bg-slate-800", attendanceView === 'insights' && "hidden")} />

                            {/* Group Rankings - [NEW] */}
                            <div className="space-y-5 rounded-[2rem] border border-slate-100 bg-slate-50/60 p-5 dark:border-slate-800 dark:bg-slate-950/30">
                                <div className="flex items-center gap-2">
                                    <div className="w-9 h-9 rounded-2xl bg-indigo-500/10 flex items-center justify-center">
                                        <BarChart3 className="w-3.5 h-3.5 text-indigo-500" />
                                    </div>
                                    <div>
                                        <span className="text-sm font-black text-slate-900 dark:text-white">조별 출석 순위</span>
                                        <p className="text-[10px] font-bold text-slate-400">선택 기간 평균 출석률 상위 3개 조</p>
                                    </div>
                                </div>
                                <div className="space-y-3">
                                    {groupRankings.length > 0 ? (
                                        groupRankings.slice(0, 3).map((group, idx) => (
                                            <div key={group.name} className="relative overflow-hidden rounded-3xl bg-white p-4 shadow-sm ring-1 ring-slate-100 dark:bg-slate-900/70 dark:ring-slate-800">
                                                <div className="relative z-10 space-y-3">
                                                    <div className="flex items-center gap-4">
                                                        <div className={cn(
                                                            "w-9 h-9 rounded-2xl flex items-center justify-center text-xs font-black shadow-sm",
                                                            idx === 0 ? "bg-amber-400 text-white" :
                                                                idx === 1 ? "bg-slate-300 text-slate-700" :
                                                                    "bg-orange-300 text-orange-800"
                                                        )}>
                                                            {idx + 1}
                                                        </div>
                                                        <div>
                                                            <p className="text-xs font-black text-slate-900 dark:text-white uppercase tracking-tight">{group.name}</p>
                                                            <p className="text-[10px] font-bold text-indigo-500/60">
                                                                평균 {group.averagePresent.toFixed(1)}/{group.averageTarget.toFixed(1)}명 출석
                                                            </p>
                                                        </div>
                                                    </div>
                                                    <div className="flex items-center justify-between text-[9px] font-black text-slate-400">
                                                        <span>
                                                            {group.weekCount}개 모임 주차 기준
                                                            {group.dataWeekCount < group.weekCount ? ` · ${group.dataWeekCount}주 데이터` : ''}
                                                        </span>
                                                        <span>기간 누적 {group.presentSum}/{group.totalAttCount}</span>
                                                    </div>
                                                    <div className="h-2 overflow-hidden rounded-full bg-slate-100 dark:bg-slate-800">
                                                        <div
                                                            className="h-full rounded-full bg-indigo-500"
                                                            style={{ width: `${Math.min(100, Math.max(0, group.rate))}%` }}
                                                        />
                                                    </div>
                                                </div>
                                            </div>
                                        ))
                                    ) : (
                                        <div className="py-8 text-center bg-slate-50 dark:bg-slate-800/20 rounded-2xl border border-dashed border-slate-200 dark:border-slate-800">
                                            <p className="text-[10px] font-bold text-slate-400 uppercase tracking-tight">출석 데이터가 없습니다.</p>
                                        </div>
                                    )}
                                </div>
                            </div>

                            <div className={cn("h-px bg-slate-100 dark:bg-slate-800", attendanceView === 'insights' && "hidden")} />

                            {/* Submission Risk Groups */}
                            <div className="space-y-5 rounded-[2rem] border border-slate-100 bg-slate-50/60 p-5 dark:border-slate-800 dark:bg-slate-950/30">
                                <div className="flex items-center gap-2">
                                    <div className="w-9 h-9 rounded-2xl bg-orange-500/10 flex items-center justify-center">
                                        <AlertCircle className="w-3.5 h-3.5 text-orange-500" />
                                    </div>
                                    <div>
                                        <span className="text-sm font-black text-slate-900 dark:text-white">출석 제출 점검 조</span>
                                        <p className="text-[10px] font-bold text-slate-400">출석 대상이 있었지만 제출이 반복 누락된 조</p>
                                    </div>
                                </div>
                                <div className="max-h-[460px] space-y-3 overflow-y-auto pr-1">
                                    {submissionRiskGroups.length > 0 ? (
                                        submissionRiskGroups.map((group) => (
                                            <div key={group.id} className="rounded-3xl bg-white p-4 shadow-sm ring-1 ring-orange-100 dark:bg-slate-900/70 dark:ring-orange-500/20">
                                                <div className="flex items-start justify-between gap-4">
                                                    <div>
                                                        <p className="text-xs font-black text-slate-900 dark:text-white">{group.name}</p>
                                                        <p className="mt-1 text-[10px] font-bold text-orange-500/70">
                                                            {group.missedWeeks}/{group.expectedWeeks}주 미제출 · 평균 대상 {group.averageTarget.toFixed(1)}명
                                                        </p>
                                                    </div>
                                                    <span className="rounded-2xl bg-orange-50 px-3 py-1 text-[10px] font-black text-orange-600 ring-1 ring-orange-100 dark:bg-orange-500/10 dark:text-orange-200 dark:ring-orange-500/20">
                                                        {Math.round(group.riskRate)}%
                                                    </span>
                                                </div>
                                                <div className="mt-3 flex flex-wrap gap-1.5">
                                                    {group.missedWeekLabels.slice(0, 8).map((label) => (
                                                        <span
                                                            key={`${group.id}-${label}`}
                                                            className="rounded-xl bg-slate-50 px-2.5 py-1 text-[9px] font-black text-slate-500 ring-1 ring-slate-100 dark:bg-slate-950/40 dark:text-slate-300 dark:ring-slate-800"
                                                        >
                                                            {label}
                                                        </span>
                                                    ))}
                                                    {group.missedWeekLabels.length > 8 && (
                                                        <span className="rounded-xl bg-slate-100 px-2.5 py-1 text-[9px] font-black text-slate-500 dark:bg-slate-800 dark:text-slate-300">
                                                            외 {group.missedWeekLabels.length - 8}주
                                                        </span>
                                                    )}
                                                </div>
                                            </div>
                                        ))
                                    ) : (
                                        <div className="py-8 text-center bg-orange-50/30 dark:bg-orange-900/10 rounded-2xl border border-dashed border-orange-200/50 dark:border-orange-900/30">
                                            <p className="text-[10px] font-bold text-orange-400 uppercase tracking-tight">반복적으로 제출이 누락된 조가 없습니다.</p>
                                        </div>
                                    )}
                                </div>
                            </div>

                            <div className={cn("h-px bg-slate-100 dark:bg-slate-800", attendanceView === 'insights' && "hidden")} />

                            {/* Care List - Compact */}
                            <div className="space-y-5 rounded-[2rem] border border-slate-100 bg-slate-50/60 p-5 dark:border-slate-800 dark:bg-slate-950/30">
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-2">
                                        <div className="w-9 h-9 rounded-2xl bg-rose-500/10 flex items-center justify-center">
                                            <HeartPulse className="w-3.5 h-3.5 text-rose-500" />
                                        </div>
                                        <div>
                                            <span className="text-sm font-black text-slate-900 dark:text-white">집중 보살핌</span>
                                            <p className="text-[10px] font-bold text-slate-400">최근 3회 연속 미출석, 총 {careList.length}명</p>
                                        </div>
                                    </div>
                                </div>
                                <div className="max-h-[460px] space-y-3 overflow-y-auto pr-1">
                                    {careList.length > 0 ? (
                                        careList.map(member => (
                                            <div
                                                key={member.id}
                                                className={cn(
                                                    "flex items-center justify-between rounded-3xl bg-white p-4 shadow-sm ring-1 ring-rose-100 transition-all group dark:bg-slate-900/70 dark:ring-rose-500/20",
                                                    member.directoryMemberId
                                                        ? "cursor-pointer hover:-translate-y-0.5 hover:bg-rose-50 dark:hover:bg-rose-500/10"
                                                        : "cursor-default opacity-70"
                                                )}
                                                onClick={() => {
                                                    if (member.directoryMemberId) {
                                                        router.push(`/members/${member.directoryMemberId}`);
                                                    }
                                                }}
                                            >
                                                <div className="flex items-center gap-4">
                                                    <div className="w-9 h-9 rounded-xl bg-rose-500/10 flex items-center justify-center">
                                                        <AlertCircle className="w-4 h-4 text-rose-500" />
                                                    </div>
                                                    <div>
                                                        <p className="text-xs font-black text-slate-900 dark:text-white group-hover:text-rose-500 transition-colors">{member.full_name}</p>
                                                        <p className="text-[10px] font-bold text-rose-500/60 uppercase tracking-tighter">
                                                            {member.consecutiveAbsences ? '최근 3회 연속 미출석' : `${Math.round(member.rate)}% 출석률`}
                                                        </p>
                                                    </div>
                                                </div>
                                                <ChevronRight className="w-4 h-4 text-slate-300 group-hover:text-rose-500 transition-all" />
                                            </div>
                                        ))
                                    ) : (
                                        <div className="py-8 text-center bg-rose-50/30 dark:bg-rose-900/10 rounded-2xl border border-dashed border-rose-200/50 dark:border-rose-900/30">
                                            <p className="text-[10px] font-bold text-rose-400 uppercase tracking-tight">관리가 필요한 성도가 없습니다.</p>
                                        </div>
                                    )}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <Modal
                isOpen={isAddSnapshotMemberModalOpen}
                onClose={() => setIsAddSnapshotMemberModalOpen(false)}
                title="이 주차 출석 대상 추가"
                maxWidth="md"
            >
                <div className="space-y-5">
                    <div className="space-y-2">
                        <label className="text-xs font-black text-slate-400 uppercase tracking-widest">성도 검색</label>
                        <input
                            value={addSnapshotSearch}
                            onChange={(event) => setAddSnapshotSearch(event.target.value)}
                            placeholder="이름으로 검색"
                            className="w-full rounded-2xl bg-slate-100 px-4 py-3 text-sm font-bold outline-none focus:ring-2 focus:ring-indigo-500/20 dark:bg-slate-800"
                        />
                    </div>
                    <div className="max-h-80 space-y-2 overflow-y-auto pr-1">
                        {addSnapshotCandidates
                            .filter((candidate) => candidate.name.toLowerCase().includes(addSnapshotSearch.toLowerCase()))
                            .slice(0, 30)
                            .map((candidate) => (
                                <button
                                    key={candidate.personId}
                                    type="button"
                                    onClick={() => addPersonToCurrentSnapshot(candidate)}
                                    className="flex w-full items-center justify-between rounded-2xl border border-slate-100 bg-white px-4 py-3 text-left hover:border-indigo-200 hover:bg-indigo-50/50 dark:border-slate-800 dark:bg-slate-900 dark:hover:border-indigo-500/30 dark:hover:bg-indigo-500/10"
                                >
                                    <span className="flex flex-col gap-1">
                                        <span className="text-sm font-black text-slate-900 dark:text-white">{candidate.name}</span>
                                        <span className="text-[10px] font-bold text-slate-400">{candidate.scopeLabel}</span>
                                    </span>
                                    <span className="text-[11px] font-bold text-slate-400">{candidate.groupName || '미편성'}</span>
                                </button>
                            ))}
                        {addSnapshotCandidates.length === 0 && (
                            <p className="rounded-2xl border border-dashed border-slate-200 py-8 text-center text-xs font-bold text-slate-400 dark:border-slate-800">
                                추가할 수 있는 성도를 찾지 못했습니다.
                            </p>
                        )}
                    </div>
                </div>
            </Modal>

            {/* Modal - Responsive */}
            <Modal
                isOpen={isExportModalOpen}
                onClose={() => setIsExportModalOpen(false)}
                title="통합 출석부 추출"
                maxWidth="md"
            >
                <div className="space-y-8">
                    {/* Start Range */}
                    <div className="space-y-3">
                        <label className="text-xs font-black text-slate-400 uppercase tracking-widest pl-1">시작 기간</label>
                        <div className="flex gap-2">
                            <select
                                value={startYear}
                                onChange={(e) => setStartYear(parseInt(e.target.value))}
                                className="flex-1 p-4 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20"
                            >
                                {[2024, 2025, 2026].map(y => <option key={y} value={y}>{y}년</option>)}
                            </select>
                            <select
                                value={startMonth}
                                onChange={(e) => setStartMonth(parseInt(e.target.value))}
                                className="flex-1 p-4 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20"
                            >
                                {Array.from({ length: 12 }, (_, i) => i + 1).map(m => <option key={m} value={m}>{m}월</option>)}
                            </select>
                        </div>
                    </div>

                    {/* End Range */}
                    <div className="space-y-3">
                        <label className="text-xs font-black text-slate-400 uppercase tracking-widest pl-1">종료 기간</label>
                        <div className="flex gap-2">
                            <select
                                value={endYear}
                                onChange={(e) => setEndYear(parseInt(e.target.value))}
                                className="flex-1 p-4 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20"
                            >
                                {[2024, 2025, 2026].map(y => <option key={y} value={y}>{y}년</option>)}
                            </select>
                            <select
                                value={endMonth}
                                onChange={(e) => setEndMonth(parseInt(e.target.value))}
                                className="flex-1 p-4 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20"
                            >
                                {Array.from({ length: 12 }, (_, i) => i + 1).map(m => <option key={m} value={m}>{m}월</option>)}
                            </select>
                        </div>
                    </div>

                    <div className="pt-4">
                        <button
                            onClick={downloadRangeExcel}
                            disabled={isExportLoading}
                            className="w-full py-5 bg-indigo-600 text-white rounded-3xl font-black hover:bg-indigo-700 transition-all hover:scale-[1.02] active:scale-[0.98] flex items-center justify-center gap-3 shadow-xl shadow-indigo-500/20 disabled:opacity-50 disabled:scale-100"
                        >
                            {isExportLoading ? <Loader2 className="w-6 h-6 animate-spin" /> : <Download className="w-6 h-6" />}
                            출석부 데이터 생성 및 다운로드
                        </button>
                        <p className="text-[10px] text-center text-slate-400 font-bold mt-4 tracking-tight">
                            선택한 기간 내의 모든 주차 데이터가 하나의 시트로 통합됩니다.
                        </p>
                    </div>
                </div>
            </Modal>
        </div>
    );
}
