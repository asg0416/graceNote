'use client';

/* eslint-disable @typescript-eslint/no-explicit-any */

import { useEffect, useState, useMemo, useRef, Suspense, useCallback } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Search,
    Loader2,
    Church,
    ChevronDown,
    Save,
    RotateCcw,
    AlertCircle,
    Download,
    FileDown,
    Image as ImageIcon,
    CalendarDays,
    ArrowLeft,
    Plus,
    CheckCircle2,
    Clock3,
    ShieldAlert,
    PencilLine,
    HelpCircle,
    SlidersHorizontal,
} from 'lucide-react';
import * as XLSX from 'xlsx';
import * as htmlToImage from 'html-to-image';
import { ExportTableView } from '@/components/kanban/ExportTableView';
import { cn } from '@/lib/utils';
import { KanbanBoard } from '@/components/kanban/KanbanBoard';
import { MemberModal } from '@/components/MemberModal';
import { Tooltip } from '@/components/Tooltip';
import { assertPhase2MemberDirectorySync } from '@/lib/phase2WriteGuards';
import { saveRegroupingMemberships } from '@/lib/memberWriteRpc';
import {
    applyRegroupingSeason,
    createRegroupingSeason,
    registerCurrentRegroupingSeason,
    saveRegroupingSeasonDraft,
    updateCurrentRegroupingGroupPeriods,
    updateRegroupingSeason,
} from '@/lib/regroupingSeasonsRpc';
import {
    buildRegroupingSeasonAssignmentsPayload,
    buildRegroupingSeasonGroupsPayload,
    mapRegroupingSeasonDraftToBoard,
} from '@/lib/regroupingSeasonPayloads';
import { SeasonChangeHistoryPanel } from './SeasonChangeHistoryPanel';

const toDateInputValue = (date: Date) => {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
};

const getCurrentSundayInputValue = () => {
    const now = new Date();
    const sunday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    sunday.setDate(sunday.getDate() - sunday.getDay());
    return toDateInputValue(sunday);
};

const addWeeksToDateInput = (value: string, weekCount: number) => {
    const base = new Date(`${snapDateInputToSunday(value)}T00:00:00`);
    base.setDate(base.getDate() + weekCount * 7);
    return toDateInputValue(base);
};

const getPreviousWeekStartInput = (value: string) => addWeeksToDateInput(value, -1);

const maxDateInput = (...values: string[]) =>
    values.filter(Boolean).sort().at(-1) || getCurrentSundayInputValue();

const addDaysToDateInput = (value: string, dayCount: number) => {
    const base = new Date(`${value}T00:00:00`);
    if (Number.isNaN(base.getTime())) return value;
    base.setDate(base.getDate() + dayCount);
    return toDateInputValue(base);
};

const snapDateInputToSunday = (value: string) => {
    if (!value) return getCurrentSundayInputValue();
    const date = new Date(`${value}T00:00:00`);
    if (Number.isNaN(date.getTime())) return getCurrentSundayInputValue();
    date.setDate(date.getDate() - date.getDay());
    return toDateInputValue(date);
};

const formatRegroupingWeekLabel = (value: string) => {
    if (!value) return '선택 안 됨';
    const [, month, day] = value.split('-');
    return `${Number(month)}월 ${Math.floor((Number(day) - 1) / 7) + 1}주차`;
};

const formatRegroupingPeriodLabel = (startValue?: string | null, endValue?: string | null) => {
    const start = startValue ? formatRegroupingDateLabel(startValue) : '시작 미정';
    const end = endValue ? formatRegroupingDateLabel(addDaysToDateInput(endValue, 6)) : '종료 미정';
    return `${start} ~ ${end}`;
};

const formatRegroupingDateLabel = (value?: string | null) => {
    if (!value) return '날짜 미정';
    const [year, month, day] = value.split('-');
    return `${year}.${Number(month)}.${Number(day)}.`;
};

const isSeasonCoveringDate = (season: any, dateInputValue: string) => {
    if (!season?.effective_week_date || season.effective_week_date > dateInputValue) {
        return false;
    }

    if (!season.end_week_date) return true;
    return addDaysToDateInput(season.end_week_date, 6) >= dateInputValue;
};

const getSeasonStatusMeta = (season: any, todayInputValue: string) => {
    if (season?.status === 'applied') {
        if (!isSeasonCoveringDate(season, todayInputValue)) {
            return {
                label: '적용 이력',
                description: '기간이 지난 조편성 기록입니다.',
                icon: CheckCircle2,
                className: 'bg-slate-50 text-slate-600 border-slate-200',
            };
        }

        return {
            label: '현재 적용',
            description: '현재 날짜에 사용하는 조편성입니다.',
            icon: CheckCircle2,
            className: 'bg-emerald-50 text-emerald-700 border-emerald-200',
        };
    }

    if (season?.effective_week_date && season.effective_week_date > todayInputValue) {
        return {
            label: '적용 대기',
            description: '적용 주차 전까지 앱과 출석/기도에는 반영되지 않습니다.',
            icon: Clock3,
            className: 'bg-indigo-50 text-indigo-700 border-indigo-200',
        };
    }

    return {
        label: '초안',
        description: '검토 후 실제 소속에 적용할 수 있습니다.',
        icon: PencilLine,
        className: 'bg-amber-50 text-amber-700 border-amber-200',
    };
};

const getRegroupingIdentityKey = (member: any) => {
    const normalizedPhone = (member.phone || '').replace(/[^0-9]/g, '');
    return member.phase2_person_id || member.person_id || `${member.full_name}|${normalizedPhone}`;
};

const normalizeRegroupingDisplayMembers = (sourceMembers: any[]) => {
    const rowsByPerson = new Map<string, any[]>();
    sourceMembers.forEach((member) => {
        const key = getRegroupingIdentityKey(member);
        const rows = rowsByPerson.get(key) || [];
        rows.push(member);
        rowsByPerson.set(key, rows);
    });

    const visibleRows: any[] = [];
    rowsByPerson.forEach((rows) => {
        const draftRows = rows.filter(row => String(row.id || '').startsWith('temp-') || row.is_new);
        if (draftRows.length > 0) {
            visibleRows.push(...draftRows);
        }

        const activeMembershipRows = rows.filter(row =>
            !draftRows.includes(row) &&
            Boolean(row.phase2_person_id) &&
            Boolean(row.phase2_membership_id) &&
            Boolean(row.group_id) &&
            row.is_active !== false
        );
        if (activeMembershipRows.length > 0) {
            visibleRows.push(...activeMembershipRows);
            return;
        }

        const assignedLegacyRows = rows.filter(row =>
            !draftRows.includes(row) &&
            Boolean(row.group_id) &&
            row.is_active !== false
        );
        if (assignedLegacyRows.length > 0) {
            visibleRows.push(...assignedLegacyRows);
            return;
        }

        const preferredUnassignedRow = rows.find(row => row.is_active !== false) || rows[0];
        if (preferredUnassignedRow) visibleRows.push(preferredUnassignedRow);
    });

    return visibleRows;
};

const isSameRegroupingGroup = (left: any, right: any) => {
    if (!left || !right) return false;
    if (left.group_id && right.group_id && left.group_id === right.group_id) return true;
    const leftGroupName = (left.group_name || '').trim();
    const rightGroupName = (right.group_name || '').trim();
    if (!left.group_id && !right.group_id && !leftGroupName && !rightGroupName) return true;
    return Boolean(leftGroupName) && leftGroupName === rightGroupName;
};

const isSameRegroupingPerson = (left: any, right: any) => {
    return getRegroupingIdentityKey(left) === getRegroupingIdentityKey(right);
};

const getRegroupingGroupKey = (member: any) => {
    return member.group_id || (member.group_name || '').trim() || null;
};

const expandCoupleMovesBeforeSave = (draftMembers: any[], originalMembers: any[]) => {
    const nextMembers = draftMembers.map(member => ({ ...member }));
    const originalById = new Map(originalMembers.map(member => [member.id, member]));

    nextMembers.forEach(member => {
        if (!member.spouse_name) return;

        const originalMember = originalById.get(member.id);
        if (!originalMember) return;

        const originalGroupKey = getRegroupingGroupKey(originalMember);
        const draftGroupKey = getRegroupingGroupKey(member);
        if (originalGroupKey === draftGroupKey) return;

        const spouse = nextMembers.find(candidate => {
            const originalSpouse = originalById.get(candidate.id);
            return candidate.full_name === member.spouse_name &&
                candidate.spouse_name === member.full_name &&
                originalSpouse &&
                getRegroupingGroupKey(originalSpouse) === originalGroupKey;
        });

        if (!spouse) return;

        const spouseOriginal = originalById.get(spouse.id);
        if (!spouseOriginal) return;

        const spouseWasIndependentlyMoved =
            getRegroupingGroupKey(spouse) !== getRegroupingGroupKey(spouseOriginal);
        if (spouseWasIndependentlyMoved) return;

        spouse.group_id = member.group_id || null;
        spouse.group_name = member.group_name || null;
    });

    return nextMembers;
};

const applyCanonicalFamilyInfo = (sourceMembers: any[]) => {
    const rowsByPerson = new Map<string, any[]>();
    sourceMembers.forEach((member) => {
        const key = getRegroupingIdentityKey(member);
        const rows = rowsByPerson.get(key) || [];
        rows.push(member);
        rowsByPerson.set(key, rows);
    });

    return sourceMembers.map((member) => {
        const rows = rowsByPerson.get(getRegroupingIdentityKey(member)) || [member];
        const spouseName = rows.find(row => row.spouse_name)?.spouse_name || member.spouse_name;
        const childrenInfo = rows.find(row => row.children_info)?.children_info || member.children_info;
        const weddingAnniversary = rows.find(row => row.wedding_anniversary)?.wedding_anniversary || member.wedding_anniversary;

        return {
            ...member,
            spouse_name: member.spouse_name || spouseName || null,
            children_info: member.children_info || childrenInfo || null,
            wedding_anniversary: member.wedding_anniversary || weddingAnniversary || null
        };
    });
};

const buildUnassignedRegroupingMembers = (sourceMembers: any[]) => {
    return normalizeRegroupingDisplayMembers(sourceMembers).map(member => ({
        ...member,
        group_id: null,
        group_name: null,
        role_in_group: 'member',
    }));
};

export default function RegroupingPage() {
    return (
        <Suspense fallback={
            <div className="h-96 flex flex-col items-center justify-center gap-4">
                <Loader2 className="w-10 h-10 text-indigo-600 animate-spin" />
                <p className="text-slate-400 font-black text-xs uppercase tracking-widest">데이터 로딩 중...</p>
            </div>
        }>
            <RegroupingPageInner />
        </Suspense>
    );
}

