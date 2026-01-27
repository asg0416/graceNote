'use client';

import { useEffect, useState, useMemo, useRef, Fragment, Suspense } from 'react';
import { useRouter, useSearchParams, usePathname } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import {
    Users,
    Search,
    Loader2,
    ShieldCheck,
    CheckCircle2,
    X,
    UserPlus,
    Church,
    ChevronDown,
    ChevronRight,
    Layers,
    Image as ImageIcon,
    Plus,
    Filter,
    Check,
    Layout,
    LayoutGrid,
    UserCog,
    Trash2 as TrashIcon,
    Edit3,
    ArrowUpDown,
    CheckSquare,
    Square,
    Tags,
    Sparkles
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Modal } from '@/components/Modal';
import SmartBatchModal from '@/components/SmartBatchModal';
import RichTextEditor from '@/components/RichTextEditor';
import { MemberModal, MemberProfile } from '@/components/MemberModal';
import { Tooltip } from '@/components/Tooltip';

interface Church {
    id: string;
    name: string;
}

interface Department {
    id: string;
    name: string;
    color_hex: string;
    profile_mode?: 'individual' | 'couple';
}

interface Group {
    id: string;
    name: string;
    department_id: string;
    color_hex?: string;
}

export default function MembersPage() {
    return (
        <Suspense fallback={
            <div className="p-32 flex flex-col items-center justify-center gap-6 text-center">
                <Loader2 className="w-12 h-12 text-indigo-600 dark:text-indigo-500 animate-spin" />
                <p className="text-slate-400 dark:text-slate-500 font-black uppercase tracking-[0.2em] text-xs">페이지 로딩 중...</p>
            </div>
        }>
            <MembersPageInner />
        </Suspense>
    );
}

