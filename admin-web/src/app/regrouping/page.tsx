'use client';

/* eslint-disable @typescript-eslint/no-explicit-any */

import { useEffect, useState, useMemo, useRef, Suspense, useCallback } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Users,
    Search,
    Loader2,
    Church,
    ChevronDown,
    Layers,
    Save,
    RotateCcw,
    CheckCircle2,
    AlertCircle,
    Plus,
    UserPlus,
    Download,
    FileDown,
    Image as ImageIcon,
    Settings2
} from 'lucide-react';
import * as XLSX from 'xlsx';
import * as htmlToImage from 'html-to-image';
import { ExportTableView } from '@/components/kanban/ExportTableView';
import { cn } from '@/lib/utils';
import { KanbanBoard } from '@/components/kanban/KanbanBoard';
import { MemberModal } from '@/components/MemberModal';
import { Modal } from '@/components/Modal';
import { Tooltip } from '@/components/Tooltip';
import { assertPhase2MemberDirectorySync } from '@/lib/phase2WriteGuards';
import { saveRegroupingMemberships } from '@/lib/memberWriteRpc';

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
    const [phase2RegroupingCheck, setPhase2RegroupingCheck] = useState<{
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
                    fetchMembers(churchId, dept.id)
                ]);
            }
        }
    };

    const fetchData = async () => {
        if (currentChurchId && selectedDeptId) {
            await Promise.all([
                fetchGroups(selectedDeptId),
                fetchMembers(currentChurchId, selectedDeptId)
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
            church_id: currentChurchId
        };

        setLastAddedGroupId(newGroup.id);
        setGroups(prev => [...prev, newGroup]);
        setHasChanges(true);
    };

    const handleUpdateGroup = (id: string, updates: { name?: string, color_hex?: string }) => {
        setGroups(prev => prev.map(g => g.id === id ? { ...g, ...updates } : g));
        setHasChanges(true);
    };

    const handleDeleteGroup = (id: string) => {
        // Find members in this group and move to unassigned
        setLocalMembers(prev => prev.map(m => m.group_id === id ? { ...m, group_id: null } : m));
        setGroups(prev => prev.filter(g => g.id !== id));
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
            });

            await assertPhase2MemberDirectorySync(
                supabase,
                savedDirectoryIds,
                '조편성 저장'
            );

            // 3. Refresh State
            await fetchData();
            setHasChanges(false);
            alert('변경 사항이 성공적으로 저장되었습니다.');
        } catch (err: any) {
            console.error('Save failed:', err);
            alert(`저장 중 오류가 발생했습니다: ${err.message || '알 수 없는 오류'}`);
        } finally {
            setSaving(false);
        }
    };

    const handleReset = () => {
        if (confirm('모든 변경 사항을 취소하고 초기화하시겠습니까?')) {
            setLocalMembers(JSON.parse(JSON.stringify(members)));
            setHasChanges(false);
        }
    };

    const displayLocalMembers = useMemo(() => normalizeRegroupingDisplayMembers(localMembers), [localMembers]);

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
            <header className="space-y-8 px-2">
                <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
                    <div className="space-y-1.5">
                        <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">조편성 관리</h1>
                        <p className="text-slate-500 dark:text-slate-500 font-bold text-xs sm:text-sm tracking-tight">
                            {isMaster
                                ? <><span className="text-indigo-600 dark:text-indigo-400 font-extrabold underline decoration-indigo-200/50 dark:decoration-indigo-500/30 underline-offset-4">{currentChurchName || '교회 선택'}</span> · 시각적인 드래그 앤 드롭 방식으로 성도들의 소속 조를 관리합니다.</>
                                : <><span className="text-indigo-600 dark:text-indigo-400 font-extrabold underline decoration-indigo-200/50 dark:decoration-indigo-500/30 underline-offset-4">{currentChurchName} · {departments.find(d => d.id === selectedDeptId)?.name || '부서'}</span> 조편성 관리 페이지입니다. 성도들의 조 분배를 관리합니다.</>
                            }
                        </p>
                    </div>

                    {/* Stats Summary Integrated into Header */}
                    <div className="flex items-center gap-4 sm:gap-6 px-5 h-[44px] bg-white dark:bg-slate-900/60 backdrop-blur-md border border-slate-200 dark:border-slate-800 rounded-xl shadow-sm">
                        <div className="flex items-center gap-2">
                            <span className="text-[9px] sm:text-[10px] font-black text-slate-400 uppercase tracking-widest">전체 성도</span>
                            <span className="text-xs sm:text-sm font-black text-slate-900 dark:text-white leading-none">{stats.total}</span>
                        </div>
                        <div className="w-[1px] h-3 bg-slate-200 dark:bg-slate-800" />
                        <div className="flex items-center gap-2">
                            <span className="text-[9px] sm:text-[10px] font-black text-indigo-500 uppercase tracking-widest leading-none">편성 완료</span>
                            <span className="text-xs sm:text-sm font-black text-indigo-600 dark:text-indigo-400 leading-none">{stats.assigned}</span>
                        </div>
                        <div className="w-[1px] h-3 bg-slate-200 dark:bg-slate-800" />
                        <div className="flex items-center gap-2">
                            <span className="text-[9px] sm:text-[10px] font-black text-rose-500 uppercase tracking-widest leading-none">미편성</span>
                            <span className="text-xs sm:text-sm font-black text-rose-600 dark:text-rose-400 leading-none">{stats.unassigned}</span>
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
                                await fetchDepartments(newChurchId);
                            }}
                            className="appearance-none h-11 pl-10 pr-10 bg-white dark:bg-slate-900 border border-slate-200/60 dark:border-slate-800/60 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 cursor-pointer focus:outline-none focus:ring-4 focus:ring-indigo-500/5 transition-all shadow-sm"
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
                                if (currentChurchId) {
                                    fetchGroups(newDeptId);
                                    fetchMembers(currentChurchId, newDeptId);
                                }
                            }}
                            className="appearance-none h-11 pl-5 pr-10 bg-white dark:bg-slate-900 border border-slate-200/60 dark:border-slate-800/60 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 cursor-pointer focus:outline-none focus:ring-4 focus:ring-indigo-500/5 transition-all shadow-sm"
                        >
                            <option value="" disabled>부서 선택</option>
                            {departments.map(d => <option key={d.id} value={d.id}>{d.name}</option>)}
                        </select>
                        <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-400 pointer-events-none" />
                    </div>
                </div>
            )}

            <div className={cn(
                "mx-2 rounded-[24px] border p-4 sm:p-5 flex flex-col sm:flex-row sm:items-center justify-between gap-4 shadow-sm",
                phase2RegroupingCheck.status === 'warning'
                    ? "bg-rose-50/80 dark:bg-rose-500/10 border-rose-100 dark:border-rose-500/20"
                    : phase2RegroupingCheck.status === 'unavailable'
                        ? "bg-amber-50/80 dark:bg-amber-500/10 border-amber-100 dark:border-amber-500/20"
                        : "bg-emerald-50/80 dark:bg-emerald-500/10 border-emerald-100 dark:border-emerald-500/20"
            )}>
                <div className="flex items-start gap-3">
                    <div className={cn(
                        "w-10 h-10 rounded-2xl flex items-center justify-center shrink-0",
                        phase2RegroupingCheck.status === 'warning'
                            ? "bg-rose-100 text-rose-600 dark:bg-rose-500/20 dark:text-rose-300"
                            : phase2RegroupingCheck.status === 'unavailable'
                                ? "bg-amber-100 text-amber-600 dark:bg-amber-500/20 dark:text-amber-300"
                                : "bg-emerald-100 text-emerald-600 dark:bg-emerald-500/20 dark:text-emerald-300"
                    )}>
                        {phase2RegroupingCheck.status === 'warning'
                            ? <AlertCircle className="w-5 h-5" />
                            : <CheckCircle2 className="w-5 h-5" />}
                    </div>
                    <div className="space-y-1">
                        <div className="flex items-center gap-2">
                            <p className="text-[10px] font-black uppercase tracking-[0.2em] text-slate-500 dark:text-slate-300">
                                Phase 2 조편성 진단
                            </p>
                            <span className="px-2 py-0.5 rounded-lg bg-white/70 dark:bg-slate-900/50 text-[8px] font-black text-slate-400 uppercase tracking-widest">
                                Read Only
                            </span>
                        </div>
                        <p className={cn(
                            "text-xs sm:text-sm font-black",
                            phase2RegroupingCheck.status === 'warning'
                                ? "text-rose-700 dark:text-rose-300"
                                : phase2RegroupingCheck.status === 'unavailable'
                                    ? "text-amber-700 dark:text-amber-300"
                                    : "text-emerald-700 dark:text-emerald-300"
                        )}>
                            {phase2RegroupingCheck.message}
                        </p>
                        <p className="text-[10px] font-bold text-slate-500 dark:text-slate-400">
                            저장 전후 선택 부서의 실제 사람 수와 active 소속 수를 Phase 2와 비교합니다. 조편성 저장 로직에는 영향을 주지 않습니다.
                        </p>
                    </div>
                </div>
                <div className="grid grid-cols-3 gap-2 sm:min-w-[280px]">
                    <div className="p-3 rounded-2xl bg-white/70 dark:bg-slate-900/40 border border-white/80 dark:border-slate-800">
                        <p className="text-[8px] font-black text-slate-400 uppercase tracking-widest">legacy people</p>
                        <p className="text-lg font-black text-slate-900 dark:text-white">{phase2RegroupingCheck.legacyActivePersonCount}</p>
                        <p className="text-[8px] font-bold text-slate-400">{phase2RegroupingCheck.legacyActiveCount} rows</p>
                    </div>
                    <div className="p-3 rounded-2xl bg-white/70 dark:bg-slate-900/40 border border-white/80 dark:border-slate-800">
                        <p className="text-[8px] font-black text-slate-400 uppercase tracking-widest">phase2 people</p>
                        <p className="text-lg font-black text-slate-900 dark:text-white">{phase2RegroupingCheck.phase2ActivePersonCount}</p>
                        <p className="text-[8px] font-bold text-slate-400">{phase2RegroupingCheck.phase2ActiveCount} memberships</p>
                    </div>
                    <div className="p-3 rounded-2xl bg-white/70 dark:bg-slate-900/40 border border-white/80 dark:border-slate-800">
                        <p className="text-[8px] font-black text-slate-400 uppercase tracking-widest">issues</p>
                        <p className={cn(
                            "text-lg font-black",
                            phase2RegroupingCheck.issueCount > 0 ? "text-rose-600 dark:text-rose-300" : "text-slate-900 dark:text-white"
                        )}>
                            {phase2RegroupingCheck.issueCount}
                        </p>
                    </div>
                </div>
            </div>

            {/* Sticky Interaction Toolbar */}
            <div className="sticky top-16 sm:top-20 z-30 bg-white/80 dark:bg-slate-950/80 backdrop-blur-xl border border-slate-200 dark:border-slate-800 rounded-2xl px-6 py-4 mb-12 shadow-sm transition-all">
                <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                    <div className="flex-1 max-w-md relative group">
                        <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                        <input
                            type="text"
                            placeholder="성도 이름으로 검색..."
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                            className="w-full pl-11 pr-4 h-11 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl text-sm font-bold focus:ring-4 focus:ring-indigo-500/10 outline-none transition-all shadow-sm"
                        />
                    </div>

                    <div className="flex items-center gap-3">
                        {departments.find(d => d.id === selectedDeptId)?.profile_mode === 'couple' && (
                            <div className="flex items-center gap-2 h-11 px-4 bg-slate-50 dark:bg-slate-900 rounded-2xl border border-slate-200/60 dark:border-slate-800/60 mr-2">
                                <label className="flex items-center gap-2 cursor-pointer group">
                                    <div className="relative">
                                        <input
                                            type="checkbox"
                                            className="sr-only"
                                            checked={autoMoveCouples}
                                            onChange={(e) => setAutoMoveCouples(e.target.checked)}
                                        />
                                        <div className={cn(
                                            "w-9 h-5 rounded-full transition-colors",
                                            autoMoveCouples ? "bg-indigo-600" : "bg-slate-300 dark:bg-slate-700"
                                        )} />
                                        <div className={cn(
                                            "absolute left-1 top-1 w-3 h-3 bg-white rounded-full transition-transform",
                                            autoMoveCouples && "translate-x-4"
                                        )} />
                                    </div>
                                    <span className="text-[10px] font-black text-slate-500 uppercase tracking-widest group-hover:text-slate-900 dark:group-hover:text-slate-200 transition-colors">부부 동시 이동</span>
                                </label>
                            </div>
                        )}

                        <div className="relative group/export">
                            <Tooltip content="현재 조편성 화면을 이미지(.png)나 엑셀(.xlsx) 파일로 저장합니다.">
                                <button
                                    onClick={() => setShowExportMenu(!showExportMenu)}
                                    className="flex items-center gap-2 px-5 h-11 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 text-slate-700 dark:text-slate-300 rounded-2xl font-black text-xs uppercase tracking-widest hover:border-indigo-500/30 transition-all shadow-sm"
                                >
                                    <Download className="w-4 h-4 text-slate-500" />
                                    내보내기
                                </button>
                            </Tooltip>

                            {showExportMenu && (
                                <div className="absolute top-full right-0 mt-2 w-48 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl shadow-xl z-50 overflow-hidden animate-in fade-in slide-in-from-top-2">
                                    <button
                                        onClick={() => {
                                            handleExportExcel();
                                            setShowExportMenu(false);
                                        }}
                                        className="w-full flex items-center gap-3 px-5 py-3 text-xs font-bold text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors border-b border-slate-100 dark:border-slate-800 text-left"
                                    >
                                        <FileDown className="w-4 h-4 text-green-500" />
                                        엑셀 파일로 저장 (.xlsx)
                                    </button>
                                    <button
                                        onClick={() => {
                                            handleExportImage();
                                            setShowExportMenu(false);
                                        }}
                                        disabled={isExporting}
                                        className="w-full flex items-center gap-3 px-5 py-3 text-xs font-bold text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors disabled:opacity-50 text-left"
                                    >
                                        <ImageIcon className="w-4 h-4 text-indigo-500" />
                                        {isExporting ? '추출 중...' : '이미지 파일로 저장 (.png)'}
                                    </button>
                                </div>
                            )}
                        </div>

                        <button
                            onClick={handleReset}
                            className="flex items-center gap-2 px-5 h-11 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 text-slate-700 dark:text-slate-300 rounded-2xl font-black text-xs uppercase tracking-widest hover:border-rose-500/30 transition-all shadow-sm"
                        >
                            <RotateCcw className="w-4 h-4 text-slate-500" />
                            초기화
                        </button>

                        <button
                            onClick={handleSave}
                            disabled={saving || !hasChanges}
                            className={cn(
                                "flex items-center gap-2 px-6 h-11 rounded-2xl font-black text-xs uppercase tracking-widest transition-all shadow-lg active:scale-95 disabled:opacity-50 disabled:scale-100 border",
                                hasChanges
                                    ? "bg-indigo-600 text-white border-indigo-600 shadow-indigo-600/20 hover:bg-indigo-500"
                                    : "bg-white dark:bg-slate-900 text-slate-600 dark:text-slate-400 border-slate-200 dark:border-slate-800 shadow-none"
                            )}
                        >
                            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
                            {saving ? '저장 중...' : '변경사항 확정'}
                        </button>
                    </div>
                </div>
            </div>

            {/* Kanban Board Container - Brightened background for a premium white theme (Photo ref) */}
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
                        onQuickAddMember={handleOpenAddMemberModal}
                        onAddMembers={handleOpenAddMemberModal}
                        profileMode={departments.find(d => d.id === selectedDeptId)?.profile_mode}
                        autoMoveCouples={autoMoveCouples}
                        onDeleteMember={handleDeleteMember}
                        isDeletableMap={isDeletableMap}
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

            {isMemberModalOpen && currentChurchId && (
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