function RegroupingPageInner() {
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [members, setMembers] = useState<any[]>([]);
    const [localMembers, setLocalMembers] = useState<any[]>([]); // Draft state
    const [groups, setGroups] = useState<any[]>([]);
    const [seasonArchivedGroups, setSeasonArchivedGroups] = useState<any[]>([]);
    const [boardBaselineMembers, setBoardBaselineMembers] = useState<any[]>([]);
    const [boardBaselineGroups, setBoardBaselineGroups] = useState<any[]>([]);
    const [boardBaselineArchivedGroups, setBoardBaselineArchivedGroups] = useState<any[]>([]);
    const [departments, setDepartments] = useState<any[]>([]);
    const [churches, setChurches] = useState<any[]>([]);

    const [currentChurchId, setCurrentChurchId] = useState<string | null>(null);
    const [selectedDeptId, setSelectedDeptId] = useState<string | null>(null);
    const [isMaster, setIsMaster] = useState(false);
    const [searchTerm, setSearchTerm] = useState('');
    const [selectedMemberIds, setSelectedMemberIds] = useState<string[]>([]);

    const [isMemberModalOpen, setIsMemberModalOpen] = useState(false);
    const [memberToEdit, setMemberToEdit] = useState<any>(null);
    const [targetGroupForNewMember, setTargetGroupForNewMember] = useState<{ id: string | null, name: string } | null>(null);
    const [lastAddedGroupId, setLastAddedGroupId] = useState<string | null>(null);
    const [autoMoveCouples, setAutoMoveCouples] = useState(true);
    const [isExporting, setIsExporting] = useState(false);
    const [showExportMenu, setShowExportMenu] = useState(false);
    const [effectiveWeekDate, setEffectiveWeekDate] = useState(getCurrentSundayInputValue);
    const [regroupingView, setRegroupingView] = useState<'list' | 'seasonEditor' | 'liveCorrection'>('list');
    const [regroupingMode, setRegroupingMode] = useState<'season' | 'live'>('season');
    const [selectedSeasonId, setSelectedSeasonId] = useState<string | null>(null);
    const [regroupingSeasons, setRegroupingSeasons] = useState<any[]>([]);
    const [seasonTitle, setSeasonTitle] = useState('');
    const [seasonEffectiveWeekDate, setSeasonEffectiveWeekDate] = useState(getCurrentSundayInputValue);
    const [seasonEndWeekDate, setSeasonEndWeekDate] = useState(() => addWeeksToDateInput(getCurrentSundayInputValue(), 24));
    const [currentRegistrationStartWeek, setCurrentRegistrationStartWeek] = useState(getCurrentSundayInputValue);
    const [currentRegistrationEndWeek, setCurrentRegistrationEndWeek] = useState(() => addWeeksToDateInput(getCurrentSundayInputValue(), 24));
    const [, setPhase2RegroupingCheck] = useState<{
        status: 'idle' | 'ok' | 'warning' | 'unavailable';
        legacyActiveCount: number;
        phase2ActiveCount: number;
        legacyActivePersonCount: number;
        phase2ActivePersonCount: number;
        issueCount: number;
        message: string;
    }>({
        status: 'idle',
        legacyActiveCount: 0,
        phase2ActiveCount: 0,
        legacyActivePersonCount: 0,
        phase2ActivePersonCount: 0,
        issueCount: 0,
        message: 'Phase 2 진단 대기 중'
    });

    const [hasChanges, setHasChanges] = useState(false);
    const boardRef = useRef<HTMLDivElement>(null);
    const exportTableRef = useRef<HTMLDivElement>(null);
    const router = useRouter();
    const searchParams = useSearchParams();
    const selectedChurch = useMemo(
        () => churches.find(church => church.id === currentChurchId) || null,
        [churches, currentChurchId]
    );
    const selectedDepartment = useMemo(
        () => departments.find(department => department.id === selectedDeptId) || null,
        [departments, selectedDeptId]
    );
    const selectedSeason = useMemo(
        () => regroupingSeasons.find(season => season.id === selectedSeasonId) || null,
        [regroupingSeasons, selectedSeasonId]
    );
    const todayInputValue = toDateInputValue(new Date());
    const currentAppliedSeason = useMemo(() => {
        const appliedSeasons = regroupingSeasons
            .filter(season => season.status === 'applied' && season.effective_week_date <= todayInputValue)
            .sort((left, right) => String(right.effective_week_date).localeCompare(String(left.effective_week_date)));
        return appliedSeasons.find(season => isSeasonCoveringDate(season, todayInputValue)) || appliedSeasons[0] || null;
    }, [regroupingSeasons, todayInputValue]);
    const isCurrentAppliedSeasonExpired = Boolean(currentAppliedSeason) && !isSeasonCoveringDate(currentAppliedSeason, todayInputValue);
    const isSelectedSeasonApplied = selectedSeason?.status === 'applied';
    const isSelectedCurrentAppliedSeason = Boolean(
        selectedSeason &&
        currentAppliedSeason &&
        selectedSeason.status === 'applied' &&
        selectedSeason.id === currentAppliedSeason.id &&
        !isCurrentAppliedSeasonExpired
    );
    const isSelectedSeasonLocked = isSelectedSeasonApplied && !isSelectedCurrentAppliedSeason;
    const isBoardReadonly = regroupingMode === 'season' && isSelectedSeasonLocked;
    const isSeasonEffectiveFuture = seasonEffectiveWeekDate > toDateInputValue(new Date());
    const isSeasonPeriodInvalid = Boolean(seasonEndWeekDate) && seasonEndWeekDate < seasonEffectiveWeekDate;
    const isCurrentRegistrationPeriodInvalid = Boolean(currentRegistrationEndWeek) && currentRegistrationEndWeek < currentRegistrationStartWeek;
    const canSaveSeasonDraft = regroupingMode === 'season' &&
        Boolean(selectedChurch) &&
        Boolean(selectedDepartment) &&
        !isSelectedSeasonLocked &&
        !isSeasonPeriodInvalid;
    const canApplySeason = regroupingMode === 'season' &&
        Boolean(selectedSeasonId) &&
        !isSelectedSeasonApplied &&
        !isSeasonEffectiveFuture &&
        !isSeasonPeriodInvalid;
    const viewTitle = regroupingView === 'list'
        ? '조편성 시즌'
        : regroupingMode === 'live'
            ? '현재/과거 조편성 보정'
            : selectedSeasonId
                ? '시즌 조편성 편집'
                : '새 조편성 만들기';
    const viewDescription = regroupingView === 'list'
        ? '시즌을 선택하거나 새 조편성을 만들어 시즌별 소속 기간을 관리합니다.'
        : regroupingMode === 'live'
            ? '저장 즉시 실제 소속과 호환 데이터가 변경되는 예외 작업입니다.'
            : '초안은 저장해도 적용 전까지 앱, 출석, 기도 화면에 반영되지 않습니다.';
    const editorHelpText = regroupingMode === 'live'
        ? '현재/과거 보정은 저장 즉시 실제 소속에 반영됩니다. 미래 조편성은 시즌 초안에서 준비하세요.'
        : isSelectedCurrentAppliedSeason
            ? '현재 시즌은 각 조와 성도 소속의 시즌 내 유효기간을 조정합니다. 같은 성도가 여러 조에 동시에 속할 수 있으며, 같은 조 중복 기간만 피하면 됩니다.'
            : '미래 시즌은 조와 구성원 모두 시즌 기간 전체에 적용됩니다. 시즌 중간 변동은 현재 시즌에서 처리합니다.';
    const editorPeriodSummary = regroupingMode === 'live'
        ? formatRegroupingWeekLabel(effectiveWeekDate)
        : isSelectedCurrentAppliedSeason
            ? formatRegroupingPeriodLabel(seasonEffectiveWeekDate, seasonEndWeekDate)
            : `${formatRegroupingWeekLabel(seasonEffectiveWeekDate)} - ${formatRegroupingWeekLabel(seasonEndWeekDate)}`;

    // Calculate duplicate status for members (only show delete button if duplicated)
    const isDeletableMap = useMemo(() => {
        const counts: Record<string, number> = {};

        // Count by identity (person_id or normalized name+phone)
        localMembers.forEach(m => {
            const key = getRegroupingIdentityKey(m);
            counts[key] = (counts[key] || 0) + 1;
        });

        const map: Record<string, boolean> = {};
        localMembers.forEach(m => {
            const key = getRegroupingIdentityKey(m);
            // Member is deletable if their identity appears more than once
            // OR if it's a temporary copy/new member
            map[m.id] = counts[key] > 1 || m.id.startsWith('temp-');
        });
        return map;
    }, [localMembers]);

    useEffect(() => {
        const init = async () => {
            setLoading(true);
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                router.push('/login');
                return;
            }

            const { data: profile } = await supabase
                .from('profiles')
                .select('church_id, department_id, is_master, role, admin_status')
                .eq('id', session.user.id)
                .single();

            const isAuthorized = profile && (profile.is_master || (profile.role === 'admin' && profile.admin_status === 'approved'));

            if (!isAuthorized) {
                await supabase.auth.signOut();
                router.push('/login?error=unauthorized');
                return;
            }

            if (profile) {
                setIsMaster(profile.is_master);
                const cId = profile.church_id;
                const dId = searchParams.get('deptId') || profile.department_id;

                setCurrentChurchId(cId);
                setSelectedDeptId(dId);

                // Start single unified loading chain
                if (profile.is_master) {
                    await fetchChurches(cId, dId);
                } else if (cId) {
                    await fetchChurchInfo(cId);
                    await fetchDepartments(cId, dId);
                }
            }
            setLoading(false);
        };

        init();
    }, []);

    // Clear lastAddedGroupId when user interacts with other elements
    useEffect(() => {
        const handleMouseDown = () => {
            if (lastAddedGroupId) setLastAddedGroupId(null);
        };
        document.addEventListener('mousedown', handleMouseDown);
        return () => document.removeEventListener('mousedown', handleMouseDown);
    }, [lastAddedGroupId]);

    const fetchChurchInfo = async (churchId: string) => {
        try {
            const { data } = await supabase.from('churches').select('name').eq('id', churchId).single();
            if (data) {
                // We need to make sure the churches list also has this if we use the memo, 
                // or just set a separate state. For consistency with the memo:
                setChurches([{ id: churchId, name: data.name }]);
            }
        } catch (err) {
            console.error(err);
        }
    };

    const fetchChurches = async (targetChurchId?: string | null, targetDeptId?: string | null) => {
        const { data } = await supabase.from('churches').select('id, name').order('name');
        setChurches(data || []);

        const effectiveChurchId = targetChurchId || (data && data.length > 0 ? data[0].id : null);
        if (effectiveChurchId) {
            if (!targetChurchId) setCurrentChurchId(effectiveChurchId);
            await fetchDepartments(effectiveChurchId, targetDeptId);
        }
    };

    const fetchRegroupingSeasons = async (churchId: string, deptId: string) => {
        const { data, error } = await supabase
            .from('regrouping_seasons')
            .select('id, title, status, effective_week_date, end_week_date, updated_at, created_at')
            .eq('church_id', churchId)
            .eq('department_id', deptId)
            .in('status', ['draft', 'ready', 'applied'])
            .order('effective_week_date', { ascending: false })
            .order('updated_at', { ascending: false });

        if (error) {
            console.error('Fetch regrouping seasons error:', error);
            setRegroupingSeasons([]);
            return;
        }

        setRegroupingSeasons(data || []);
    };

    const fetchDepartments = async (churchId: string, targetDeptId?: string | null) => {
        const { data } = await supabase
            .from('departments')
            .select('id, name, color_hex, profile_mode')
            .eq('church_id', churchId)
            .eq('is_active', true)
            .order('name');
        setDepartments(data || []);

        if (data && data.length > 0) {
            // Use targetDeptId from argument if available, fallback to state or first dept
            const deptIdToUse = targetDeptId || selectedDeptId || data[0].id;
            const dept = data.find(d => d.id === deptIdToUse) || data[0];

            if (dept) {
                setSelectedDeptId(dept.id);
                setAutoMoveCouples(dept.profile_mode === 'couple');
                // Fetch groups and members in parallel for visual smoothness
                await Promise.all([
                    fetchGroups(dept.id),
                    fetchMembers(churchId, dept.id),
                    fetchRegroupingSeasons(churchId, dept.id)
                ]);
            }
        }
    };

    const fetchData = async () => {
        if (currentChurchId && selectedDeptId) {
            await Promise.all([
                fetchGroups(selectedDeptId),
                fetchMembers(currentChurchId, selectedDeptId),
                fetchRegroupingSeasons(currentChurchId, selectedDeptId)
            ]);
        }
    };

    const fetchGroups = async (deptId: string) => {
        const { data } = await supabase
            .from('groups')
            .select('id, name, color_hex, department_id')
            .eq('department_id', deptId)
            .eq('is_active', true)
            .order('name');
        setGroups(data || []);
        setSeasonArchivedGroups([]);
        setBoardBaselineGroups(data || []);
        setBoardBaselineArchivedGroups([]);
    };

    const fetchPhase2PersonMap = async (directoryIds: string[]) => {
        if (directoryIds.length === 0) return new Map<string, string>();

        const { data, error } = await supabase
            .from('member_profiles')
            .select('person_id, member_directory_id')
            .in('member_directory_id', directoryIds);

        if (error) throw error;

        return new Map(
            (data || [])
                .filter(profile => profile.member_directory_id && profile.person_id)
                .map(profile => [profile.member_directory_id as string, profile.person_id as string])
        );
    };

    const fetchPhase2ActiveMembershipMap = async (directoryIds: string[], churchId: string, deptId: string) => {
        if (directoryIds.length === 0) return new Map<string, any>();

        const { data, error } = await supabase
            .from('memberships')
            .select('id, person_id, legacy_member_directory_id, group_id, role')
            .eq('church_id', churchId)
            .eq('department_id', deptId)
            .eq('status', 'active')
            .in('legacy_member_directory_id', directoryIds);

        if (error) throw error;

        return new Map(
            (data || [])
                .filter(membership => membership.legacy_member_directory_id)
                .map(membership => [membership.legacy_member_directory_id as string, membership])
        );
    };

    const fetchMembers = async (churchId: string, deptId: string) => {
        setLoading(true);
        const { data } = await supabase
            .from('member_directory')
            .select('*')
            .eq('church_id', churchId)
            .eq('department_id', deptId)
            .neq('is_active', false);

        // Match members with their group_id for Kanban
        const { data: groupData } = await supabase
            .from('groups')
            .select('id, name')
            .eq('department_id', deptId)
            .eq('is_active', true);

        const directoryIds = (data || []).map(m => m.id);
        const [phase2PersonMap, phase2MembershipMap] = await Promise.all([
            fetchPhase2PersonMap(directoryIds),
            fetchPhase2ActiveMembershipMap(directoryIds, churchId, deptId)
        ]);
        const membersWithGroupId = applyCanonicalFamilyInfo((data || []).map(m => ({
            ...m,
            group_id: phase2MembershipMap.get(m.id)?.group_id || groupData?.find(g => g.name === m.group_name)?.id || null,
            role_in_group: phase2MembershipMap.get(m.id)?.role || m.role_in_group,
            phase2_membership_id: phase2MembershipMap.get(m.id)?.id || null,
            phase2_person_id: phase2MembershipMap.get(m.id)?.person_id || phase2PersonMap.get(m.id) || null
        })));

        await refreshPhase2RegroupingCheck(membersWithGroupId, churchId, deptId);
        setMembers(membersWithGroupId);
        setLocalMembers(JSON.parse(JSON.stringify(membersWithGroupId)));
        setBoardBaselineMembers(JSON.parse(JSON.stringify(membersWithGroupId)));
        setHasChanges(false);
        setLoading(false);
    };

    const refreshPhase2RegroupingCheck = async (loadedMembers: any[], churchId: string, deptId: string) => {
        // '미정'(unassigned)은 아직 조에 배정되지 않은 대기 상태 — Phase 2 group membership이 없어도 정상이므로 진단에서 제외
        const activeLegacyMembers = loadedMembers.filter(member =>
            member.is_active !== false &&
            Boolean(member.group_name) &&
            member.group_name !== '미정'
        );
        const activeLegacyDirectoryIds = new Set(activeLegacyMembers.map(member => member.id));
        const activeLegacyPersonIds = new Set(activeLegacyMembers.map(getRegroupingIdentityKey));
        const directoryIds = loadedMembers.map(member => member.id).filter(Boolean);

        if (directoryIds.length === 0) {
            setPhase2RegroupingCheck({
                status: 'ok',
                legacyActiveCount: 0,
                phase2ActiveCount: 0,
                legacyActivePersonCount: 0,
                phase2ActivePersonCount: 0,
                issueCount: 0,
                message: '확인할 명부 row가 없습니다.'
            });
            return;
        }

        try {
            const { data: memberProfiles, error: memberProfilesError } = await supabase
                .from('member_profiles')
                .select('person_id, member_directory_id')
                .in('member_directory_id', directoryIds);

            if (memberProfilesError) throw memberProfilesError;

            const personIds = Array.from(new Set((memberProfiles || []).map(profile => profile.person_id).filter(Boolean)));
            if (personIds.length === 0) {
                setPhase2RegroupingCheck({
                    status: activeLegacyMembers.length === 0 ? 'ok' : 'warning',
                    legacyActiveCount: activeLegacyMembers.length,
                    phase2ActiveCount: 0,
                    legacyActivePersonCount: activeLegacyPersonIds.size,
                    phase2ActivePersonCount: 0,
                    issueCount: activeLegacyMembers.length,
                    message: activeLegacyMembers.length === 0
                        ? 'Phase 2 비교 대상이 없습니다.'
                        : 'Phase 2 member_profiles 연결이 없는 active 명부가 있습니다.'
                });
                return;
            }

            const { data: memberships, error: membershipsError } = await supabase
                .from('memberships')
                .select('id, person_id, status, department_id, legacy_member_directory_id')
                .in('person_id', personIds)
                .eq('church_id', churchId)
                .eq('department_id', deptId)
                .eq('status', 'active');

            if (membershipsError) throw membershipsError;

            const activeMemberships = memberships || [];
            const phase2ActivePersonIds = new Set(activeMemberships.map(membership => membership.person_id).filter(Boolean));
            const phase2ActiveDirectoryIds = new Set(
                activeMemberships
                    .map(membership => membership.legacy_member_directory_id)
                    .filter(Boolean)
            );
            const missingPhase2Count = activeLegacyMembers.filter(member => !phase2ActiveDirectoryIds.has(member.id)).length;
            const extraPhase2Count = activeMemberships.filter(membership => (
                !membership.legacy_member_directory_id || !activeLegacyDirectoryIds.has(membership.legacy_member_directory_id)
            )).length;
            const issueCount = missingPhase2Count + extraPhase2Count;

            setPhase2RegroupingCheck({
                status: issueCount === 0 ? 'ok' : 'warning',
                legacyActiveCount: activeLegacyMembers.length,
                phase2ActiveCount: activeMemberships.length,
                legacyActivePersonCount: activeLegacyPersonIds.size,
                phase2ActivePersonCount: phase2ActivePersonIds.size,
                issueCount,
                message: issueCount === 0
                    ? '선택 부서의 조편성 active 사람/소속이 Phase 2와 일치합니다.'
                    : `누락 ${missingPhase2Count}건 / 추가 확인 ${extraPhase2Count}건`
            });
        } catch (error) {
            console.warn('Phase 2 regrouping diagnostic unavailable:', error);
            setPhase2RegroupingCheck({
                status: 'unavailable',
                legacyActiveCount: activeLegacyMembers.length,
                phase2ActiveCount: 0,
                legacyActivePersonCount: activeLegacyPersonIds.size,
                phase2ActivePersonCount: 0,
                issueCount: 0,
                message: 'Phase 2 조편성 진단을 불러오지 못했습니다.'
            });
        }
    };

    const getMemberIdentityKey = useCallback((member: any) => {
        return getRegroupingIdentityKey(member);
    }, []);

    const findDuplicateIdentityNames = useCallback((candidateMembers: any[]) => {
        const identityMap = new Map<string, string[]>();

        candidateMembers.forEach(member => {
            const key = getMemberIdentityKey(member);
            const names = identityMap.get(key) || [];
            names.push(member.full_name);
            identityMap.set(key, names);
        });

        return Array.from(identityMap.values())
            .filter(names => names.length > 1)
            .flat();
    }, [getMemberIdentityKey]);

    const handleReorderMembers = useMemo(() => (ids: string[], targetGroupId: string | null) => {
        if (targetGroupId) {
            const movingMembers = localMembers.filter(member => ids.includes(member.id));
            const duplicateMovingNames = findDuplicateIdentityNames(movingMembers);

            if (duplicateMovingNames.length > 0) {
                alert(`같은 사람의 여러 소속 카드를 한 조에 동시에 넣을 수 없습니다: ${Array.from(new Set(duplicateMovingNames)).join(', ')}`);
                return;
            }
        }

        // Prevent duplicates in the target group
        if (targetGroupId) {
            const targetGroupMembers = localMembers.filter(m => m.group_id === targetGroupId);
            const duplicates = ids.filter(id => {
                const memberToMove = localMembers.find(m => m.id === id);
                if (!memberToMove || ids.includes(memberToMove.id) && memberToMove.group_id === targetGroupId) return false;

                return targetGroupMembers.some(tm =>
                    !ids.includes(tm.id) &&
                    isSameRegroupingPerson(tm, memberToMove)
                );
            });

            if (duplicates.length > 0) {
                const duplicateNames = duplicates.map(id => localMembers.find(m => m.id === id)?.full_name).join(', ');
                alert(`${duplicateNames} 성도님은 이미 해당 조에 편성되어 있습니다.`);
                return;
            }
        }

        setLocalMembers(prev => {
            // Check if anything actually changed to avoid unnecessary re-renders
            let changed = false;
            const next = prev.map(m => {
                if (ids.includes(m.id) && m.group_id !== targetGroupId) {
                    changed = true;
                    return { ...m, group_id: targetGroupId };
                }
                return m;
            });
            return changed ? next : prev;
        });
        setHasChanges(true);
    }, [findDuplicateIdentityNames, localMembers]); // Needs localMembers for duplicate check

    const handleMoveMembers = (ids: string[], targetGroupId: string | null, isCopy: boolean = false, targetIndex?: number) => {
        let finalIdsToMove = [...ids];

        // Couple-aware logic: if autoMoveCouples is on, find spouses
        if (autoMoveCouples && !isCopy) {
            const spousesToInclude: string[] = [];
            ids.forEach(id => {
                const member = localMembers.find(m => m.id === id);
                if (member?.spouse_name) {
                    const spouse = localMembers.find(m =>
                        m.full_name === member.spouse_name &&
                        m.spouse_name === member.full_name &&
                        isSameRegroupingGroup(m, member)
                    );
                    if (spouse && !finalIdsToMove.includes(spouse.id)) {
                        spousesToInclude.push(spouse.id);
                    }
                }
            });
            finalIdsToMove = [...finalIdsToMove, ...spousesToInclude];
        }

        if (targetGroupId) {
            const movingMembers = localMembers.filter(member => finalIdsToMove.includes(member.id));
            const duplicateMovingNames = findDuplicateIdentityNames(movingMembers);

            if (duplicateMovingNames.length > 0) {
                alert(`같은 사람의 여러 소속 카드를 한 조에 동시에 넣을 수 없습니다: ${Array.from(new Set(duplicateMovingNames)).join(', ')}`);
                setSelectedMemberIds([]);
                return;
            }
        }

        // Prevent duplicates in the target group
        if (targetGroupId) {
            const targetGroupMembers = localMembers.filter(m => m.group_id === targetGroupId);
            const idsBeingMoved = new Set(finalIdsToMove);
            const duplicates = finalIdsToMove.filter(id => {
                const memberToMove = localMembers.find(m => m.id === id);
                if (!memberToMove) return false;

                if (isCopy && (memberToMove.group_id || null) === targetGroupId) {
                    return true;
                }

                // Check if someone with same identity already exists in the target group (excluding the ones being moved)
                return targetGroupMembers.some(tm =>
                    !idsBeingMoved.has(tm.id) &&
                    isSameRegroupingPerson(tm, memberToMove)
                );
            });

            if (duplicates.length > 0) {
                const duplicateNames = duplicates.map(id => localMembers.find(m => m.id === id)?.full_name).join(', ');
                alert(`${duplicateNames} 성도님은 이미 해당 조에 편성되어 있습니다.`);

                // Filter out duplicates from moves
                finalIdsToMove = finalIdsToMove.filter(id => !duplicates.includes(id));
                if (finalIdsToMove.length === 0) {
                    setSelectedMemberIds([]);
                    return;
                }
            }
        }

        if (isCopy) {
            const membersToCopy = localMembers.filter(m => finalIdsToMove.includes(m.id));
            const newCopies = membersToCopy.map(m => ({
                ...m,
                id: `temp-copy-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
                group_id: targetGroupId,
            }));

            // If targetIndex is provided, we insert them at that position in the group
            if (targetIndex !== undefined) {
                setLocalMembers(prev => {
                    const groupMembers = prev.filter(m => m.group_id === targetGroupId);
                    const otherMembers = prev.filter(m => m.group_id !== targetGroupId);

                    const updatedGroupMembers = [...groupMembers];
                    updatedGroupMembers.splice(targetIndex, 0, ...newCopies);

                    return [...otherMembers, ...updatedGroupMembers];
                });
            } else {
                setLocalMembers(prev => [...prev, ...newCopies]);
            }
        } else {
            // MOVE logic
            setLocalMembers(prev => {
                // 1. Separate members to move from others
                const movingMembers = prev.filter(m => finalIdsToMove.includes(m.id))
                    .map(m => ({ ...m, group_id: targetGroupId }));
                const remainingMembers = prev.filter(m => !finalIdsToMove.includes(m.id));

                // 2. If targetIndex is specified, insert them at the position within the target group
                if (targetIndex !== undefined) {
                    const targetGroupMembers = remainingMembers.filter(m => m.group_id === targetGroupId);
                    const otherMembers = remainingMembers.filter(m => m.group_id !== targetGroupId);

                    const updatedTargetGroup = [...targetGroupMembers];
                    updatedTargetGroup.splice(targetIndex, 0, ...movingMembers);

                    return [...otherMembers, ...updatedTargetGroup];
                } else {
                    // Default to end of group
                    return [...remainingMembers, ...movingMembers];
                }
            });
        }
        setSelectedMemberIds([]);
        setHasChanges(true);
    };

    const handleDeleteMember = async (id: string) => {
        const member = localMembers.find(m => m.id === id);
        if (!member) return;

        const personIdCount = localMembers.filter(m => m.person_id === member.person_id).length;

        if (id.startsWith('temp-')) {
            // Temporary members are always safe to remove locally
            setLocalMembers(prev => prev.filter(m => m.id !== id));
            setHasChanges(true);
        } else if (personIdCount > 1) {
            // If the member is duplicated (exists in other groups), we only remove this instance
            // This is effectively "de-assigning" from THIS group.
            if (confirm(`${member.full_name} 성도님을 이 조에서 제외하시겠습니까? (다른 조에 등록된 정보는 유지됩니다.)`)) {
                setLocalMembers(prev => prev.filter(m => m.id !== id));
                setHasChanges(true); // User needs to click "Save" to persist this "de-assignment"
            }
        } else {
            // If it's the last remaining card, we MUST NOT delete or remove it.
            // The user requested that the actual member info never be deleted.
            alert('이 성도는 현재 한 곳에만 편성되어 있어 삭제할 수 없습니다. 대신 다른 조로 이동시키거나 명단에 유지해 주세요.');
        }
    };

    const handleToggleLeader = (memberId: string) => {
        setLocalMembers(prev => prev.map(m => {
            if (m.id === memberId) {
                return { ...m, role_in_group: m.role_in_group === 'leader' ? 'member' : 'leader' };
            }
            return m;
        }));
        setHasChanges(true);
    };

    const handleOpenAddMemberModal = (groupInfo?: any) => {
        let target = null;
        if (typeof groupInfo === 'string') {
            // It's an ID
            const found = groups.find(g => g.id === groupInfo);
            if (found) target = found;
        } else if (groupInfo) {
            // It's already an object
            target = groupInfo;
        }

        setTargetGroupForNewMember(target);
        setMemberToEdit(null);
        setIsMemberModalOpen(true);
    };

    const handleMemberClick = (id: string) => {
        const member = localMembers.find(m => m.id === id);
        const idsToToggle = [id];

        if (autoMoveCouples && member?.spouse_name) {
            const spouse = localMembers.find(s =>
                s.full_name === member.spouse_name &&
                s.spouse_name === member.full_name &&
                isSameRegroupingGroup(s, member)
            );
            if (spouse) {
                idsToToggle.push(spouse.id);
            }
        }

        setSelectedMemberIds(prev => {
            const isRemoving = prev.includes(id);
            if (isRemoving) {
                return prev.filter(mid => !idsToToggle.includes(mid));
            } else {
                // Add all but avoid duplicates
                const next = [...prev];
                idsToToggle.forEach(tid => {
                    if (!next.includes(tid)) next.push(tid);
                });
                return next;
            }
        });
    };

    const handleExportExcel = () => {
        const deptName = departments.find(d => d.id === selectedDeptId)?.name || '조편성';
        const date = new Date().toISOString().split('T')[0];

        // Prepare data in a structured format: Group, Leader(s), Members
        const exportData: any[] = [];
        const currentProfileMode = departments.find(d => d.id === selectedDeptId)?.profile_mode;

        groups.forEach(group => {
            const members = displayLocalMembers.filter(m => m.group_id === group.id);

            // Unified Leader logic for Excel
            const currentLeaders = members.filter(m => m.role_in_group === 'leader');
            let leadersText = '';

            if (currentProfileMode === 'couple') {
                const seenL = new Set<string>();
                const leaderFamilies: string[] = [];
                currentLeaders.forEach(l => {
                    if (seenL.has(l.id)) return;
                    const spouse = currentLeaders.find(s =>
                        !seenL.has(s.id) &&
                        s.full_name === l.spouse_name &&
                        s.spouse_name === l.full_name
                    );

                    if (spouse) {
                        let text = `${l.full_name}, ${spouse.full_name} (부부)`;
                        if (l.children_info || spouse.children_info) {
                            text += ` [자녀: ${l.children_info || spouse.children_info}]`;
                        }
                        leaderFamilies.push(text);
                        seenL.add(l.id);
                        seenL.add(spouse.id);
                    } else {
                        let text = l.full_name;
                        if (l.children_info) text += ` [자녀: ${l.children_info}]`;
                        leaderFamilies.push(text);
                        seenL.add(l.id);
                    }
                });
                leadersText = leaderFamilies.join('\n');
            } else {
                leadersText = currentLeaders.map(l => l.full_name).join(', ');
            }

            let regularMembersText = '';
            const commonMembers = members.filter(m => m.role_in_group !== 'leader');

            if (currentProfileMode === 'couple') {
                const seen = new Set<string>();
                const families: string[] = [];
                commonMembers.forEach(m => {
                    if (seen.has(m.id)) return;
                    const spouse = commonMembers.find(s =>
                        !seen.has(s.id) &&
                        s.full_name === m.spouse_name &&
                        s.spouse_name === m.full_name
                    );

                    if (spouse) {
                        let famText = `${m.full_name}, ${spouse.full_name} (부부)`;
                        if (m.children_info || spouse.children_info) {
                            famText += ` [자녀: ${m.children_info || spouse.children_info}]`;
                        }
                        families.push(famText);
                        seen.add(m.id);
                        seen.add(spouse.id);
                    } else {
                        let famText = m.full_name;
                        if (m.children_info) famText += ` [자녀: ${m.children_info}]`;
                        families.push(famText);
                        seen.add(m.id);
                    }
                });
                regularMembersText = families.join('\n');
            } else {
                regularMembersText = commonMembers.map(m => m.full_name).join(', ');
            }

            exportData.push({
                '조': group.name,
                '조장': leadersText || '-',
                '조원': regularMembersText || '-'
            });
        });

        // Add unassigned
        const unassigned = displayLocalMembers.filter(m => !m.group_id);
        if (unassigned.length > 0) {
            exportData.push({
                '조': '미편성',
                '조장': '-',
                '조원': unassigned.map(m => m.full_name).join(', ')
            });
        }

        const ws = XLSX.utils.json_to_sheet(exportData);

        // Adjust column widths
        ws['!cols'] = [
            { wch: 15 }, // 조
            { wch: 25 }, // 조장
            { wch: 60 }, // 조원
        ];

        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, "조편성결과");
        XLSX.writeFile(wb, `${deptName}_조편성_${date}.xlsx`);
    };

    const handleExportImage = async () => {
        if (!boardRef.current) return;

        setIsExporting(true);
        try {
            const deptName = departments.find(d => d.id === selectedDeptId)?.name || '조편성';
            const date = new Date().toISOString().split('T')[0];

            // Allow some time for UI to settle if needed
            const dataUrl = await htmlToImage.toPng(exportTableRef.current!, {
                backgroundColor: '#ffffff',
                quality: 1.0,
                pixelRatio: 2 // High quality
            });

            const link = document.createElement('a');
            link.download = `${deptName}_조편성_${date}.png`;
            link.href = dataUrl;
            link.click();
        } catch (error) {
            console.error('Image export failed:', error);
            alert('이미지 추출 중 오류가 발생했습니다.');
        } finally {
            setIsExporting(false);
        }
    };

    const handleMemberEdit = (id: string) => {
        const member = localMembers.find(m => m.id === id);
        if (member) {
            setMemberToEdit(member);
            setIsMemberModalOpen(true);
        }
    };

    const handleMemberModalSuccess = (memberData: any) => {
        const normalizedNewPhone = (memberData.phone || '').replace(/[^0-9]/g, '');

        if (memberToEdit) {
            // Edit existing
            setLocalMembers(prev => prev.map(m => m.id === memberData.id ? { ...m, ...memberData } : m));
        } else {
            // Add new - Check for duplicates in the target group first
            const targetGroupId = targetGroupForNewMember?.id || null;
            const isDuplicate = localMembers.some(m =>
                m.group_id === targetGroupId &&
                isSameRegroupingPerson(m, {
                    ...memberData,
                    phone: normalizedNewPhone,
                })
            );

            if (isDuplicate) {
                alert(`${memberData.full_name} 성도님은 이미 이 조에 편성되어 있습니다.`);
                return;
            }

            const newMember = {
                ...memberData,
                group_id: targetGroupId,
                is_new: true
            };
            setLocalMembers(prev => [...prev, newMember]);
        }
        setHasChanges(true);
    };

    const handleAddGroup = async (name: string = '새로운 조', color?: string) => {
        if (!selectedDeptId || !currentChurchId) return;

        const newGroup = {
            id: `temp-${Date.now()}`,
            name: name,
            color_hex: color || '#4f46e5',
            department_id: selectedDeptId,
            church_id: currentChurchId,
            plan_status: 'active',
            starts_week_date: isSelectedCurrentAppliedSeason ? getCurrentSundayInputValue() : seasonEffectiveWeekDate,
            ends_week_date: seasonEndWeekDate || null,
        };

        setLastAddedGroupId(newGroup.id);
        setGroups(prev => [...prev, newGroup]);
        setHasChanges(true);
    };

    const handleUpdateGroup = (id: string, updates: { name?: string, color_hex?: string }) => {
        setGroups(prev => prev.map(g => g.id === id ? { ...g, ...updates } : g));
        setHasChanges(true);
    };

    const handleUpdateSeasonGroupPeriod = (id: string, updates: Record<string, unknown>) => {
        setGroups(prev => prev.map(group => (
            group.id === id ? { ...group, ...updates } : group
        )));
        setHasChanges(true);
    };

    const handleUpdateSeasonMemberPeriod = (id: string, updates: Record<string, unknown>) => {
        setLocalMembers(prev => prev.map(member => (
            member.id === id ? { ...member, ...updates } : member
        )));
        setHasChanges(true);
    };

    const handleDeleteGroup = (id: string) => {
        const deletedGroup = groups.find(g => g.id === id);
        if (!deletedGroup) return;

        // Find members in this group and move to unassigned
        setLocalMembers(prev => prev.map(m => m.group_id === id ? { ...m, group_id: null } : m));
        setGroups(prev => prev.filter(g => g.id !== id));

        if (regroupingMode === 'season' && isSelectedCurrentAppliedSeason) {
            const endedWeekDate = maxDateInput(
                seasonEffectiveWeekDate,
                getPreviousWeekStartInput(getCurrentSundayInputValue())
            );

            setSeasonArchivedGroups(prev => {
                const archivedGroup = {
                    ...deletedGroup,
                    plan_status: 'ended',
                    starts_week_date: deletedGroup.starts_week_date || seasonEffectiveWeekDate,
                    ends_week_date: deletedGroup.ends_week_date || endedWeekDate,
                };
                const exists = prev.some(group => group.id === id);
                return exists
                    ? prev.map(group => group.id === id ? { ...group, ...archivedGroup } : group)
                    : [...prev, archivedGroup];
            });
        }

        setHasChanges(true);
    };

    const handleUpdateArchivedGroup = (id: string, updates: Record<string, unknown>) => {
        setSeasonArchivedGroups(prev => prev.map(group => (
            group.id === id ? { ...group, ...updates } : group
        )));
        setHasChanges(true);
    };

    const handleRestoreArchivedGroup = (id: string) => {
        const archivedGroup = seasonArchivedGroups.find(group => group.id === id);
        if (!archivedGroup) return;

        setSeasonArchivedGroups(prev => prev.filter(group => group.id !== id));
        setGroups(prev => [
            ...prev,
            {
                ...archivedGroup,
                plan_status: 'active',
                ends_week_date: archivedGroup.ends_week_date || seasonEndWeekDate || null,
            },
        ]);
        setHasChanges(true);
    };

    const handleSave = async () => {
        if (!selectedDeptId || !currentChurchId) return;
        setSaving(true);

        try {
            const duplicateAssignments = new Map<string, string[]>();
            localMembers.forEach(member => {
                const targetGroup = member.group_id ? groups.find(group => group.id === member.group_id) : null;
                const targetGroupName = targetGroup?.name || null;
                if (!targetGroupName) return;

                const key = [
                    currentChurchId,
                    selectedDeptId,
                    targetGroupName,
                    member.full_name,
                    member.phone || ''
                ].join('|');
                const labels = duplicateAssignments.get(key) || [];
                labels.push(member.full_name);
                duplicateAssignments.set(key, labels);
            });

            const duplicateAssignmentNames = Array.from(duplicateAssignments.values())
                .filter(labels => labels.length > 1)
                .flat();

            if (duplicateAssignmentNames.length > 0) {
                throw new Error(`같은 조에 같은 이름/전화번호의 성도가 중복 편성되어 있습니다: ${Array.from(new Set(duplicateAssignmentNames)).join(', ')}`);
            }

            const membersToSave = autoMoveCouples
                ? expandCoupleMovesBeforeSave(localMembers, members)
                : localMembers;

            const savedDirectoryIds = await saveRegroupingMemberships(supabase, {
                churchId: currentChurchId,
                departmentId: selectedDeptId,
                groups: groups.map(group => ({
                    id: group.id,
                    name: group.name,
                    color_hex: group.color_hex,
                })),
                assignments: membersToSave.map(member => ({
                    id: member.id,
                    full_name: member.full_name,
                    phone: member.phone || '',
                    group_id: member.group_id || null,
                    role_in_group: member.role_in_group || 'member',
                    family_name: member.family_name || null,
                    spouse_name: member.spouse_name || null,
                    children_info: member.children_info || null,
                    birth_date: member.birth_date || null,
                    wedding_anniversary: member.wedding_anniversary || null,
                    notes: member.notes || null,
                    avatar_url: member.avatar_url || null,
                    person_id: member.person_id || null,
                    phase2_person_id: member.phase2_person_id || null,
                    profile_id: member.profile_id || null,
                })),
                effectiveWeekDate,
            });

            await assertPhase2MemberDirectorySync(
                supabase,
                savedDirectoryIds,
                '조편성 저장'
            );

            // 3. Refresh State
            await fetchData();
            setHasChanges(false);
            alert(`변경 사항이 ${formatRegroupingWeekLabel(effectiveWeekDate)} 기준으로 저장되었습니다.`);
        } catch (err: any) {
            console.error('Save failed:', err);
            alert(`저장 중 오류가 발생했습니다: ${err.message || '알 수 없는 오류'}`);
        } finally {
            setSaving(false);
        }
    };

    const handleSaveSeasonDraft = async () => {
        if (!selectedChurch || !selectedDepartment) {
            alert('교회와 부서를 먼저 선택하세요.');
            return;
        }

        if (isSelectedSeasonLocked) {
            alert('기간이 지난 적용 시즌은 수정할 수 없습니다.');
            return;
        }

        if (isSeasonPeriodInvalid) {
            alert('종료 주차는 시작 주차보다 빠를 수 없습니다.');
            return;
        }

        setSaving(true);

        try {
            const title = seasonTitle.trim() || `${selectedDepartment.name} ${formatRegroupingWeekLabel(seasonEffectiveWeekDate)} 조편성`;
            const seasonId = selectedSeasonId ?? await createRegroupingSeason(supabase, {
                churchId: selectedChurch.id,
                departmentId: selectedDepartment.id,
                title,
                effectiveWeekDate: seasonEffectiveWeekDate,
                endWeekDate: seasonEndWeekDate,
            });

            if (selectedSeasonId) {
                await updateRegroupingSeason(supabase, {
                    seasonId: selectedSeasonId,
                    title,
                    effectiveWeekDate: seasonEffectiveWeekDate,
                    endWeekDate: seasonEndWeekDate,
                });
            }

            if (!selectedSeasonId) {
                setSelectedSeasonId(seasonId);
                setSeasonTitle(title);
            }

            const membersToSave = autoMoveCouples
                ? expandCoupleMovesBeforeSave(displayLocalMembers, members)
                : displayLocalMembers;
            const seasonPlanGroupsToSave = [
                ...groups.map(group => ({
                    ...group,
                    plan_status: group.plan_status || 'active',
                    starts_week_date: group.starts_week_date || seasonEffectiveWeekDate,
                    ends_week_date: group.ends_week_date || seasonEndWeekDate || null,
                })),
                ...seasonArchivedGroups.map(group => ({
                    ...group,
                    plan_status: 'ended',
                    starts_week_date: group.starts_week_date || seasonEffectiveWeekDate,
                    ends_week_date: group.ends_week_date || seasonEndWeekDate || null,
                })),
            ];

            if (isSelectedCurrentAppliedSeason) {
                const liveGroupIdByBoardGroupId = new Map(
                    groups.map(group => [
                        group.id,
                        group.source_group_id || group.id
                    ])
                );

                const savedDirectoryIds = await saveRegroupingMemberships(supabase, {
                    churchId: selectedChurch.id,
                    departmentId: selectedDepartment.id,
                    groups: groups.map(group => ({
                        id: group.source_group_id || group.id,
                        name: group.name,
                        color_hex: group.color_hex,
                    })),
                    assignments: membersToSave.map(member => ({
                        id: member.source_member_directory_id || member.id,
                        full_name: member.full_name,
                        phone: member.phone || '',
                        group_id: member.group_id
                            ? liveGroupIdByBoardGroupId.get(member.group_id) || member.group_id
                            : null,
                        role_in_group: member.role_in_group || 'member',
                        family_name: member.family_name || null,
                        spouse_name: member.spouse_name || null,
                        children_info: member.children_info || null,
                        birth_date: member.birth_date || null,
                        wedding_anniversary: member.wedding_anniversary || null,
                        notes: member.notes || null,
                        avatar_url: member.avatar_url || null,
                        person_id: member.person_id || null,
                        phase2_person_id: member.phase2_person_id || null,
                        profile_id: member.profile_id || null,
                    })),
                    effectiveWeekDate: getCurrentSundayInputValue(),
                });

                await assertPhase2MemberDirectorySync(
                    supabase,
                    savedDirectoryIds,
                    '현재 시즌 조편성 저장'
                );

                await updateCurrentRegroupingGroupPeriods(supabase, {
                    seasonId,
                    groups: buildRegroupingSeasonGroupsPayload(seasonArchivedGroups),
                });
                await saveRegroupingSeasonDraft(supabase, {
                    seasonId,
                    groups: buildRegroupingSeasonGroupsPayload(seasonPlanGroupsToSave),
                    assignments: buildRegroupingSeasonAssignmentsPayload(membersToSave),
                });
                const reloaded = await fetchSeasonPlanBoard(seasonId);

                setGroups(reloaded.activeGroups);
                setSeasonArchivedGroups(reloaded.endedGroups);
                setLocalMembers(reloaded.members);
                setMembers(reloaded.members);
                setHasChanges(false);
                setBoardBaselineGroups(JSON.parse(JSON.stringify(reloaded.activeGroups)));
                setBoardBaselineArchivedGroups(JSON.parse(JSON.stringify(reloaded.endedGroups)));
                setBoardBaselineMembers(JSON.parse(JSON.stringify(reloaded.members)));
                await fetchRegroupingSeasons(selectedChurch.id, selectedDepartment.id);
                alert('현재 시즌 조편성을 저장했습니다.');
                return;
            }

            const result = await saveRegroupingSeasonDraft(supabase, {
                seasonId,
                groups: buildRegroupingSeasonGroupsPayload(seasonPlanGroupsToSave),
                assignments: buildRegroupingSeasonAssignmentsPayload(membersToSave),
            });

            const reloaded = await fetchSeasonPlanBoard(seasonId);
            setGroups(reloaded.activeGroups);
            setSeasonArchivedGroups(reloaded.endedGroups);
            setLocalMembers(reloaded.members);
            setHasChanges(false);
            setBoardBaselineGroups(JSON.parse(JSON.stringify(reloaded.activeGroups)));
            setBoardBaselineArchivedGroups(JSON.parse(JSON.stringify(reloaded.endedGroups)));
            setBoardBaselineMembers(JSON.parse(JSON.stringify(reloaded.members)));
            await fetchRegroupingSeasons(selectedChurch.id, selectedDepartment.id);
            alert(`시즌 초안이 저장되었습니다. 조 ${result.planGroupCount}개, 소속 ${result.assignmentCount}개`);
        } catch (error) {
            console.error('Save regrouping season draft error:', error);
            alert(error instanceof Error ? error.message : '시즌 초안 저장 중 오류가 발생했습니다.');
        } finally {
            setSaving(false);
        }
    };

    const handleLoadSeasonDraft = async (seasonId: string) => {
        const season = regroupingSeasons.find(item => item.id === seasonId);
        if (!season) return;

        if (hasChanges && !window.confirm('현재 화면의 저장되지 않은 변경 사항을 버리고 선택한 시즌 초안을 불러올까요?')) {
            return;
        }

        setSaving(true);

        try {
            const reloaded = await fetchSeasonPlanBoard(seasonId);

            setSelectedSeasonId(seasonId);
            setSeasonTitle(season.title || '');
            setSeasonEffectiveWeekDate(season.effective_week_date || getCurrentSundayInputValue());
            setSeasonEndWeekDate(season.end_week_date || addWeeksToDateInput(season.effective_week_date || getCurrentSundayInputValue(), 24));
            setGroups(reloaded.activeGroups);
            setSeasonArchivedGroups(reloaded.endedGroups);
            setLocalMembers(reloaded.members);
            setBoardBaselineGroups(JSON.parse(JSON.stringify(reloaded.activeGroups)));
            setBoardBaselineArchivedGroups(JSON.parse(JSON.stringify(reloaded.endedGroups)));
            setBoardBaselineMembers(JSON.parse(JSON.stringify(reloaded.members)));
            setHasChanges(false);
            setRegroupingMode('season');
            setRegroupingView('seasonEditor');
        } catch (error) {
            console.error('Load regrouping season draft error:', error);
            alert(error instanceof Error ? error.message : '시즌 초안을 불러오는 중 오류가 발생했습니다.');
        } finally {
            setSaving(false);
        }
    };

    const handleApplySeason = async () => {
        if (!selectedSeasonId) {
            alert('먼저 시즌 초안을 저장하세요.');
            return;
        }

        if (isSelectedSeasonApplied) {
            alert('이미 실제 소속에 적용된 시즌입니다.');
            return;
        }

        if (isSeasonEffectiveFuture) {
            alert('적용 주차가 아직 도래하지 않았습니다. 미래 조편성은 초안으로만 보관됩니다.');
            return;
        }

        if (!window.confirm('이 조편성 계획을 실제 소속으로 적용할까요? 적용 후에는 앱과 출석/기도 화면에 반영됩니다.')) {
            return;
        }

        setSaving(true);

        try {
            await applyRegroupingSeason(supabase, { seasonId: selectedSeasonId });
            alert('조편성 계획이 실제 소속으로 적용되었습니다.');
            await fetchData();
            setHasChanges(false);
        } catch (error) {
            console.error('Apply regrouping season error:', error);
            alert(error instanceof Error ? error.message : '조편성 계획 적용 중 오류가 발생했습니다.');
        } finally {
            setSaving(false);
        }
    };

    const fetchSeasonPlanBoard = async (seasonId: string) => {
        const [{ data: planGroups, error: groupsError }, { data: assignments, error: assignmentsError }] = await Promise.all([
            supabase
                .from('regrouping_plan_groups')
                .select('id, source_group_id, name, color_hex, sort_order, leader_person_id, starts_week_date, ends_week_date, plan_status')
                .eq('season_id', seasonId)
                .order('sort_order', { ascending: true })
                .order('name', { ascending: true }),
            supabase
                .from('regrouping_plan_assignments')
                .select(`
                    id,
                    plan_group_id,
                    person_id,
                    role_in_group,
                    sort_order,
                    source_membership_id,
                    source_member_directory_id,
                    starts_week_date,
                    ends_week_date,
                    people:person_id(display_name, normalized_phone),
                    member_directory:source_member_directory_id(full_name, phone, family_name, spouse_name, children_info, birth_date, wedding_anniversary, notes, avatar_url, profile_id)
                `)
                .eq('season_id', seasonId)
                .order('sort_order', { ascending: true }),
        ]);

        if (groupsError) throw groupsError;
        if (assignmentsError) throw assignmentsError;

        const mapped = mapRegroupingSeasonDraftToBoard({
            planGroups: planGroups || [],
            assignments: assignments || [],
        });

        return {
            activeGroups: mapped.groups.filter(group => group.plan_status !== 'ended'),
            endedGroups: mapped.groups.filter(group => group.plan_status === 'ended'),
            members: mapped.members,
        };
    };

    const handleStartBlankSeason = async () => {
        if (hasChanges && !window.confirm('현재 화면의 저장되지 않은 변경 사항을 버리고 새 조편성을 시작할까요?')) {
            return;
        }

        const defaultStartWeek = getCurrentSundayInputValue();
        const unassignedMembers = buildUnassignedRegroupingMembers(members.length > 0 ? members : localMembers);
        setRegroupingMode('season');
        setRegroupingView('seasonEditor');
        setSelectedSeasonId(null);
        setSeasonTitle('');
        setSeasonEffectiveWeekDate(defaultStartWeek);
        setSeasonEndWeekDate(addWeeksToDateInput(defaultStartWeek, 24));
        setGroups([]);
        setSeasonArchivedGroups([]);
        setLocalMembers(unassignedMembers);
        setBoardBaselineGroups([]);
        setBoardBaselineArchivedGroups([]);
        setBoardBaselineMembers(JSON.parse(JSON.stringify(unassignedMembers)));
        setHasChanges(false);
    };

    const handleRegisterCurrentSeason = async () => {
        if (!selectedChurch || !selectedDepartment) {
            alert('교회와 부서를 먼저 선택하세요.');
            return;
        }

        if (!hasActiveBoard) {
            await handleStartBlankSeason();
            return;
        }

        if (isCurrentRegistrationPeriodInvalid) {
            alert('현재 조편성 시즌 종료 주차는 시작 주차보다 빠를 수 없습니다.');
            return;
        }

        const title = `${selectedDepartment.name} 현재 조편성`;
        if (!window.confirm(`${title}을(를) 시즌으로 등록할까요? 실제 조/성도 소속은 다시 저장하지 않고, 현재 상태를 시즌 기록으로만 남깁니다.`)) {
            return;
        }

        setSaving(true);

        try {
            await registerCurrentRegroupingSeason(supabase, {
                churchId: selectedChurch.id,
                departmentId: selectedDepartment.id,
                title,
                effectiveWeekDate: currentRegistrationStartWeek,
                endWeekDate: currentRegistrationEndWeek,
            });
            await fetchRegroupingSeasons(selectedChurch.id, selectedDepartment.id);
            alert('현재 조편성을 시즌으로 등록했습니다.');
        } catch (error) {
            console.error('Register current regrouping season error:', error);
            alert(error instanceof Error ? error.message : '현재 조편성 시즌 등록 중 오류가 발생했습니다.');
        } finally {
            setSaving(false);
        }
    };

    const handleLoadCurrentBoardIntoSeason = async () => {
        if (!window.confirm('현재 조편성을 이 시즌 초안의 시작점으로 불러올까요? 지금 편집 중인 배치는 현재 소속 기준으로 덮어씁니다.')) {
            return;
        }

        await fetchData();
        setBoardBaselineGroups(JSON.parse(JSON.stringify(groups)));
        setSeasonArchivedGroups([]);
        setBoardBaselineArchivedGroups([]);
        setBoardBaselineMembers(JSON.parse(JSON.stringify(localMembers)));
        setHasChanges(true);
    };

    const handleBackToSeasonList = async () => {
        if (hasChanges && !window.confirm('저장되지 않은 변경 사항을 버리고 시즌 목록으로 돌아갈까요?')) {
            return;
        }

        setRegroupingView('list');
        setRegroupingMode('season');
        setSelectedSeasonId(null);
        setSeasonTitle('');
        setSeasonEffectiveWeekDate(getCurrentSundayInputValue());
        setSeasonEndWeekDate(addWeeksToDateInput(getCurrentSundayInputValue(), 24));
        setSeasonArchivedGroups([]);
        setHasChanges(false);
        if (currentChurchId && selectedDeptId) {
            await fetchData();
        }
    };

    const handleReset = () => {
        if (confirm('모든 변경 사항을 취소하고 초기화하시겠습니까?')) {
            setGroups(JSON.parse(JSON.stringify(boardBaselineGroups)));
            setSeasonArchivedGroups(JSON.parse(JSON.stringify(boardBaselineArchivedGroups)));
            setLocalMembers(JSON.parse(JSON.stringify(boardBaselineMembers)));
            setHasChanges(false);
        }
    };

    const displayLocalMembers = useMemo(() => normalizeRegroupingDisplayMembers(localMembers), [localMembers]);
    const hasActiveBoard = groups.length > 0 || displayLocalMembers.some(member => Boolean(member.group_id));

    const filteredLocalMembers = useMemo(() => {
        if (!searchTerm) return displayLocalMembers;
        return displayLocalMembers.filter(m =>
            m.full_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
            m.phone?.includes(searchTerm)
        );
    }, [displayLocalMembers, searchTerm]);

    const sortedMembers = useMemo(() => {
        const dept = departments.find(d => d.id === selectedDeptId);
        if (dept?.profile_mode !== 'couple') return filteredLocalMembers;

        // Group couples together
        const seen = new Set<string>();
        const result: any[] = [];

        filteredLocalMembers.forEach(m => {
            if (seen.has(m.id)) return;

            result.push(m);
            seen.add(m.id);

            if (m.spouse_name) {
                const spouse = filteredLocalMembers.find(s =>
                    !seen.has(s.id) &&
                    s.full_name === m.spouse_name &&
                    s.spouse_name === m.full_name &&
                    s.group_id === m.group_id
                );
                if (spouse) {
                    result.push(spouse);
                    seen.add(spouse.id);
                }
            }
        });

        return result;
    }, [filteredLocalMembers, departments, selectedDeptId]);

    const seasonNewGroups = useMemo(() => (
        groups.filter(group => !group.source_group_id)
    ), [groups]);

    const movedSeasonMembers = useMemo(() => {
        const baselineById = new Map(boardBaselineMembers.map(member => [member.id, member]));
        const baselineGroups = [...boardBaselineGroups, ...boardBaselineArchivedGroups];
        return displayLocalMembers
            .map(member => {
                const baseline = baselineById.get(member.id);
                const nextGroupId = member.group_id || null;
                if (!baseline) {
                    if (!nextGroupId) return null;
                    const nextGroup = groups.find(group => group.id === nextGroupId);
                    return {
                        id: member.id,
                        full_name: member.full_name,
                        changeType: 'added' as const,
                        previousGroupName: '추가 소속',
                        nextGroupName: nextGroup?.name || member.group_name || '미편성',
                        starts_week_date: member.starts_week_date || seasonEffectiveWeekDate,
                        ends_week_date: member.ends_week_date || seasonEndWeekDate || null,
                    };
                }
                const previousGroupId = baseline.group_id || null;
                if (previousGroupId === nextGroupId) return null;
                const previousGroup = baselineGroups.find(group => group.id === previousGroupId);
                const nextGroup = groups.find(group => group.id === nextGroupId);
                return {
                    id: member.id,
                    full_name: member.full_name,
                    changeType: 'moved' as const,
                    previousGroupName: previousGroup?.name || '미편성',
                    nextGroupName: nextGroup?.name || '미편성',
                    starts_week_date: member.starts_week_date || seasonEffectiveWeekDate,
                    ends_week_date: member.ends_week_date || seasonEndWeekDate || null,
                };
            })
            .filter((member): member is NonNullable<typeof member> => Boolean(member));
    }, [boardBaselineArchivedGroups, boardBaselineGroups, boardBaselineMembers, displayLocalMembers, groups, seasonEffectiveWeekDate, seasonEndWeekDate]);

    const currentChurchName = useMemo(() => {
        if (!currentChurchId) return null;
        return churches.find(c => c.id === currentChurchId)?.name || null;
    }, [currentChurchId, churches]);

    const stats = useMemo(() => {
        const people = new Map<string, { assigned: boolean }>();

        displayLocalMembers.forEach(member => {
            const identityKey = getMemberIdentityKey(member);
            const current = people.get(identityKey) || { assigned: false };
            people.set(identityKey, {
                assigned: current.assigned || Boolean(member.group_id)
            });
        });

        const total = people.size;
        const assigned = Array.from(people.values()).filter(person => person.assigned).length;
        const unassigned = total - assigned;
        return { total, assigned, unassigned };
    }, [displayLocalMembers, getMemberIdentityKey]);

    if (loading) {
        return (
            <div className="h-96 flex flex-col items-center justify-center gap-4">
                <Loader2 className="w-10 h-10 text-indigo-600 animate-spin" />
                <p className="text-slate-400 font-black text-xs uppercase tracking-widest">데이터 로딩 중...</p>
            </div>
        );
    }

    return (
        <div className="space-y-8 sm:space-y-10 max-w-7xl mx-auto">
            {/* Page Header */}
            <header className="space-y-6 px-2">
                <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
                    <div className="space-y-2">
                        <h1 className="text-3xl font-black text-slate-950 dark:text-white tracking-tight">조편성 관리</h1>
                        <p className="text-slate-500 dark:text-slate-500 font-semibold text-sm tracking-tight">
                            {isMaster
                                ? <><span className="font-bold text-slate-900 dark:text-white">{currentChurchName || '교회 선택'}</span> · 시즌별 조편성과 현재 소속을 관리합니다.</>
                                : <><span className="font-bold text-slate-900 dark:text-white">{currentChurchName} · {departments.find(d => d.id === selectedDeptId)?.name || '부서'}</span> 시즌별 조편성과 현재 소속을 관리합니다.</>
                            }
                        </p>
                    </div>

                    <div className="grid grid-cols-3 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
                        <div className="px-4 py-3">
                            <span className="block text-[10px] font-black uppercase tracking-widest text-slate-400">전체</span>
                            <span className="mt-1 block text-lg font-black text-slate-950 dark:text-white">{stats.total}</span>
                        </div>
                        <div className="border-x border-slate-100 px-4 py-3 dark:border-slate-800">
                            <span className="block text-[10px] font-black uppercase tracking-widest text-slate-400">편성</span>
                            <span className="mt-1 block text-lg font-black text-blue-600">{stats.assigned}</span>
                        </div>
                        <div className="px-4 py-3">
                            <span className="block text-[10px] font-black uppercase tracking-widest text-slate-400">미편성</span>
                            <span className="mt-1 block text-lg font-black text-rose-600">{stats.unassigned}</span>
                        </div>
                    </div>
                </div>
            </header>

            {isMaster && (
                <div className="flex items-center gap-3 px-2">
                    <div className="relative group">
                        <div className="absolute left-4 top-1/2 -translate-y-1/2">
                            <Church className="w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                        </div>
                        <select
                            value={currentChurchId || ''}
                            onChange={async (e) => {
                                const newChurchId = e.target.value;
                                setCurrentChurchId(newChurchId);
                                setSelectedDeptId(null);
                                setSelectedSeasonId(null);
                                setRegroupingSeasons([]);
                                setSeasonTitle('');
                                setSeasonEffectiveWeekDate(getCurrentSundayInputValue());
                                setSeasonEndWeekDate(addWeeksToDateInput(getCurrentSundayInputValue(), 24));
                                setCurrentRegistrationStartWeek(getCurrentSundayInputValue());
                                setCurrentRegistrationEndWeek(addWeeksToDateInput(getCurrentSundayInputValue(), 24));
                                setRegroupingView('list');
                                setSeasonArchivedGroups([]);
                                setBoardBaselineArchivedGroups([]);
                                await fetchDepartments(newChurchId);
                            }}
                            className="appearance-none h-10 pl-10 pr-10 bg-white dark:bg-slate-900 border border-slate-200/80 dark:border-slate-800 rounded-xl font-bold text-xs text-slate-700 dark:text-slate-200 cursor-pointer focus:outline-none focus:ring-4 focus:ring-blue-500/10 transition-all"
                        >
                            <option value="" disabled>교회 선택</option>
                            {churches.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                        </select>
                        <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-400 pointer-events-none" />
                    </div>

                    <div className="relative group">
                        <select
                            value={selectedDeptId || ''}
                            onChange={(e) => {
                                const newDeptId = e.target.value;
                                setSelectedDeptId(newDeptId);
                                setSelectedSeasonId(null);
                                setSeasonTitle('');
                                setSeasonEffectiveWeekDate(getCurrentSundayInputValue());
                                setSeasonEndWeekDate(addWeeksToDateInput(getCurrentSundayInputValue(), 24));
                                setCurrentRegistrationStartWeek(getCurrentSundayInputValue());
                                setCurrentRegistrationEndWeek(addWeeksToDateInput(getCurrentSundayInputValue(), 24));
                                setRegroupingView('list');
                                if (currentChurchId) {
                                    fetchGroups(newDeptId);
                                    fetchMembers(currentChurchId, newDeptId);
                                    fetchRegroupingSeasons(currentChurchId, newDeptId);
                                }
                            }}
                            className="appearance-none h-10 pl-5 pr-10 bg-white dark:bg-slate-900 border border-slate-200/80 dark:border-slate-800 rounded-xl font-bold text-xs text-slate-700 dark:text-slate-200 cursor-pointer focus:outline-none focus:ring-4 focus:ring-blue-500/10 transition-all"
                        >
                            <option value="" disabled>부서 선택</option>
                            {departments.map(d => <option key={d.id} value={d.id}>{d.name}</option>)}
                        </select>
                        <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-400 pointer-events-none" />
                    </div>
                </div>
            )}

            {regroupingView === 'list' ? (
                <section className="space-y-6">
                    <div className="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
                        <div className="flex flex-col gap-5 xl:flex-row xl:items-center xl:justify-between">
                            <div className="min-w-0">
                                <span className={cn(
                                    "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-black",
                                    isCurrentAppliedSeasonExpired
                                        ? "border-amber-200 bg-amber-50 text-amber-700"
                                        : "border-emerald-200 bg-emerald-50 text-emerald-700"
                                )}>
                                    {isCurrentAppliedSeasonExpired ? <AlertCircle className="h-3.5 w-3.5" /> : <CheckCircle2 className="h-3.5 w-3.5" />}
                                    {isCurrentAppliedSeasonExpired ? '다음 시즌 필요' : '현재 사용 중'}
                                </span>
                                <h2 className="mt-3 text-xl font-black tracking-tight text-slate-950 dark:text-white">
                                    {currentAppliedSeason?.title || `${selectedDepartment?.name || '선택 부서'} 현재 조편성`}
                                </h2>
                                <p className="mt-1 text-sm font-semibold leading-6 text-slate-500">
                                    {isCurrentAppliedSeasonExpired
                                        ? '다음 시즌이 없어 마지막 적용 시즌을 임시 기준으로 사용합니다. 새 시즌을 만들어 적용하세요.'
                                        : '현재 날짜에 앱, 출석, 기도 화면에서 사용되는 실제 조편성입니다.'}
                                </p>
                                <p className="mt-2 text-xs font-bold text-slate-400">
                                    {currentAppliedSeason
                                        ? formatRegroupingPeriodLabel(currentAppliedSeason.effective_week_date, currentAppliedSeason.end_week_date)
                                        : hasActiveBoard
                                            ? '시즌 기록은 아직 없지만 현재 활성 조편성 명단이 있습니다. 이 명단을 기준으로 시즌을 만들 수 있습니다.'
                                            : '아직 현재 날짜가 포함된 시즌이 없습니다. 현재 명단을 기준으로 새 시즌을 만들 수 있습니다.'}
                                </p>
                            </div>
                            <div className="flex flex-col gap-3 xl:items-end">
                                {!currentAppliedSeason && hasActiveBoard && (
                                    <div className="flex flex-wrap gap-2 rounded-2xl border border-slate-200 bg-slate-50/80 p-2 dark:border-slate-800 dark:bg-slate-950/40">
                                        <label className="space-y-1">
                                            <span className="block text-[10px] font-black text-slate-400">시즌 시작</span>
                                            <input
                                                type="date"
                                                value={currentRegistrationStartWeek}
                                                onChange={(event) => {
                                                    const nextStart = snapDateInputToSunday(event.target.value);
                                                    setCurrentRegistrationStartWeek(nextStart);
                                                    if (currentRegistrationEndWeek < nextStart) {
                                                        setCurrentRegistrationEndWeek(addWeeksToDateInput(nextStart, 24));
                                                    }
                                                }}
                                                className="h-9 w-[148px] rounded-xl border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 outline-none transition focus:ring-4 focus:ring-blue-500/10 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-100"
                                            />
                                        </label>
                                        <label className="space-y-1">
                                            <span className="block text-[10px] font-black text-slate-400">마지막 주차</span>
                                            <input
                                                type="date"
                                                value={currentRegistrationEndWeek}
                                                min={currentRegistrationStartWeek}
                                                onChange={(event) => setCurrentRegistrationEndWeek(snapDateInputToSunday(event.target.value))}
                                                className={cn(
                                                    "h-9 w-[148px] rounded-xl border bg-white px-3 text-xs font-black text-slate-700 outline-none transition focus:ring-4 dark:bg-slate-900 dark:text-slate-100",
                                                    isCurrentRegistrationPeriodInvalid
                                                        ? "border-rose-200 focus:ring-rose-500/10"
                                                    : "border-slate-200 focus:ring-blue-500/10 dark:border-slate-800"
                                            )}
                                        />
                                            <span className="block text-[10px] font-black text-slate-400">
                                                실제 종료 {formatRegroupingDateLabel(addDaysToDateInput(currentRegistrationEndWeek, 6))}
                                            </span>
                                        </label>
                                    </div>
                                )}
                                <button
                                    type="button"
                                    onClick={() => {
                                        if (currentAppliedSeason && !isCurrentAppliedSeasonExpired) {
                                            handleLoadSeasonDraft(currentAppliedSeason.id);
                                            return;
                                        }
                                        if (hasActiveBoard) {
                                            if (isCurrentAppliedSeasonExpired) {
                                                handleStartBlankSeason();
                                            } else {
                                                handleRegisterCurrentSeason();
                                            }
                                            return;
                                        }
                                        handleStartBlankSeason();
                                    }}
                                    disabled={!selectedChurch || !selectedDepartment || saving || (!currentAppliedSeason && isCurrentRegistrationPeriodInvalid)}
                                    className="inline-flex h-10 items-center justify-center gap-2 rounded-xl bg-slate-950 px-4 text-sm font-black text-white transition hover:bg-slate-800 active:scale-95 disabled:cursor-not-allowed disabled:bg-slate-300 dark:bg-white dark:text-slate-950"
                                >
                                    {saving && !currentAppliedSeason ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
                                    {currentAppliedSeason
                                        ? isCurrentAppliedSeasonExpired ? '다음 시즌 만들기' : '현재 시즌 열기'
                                        : hasActiveBoard ? '현재 조편성을 시즌으로 등록' : '빈 시즌 만들기'}
                                </button>
                            </div>
                        </div>
                    </div>

                    <div className="overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
                        <div className="flex flex-col gap-5 border-b border-slate-100 px-6 py-5 dark:border-slate-800 lg:flex-row lg:items-center lg:justify-between">
                            <div>
                                <h2 className="text-xl font-black tracking-tight text-slate-950 dark:text-white">{viewTitle}</h2>
                                <p className="mt-1 text-sm font-semibold text-slate-500 dark:text-slate-400">{viewDescription}</p>
                            </div>
                            <button
                                type="button"
                                onClick={handleStartBlankSeason}
                                disabled={!selectedChurch || !selectedDepartment || saving}
                                className="inline-flex h-10 items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 text-sm font-black text-white transition hover:bg-blue-500 active:scale-95 disabled:cursor-not-allowed disabled:bg-slate-300"
                            >
                                <Plus className="h-4 w-4" />
                                새 조편성 만들기
                            </button>
                        </div>

                        {regroupingSeasons.length === 0 ? (
                            <div className="flex min-h-[280px] flex-col items-center justify-center px-6 py-12 text-center">
                                <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-blue-50 text-blue-500">
                                    <CalendarDays className="h-6 w-6" />
                                </div>
                                <h3 className="mt-5 text-xl font-black text-slate-900 dark:text-white">아직 저장된 조편성 시즌이 없습니다</h3>
                                <p className="mt-2 max-w-md text-sm font-semibold leading-6 text-slate-500">
                                    새 조편성을 만들고 적용 시작 주차를 정하면, 적용 전까지는 초안으로 보관됩니다.
                                </p>
                                <button
                                    type="button"
                                    onClick={handleStartBlankSeason}
                                    className="mt-6 inline-flex h-10 items-center gap-2 rounded-xl bg-blue-600 px-4 text-sm font-black text-white transition hover:bg-blue-500 active:scale-95"
                                >
                                    <Plus className="h-4 w-4" />
                                    빈 조편성 만들기
                                </button>
                            </div>
                        ) : (
                            <div className="overflow-x-auto">
                                <table className="w-full min-w-[760px] text-left">
                                    <thead className="border-b border-slate-100 bg-slate-50/70 text-[11px] font-black uppercase tracking-widest text-slate-400 dark:border-slate-800 dark:bg-slate-950/40">
                                        <tr>
                                            <th className="px-6 py-3">시즌</th>
                                            <th className="px-4 py-3">상태</th>
                                            <th className="px-4 py-3">적용 기간</th>
                                            <th className="px-4 py-3">수정일</th>
                                            <th className="px-6 py-3 text-right">작업</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                                        {regroupingSeasons.map((season) => {
                                            const statusMeta = getSeasonStatusMeta(season, todayInputValue);
                                            const StatusIcon = statusMeta.icon;
                                            const canApplyThisSeason = season.status !== 'applied' && season.effective_week_date <= todayInputValue;

                                            return (
                                                <tr key={season.id} className="transition hover:bg-slate-50/80 dark:hover:bg-slate-950/40">
                                                    <td className="px-6 py-4">
                                                        <p className="font-black text-slate-950 dark:text-white">{season.title}</p>
                                                        <p className="mt-1 text-xs font-semibold text-slate-500">{statusMeta.description}</p>
                                                    </td>
                                                    <td className="px-4 py-4">
                                                        <span className={cn("inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-black", statusMeta.className)}>
                                                            <StatusIcon className="h-3.5 w-3.5" />
                                                            {statusMeta.label}
                                                        </span>
                                                    </td>
                                                    <td className="px-4 py-4">
                                                        <p className="text-sm font-black text-slate-800 dark:text-slate-100">{formatRegroupingWeekLabel(season.effective_week_date)}</p>
                                                        <p className="mt-1 text-xs font-semibold text-slate-400">{formatRegroupingPeriodLabel(season.effective_week_date, season.end_week_date)}</p>
                                                    </td>
                                                    <td className="px-4 py-4 text-xs font-semibold text-slate-500">
                                                        {formatRegroupingDateLabel((season.updated_at || season.created_at || '').slice(0, 10))}
                                                    </td>
                                                    <td className="px-6 py-4">
                                                        <div className="flex justify-end gap-2">
                                                            <button
                                                                type="button"
                                                                onClick={() => handleLoadSeasonDraft(season.id)}
                                                                className="inline-flex h-9 items-center justify-center rounded-xl border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 transition hover:border-blue-200 hover:text-blue-600 active:scale-95 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-200"
                                                            >
                                                                열기
                                                            </button>
                                                            {canApplyThisSeason && (
                                                                <button
                                                                    type="button"
                                                                    onClick={async () => {
                                                                        await handleLoadSeasonDraft(season.id);
                                                                    }}
                                                                    className="inline-flex h-9 items-center justify-center rounded-xl bg-emerald-600 px-3 text-xs font-black text-white transition hover:bg-emerald-500 active:scale-95"
                                                                >
                                                                    적용 검토
                                                                </button>
                                                            )}
                                                        </div>
                                                    </td>
                                                </tr>
                                            );
                                        })}
                                    </tbody>
                                </table>
                            </div>
                        )}
                    </div>
                </section>
            ) : (
                <section className="z-30 space-y-3 rounded-2xl border border-slate-200 bg-white/95 p-3 shadow-sm backdrop-blur-xl xl:sticky xl:top-20 xl:rounded-3xl xl:p-4 dark:border-slate-800 dark:bg-slate-950/95">
                    <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                        <div className="min-w-0">
                            <button
                                type="button"
                                onClick={handleBackToSeasonList}
                                className="mb-2 inline-flex items-center gap-2 text-xs font-black text-slate-400 transition hover:text-blue-600"
                            >
                                <ArrowLeft className="h-4 w-4" />
                                시즌 목록으로
                            </button>
                            <div className="flex flex-wrap items-center gap-3">
                                <h2 className="text-xl font-black tracking-tight text-slate-950 dark:text-white">{viewTitle}</h2>
                                <Tooltip content={editorHelpText} position="bottom">
                                    <button
                                        type="button"
                                        className="inline-flex h-7 w-7 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-400 transition hover:border-blue-200 hover:text-blue-600 dark:border-slate-800 dark:bg-slate-900"
                                        aria-label="조편성 설정 설명"
                                    >
                                        <HelpCircle className="h-4 w-4" />
                                    </button>
                                </Tooltip>
                                {regroupingMode === 'season' && selectedSeason && (
                                    <span className={cn("inline-flex items-center rounded-full border px-3 py-1 text-[11px] font-black", getSeasonStatusMeta(selectedSeason, todayInputValue).className)}>
                                        {getSeasonStatusMeta(selectedSeason, todayInputValue).label}
                                    </span>
                                )}
                                {regroupingMode === 'live' && (
                                    <span className="inline-flex items-center gap-1.5 rounded-full border border-amber-200 bg-amber-50 px-3 py-1 text-[11px] font-black text-amber-700">
                                        <ShieldAlert className="h-3.5 w-3.5" />
                                        즉시 반영
                                    </span>
                                )}
                            </div>
                        </div>

                        <div className="grid grid-cols-2 gap-2 sm:flex sm:flex-row">
                            <button
                                onClick={handleReset}
                                className="inline-flex h-10 items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 transition hover:border-rose-200 hover:text-rose-600 active:scale-95 sm:px-4 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300"
                            >
                                <RotateCcw className="h-4 w-4" />
                                변경 취소
                            </button>
                            {regroupingMode === 'live' ? (
                                <button
                                    onClick={handleSave}
                                    disabled={saving || !hasChanges}
                                    className={cn(
                                        "inline-flex h-10 items-center justify-center gap-2 rounded-xl px-3 text-xs font-black text-white transition active:scale-95 disabled:cursor-not-allowed disabled:bg-slate-300 sm:px-5",
                                        hasChanges ? "bg-amber-500 hover:bg-amber-400" : "bg-slate-300"
                                    )}
                                >
                                    {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                                    {saving ? '저장 중...' : '보정 저장'}
                                </button>
                            ) : (
                                <>
                                    <button
                                        type="button"
                                        onClick={handleSaveSeasonDraft}
                                        disabled={saving || !canSaveSeasonDraft}
                                        className="inline-flex h-10 items-center justify-center gap-2 rounded-xl bg-blue-600 px-3 text-xs font-black text-white transition hover:bg-blue-500 active:scale-95 disabled:cursor-not-allowed disabled:bg-slate-300 sm:px-5"
                                    >
                                        {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                                        {isSelectedCurrentAppliedSeason ? '현재 시즌 저장' : '초안 저장'}
                                    </button>
                                    <button
                                        type="button"
                                        onClick={handleApplySeason}
                                        disabled={saving || !canApplySeason}
                                        className="inline-flex h-10 items-center justify-center gap-2 rounded-xl bg-emerald-600 px-3 text-xs font-black text-white transition hover:bg-emerald-500 active:scale-95 disabled:cursor-not-allowed disabled:bg-slate-300 sm:px-5"
                                    >
                                        {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />}
                                        {isSelectedSeasonApplied ? '적용 완료' : isSeasonEffectiveFuture ? '적용 주차 대기' : '실제 소속에 적용'}
                                    </button>
                                </>
                            )}
                        </div>
                    </div>

                    <details className="group rounded-xl border border-slate-200 bg-slate-50/70 xl:hidden dark:border-slate-800 dark:bg-slate-900/60">
                        <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-3 py-2.5">
                            <div className="flex min-w-0 items-center gap-2">
                                <SlidersHorizontal className="h-4 w-4 shrink-0 text-blue-600" />
                                <span className="shrink-0 text-xs font-black text-slate-900 dark:text-white">시즌 설정</span>
                                <span className="truncate text-[11px] font-bold text-slate-500">{editorPeriodSummary}</span>
                            </div>
                            <ChevronDown className="h-4 w-4 shrink-0 text-slate-400 transition group-open:rotate-180" />
                        </summary>
                        <div className="grid gap-2 border-t border-slate-200 px-3 py-3 dark:border-slate-800">
                            {regroupingMode === 'season' ? (
                                <>
                                    <label className="space-y-1">
                                        <span className="text-[10px] font-black uppercase tracking-[0.16em] text-slate-500">시즌 이름</span>
                                        <input
                                            type="text"
                                            value={seasonTitle}
                                            onChange={(event) => setSeasonTitle(event.target.value)}
                                            disabled={isSelectedSeasonLocked}
                                            placeholder={`${selectedDepartment?.name || '선택 부서'} 다음 시즌 조편성`}
                                            className="h-9 w-full rounded-lg border border-slate-200 bg-white px-3 text-xs font-bold text-slate-700 outline-none transition focus:ring-4 focus:ring-blue-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                        />
                                    </label>
                                    {isSelectedCurrentAppliedSeason ? (
                                        <div className="rounded-xl border border-blue-100 bg-white p-3 dark:border-blue-500/20 dark:bg-slate-950">
                                            <span className="text-[10px] font-black uppercase tracking-[0.16em] text-blue-600">현재 시즌 기간</span>
                                            <p className="mt-1 text-xs font-black text-slate-700 dark:text-slate-100">
                                                {formatRegroupingPeriodLabel(seasonEffectiveWeekDate, seasonEndWeekDate)}
                                            </p>
                                            <p className="mt-2 text-[11px] font-bold leading-5 text-slate-500">
                                                조 생성/종료와 성도 이동은 아래 기간 조정 패널에서 각각의 시작·마지막 주차를 수정합니다.
                                            </p>
                                        </div>
                                    ) : (
                                        <div className="rounded-xl border border-slate-200 bg-white p-3 dark:border-slate-800 dark:bg-slate-950">
                                            <div className="mb-2 flex items-center justify-between gap-3">
                                                <span className="text-[10px] font-black uppercase tracking-[0.16em] text-slate-500">기간 설정</span>
                                                <span className="truncate text-[11px] font-black text-blue-600 dark:text-blue-300">{editorPeriodSummary}</span>
                                            </div>
                                            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                                                <label className="space-y-1.5">
                                                    <span className="text-[11px] font-black text-slate-500">시작</span>
                                                    <input
                                                        type="date"
                                                        value={seasonEffectiveWeekDate}
                                                        disabled={isSelectedSeasonLocked}
                                                        onChange={(event) => {
                                                            const nextStart = snapDateInputToSunday(event.target.value);
                                                            setSeasonEffectiveWeekDate(nextStart);
                                                            if (seasonEndWeekDate < nextStart) {
                                                                setSeasonEndWeekDate(addWeeksToDateInput(nextStart, 24));
                                                            }
                                                            setHasChanges(true);
                                                        }}
                                                        className="h-9 w-full rounded-lg border border-slate-200 bg-slate-50 px-3 text-xs font-black text-slate-700 outline-none transition focus:bg-white focus:ring-4 focus:ring-blue-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-100"
                                                    />
                                                    <span className="block text-[10px] font-black text-blue-600 dark:text-blue-300">{formatRegroupingWeekLabel(seasonEffectiveWeekDate)}</span>
                                                </label>
                                                <label className="space-y-1.5">
                                                    <span className="text-[11px] font-black text-slate-500">종료</span>
                                                    <input
                                                        type="date"
                                                        value={seasonEndWeekDate}
                                                        min={seasonEffectiveWeekDate}
                                                        disabled={isSelectedSeasonLocked}
                                                        onChange={(event) => {
                                                            setSeasonEndWeekDate(snapDateInputToSunday(event.target.value));
                                                            setHasChanges(true);
                                                        }}
                                                        className={cn(
                                                            "h-9 w-full rounded-lg border bg-slate-50 px-3 text-xs font-black text-slate-700 outline-none transition focus:bg-white focus:ring-4 disabled:bg-slate-100 disabled:text-slate-400 dark:bg-slate-900 dark:text-slate-100",
                                                            isSeasonPeriodInvalid
                                                                ? "border-rose-200 focus:ring-rose-500/10"
                                                                : "border-slate-200 focus:ring-blue-500/10 dark:border-slate-800"
                                                        )}
                                                    />
                                                    <span className={cn(
                                                        "block text-[10px] font-black",
                                                        isSeasonPeriodInvalid ? "text-rose-600" : "text-blue-600 dark:text-blue-300"
                                                    )}>
                                                        {isSeasonPeriodInvalid ? '기간 확인 필요' : `${formatRegroupingWeekLabel(seasonEndWeekDate)} · ${formatRegroupingDateLabel(addDaysToDateInput(seasonEndWeekDate, 6))}까지`}
                                                    </span>
                                                </label>
                                            </div>
                                        </div>
                                    )}
                                    {!selectedSeasonId && !isSelectedCurrentAppliedSeason && (
                                        <button
                                            type="button"
                                            onClick={handleLoadCurrentBoardIntoSeason}
                                            className="inline-flex h-9 w-fit items-center justify-center rounded-lg border border-slate-200 bg-white px-3 text-[11px] font-black text-blue-600 transition hover:bg-blue-50 active:scale-95 dark:border-slate-800"
                                        >
                                            현재 조편성 불러오기
                                        </button>
                                    )}
                                </>
                            ) : (
                                <label className="space-y-1">
                                    <span className="text-[10px] font-black uppercase tracking-[0.16em] text-amber-600">보정 기준 주차</span>
                                    <div className="grid grid-cols-[1fr_auto] gap-2">
                                        <input
                                            type="date"
                                            value={effectiveWeekDate}
                                            max={getCurrentSundayInputValue()}
                                            onChange={(event) => {
                                                setEffectiveWeekDate(snapDateInputToSunday(event.target.value));
                                                setHasChanges(true);
                                            }}
                                            className="h-9 min-w-0 rounded-lg border border-amber-100 bg-white px-3 text-xs font-black text-slate-700 outline-none transition focus:ring-4 focus:ring-amber-500/10"
                                        />
                                        <span className="inline-flex h-9 items-center rounded-lg bg-white px-3 text-[11px] font-black text-amber-700">
                                            {formatRegroupingWeekLabel(effectiveWeekDate)}
                                        </span>
                                    </div>
                                </label>
                            )}
                        </div>
                    </details>

                    <div className={cn(
                        "hidden gap-3 rounded-2xl border p-4 xl:grid xl:grid-cols-[minmax(220px,1fr)_minmax(200px,0.75fr)_minmax(200px,0.75fr)_auto]",
                        regroupingMode === 'live'
                            ? "border-amber-200 bg-amber-50/70"
                            : "border-slate-200 bg-slate-50/70 dark:border-slate-800 dark:bg-slate-900/60"
                    )}>
                        {regroupingMode === 'season' ? (
                            <>
                                <label className="space-y-1.5 md:col-span-2 xl:col-span-1">
                                    <span className="text-[10px] font-black uppercase tracking-[0.18em] text-slate-500">시즌 이름</span>
                                    <input
                                        type="text"
                                        value={seasonTitle}
                                        onChange={(event) => setSeasonTitle(event.target.value)}
                                        disabled={isSelectedSeasonLocked}
                                        placeholder={`${selectedDepartment?.name || '선택 부서'} 다음 시즌 조편성`}
                                        className="h-10 w-full rounded-xl border border-slate-200 bg-white px-3 text-sm font-bold text-slate-700 outline-none transition focus:ring-4 focus:ring-blue-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                    />
                                </label>
                                {isSelectedCurrentAppliedSeason ? (
                                    <>
                                        <div className="space-y-1.5">
                                            <span className="text-[10px] font-black uppercase tracking-[0.18em] text-slate-500">시즌 기간</span>
                                            <div className="flex h-10 items-center rounded-xl border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100">
                                                {formatRegroupingPeriodLabel(seasonEffectiveWeekDate, seasonEndWeekDate)}
                                            </div>
                                        </div>
                                        <div className="flex items-center justify-between gap-3 rounded-xl bg-white px-4 py-3 text-xs font-black text-slate-600 xl:col-span-2 dark:bg-slate-950 dark:text-slate-300">
                                            <span>각 조/성도별 기간은 아래 기간 조정 패널에서 수정합니다</span>
                                            <Tooltip content="현재 시즌 편집은 저장 전체의 적용 주차를 하나로 정하지 않습니다. 조와 성도 소속마다 시즌 안에서 유효한 시작·마지막 주차를 관리합니다.">
                                                <HelpCircle className="h-4 w-4 text-slate-400" />
                                            </Tooltip>
                                        </div>
                                    </>
                                ) : (
                                    <>
                                        <label className="space-y-1.5">
                                            <span className="text-[10px] font-black uppercase tracking-[0.18em] text-slate-500">적용 시작 주차</span>
                                            <div className="space-y-1.5">
                                                <input
                                                    type="date"
                                                    value={seasonEffectiveWeekDate}
                                                    disabled={isSelectedSeasonLocked}
                                                    onChange={(event) => {
                                                        const nextStart = snapDateInputToSunday(event.target.value);
                                                        setSeasonEffectiveWeekDate(nextStart);
                                                        if (seasonEndWeekDate < nextStart) {
                                                            setSeasonEndWeekDate(addWeeksToDateInput(nextStart, 24));
                                                        }
                                                        setHasChanges(true);
                                                    }}
                                                    className="h-10 w-full rounded-xl border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 outline-none transition focus:ring-4 focus:ring-blue-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                />
                                                <span className="block text-xs font-black text-blue-600 dark:text-blue-300">
                                                    {formatRegroupingWeekLabel(seasonEffectiveWeekDate)}
                                                </span>
                                            </div>
                                        </label>
                                        <label className="space-y-1.5">
                                            <span className="text-[10px] font-black uppercase tracking-[0.18em] text-slate-500">마지막 적용 주차</span>
                                            <div className="space-y-1.5">
                                                <input
                                                    type="date"
                                                    value={seasonEndWeekDate}
                                                    min={seasonEffectiveWeekDate}
                                                    disabled={isSelectedSeasonLocked}
                                                    onChange={(event) => {
                                                        setSeasonEndWeekDate(snapDateInputToSunday(event.target.value));
                                                        setHasChanges(true);
                                                    }}
                                                    className={cn(
                                                        "h-10 w-full rounded-xl border bg-white px-3 text-xs font-black text-slate-700 outline-none transition focus:ring-4 disabled:bg-slate-100 disabled:text-slate-400 dark:bg-slate-950 dark:text-slate-100",
                                                        isSeasonPeriodInvalid
                                                            ? "border-rose-200 focus:ring-rose-500/10"
                                                            : "border-slate-200 focus:ring-blue-500/10 dark:border-slate-800"
                                                    )}
                                                />
                                                <span className={cn(
                                                    "block text-xs font-black",
                                                    isSeasonPeriodInvalid ? "text-rose-600" : "text-blue-600 dark:text-blue-300"
                                                )}>
                                                    {isSeasonPeriodInvalid ? '기간 확인 필요' : `${formatRegroupingWeekLabel(seasonEndWeekDate)} · ${formatRegroupingDateLabel(addDaysToDateInput(seasonEndWeekDate, 6))}까지`}
                                                </span>
                                            </div>
                                        </label>
                                        <div className="flex items-center justify-between gap-3 rounded-xl bg-white px-4 py-3 text-xs font-black text-slate-600 xl:col-span-2 dark:bg-slate-950 dark:text-slate-300">
                                            <div className="flex items-center gap-2">
                                                <span>{selectedSeasonId ? '초안 보관' : '초안 시작점'}</span>
                                                <Tooltip content="미래 시즌은 설정한 기간 전체에 적용됩니다. 시즌 중간 변동은 현재 시즌에서 변경 주차를 정해 처리합니다.">
                                                    <HelpCircle className="h-4 w-4 text-slate-400" />
                                                </Tooltip>
                                            </div>
                                            {!selectedSeasonId && (
                                                <button
                                                    type="button"
                                                    onClick={handleLoadCurrentBoardIntoSeason}
                                                    className="inline-flex h-8 w-fit items-center justify-center rounded-lg border border-slate-200 px-3 text-[11px] font-black text-blue-600 transition hover:bg-blue-50 active:scale-95 dark:border-slate-800"
                                                >
                                                    현재 조편성 불러오기
                                                </button>
                                            )}
                                        </div>
                                    </>
                                )}
                            </>
                        ) : (
                            <>
                                <label className="space-y-1.5 md:col-span-2 xl:col-span-1">
                                    <span className="text-[10px] font-black uppercase tracking-[0.18em] text-amber-600">보정 기준 주차</span>
                                    <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
                                        <input
                                            type="date"
                                            value={effectiveWeekDate}
                                            max={getCurrentSundayInputValue()}
                                            onChange={(event) => {
                                                setEffectiveWeekDate(snapDateInputToSunday(event.target.value));
                                                setHasChanges(true);
                                            }}
                                            className="h-10 w-full rounded-xl border border-amber-100 bg-white px-3 text-xs font-black text-slate-700 outline-none transition focus:ring-4 focus:ring-amber-500/10 sm:w-[150px]"
                                        />
                                        <span className="rounded-full bg-white px-3 py-2 text-xs font-black text-amber-700">
                                            {formatRegroupingWeekLabel(effectiveWeekDate)}
                                        </span>
                                    </div>
                                </label>
                                <div className="flex items-center justify-between gap-3 rounded-xl bg-white px-4 py-3 text-xs font-black text-amber-800 xl:col-span-3">
                                    <span>저장 즉시 반영</span>
                                    <Tooltip content="현재/과거 보정은 저장 즉시 실제 소속에 반영됩니다. 미래 조편성은 시즌 초안에서 준비하세요.">
                                        <HelpCircle className="h-4 w-4 text-amber-500" />
                                    </Tooltip>
                                </div>
                            </>
                        )}
                    </div>

                    <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
                        <div className="relative max-w-md flex-1 group">
                            <Search className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400 transition group-focus-within:text-indigo-500" />
                            <input
                                type="text"
                                placeholder="성도 이름으로 검색..."
                                value={searchTerm}
                                onChange={(e) => setSearchTerm(e.target.value)}
                                className="h-10 w-full rounded-xl border border-slate-200 bg-white pl-10 pr-4 text-sm font-bold outline-none transition focus:ring-4 focus:ring-blue-500/10 dark:border-slate-800 dark:bg-slate-900"
                            />
                        </div>

                        <div className="flex flex-wrap items-center gap-3">
                            {departments.find(d => d.id === selectedDeptId)?.profile_mode === 'couple' && (
                                <label className="flex h-10 cursor-pointer items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 dark:border-slate-800 dark:bg-slate-900">
                                    <div className="relative">
                                        <input
                                            type="checkbox"
                                            className="sr-only"
                                            checked={autoMoveCouples}
                                            onChange={(e) => setAutoMoveCouples(e.target.checked)}
                                        />
                                        <div className={cn("h-5 w-9 rounded-full transition", autoMoveCouples ? "bg-indigo-600" : "bg-slate-300 dark:bg-slate-700")} />
                                        <div className={cn("absolute left-1 top-1 h-3 w-3 rounded-full bg-white transition", autoMoveCouples && "translate-x-4")} />
                                    </div>
                                    <Tooltip content="같은 조에 함께 있는 배우자만 같이 이동합니다. 다른 조에 떨어져 있는 배우자는 자동으로 끌고 오지 않습니다.">
                                        <span className="text-[10px] font-black uppercase tracking-widest text-slate-500">부부 동시 이동</span>
                                    </Tooltip>
                                </label>
                            )}

                            <div className="relative">
                                <button
                                    onClick={() => setShowExportMenu(!showExportMenu)}
                                    className="inline-flex h-10 items-center gap-2 rounded-xl border border-slate-200 bg-white px-4 text-xs font-black text-slate-700 transition hover:border-blue-200 hover:text-blue-600 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300"
                                >
                                    <Download className="h-4 w-4" />
                                    내보내기
                                </button>

                                {showExportMenu && (
                                    <div className="absolute right-0 top-full z-50 mt-2 w-52 overflow-hidden rounded-xl border border-slate-200 bg-white shadow-xl dark:border-slate-800 dark:bg-slate-900">
                                        <button
                                            onClick={() => {
                                                handleExportExcel();
                                                setShowExportMenu(false);
                                            }}
                                            className="flex w-full items-center gap-3 border-b border-slate-100 px-5 py-3 text-left text-xs font-bold text-slate-600 transition hover:bg-slate-50 dark:border-slate-800 dark:text-slate-300 dark:hover:bg-slate-800"
                                        >
                                            <FileDown className="h-4 w-4 text-emerald-500" />
                                            엑셀 파일로 저장
                                        </button>
                                        <button
                                            onClick={() => {
                                                handleExportImage();
                                                setShowExportMenu(false);
                                            }}
                                            disabled={isExporting}
                                            className="flex w-full items-center gap-3 px-5 py-3 text-left text-xs font-bold text-slate-600 transition hover:bg-slate-50 disabled:opacity-50 dark:text-slate-300 dark:hover:bg-slate-800"
                                        >
                                            <ImageIcon className="h-4 w-4 text-indigo-500" />
                                            {isExporting ? '추출 중...' : '이미지 파일로 저장'}
                                        </button>
                                    </div>
                                )}
                            </div>
                        </div>
                    </div>
                </section>
            )}

            {regroupingView !== 'list' && (
            <div className="bg-white/50 dark:bg-slate-900/10 rounded-3xl border border-slate-200/50 dark:border-slate-800/50 p-1 sm:p-2 shadow-inner overflow-hidden">
                <div ref={boardRef} className="relative w-full overflow-x-auto custom-scrollbar p-5 sm:p-8 bg-white/30">
                    <KanbanBoard
                        groups={groups}
                        members={sortedMembers}
                        onMoveMembers={handleMoveMembers}
                        onReorderMembers={handleReorderMembers}
                        onToggleLeader={handleToggleLeader}
                        selectedMemberIds={selectedMemberIds}
                        onMemberClick={handleMemberClick}
                        onMemberDoubleClick={handleMemberEdit}
                        onAddGroup={handleAddGroup}
                        onDeleteGroup={handleDeleteGroup}
                        onUpdateGroup={handleUpdateGroup}
                        onAddMembers={handleOpenAddMemberModal}
                        profileMode={departments.find(d => d.id === selectedDeptId)?.profile_mode}
                        autoMoveCouples={autoMoveCouples}
                        onDeleteMember={handleDeleteMember}
                        isDeletableMap={isDeletableMap}
                        readOnly={isBoardReadonly}
                    />
                </div>

                {/* Keyboard Shortcuts Legend */}
                <div className="px-8 py-4 bg-slate-50/50 dark:bg-slate-900/40 border-t border-slate-200/50 dark:border-slate-800/50 flex items-center gap-8">
                    <div className="flex items-center gap-3">
                        <div className="flex items-center gap-2">
                            <kbd className="min-w-[40px] h-7 px-2 flex items-center justify-center bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-sm text-[10px] font-black text-slate-700 dark:text-slate-300">Drag</kbd>
                            <span className="text-[10px] font-black text-slate-400 uppercase tracking-widest">이동</span>
                        </div>
                    </div>
                    <div className="w-[1px] h-3 bg-slate-200 dark:bg-slate-800" />
                    <div className="flex items-center gap-3">
                        <div className="flex items-center gap-2.5">
                            <div className="flex items-center gap-1.5">
                                <kbd className="min-w-[40px] h-7 px-2 flex items-center justify-center bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-sm text-[10px] font-black text-slate-700 dark:text-slate-300 uppercase tracking-tighter">Shift</kbd>
                                <span className="text-slate-300 font-bold">+</span>
                                <kbd className="min-w-[40px] h-7 px-2 flex items-center justify-center bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-sm text-[10px] font-black text-slate-700 dark:text-slate-300">Drag</kbd>
                            </div>
                            <div className="flex flex-col">
                                <span className="text-[10px] font-black text-indigo-500 uppercase tracking-widest">다른 조로 복사</span>
                                <span className="text-[9px] font-bold text-slate-400 bg-indigo-50 dark:bg-indigo-500/5 px-1.5 py-0.5 rounded-md mt-0.5">* Shift를 먼저 누른 채 드래그하세요</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            )}

            {regroupingView !== 'list' && regroupingMode === 'season' && isSelectedSeasonApplied && (
                <SeasonChangeHistoryPanel
                    archivedGroups={seasonArchivedGroups}
                    newGroups={seasonNewGroups}
                    movedMembers={movedSeasonMembers}
                    seasonEffectiveWeekDate={seasonEffectiveWeekDate}
                    seasonEndWeekDate={seasonEndWeekDate}
                    readOnly={isBoardReadonly}
                    onArchivedGroupStartChange={(groupId, value) => handleUpdateArchivedGroup(groupId, {
                        starts_week_date: snapDateInputToSunday(value),
                    })}
                    onArchivedGroupEndChange={(groupId, value) => handleUpdateArchivedGroup(groupId, {
                        ends_week_date: snapDateInputToSunday(value),
                    })}
                    onNewGroupStartChange={(groupId, value) => handleUpdateSeasonGroupPeriod(groupId, {
                        starts_week_date: snapDateInputToSunday(value),
                    })}
                    onNewGroupEndChange={(groupId, value) => handleUpdateSeasonGroupPeriod(groupId, {
                        ends_week_date: snapDateInputToSunday(value),
                    })}
                    onMovedMemberStartChange={(memberId, value) => handleUpdateSeasonMemberPeriod(memberId, {
                        starts_week_date: snapDateInputToSunday(value),
                    })}
                    onMovedMemberEndChange={(memberId, value) => handleUpdateSeasonMemberPeriod(memberId, {
                        ends_week_date: snapDateInputToSunday(value),
                    })}
                    onRestoreArchivedGroup={handleRestoreArchivedGroup}
                />
            )}

            {regroupingView !== 'list' && isMemberModalOpen && currentChurchId && (
                <MemberModal
                    isOpen={isMemberModalOpen}
                    onClose={() => setIsMemberModalOpen(false)}
                    onSuccess={handleMemberModalSuccess}
                    member={memberToEdit}
                    churchId={currentChurchId}
                    departmentId={selectedDeptId || undefined}
                    groupId={targetGroupForNewMember?.id || undefined}
                    groupName={targetGroupForNewMember?.name || undefined}
                    departments={departments}
                    groups={groups}
                    persistImmediately={false}
                />
            )}

            {hasChanges && (
                <div className="fixed bottom-6 right-6 flex items-center gap-2 px-4 py-3 bg-amber-50 dark:bg-amber-500/10 border border-amber-200 dark:border-amber-500/30 rounded-2xl shadow-xl z-50 animate-in fade-in slide-in-from-bottom-4">
                    <AlertCircle className="w-5 h-5 text-amber-500" />
                    <div>
                        <p className="text-[10px] font-black text-amber-600 dark:text-amber-500 uppercase tracking-widest leading-tight">알림</p>
                        <p className="text-xs font-bold text-amber-700 dark:text-amber-400">저장되지 않은 변경 사항이 있습니다</p>
                    </div>
                </div>
            )}

            {/* Hidden export template */}
            <div className="fixed -left-[10000px] top-0 pointer-events-none overflow-hidden">
                <ExportTableView
                    tableRef={exportTableRef}
                    deptName={departments.find(d => d.id === selectedDeptId)?.name || '조편성'}
                    groups={groups}
                    localMembers={displayLocalMembers}
                    profileMode={departments.find(d => d.id === selectedDeptId)?.profile_mode}
                />
            </div>
        </div>
    );
}