function MembersPageInner() {
    const [loading, setLoading] = useState(true);
    const [members, setMembers] = useState<MemberProfile[]>([]);
    const [churches, setChurches] = useState<Church[]>([]);
    const [departments, setDepartments] = useState<Department[]>([]);
    const [isMaster, setIsMaster] = useState(false);
    const [assignedDeptId, setAssignedDeptId] = useState<string | null>(null);

    const [currentChurchId, setCurrentChurchId] = useState<string | null>(null);
    const [currentChurchName, setCurrentChurchName] = useState('');
    const [selectedDeptId, setSelectedDeptId] = useState<string>('all');
    const [deptProfileMode, setDeptProfileMode] = useState<'individual' | 'couple'>('individual');
    const [selectedGroupId, setSelectedGroupId] = useState<string>('all');
    const [groups, setGroups] = useState<Group[]>([]);

    const [isChurchSelectOpen, setIsChurchSelectOpen] = useState(false);
    const [isDeptSelectOpen, setIsDeptSelectOpen] = useState(false);
    const [searchTerm, setSearchTerm] = useState('');
    const [isBatchModalOpen, setIsBatchModalOpen] = useState(false);
    const [isEditModalOpen, setIsEditModalOpen] = useState(false);
    const [editingMember, setEditingMember] = useState<MemberProfile | null>(null);
    const [isMoveModalOpen, setIsMoveModalOpen] = useState(false);
    const [targetDeptIdForMove, setTargetDeptIdForMove] = useState<string>('');
    const [targetGroupIdForMove, setTargetGroupIdForMove] = useState<string>('');
    const [isAddModalOpen, setIsAddModalOpen] = useState(false);

    const [isGroupedView, setIsGroupedView] = useState(false);

    const [selectedMemberIds, setSelectedMemberIds] = useState<string[]>([]);
    const [lastAction, setLastAction] = useState<{ type: 'move' | 'delete', data: MemberProfile[] } | null>(null);
    const [showUndo, setShowUndo] = useState(false);
    const [sortBy, setSortBy] = useState<'name' | 'group' | 'role' | 'family'>('name');
    const [filterStatus, setFilterStatus] = useState<'all' | 'linked' | 'not_linked'>('all');
    const [filterRole, setFilterRole] = useState<'all' | 'leader' | 'member'>('all');
    const [filterActive, setFilterActive] = useState<'all' | 'active' | 'inactive'>('all');
    const [isSortOpen, setIsSortOpen] = useState(false);
    const [isFilterOpen, setIsFilterOpen] = useState(false);
    const [collapsedGroups, setCollapsedGroups] = useState<string[]>([]);
    const [collapsedDepts, setCollapsedDepts] = useState<string[]>([]);
    const [nameSuggestions, setNameSuggestions] = useState<MemberProfile[]>([]);

    const router = useRouter();
    const searchParams = useSearchParams();
    const pathname = usePathname();

    // URL 파라미터 업데이트 헬퍼
    const updateQueryParams = (params: Record<string, string | null>) => {
        const newSearchParams = new URLSearchParams(searchParams.toString());
        Object.entries(params).forEach(([key, value]) => {
            if (value === null || value === 'all' || value === '') {
                newSearchParams.delete(key);
            } else {
                newSearchParams.set(key, value);
            }
        });
        const query = newSearchParams.toString();
        router.replace(`${pathname}${query ? `?${query}` : ''}`, { scroll: false });
    };

    useEffect(() => {
        const init = async () => {
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

                const urlChurchId = searchParams.get('churchId');
                const urlDeptId = searchParams.get('deptId') || 'all';
                const urlGroupId = searchParams.get('groupId') || 'all';
                const urlSort = (searchParams.get('sort') as 'name' | 'group' | 'role' | 'family') || 'name';
                const urlSearch = searchParams.get('q') || '';

                setSortBy(urlSort);
                setSearchTerm(urlSearch);

                if (profile.is_master) {
                    await fetchChurches();
                } else if (profile.church_id) {
                    const cId = profile.church_id;
                    const dId = profile.department_id || urlDeptId;

                    setIsMaster(false);
                    setAssignedDeptId(profile.department_id);
                    setCurrentChurchId(cId);
                    setSelectedDeptId(dId);
                    setSelectedGroupId(urlGroupId);

                    await fetchChurchInfo(cId);
                    await Promise.all([
                        fetchDepartments(cId, profile.department_id),
                        dId !== 'all' ? fetchGroups(dId) : Promise.resolve(),
                        fetchMembers(cId, dId)
                    ]);
                }
            } else {
                setLoading(false);
            }
        };

        init();
    }, [router]); // searchParams 의존성은 뺌 (무한 루프 방지용, 초기 로드만 수행)

    // Background scroll lock when modals are open
    useEffect(() => {
        const isAnyModalOpen = isAddModalOpen || isEditModalOpen || isMoveModalOpen || isBatchModalOpen;
        if (isAnyModalOpen) {
            document.body.style.overflow = 'hidden';
        } else {
            document.body.style.overflow = 'unset';
        }
        return () => {
            document.body.style.overflow = 'unset';
        };
    }, [isAddModalOpen, isEditModalOpen, isMoveModalOpen, isBatchModalOpen]);

    useEffect(() => {
        if (!isAddModalOpen) {
            setNameSuggestions([]);
        }
    }, [isAddModalOpen]);

    const fetchChurches = async () => {
        try {
            const { data, error } = await supabase
                .from('churches')
                .select('id, name')
                .order('name');
            if (error) throw error;
            setChurches(data || []);

            if (data?.length > 0) {
                const urlChurchId = searchParams.get('churchId');
                const initialChurch = data.find(c => c.id === urlChurchId) || data[0];

                const urlDeptId = searchParams.get('deptId') || 'all';
                const urlGroupId = searchParams.get('groupId') || 'all';

                setCurrentChurchId(initialChurch.id);
                setCurrentChurchName(initialChurch.name);
                setSelectedDeptId(urlDeptId);
                setSelectedGroupId(urlGroupId);

                await fetchChurchInfo(initialChurch.id);
                await fetchDepartments(initialChurch.id, null);
                if (urlDeptId !== 'all') await fetchGroups(urlDeptId);
                await fetchMembers(initialChurch.id, urlDeptId);
            } else {
                setLoading(false);
            }
        } catch (err) {
            console.error(err);
            setLoading(false);
        }
    };

    const fetchChurchInfo = async (churchId: string) => {
        try {
            const { data } = await supabase.from('churches').select('name').eq('id', churchId).single();
            if (data) setCurrentChurchName(data.name);
        } catch (err) {
            console.error(err);
        }
    };

    const fetchDepartments = async (churchId: string, assignedDeptId: string | null = null) => {
        try {
            let query = supabase
                .from('departments')
                .select('id, name, color_hex')
                .eq('church_id', churchId);

            if (assignedDeptId) {
                query = query.eq('id', assignedDeptId);
            }

            const { data } = await query.order('name');
            setDepartments(data || []);
        } catch (err) {
            console.error(err);
        }
    };

    const fetchGroups = async (deptId: string) => {
        if (deptId === 'all') {
            setGroups([]);
            return;
        }
        try {
            const { data } = await supabase
                .from('groups')
                .select('id, name, color_hex')
                .eq('department_id', deptId)
                .order('name');
            setGroups((data as Group[]) || []);
        } catch (err) {
            console.error(err);
        }
    };

    const fetchMembers = async (churchId: string, deptId: string = 'all') => {
        setLoading(true);
        // Reset collapse states on refresh or filter change if needed, 
        // but often better to keep them unless the data truly changes.
        // For now, keep them.
        try {
            // member_directory를 중심으로 가져오고, 연동된 프로필 정보가 있다면 가져옴
            let query = supabase
                .from('member_directory')
                .select(`
                    *,
                    departments!department_id (name, color_hex)
                `)
                .eq('church_id', churchId);

            if (deptId !== 'all') {
                query = query.eq('department_id', deptId);

                // 부서의 프로필 모드 가져오기
                const { data: deptData } = await supabase
                    .from('departments')
                    .select('profile_mode')
                    .eq('id', deptId)
                    .single();
                if (deptData) setDeptProfileMode(deptData.profile_mode || 'individual');
            } else {
                setDeptProfileMode('individual');
            }

            // DB 레벨에서는 이름순으로 가져오고, 클라이언트 측 정렬(`filteredMembers`)에서 가족 단위 정렬 수행
            const { data, error } = await query.order('full_name');

            if (error) throw error;
            const fetchedMembers = data || [];



            setMembers(fetchedMembers as MemberProfile[]);
        } catch (err) {
            console.error(err);
        } finally {
            setLoading(false);
        }
    };



    const toggleGroupCollapse = (groupName: string) => {
        setCollapsedGroups(prev =>
            prev.includes(groupName)
                ? prev.filter(g => g !== groupName)
                : [...prev, groupName]
        );
    };

    const toggleDeptCollapse = (deptName: string) => {
        setCollapsedDepts(prev =>
            prev.includes(deptName)
                ? prev.filter(d => d !== deptName)
                : [...prev, deptName]
        );
    };

    const handleChurchChange = async (id: string, name: string) => {
        setCollapsedGroups([]);
        setCollapsedDepts([]);
        setCurrentChurchId(id);
        setCurrentChurchName(name);
        setIsChurchSelectOpen(false);
        setSelectedDeptId('all');
        setSelectedGroupId('all');

        updateQueryParams({ churchId: id, deptId: 'all', groupId: 'all' });

        await fetchDepartments(id);
        await fetchMembers(id, 'all');
    };

    const handleDeptChange = async (deptId: string) => {
        setCollapsedGroups([]);
        setSelectedDeptId(deptId);
        setSelectedGroupId('all');
        setIsDeptSelectOpen(false);

        updateQueryParams({ deptId });

        if (currentChurchId) {
            await fetchGroups(deptId);
            await fetchMembers(currentChurchId, deptId);
        }
    };

    const handleGroupChange = (groupId: string) => {
        setSelectedGroupId(groupId);
        updateQueryParams({ groupId });
    };

    const handleBulkMove = async () => {
        if (!targetGroupIdForMove) {
            alert('이동할 조를 선택해 주세요.');
            return;
        }

        const selectedGroup = groups.find(g => g.id === targetGroupIdForMove);
        if (!selectedGroup) return;

        // Save for undo
        const previousStates = members
            .filter(m => selectedMemberIds.includes(m.id))
            .map(m => ({ id: m.id, group_name: m.group_name, department_id: m.department_id }));

        setLoading(true);
        try {
            const { error } = await supabase
                .from('member_directory')
                .update({
                    group_name: selectedGroup.name,
                    department_id: targetDeptIdForMove
                })
                .in('id', selectedMemberIds);

            if (error) throw error;
            setIsMoveModalOpen(false);
            setLastAction({ type: 'move', data: previousStates as MemberProfile[] });
            setShowUndo(true);
            setSelectedMemberIds([]);
            if (currentChurchId) fetchMembers(currentChurchId, selectedDeptId);

            // Auto hide undo after 10s
            setTimeout(() => setShowUndo(false), 10000);
        } catch (err) {
            console.error(err);
            alert('이동 중 오류가 발생했습니다.');
        } finally {
            setLoading(false);
        }
    };

    const handleUndo = async () => {
        if (!lastAction) return;
        setLoading(true);
        try {
            if (lastAction.type === 'move') {
                // Restore move: individually or in batches if same
                // For simplicity, we can do multiple updates or a smarter mapping if needed
                // But since it's just a few members usually, we can loop or use a custom RPC if it grows
                for (const item of lastAction.data) {
                    await supabase
                        .from('member_directory')
                        .update({ group_name: item.group_name, department_id: item.department_id })
                        .eq('id', item.id);
                }
            } else if (lastAction.type === 'delete') {
                // Restore delete: re-insert
                const { error } = await supabase
                    .from('member_directory')
                    .insert(lastAction.data);
                if (error) throw error;
            }

            setLastAction(null);
            setShowUndo(false);
            if (currentChurchId) fetchMembers(currentChurchId, selectedDeptId);
            alert('작업이 취소되었습니다.');
        } catch (err) {
            console.error(err);
            alert('되돌리기 중 오류가 발생했습니다.');
        } finally {
            setLoading(false);
        }
    };

    const filteredMembers = members.filter(m => {
        const matchesSearch = m.full_name?.toLowerCase().includes(searchTerm.toLowerCase());
        const matchesGroup = selectedGroupId === 'all' || m.group_name === groups.find(g => g.id === selectedGroupId)?.name;
        const matchesStatus = filterStatus === 'all'
            ? true
            : filterStatus === 'linked' ? m.is_linked : !m.is_linked;

        const matchesRole = filterRole === 'all'
            ? true
            : m.role_in_group === filterRole;

        const matchesActive = filterActive === 'all'
            ? true
            : filterActive === 'active' ? m.is_active !== false : m.is_active === false;

        return matchesSearch && matchesGroup && matchesStatus && matchesRole && matchesActive;
    }).sort((a, b) => {
        // Priority 1: If sorted by family OR in couple mode, use family grouping
        if (sortBy === 'family' || (sortBy === 'name' && deptProfileMode === 'couple')) {
            const getFamilyKey = (m: MemberProfile) => {
                if (m.family_id) return m.family_id;
                if (m.spouse_name) {
                    // Create a stable key from both names so husband/wife get same key
                    return [m.full_name, m.spouse_name].sort().join('_');
                }
                return `single_${m.id}`;
            };
            const keyA = getFamilyKey(a);
            const keyB = getFamilyKey(b);
            const familyDiff = keyA.localeCompare(keyB);
            if (familyDiff !== 0) return familyDiff;
        }

        if (sortBy === 'name' || sortBy === 'family') {
            return a.full_name.localeCompare(b.full_name);
        }
        if (sortBy === 'group') return (a.group_name || '').localeCompare(b.group_name || '');
        if (sortBy === 'role') return (a.role_in_group || '').localeCompare(b.role_in_group || '');
        return 0;
    });

    // 3. Deduplicate by person_id to create 'Master List'
    const masterMembers = useMemo(() => {
        const map = new Map();
        filteredMembers.forEach((m: MemberProfile) => {
            const key = m.person_id || m.id;
            // If already exists, keep the one with group info or preferred metadata
            if (!map.has(key)) {
                map.set(key, m);
            } else if (!map.get(key).group_name && m.group_name) {
                map.set(key, m);
            }
        });
        return Array.from(map.values());
    }, [filteredMembers]);

    useEffect(() => {
        setIsGroupedView(selectedDeptId !== 'all');
    }, [selectedDeptId]);

    const groupedData = useMemo(() => {
        if (!isGroupedView) return null;

        const groups: Record<string, MemberProfile[]> = {};
        masterMembers.forEach((m: MemberProfile) => {
            const groupName = m.group_name || '미배정';
            if (!groups[groupName]) groups[groupName] = [];
            groups[groupName].push(m);
        });
        return groups;
    }, [masterMembers, isGroupedView]);

    const toggleMemberSelection = (id: string) => {
        setSelectedMemberIds(prev =>
            prev.includes(id) ? prev.filter(mid => mid !== id) : [...prev, id]
        );
    };

    const toggleAllMembers = () => {
        if (selectedMemberIds.length === filteredMembers.length) {
            setSelectedMemberIds([]);
        } else {
            setSelectedMemberIds(filteredMembers.map((m: MemberProfile) => m.id));
        }
    };

    const handleDeleteMember = async (id: string) => {
        if (!confirm('이 성도 정보를 삭제하시겠습니까?')) return;
        try {
            const { error } = await supabase.from('member_directory').delete().eq('id', id);
            if (error) throw error;
            if (currentChurchId) fetchMembers(currentChurchId, selectedDeptId);
        } catch (err) {
            alert('삭제 중 오류가 발생했습니다.');
        }
    };

    const handleRenameGroup = async (groupId: string, currentName: string) => {
        const newName = prompt('변경할 조 이름을 입력하세요:', currentName);
        if (!newName || newName === currentName) return;

        try {
            const { error } = await supabase
                .from('groups')
                .update({ name: newName })
                .eq('id', groupId);

            if (error) throw error;

            // Sync with member_directory: 조 이름이 명부에도 저장되어 있으므로 함께 업데이트
            const { error: syncError } = await supabase
                .from('member_directory')
                .update({ group_name: newName.trim() })
                .eq('church_id', currentChurchId)
                .eq('group_name', currentName.trim());

            if (syncError) throw syncError;

            // Update local member data to reflect change immediately if current view uses this group
            setMembers(prev => prev.map(m => m.group_name === currentName ? { ...m, group_name: newName } : m));
            if (currentChurchId) await fetchGroups(selectedDeptId);
        } catch (err) {
            console.error(err);
            alert('이름 변경 중 오류가 발생했습니다.');
        }
    };


    if (loading) {
        return (
            <div className="p-32 flex flex-col items-center justify-center gap-6 text-center">
                <Loader2 className="w-12 h-12 text-indigo-600 dark:text-indigo-500 animate-spin" />
                <p className="text-slate-400 dark:text-slate-500 font-black uppercase tracking-[0.2em] text-xs">페이지 로딩 중...</p>
            </div>
        );
    }

    return (
        <div className="space-y-8 sm:space-y-10 max-w-7xl mx-auto">
            <header className="space-y-8">
                <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
                    <div className="space-y-1.5">
                        <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">성도 명부</h1>
                        <p className="text-slate-500 dark:text-slate-500 font-bold text-xs sm:text-sm tracking-tight">
                            {isMaster
                                ? '성도 개개인의 상세 프로필과 신상 정보를 통합 관리하는 마스터 명부입니다.'
                                : <><span className="text-indigo-600 dark:text-indigo-400 font-extrabold underline decoration-indigo-200/50 dark:decoration-indigo-500/30 underline-offset-4">{currentChurchName} · {departments.find(d => d.id === selectedDeptId)?.name || (selectedDeptId === 'all' ? '교회 전체' : '부서')}</span> 명부입니다. 소속 성도들의 정보를 관리합니다.</>}
                        </p>
                    </div>
                    <div className="flex items-center gap-2 sm:gap-3">
                        <Tooltip content="이미지나 CSV 파일을 분석하여 여러 성도를 한 번에 등록합니다.">
                            <button
                                onClick={() => setIsBatchModalOpen(true)}
                                disabled={!currentChurchId}
                                className="flex items-center gap-2 px-4 h-[44px] bg-white dark:bg-slate-900 text-indigo-600 dark:text-white border border-indigo-100 dark:border-slate-800 rounded-xl font-bold text-[11px] sm:text-xs hover:bg-slate-50 dark:hover:bg-slate-800 transition-all shadow-sm active:scale-95 disabled:opacity-50 whitespace-nowrap"
                            >
                                <Sparkles className="w-4 h-4 text-indigo-500" />
                                <span className="hidden xs:inline">스마트 등록 (AI)</span>
                                <span className="xs:hidden">AI 등록</span>
                            </button>
                        </Tooltip>
                        <Tooltip content="새로운 성도 정보를 한 명씩 직접 입력하여 등록합니다.">
                            <button
                                onClick={() => setIsAddModalOpen(true)}
                                disabled={!currentChurchId}
                                className="flex items-center gap-2 px-4 h-[44px] bg-indigo-600 text-white rounded-xl font-bold text-[11px] sm:text-xs hover:bg-indigo-500 transition-all shadow-md shadow-indigo-600/10 active:scale-95 disabled:opacity-50 whitespace-nowrap"
                            >
                                <UserPlus className="w-4 h-4" />
                                <span>개별 성도 추가</span>
                            </button>
                        </Tooltip>
                    </div>
                </div>

                {isMaster && (
                    <div className="flex flex-col xl:flex-row gap-6 items-stretch">
                        {/* Selection Group - Left side (Red box in Photo 2) - Visible only to Master */}
                        <div className="flex-1 bg-white dark:bg-[#111827]/40 p-5 sm:p-6 rounded-[32px] border border-slate-200 dark:border-slate-800 shadow-sm">
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                {/* Church Selection */}
                                <div className="relative group/select">
                                    <div className="absolute left-4 top-1/2 -translate-y-1/2 w-8 h-8 bg-indigo-50 dark:bg-indigo-500/10 rounded-lg flex items-center justify-center">
                                        <Church className="w-4 h-4 text-indigo-600 dark:text-indigo-400" />
                                    </div>
                                    <button
                                        onClick={() => setIsChurchSelectOpen(!isChurchSelectOpen)}
                                        className="w-full h-[56px] pl-14 pr-10 bg-slate-50/50 dark:bg-slate-900/40 border border-slate-200 dark:border-slate-800 rounded-2xl font-black text-xs text-slate-900 dark:text-white text-left transition-all hover:border-indigo-500/30 shadow-none flex items-center"
                                    >
                                        {currentChurchName}
                                    </button>
                                    <div className="absolute right-4 top-1/2 -translate-y-1/2 pointer-events-none">
                                        <ChevronDown className={cn("w-4 h-4 text-slate-400 transition-transform duration-300", isChurchSelectOpen && "rotate-180")} />
                                    </div>
                                    {isChurchSelectOpen && (
                                        <div className="absolute top-full left-0 right-0 mt-2 bg-white dark:bg-slate-950 border border-slate-200 dark:border-slate-800 rounded-2xl shadow-2xl z-[80] overflow-hidden animate-in fade-in slide-in-from-top-2">
                                            <div className="max-h-64 overflow-y-auto p-1.5">
                                                {churches.map(c => (
                                                    <button
                                                        key={c.id}
                                                        onClick={() => { handleChurchChange(c.id, c.name); setIsChurchSelectOpen(false); }}
                                                        className={cn(
                                                            "w-full flex items-center gap-3 px-4 py-3 rounded-xl text-left font-bold text-xs transition-colors",
                                                            currentChurchId === c.id ? "bg-indigo-50 dark:bg-indigo-500/10 text-indigo-600" : "hover:bg-slate-50 dark:hover:bg-slate-800 text-slate-600 dark:text-slate-400"
                                                        )}
                                                    >
                                                        {c.name}
                                                    </button>
                                                ))}
                                            </div>
                                        </div>
                                    )}
                                    <div className="absolute -top-2 left-4 px-1.5 bg-white dark:bg-[#111827] text-[8px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest">Church</div>
                                </div>

                                {/* Department Selection */}
                                <div className="relative group/select">
                                    <div className="absolute left-4 top-1/2 -translate-y-1/2 w-8 h-8 bg-indigo-50 dark:bg-indigo-500/10 rounded-lg flex items-center justify-center">
                                        <Layers className="w-4 h-4 text-indigo-600 dark:text-indigo-400" />
                                    </div>
                                    <select
                                        className="w-full h-[56px] pl-14 pr-10 bg-slate-50/50 dark:bg-slate-900/40 border border-slate-200 dark:border-slate-800 rounded-2xl font-black text-xs text-slate-900 dark:text-white appearance-none transition-all focus:ring-2 focus:ring-indigo-500/20 outline-none hover:border-indigo-500/30 shadow-none"
                                        value={selectedDeptId}
                                        onChange={(e) => handleDeptChange(e.target.value)}
                                    >
                                        <option value="all">전체 부서 보기</option>
                                        {departments.map(d => <option key={d.id} value={d.id}>{d.name}</option>)}
                                    </select>
                                    <div className="absolute right-4 top-1/2 -translate-y-1/2 pointer-events-none">
                                        <ChevronDown className="w-4 h-4 text-slate-400 group-hover/select:text-indigo-500 transition-colors" />
                                    </div>
                                    <div className="absolute -top-2 left-4 px-1.5 bg-white dark:bg-[#111827] text-[8px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest">Department</div>
                                </div>
                            </div>
                        </div>
                    </div>
                )}
            </header>

            {/* Filters and Search Toolbar */}
            <div className="flex flex-col gap-4 sm:gap-6 px-1">
                <div className="flex flex-col lg:flex-row gap-3 items-stretch lg:items-center bg-white dark:bg-[#111827]/60 p-3 sm:p-5 rounded-[24px] sm:rounded-[40px] border border-slate-200 dark:border-slate-800/80 shadow-sm">
                    {/* Search Field */}
                    <div className="flex-1 relative group">
                        <div className="absolute left-5 top-1/2 -translate-y-1/2">
                            <Search className="w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                        </div>
                        <input
                            type="text"
                            placeholder="이름으로 성도 검색..."
                            value={searchTerm}
                            onChange={(e) => {
                                setSearchTerm(e.target.value);
                                updateQueryParams({ q: e.target.value });
                            }}
                            className="w-full pl-12 pr-12 py-3 sm:py-3.5 bg-slate-50/50 dark:bg-slate-900/40 border border-slate-100 dark:border-slate-800 rounded-[18px] sm:rounded-[24px] text-slate-900 dark:text-white font-bold placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/10 transition-all text-sm"
                        />
                        {searchTerm && (
                            <button
                                onClick={() => {
                                    setSearchTerm('');
                                    updateQueryParams({ q: '' });
                                }}
                                className="absolute right-4 top-1/2 -translate-y-1/2 p-1.5 bg-slate-200/50 dark:bg-slate-700/50 hover:bg-slate-300 dark:hover:bg-slate-600 rounded-lg text-slate-500 transition-all"
                            >
                                <X className="w-3.5 h-3.5" />
                            </button>
                        )}
                    </div>

                    <Tooltip content={isGroupedView ? "모든 성도를 한 번에 나열하여 확인합니다." : "성도를 조별로 묶어서 관리하기 편하게 보여줍니다."}>
                        <button
                            onClick={() => setIsGroupedView(!isGroupedView)}
                            className={cn(
                                "flex items-center gap-2 h-[48px] px-5 rounded-[18px] sm:rounded-[24px] font-black text-xs transition-all border shrink-0",
                                isGroupedView
                                    ? "bg-indigo-50 dark:bg-indigo-500/10 border-indigo-200 dark:border-indigo-500/30 text-indigo-600 dark:text-indigo-400 shadow-sm"
                                    : "bg-slate-50/50 dark:bg-slate-900/40 border-slate-100 dark:border-slate-800 text-slate-600 dark:text-slate-400 hover:bg-white dark:hover:bg-slate-800"
                            )}
                            title={""}
                        >
                            {isGroupedView ? <LayoutGrid className="w-4 h-4 text-indigo-500" /> : <Layout className="w-4 h-4" />}
                            <span>{isGroupedView ? '조별 모드' : '목록 모드'}</span>
                        </button>
                    </Tooltip>

                    {/* Sorting Dropdown */}
                    <div className="flex-1 sm:flex-none relative min-w-[120px]">
                        <button
                            onClick={() => setIsSortOpen(!isSortOpen)}
                            className="w-full flex items-center justify-between px-4 py-3 sm:py-3.5 bg-slate-50/50 dark:bg-slate-900/40 border border-slate-100 dark:border-slate-800 rounded-[18px] sm:rounded-[24px] text-slate-900 dark:text-white font-black text-[10px] sm:text-xs transition-all hover:bg-white dark:hover:bg-slate-800 cursor-pointer"
                        >
                            <div className="flex items-center gap-2">
                                <ArrowUpDown className="w-3.5 h-3.5 text-indigo-500" />
                                <span>{sortBy === 'name' ? '이름순' : sortBy === 'group' ? '조별순' : sortBy === 'role' ? '역할순' : '부부/가족순'}</span>
                            </div>
                            <ChevronDown className={cn("w-3.5 h-3.5 text-slate-400 transition-transform", isSortOpen && "rotate-180")} />
                        </button>

                        {isSortOpen && (
                            <div className="absolute top-full mt-2 right-0 left-0 sm:left-auto sm:w-48 z-[60] bg-white dark:bg-slate-950 border border-slate-200 dark:border-slate-800 rounded-2xl shadow-2xl overflow-hidden animate-in fade-in slide-in-from-top-2">
                                <div className="p-1.5">
                                    {[
                                        { id: 'name', label: '이름순' },
                                        { id: 'family', label: '부부/가족순' },
                                        { id: 'group', label: '조별순' },
                                        { id: 'role', label: '역할순' }
                                    ].map(item => (
                                        <button
                                            key={item.id}
                                            onClick={() => {
                                                setSortBy(item.id as 'name' | 'group' | 'role' | 'family');
                                                setIsSortOpen(false);
                                                updateQueryParams({ sort: item.id });
                                            }}
                                            className={cn(
                                                "w-full px-4 py-2.5 rounded-xl text-left font-bold text-xs transition-colors",
                                                sortBy === item.id ? "bg-indigo-50 dark:bg-indigo-500/10 text-indigo-600" : "hover:bg-slate-50 dark:hover:bg-slate-800 text-slate-600 dark:text-slate-400"
                                            )}
                                        >
                                            {item.label}
                                        </button>
                                    ))}
                                </div>
                            </div>
                        )}
                    </div>

                    {/* Filter Dropdown */}
                    <div className="flex-1 sm:flex-none relative min-w-[120px]">
                        <button
                            onClick={() => setIsFilterOpen(!isFilterOpen)}
                            className="w-full flex items-center justify-between px-4 py-3 sm:py-3.5 bg-slate-50/50 dark:bg-slate-900/40 border border-slate-100 dark:border-slate-800 rounded-[18px] sm:rounded-[24px] text-slate-900 dark:text-white font-black text-[10px] sm:text-xs transition-all hover:bg-white dark:hover:bg-slate-800 cursor-pointer"
                        >
                            <div className="flex items-center gap-2">
                                <Filter className="w-3.5 h-3.5 text-indigo-500" />
                                <span>{filterStatus === 'all' ? '전체 상태' : filterStatus === 'linked' ? '앱 연동됨' : '미가입'}</span>
                            </div>
                            <ChevronDown className={cn("w-3.5 h-3.5 text-slate-400 transition-transform", isFilterOpen && "rotate-180")} />
                        </button>

                        {isFilterOpen && (
                            <div className="absolute top-full mt-2 right-0 sm:w-[320px] z-[60] bg-white dark:bg-slate-950 border border-slate-200 dark:border-slate-800 rounded-2xl shadow-2xl overflow-hidden animate-in fade-in slide-in-from-top-2">
                                <div className="p-4 space-y-4">
                                    <div className="space-y-2">
                                        <p className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">앱 가입 상태</p>
                                        <div className="flex flex-wrap gap-1.5">
                                            {[
                                                { id: 'all', label: '전체' },
                                                { id: 'linked', label: '앱 연동' },
                                                { id: 'not_linked', label: '미가입' }
                                            ].map((item: { id: string; label: string }) => (
                                                <button
                                                    key={item.id}
                                                    onClick={() => setFilterStatus(item.id as 'all' | 'linked' | 'not_linked')}
                                                    className={cn(
                                                        "px-3 py-1.5 rounded-lg text-[10px] font-bold transition-colors",
                                                        filterStatus === item.id ? "bg-indigo-600 text-white" : "bg-slate-50 dark:bg-slate-900 text-slate-500 hover:bg-slate-100"
                                                    )}
                                                >
                                                    {item.label}
                                                </button>
                                            ))}
                                        </div>
                                    </div>

                                    <div className="space-y-2">
                                        <p className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">조직 역할</p>
                                        <div className="flex flex-wrap gap-1.5">
                                            {[
                                                { id: 'all', label: '전체' },
                                                { id: 'leader', label: '조장' },
                                                { id: 'member', label: '조원' }
                                            ].map((item: { id: string; label: string }) => (
                                                <button
                                                    key={item.id}
                                                    onClick={() => setFilterRole(item.id as 'all' | 'leader' | 'member')}
                                                    className={cn(
                                                        "px-3 py-1.5 rounded-lg text-[10px] font-bold transition-colors",
                                                        filterRole === item.id ? "bg-indigo-600 text-white" : "bg-slate-50 dark:bg-slate-900 text-slate-500 hover:bg-slate-100"
                                                    )}
                                                >
                                                    {item.label}
                                                </button>
                                            ))}
                                        </div>
                                    </div>

                                    <div className="space-y-2">
                                        <p className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">활성 상태</p>
                                        <div className="flex flex-wrap gap-1.5">
                                            {[
                                                { id: 'all', label: '전체' },
                                                { id: 'active', label: '활성 성도' },
                                                { id: 'inactive', label: '비활성 성도' }
                                            ].map((item: { id: string; label: string }) => (
                                                <button
                                                    key={item.id}
                                                    onClick={() => setFilterActive(item.id as 'all' | 'active' | 'inactive')}
                                                    className={cn(
                                                        "px-3 py-1.5 rounded-lg text-[10px] font-bold transition-colors",
                                                        filterActive === item.id ? "bg-indigo-600 text-white" : "bg-slate-50 dark:bg-slate-900 text-slate-500 hover:bg-slate-100"
                                                    )}
                                                >
                                                    {item.label}
                                                </button>
                                            ))}
                                        </div>
                                    </div>

                                    <div className="pt-2 border-t border-slate-100 dark:border-slate-800">
                                        <button
                                            onClick={() => setIsFilterOpen(false)}
                                            className="w-full py-2 bg-slate-900 dark:bg-white text-white dark:text-slate-900 rounded-xl text-[10px] font-black uppercase tracking-widest"
                                        >
                                            필터 적용
                                        </button>
                                    </div>
                                </div>
                            </div>
                        )}
                    </div>
                </div>
            </div>

            {/* Group Tabs (Only visible when a department is selected) */}
            {
                selectedDeptId !== 'all' && departments.length > 0 && (
                    <div className="relative group/tabs w-full max-w-full overflow-hidden min-w-0">
                        <div className="bg-white dark:bg-[#111827]/40 p-1.5 sm:p-2 rounded-[20px] sm:rounded-[32px] border border-slate-200 dark:border-slate-800 shadow-sm relative min-w-0 overflow-hidden">
                            <div className="flex items-center gap-1 overflow-x-auto px-2 relative z-10 scroll-smooth min-w-0
                                [&::-webkit-scrollbar]:h-1.5
                                [&::-webkit-scrollbar-track]:bg-slate-50/50
                                [&::-webkit-scrollbar-track]:dark:bg-slate-900/20
                                [&::-webkit-scrollbar-track]:rounded-full
                                [&::-webkit-scrollbar-thumb]:bg-slate-200
                                [&::-webkit-scrollbar-thumb]:dark:bg-slate-800/80
                                [&::-webkit-scrollbar-thumb]:rounded-full
                                hover:[&::-webkit-scrollbar-thumb]:bg-indigo-500/40
                                transition-all"
                            >
                                <button
                                    onClick={() => handleGroupChange('all')}
                                    className={cn("px-5 py-2 sm:py-2.5 rounded-[15px] sm:rounded-[24px] text-[10px] sm:text-[11px] font-black uppercase tracking-widest transition-all whitespace-nowrap flex-shrink-0 cursor-pointer",
                                        selectedGroupId === 'all'
                                            ? "bg-indigo-600 text-white shadow-lg shadow-indigo-600/20"
                                            : "text-slate-500 hover:bg-slate-100 dark:text-slate-400 dark:hover:bg-slate-800"
                                    )}
                                >
                                    전체 조 보기
                                </button>
                                <div className="w-px h-4 bg-slate-200 dark:bg-slate-800 mx-1 flex-shrink-0" />
                                {groups.map(group => (
                                    <div key={group.id} className="group relative flex-shrink-0">
                                        <button
                                            onClick={() => handleGroupChange(group.id)}
                                            className={cn("px-5 py-2 sm:py-2.5 rounded-[15px] sm:rounded-[24px] text-[10px] sm:text-[11px] font-black uppercase tracking-widest transition-all whitespace-nowrap border border-transparent flex-shrink-0 cursor-pointer",
                                                selectedGroupId === group.id
                                                    ? "bg-white dark:bg-slate-800 text-indigo-600 dark:text-white border-slate-200 dark:border-slate-700 shadow-sm"
                                                    : "text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-800/50"
                                            )}
                                        >
                                            {group.name}
                                        </button>
                                        <button
                                            onClick={(e) => { e.stopPropagation(); handleRenameGroup(group.id, group.name); }}
                                            className="absolute -top-1 -right-1 w-5 h-5 bg-white dark:bg-slate-700 border border-slate-200 dark:border-slate-600 rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-all hover:text-indigo-600 shadow-lg"
                                        >
                                            <Edit3 className="w-2.5 h-2.5" />
                                        </button>
                                    </div>
                                ))}
                            </div>
                            {/* Right Fade Gradient - Fixed to match rounded corners */}
                            <div className="absolute right-0 top-0 bottom-0 w-16 bg-gradient-to-l from-white dark:from-[#131b2e] to-transparent z-20 pointer-events-none opacity-0 group-hover/tabs:opacity-100 transition-opacity rounded-r-[20px] sm:rounded-r-[32px]" />
                        </div>
                    </div>
                )
            }
            {/* Members List Table */}
            <div className="bg-white dark:bg-[#111827]/60 backdrop-blur-xl rounded-[32px] sm:rounded-[40px] border border-slate-200 dark:border-slate-800/80 overflow-hidden shadow-xl">
                <div className="overflow-x-auto">
                    <table className="w-full text-left border-collapse">
                        <thead>
                            <tr className="bg-slate-50 dark:bg-slate-900/40 border-b border-slate-200 dark:border-slate-800/60">
                                <th className="pl-6 sm:pl-8 py-4 w-10">
                                    <button onClick={toggleAllMembers} className="text-slate-400 hover:text-indigo-600 transition-colors">
                                        {selectedMemberIds.length === filteredMembers.length ? <CheckSquare className="w-5 h-5 text-indigo-600" /> : <Square className="w-5 h-5" />}
                                    </button>
                                </th>
                                <th className="px-4 sm:px-6 py-4 text-[9px] sm:text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em]">성도 이름</th>
                                <th className="px-4 sm:px-6 py-4 text-[9px] sm:text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] hidden md:table-cell">가족 정보</th>
                                <th className="px-4 sm:px-6 py-4 text-[9px] sm:text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] hidden sm:table-cell">소속 정보</th>
                                <th className="px-4 sm:px-6 py-4 text-[9px] sm:text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] hidden lg:table-cell">앱 가입 상태</th>
                                <th className="px-6 sm:px-8 py-4 text-[9px] sm:text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] text-right">관리</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-100 dark:divide-slate-800/40">
                            {isGroupedView && groupedData ? (
                                Object.entries(groupedData).map(([groupName, groupMembers]) => (
                                    <Fragment key={groupName}>
                                        <tr className="bg-slate-50/80 dark:bg-slate-900/40 border-y border-slate-200/50 dark:border-slate-800/50">
                                            <td colSpan={6} className="px-6 py-4">
                                                <button
                                                    type="button"
                                                    onClick={() => toggleGroupCollapse(groupName)}
                                                    className="flex items-center gap-3 text-[11px] font-black text-slate-600 dark:text-slate-300 uppercase tracking-widest hover:text-indigo-600 transition-all group/gh cursor-pointer"
                                                >
                                                    <div className="w-6 h-6 rounded-lg bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 flex items-center justify-center shadow-sm group-hover/gh:scale-110 transition-transform">
                                                        <ChevronDown className={cn("w-3.5 h-3.5 transition-transform duration-300", collapsedGroups.includes(groupName) && "-rotate-90")} />
                                                    </div>
                                                    <span className="flex items-center gap-2">
                                                        {groupName}
                                                        <span className="text-slate-400 dark:text-slate-500 font-bold ml-1">({groupMembers.length}명)</span>
                                                    </span>
                                                </button>
                                            </td>
                                        </tr>
                                        {!collapsedGroups.includes(groupName) && groupMembers.map((m: MemberProfile) => (
                                            <MemberRow
                                                key={m.id}
                                                member={m}
                                                groupedGroups={groups}
                                                isSelected={selectedMemberIds.includes(m.id)}
                                                onToggle={() => toggleMemberSelection(m.id)}
                                                onEdit={() => { setEditingMember(m); setIsEditModalOpen(true); }}
                                                onDelete={() => handleDeleteMember(m.id)}
                                            />
                                        ))}
                                    </Fragment>
                                ))
                            ) : (
                                masterMembers.map((m: MemberProfile) => (
                                    <MemberRow
                                        key={m.id}
                                        member={m}
                                        groupedGroups={groups}
                                        isSelected={selectedMemberIds.includes(m.id)}
                                        onToggle={() => toggleMemberSelection(m.id)}
                                        onEdit={() => { setEditingMember(m); setIsEditModalOpen(true); }}
                                        onDelete={() => handleDeleteMember(m.id)}
                                    />
                                ))
                            )}
                            {masterMembers.length === 0 && (
                                <tr>
                                    <td colSpan={6} className="px-8 py-32 text-center">
                                        <div className="flex flex-col items-center gap-4">
                                            <div className="w-16 h-16 bg-slate-50 dark:bg-slate-900 rounded-3xl flex items-center justify-center text-slate-300">
                                                <Users className="w-8 h-8" />
                                            </div>
                                            <p className="text-slate-400 font-bold text-sm">해당하는 성도가 없습니다.</p>
                                        </div>
                                    </td>
                                </tr>
                            )}
                        </tbody>
                    </table>
                </div>
            </div>

            {/* Bulk Action Bar */}
            {
                selectedMemberIds.length > 0 && (
                    <div className="fixed bottom-10 left-1/2 -translate-x-1/2 z-[100] animate-in slide-in-from-bottom-10 duration-500">
                        <div className="bg-slate-900 dark:bg-white text-white dark:text-slate-900 px-8 py-5 rounded-[32px] shadow-2xl flex items-center gap-8 backdrop-blur-xl bg-opacity-95 dark:bg-opacity-95 border border-white/10 dark:border-slate-200">
                            <div className="flex items-center gap-3 pr-8 border-r border-white/10 dark:border-slate-200">
                                <div className="w-8 h-8 rounded-full bg-indigo-600 flex items-center justify-center font-black text-sm text-white">
                                    {selectedMemberIds.length}
                                </div>
                                <p className="font-black text-sm tracking-tight">명 선택됨</p>
                            </div>
                            <div className="flex items-center gap-4">
                                <button
                                    onClick={() => {
                                        setTargetDeptIdForMove(selectedDeptId === 'all' ? departments[0]?.id : selectedDeptId);
                                        setIsMoveModalOpen(true);
                                    }}
                                    className="flex items-center gap-2 px-5 py-2.5 bg-white/10 dark:bg-slate-100 hover:bg-white/20 dark:hover:bg-slate-200 rounded-2xl font-black text-xs transition-all active:scale-95 group"
                                >
                                    <UserCog className="w-4 h-4 text-indigo-400 dark:text-indigo-600 group-hover:scale-110 transition-transform" />
                                    조 변경
                                </button>
                                <button
                                    onClick={async () => {
                                        if (!confirm(`${selectedMemberIds.length}명을 일괄 삭제하시겠습니까?`)) return;
                                        const deletedMembers = members.filter(m => selectedMemberIds.includes(m.id));
                                        try {
                                            const { error } = await supabase.from('member_directory').delete().in('id', selectedMemberIds);
                                            if (error) throw error;
                                            setLastAction({ type: 'delete', data: deletedMembers });
                                            setShowUndo(true);
                                            setSelectedMemberIds([]);
                                            if (currentChurchId) fetchMembers(currentChurchId, selectedDeptId);
                                            setTimeout(() => setShowUndo(false), 10000);
                                        } catch (err) {
                                            alert('삭제 오류');
                                        }
                                    }}
                                    className="flex items-center gap-2 px-5 py-2.5 bg-rose-500/20 dark:bg-rose-50 hover:bg-rose-500/30 dark:hover:bg-rose-100 text-rose-500 rounded-2xl font-black text-xs transition-all active:scale-95 group"
                                >
                                    <TrashIcon className="w-4 h-4 group-hover:shake transition-transform" />
                                    일괄 삭제
                                </button>
                                <button
                                    onClick={() => setSelectedMemberIds([])}
                                    className="w-10 h-10 flex items-center justify-center bg-white/5 dark:bg-slate-100 rounded-full hover:bg-white/10 dark:hover:bg-slate-200 transition-all"
                                >
                                    <X className="w-4 h-4" />
                                </button>
                            </div>
                        </div>
                    </div>
                )
            }

            {/* Undo Notification */}
            {
                showUndo && lastAction && (
                    <div className="fixed bottom-32 left-1/2 -translate-x-1/2 z-[100] animate-in slide-in-from-bottom-5 duration-500">
                        <div className="bg-indigo-600 text-white px-6 py-4 rounded-[24px] shadow-2xl flex items-center gap-4">
                            <p className="text-sm font-bold">삭제되었습니다.</p>
                            <button
                                onClick={handleUndo}
                                className="bg-white text-indigo-600 px-4 py-1.5 rounded-xl text-xs font-black uppercase tracking-widest hover:bg-indigo-50 transition-all active:scale-95"
                            >
                                실행 취소
                            </button>
                            <button onClick={() => setShowUndo(false)} className="opacity-60 hover:opacity-100 transition-opacity">
                                <X className="w-4 h-4" />
                            </button>
                        </div>
                    </div>
                )
            }
            {/* Member Add/Edit Modal */}
            {
                (isAddModalOpen || isEditModalOpen) && currentChurchId && (
                    <MemberModal
                        isOpen={isAddModalOpen || isEditModalOpen}
                        onClose={() => {
                            setIsAddModalOpen(false);
                            setIsEditModalOpen(false);
                            setEditingMember(null);
                        }}
                        onSuccess={() => {
                            if (currentChurchId) fetchMembers(currentChurchId, selectedDeptId);
                        }}
                        member={isEditModalOpen && editingMember ? editingMember : undefined}
                        churchId={currentChurchId!}
                        departmentId={selectedDeptId !== 'all' ? selectedDeptId : (assignedDeptId || undefined)}
                        departments={departments}
                    />
                )
            }

            {/* Bulk Move Modal */}
            {
                isMoveModalOpen && (
                    <Modal
                        isOpen={isMoveModalOpen}
                        onClose={() => setIsMoveModalOpen(false)}
                        title="일괄 조 변경"
                        subtitle={`선택된 ${selectedMemberIds.length}명 이동`}
                        maxWidth="md"
                    >
                        <div className="space-y-6">
                            <div className="space-y-2 text-center py-4 bg-indigo-50/50 dark:bg-indigo-500/5 rounded-3xl border border-indigo-100/50 dark:border-indigo-500/10">
                                <p className="text-[11px] font-black text-indigo-600 dark:text-indigo-400 uppercase tracking-widest mb-1">이동할 조 선택</p>
                                <div className="flex flex-wrap justify-center gap-2 px-4">
                                    {groups.map(g => (
                                        <button
                                            key={g.id}
                                            onClick={() => setTargetGroupIdForMove(g.id)}
                                            className={cn(
                                                "px-4 py-2 rounded-xl text-[10px] font-black transition-all",
                                                targetGroupIdForMove === g.id
                                                    ? "bg-indigo-600 text-white shadow-lg shadow-indigo-600/20"
                                                    : "bg-white dark:bg-slate-800 text-slate-400 hover:text-slate-600"
                                            )}
                                        >
                                            {g.name}
                                        </button>
                                    ))}
                                </div>
                            </div>

                            <button
                                onClick={handleBulkMove}
                                className="w-full py-4 bg-indigo-600 text-white font-black rounded-3xl hover:bg-indigo-500 transition-all shadow-xl shadow-indigo-600/20 active:scale-95"
                            >
                                {selectedMemberIds.length}명 이동 완료
                            </button>
                        </div>
                    </Modal>
                )
            }

            {/* Member Add Modal is now handled by the shared MemberModal above */}

            {/* Smart Batch Modal */}
            {
                isBatchModalOpen && (
                    <SmartBatchModal
                        churchId={currentChurchId!}
                        departments={departments}
                        initialDeptId={selectedDeptId}
                        onClose={() => setIsBatchModalOpen(false)}
                        onSuccess={() => {
                            setIsBatchModalOpen(false);
                            if (currentChurchId) fetchMembers(currentChurchId, selectedDeptId);
                        }}
                    />
                )
            }
        </div >
    );
}

const getGroupColor = (groupName: string, customHex?: string) => {
    if (customHex) {
        return {
            style: {
                backgroundColor: `${customHex}15`,
                color: customHex,
                borderColor: `${customHex}30`
            }
        };
    }

    if (!groupName || groupName === '미정' || groupName === 'No Group') {
        return { className: 'bg-slate-100 text-slate-500 border-slate-200 dark:bg-slate-800 dark:text-slate-400 dark:border-slate-700' };
    }

    const colors = [
        'bg-indigo-50 text-indigo-600 border-indigo-100 dark:bg-indigo-500/10 dark:text-indigo-400 dark:border-indigo-500/20',
        'bg-emerald-50 text-emerald-600 border-emerald-100 dark:bg-emerald-500/10 dark:text-emerald-400 dark:border-emerald-500/20',
        'bg-amber-50 text-amber-600 border-amber-100 dark:bg-amber-500/10 dark:text-amber-400 dark:border-amber-500/20',
        'bg-rose-50 text-rose-600 border-rose-100 dark:bg-rose-500/10 dark:text-rose-400 dark:border-rose-500/20',
        'bg-sky-50 text-sky-600 border-sky-100 dark:bg-sky-500/10 dark:text-sky-400 dark:border-sky-500/20',
        'bg-violet-50 text-violet-600 border-violet-100 dark:bg-violet-500/10 dark:text-violet-400 dark:border-violet-500/20',
        'bg-teal-50 text-teal-600 border-teal-100 dark:bg-teal-500/10 dark:text-teal-400 dark:border-teal-500/20',
        'bg-fuchsia-50 text-fuchsia-600 border-fuchsia-100 dark:bg-fuchsia-500/10 dark:text-fuchsia-400 dark:border-fuchsia-500/20',
    ];

    let hash = 0;
    for (let i = 0; i < groupName.length; i++) {
        hash = groupName.charCodeAt(i) + ((hash << 5) - hash);
    }
    return { className: colors[Math.abs(hash) % colors.length] };
};

// Helper component for each row
interface MemberRowProps {
    member: MemberProfile;
    groupedGroups: Group[];
    isSelected: boolean;
    onToggle: () => void;
    onEdit: () => void;
    onDelete: () => void;
}

const MemberRow = ({ member: m, groupedGroups, isSelected, onToggle, onEdit, onDelete }: MemberRowProps) => {
    const groupInfo = groupedGroups.find((g) => g.name === m.group_name);
    const groupColor = getGroupColor(m.group_name || '', groupInfo?.color_hex);

    return (
        <tr className={cn("hover:bg-slate-50/80 dark:hover:bg-indigo-500/[0.02] transition-colors group", isSelected && "bg-indigo-50/50 dark:bg-indigo-500/[0.05]")}>
            <td className="pl-6 sm:pl-8 py-4 sm:py-5 border-l-[4px] border-l-transparent dark:border-l-slate-800" style={{ borderLeftColor: groupInfo?.color_hex }}>
                <button type="button" onClick={onToggle} className="text-slate-400 hover:text-indigo-600 transition-colors">
                    {isSelected ? <CheckSquare className="w-5 h-5 text-indigo-600" /> : <Square className="w-5 h-5" />}
                </button>
            </td>
            <td className="px-4 sm:px-6 py-4 sm:py-5">
                <div className="flex items-center gap-3 sm:gap-4">
                    <div className="w-10 h-10 sm:w-11 sm:h-11 rounded-xl sm:rounded-2xl bg-slate-100 dark:bg-slate-800/40 flex items-center justify-center text-slate-400 font-black group-hover:scale-105 group-hover:bg-indigo-600 group-hover:text-white transition-all duration-300 text-sm sm:text-base">
                        {m.full_name?.[0]}
                    </div>
                    <div>
                        <div className="flex items-center gap-2">
                            <Link
                                href={`/members/${m.id}`}
                                className="font-black text-slate-900 dark:text-white text-base sm:text-lg tracking-tight leading-none hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors"
                            >
                                {m.full_name}
                            </Link>
                            {m.is_active === false && (
                                <span className="px-1.5 py-0.5 bg-slate-200 text-slate-500 text-[8px] sm:text-[9px] font-black rounded-md uppercase tracking-widest border border-slate-300">
                                    비활성
                                </span>
                            )}
                            {m.role_in_group === 'leader' && (
                                <span className="px-1.5 py-0.5 bg-amber-500 text-white text-[8px] sm:text-[9px] font-black rounded-md uppercase tracking-widest shadow-lg shadow-amber-500/20">
                                    Leader
                                </span>
                            )}
                        </div>
                        <p className="text-[9px] sm:text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest mt-1 leading-none">{m.phone || 'No Contact'}</p>
                    </div>
                </div>
            </td>
            <td className="px-4 sm:px-6 py-4 sm:py-5 hidden md:table-cell">
                <div className="space-y-1">
                    {m.spouse_name && (
                        <p className="flex items-center gap-2 text-xs sm:text-sm text-slate-600 dark:text-slate-300 font-bold leading-tight">
                            <span className="text-[8px] sm:text-[9px] font-black text-indigo-500 uppercase tracking-widest bg-indigo-50 dark:bg-indigo-500/10 px-1.5 py-0.5 rounded">배우자</span>
                            {m.spouse_name}
                        </p>
                    )}
                    {m.children_info && (
                        <p className="flex items-center gap-2 text-[10px] sm:text-[11px] text-slate-500 font-medium leading-tight">
                            <span className="text-[8px] sm:text-[9px] font-black text-slate-400 uppercase tracking-widest border border-slate-200 dark:border-slate-800 px-1.5 py-0.5 rounded">자녀</span>
                            {m.children_info}
                        </p>
                    )}
                    {!m.spouse_name && !m.children_info && <p className="text-[10px] sm:text-xs text-slate-400 italic">가족 정보 없음</p>}
                </div>
            </td>
            <td className="px-4 sm:px-6 py-4 sm:py-5 hidden sm:table-cell">
                <div className="space-y-1.5">
                    <div className="flex items-center gap-1.5">
                        <div className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: m.departments?.color_hex || '#e2e8f0' }} />
                        <span className="text-[11px] sm:text-xs font-black text-slate-700 dark:text-slate-200 uppercase tracking-tight">{m.departments?.name}</span>
                    </div>
                    <div
                        className={cn(
                            "inline-flex px-2.5 py-1 border rounded-lg text-[9px] sm:text-[10px] font-black uppercase tracking-widest transition-colors",
                            groupColor.className
                        )}
                        style={groupColor.style}
                    >
                        {m.group_name || '미정'}
                    </div>
                </div>
            </td>
            <td className="px-4 sm:px-6 py-4 sm:py-5 hidden lg:table-cell">
                {m.is_linked ? (
                    <div className="flex items-center gap-1.5 font-black text-[8px] sm:text-[10px] uppercase tracking-widest px-2.5 py-1.5 rounded-xl w-fit border text-emerald-600 dark:text-emerald-500 bg-emerald-50 dark:bg-emerald-500/10 border-emerald-100 dark:border-emerald-500/20">
                        <CheckCircle2 className="w-3.5 h-3.5" />
                        연동 완료
                    </div>
                ) : (
                    <div className="flex items-center gap-1.5 text-slate-400 dark:text-slate-500 font-black text-[8px] sm:text-[10px] uppercase tracking-widest bg-slate-50 dark:bg-slate-800/40 px-2.5 py-1.5 rounded-xl w-fit">
                        <div className="w-1.5 h-1.5 rounded-full bg-slate-200 dark:bg-slate-600" />
                        미가입
                    </div>
                )}
            </td>
            <td className="px-6 sm:px-8 py-4 sm:py-5 text-right">
                <div className="flex items-center justify-end gap-1 sm:gap-2">
                    <button
                        type="button"
                        onClick={onEdit}
                        className="p-2 sm:p-2.5 bg-slate-50 dark:bg-slate-800/40 text-slate-400 hover:text-indigo-600 dark:hover:text-white hover:bg-white dark:hover:bg-slate-700 rounded-xl transition-all active:scale-95"
                    >
                        <Edit3 className="w-4 h-4" />
                    </button>
                    <button
                        type="button"
                        onClick={onDelete}
                        className="p-2 sm:p-2.5 bg-slate-50 dark:bg-slate-800/40 text-slate-400 hover:text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-500/10 rounded-xl transition-all active:scale-95"
                    >
                        <TrashIcon className="w-4 h-4" />
                    </button>
                </div>
            </td>
        </tr>
    );
};
