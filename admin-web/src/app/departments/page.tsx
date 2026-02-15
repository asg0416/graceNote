'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Plus,
    Settings,
    Users,
    Trash2,
    Edit2,
    Search,
    MoreVertical,
    ChevronRight,
    LayoutGrid,
    Bell,
    Shield,
    Check,
    User,
    Church,
    ChevronDown,
    PlusCircle,
    Loader2,
    Layers
} from 'lucide-react';
import Link from 'next/link';
import { cn } from '@/lib/utils';
import { Modal } from '@/components/Modal';

export default function DepartmentsPage() {
    const [loading, setLoading] = useState(true);
    const [departments, setDepartments] = useState<any[]>([]);
    const [churches, setChurches] = useState<any[]>([]);
    const [isMaster, setIsMaster] = useState(false);
    const [currentChurchId, setCurrentChurchId] = useState<string | null>(null);
    const [currentChurchName, setCurrentChurchName] = useState<string>('');
    const [isChurchSelectOpen, setIsChurchSelectOpen] = useState(false);
    const [churchSearch, setChurchSearch] = useState('');
    const [assignedDeptId, setAssignedDeptId] = useState<string | null>(null);

    const [groupName, setGroupName] = useState('');
    const [groupColor, setGroupColor] = useState('#4f46e5');
    const [isNewMemberGroup, setIsNewMemberGroup] = useState(false);
    const [climbingThreshold, setClimbingThreshold] = useState(4);

    const [isGroupModalOpen, setIsGroupModalOpen] = useState(false);
    const [editingGroup, setEditingGroup] = useState<any>(null);
    const [selectedDeptId, setSelectedDeptId] = useState<string | null>(null);

    // Custom Confirmation Modal State
    const [confirmModal, setConfirmModal] = useState<{
        open: boolean;
        title: string;
        message: string;
        onConfirm: () => void;
        type: 'error' | 'warning' | 'info';
    }>({
        open: false,
        title: '',
        message: '',
        onConfirm: () => { },
        type: 'warning'
    });

    const colorPalette = [
        { name: 'Indigo', hex: '#4f46e5' },
        { name: 'Emerald', hex: '#10b981' },
        { name: 'Rose', hex: '#f43f5e' },
        { name: 'Amber', hex: '#f59e0b' },
        { name: 'Sky', hex: '#0ea5e9' },
        { name: 'Violet', hex: '#8b5cf6' },
        { name: 'Teal', hex: '#14b8a6' },
        { name: 'Slate', hex: '#64748b' }
    ];

    const router = useRouter();

    useEffect(() => {
        const init = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                router.push('/login');
                return;
            }

            const { data: profile } = await supabase
                .from('profiles')
                .select('church_id, department_id, is_master')
                .eq('id', session.user.id)
                .single();

            if (profile) {
                setIsMaster(profile.is_master);

                if (profile.is_master) {
                    await fetchChurches();
                } else if (profile.church_id) {
                    setAssignedDeptId(profile.department_id);
                    setCurrentChurchId(profile.church_id);
                    await fetchChurchInfo(profile.church_id);
                    await fetchData(profile.church_id, profile.department_id);
                }
            } else {
                setLoading(false);
            }
        };

        init();
    }, [router]);

    const fetchChurches = async () => {
        try {
            const { data, error } = await supabase
                .from('churches')
                .select('id, name')
                .order('name');
            if (error) throw error;
            setChurches(data || []);

            // Default to first church if exists
            if (data && data.length > 0) {
                handleChurchChange(data[0].id, data[0].name);
            } else {
                setLoading(false);
            }
        } catch (err) {
            console.error('Fetch Churches Error:', err);
            setLoading(false);
        }
    };

    const fetchChurchInfo = async (churchId: string) => {
        try {
            const { data } = await supabase
                .from('churches')
                .select('name')
                .eq('id', churchId)
                .single();
            if (data) setCurrentChurchName(data.name);
        } catch (err) {
            console.error(err);
        }
    };

    const fetchData = async (churchId: string, assignedDeptId: string | null = null) => {
        setLoading(true);
        try {
            let query = supabase
                .from('departments')
                .select(`
                    *,
                    groups (*)
                `)
                .eq('church_id', churchId);

            if (assignedDeptId) {
                query = query.eq('id', assignedDeptId);
            }

            const { data, error } = await query.order('name');

            if (error) throw error;
            setDepartments(data || []);
        } catch (err) {
            console.error('Fetch Data Error:', err);
        } finally {
            setLoading(false);
        }
    };

    const handleChurchChange = async (id: string, name: string) => {
        setCurrentChurchId(id);
        setCurrentChurchName(name);
        setIsChurchSelectOpen(false);
        await fetchData(id);
    };


    const handleGroupSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!currentChurchId) return;

        try {
            if (editingGroup) {
                // 1. Update the group record
                const { error } = await supabase
                    .from('groups')
                    .update({
                        name: groupName,
                        color_hex: groupColor,
                        is_new_member_group: isNewMemberGroup,
                        climbing_threshold: climbingThreshold
                    })
                    .eq('id', editingGroup.id);
                if (error) throw error;

                // 2. Cascade update to members (Sync)
                // We only need to sync if the name actually changed
                if (editingGroup.name !== groupName) {
                    const { error: syncError } = await supabase
                        .from('member_directory')
                        .update({ group_name: groupName })
                        .eq('church_id', currentChurchId)
                        .eq('department_id', editingGroup.department_id)
                        .eq('group_name', editingGroup.name);

                    if (syncError) {
                        console.error('Cascading update failed:', syncError);
                        // We don't block the whole process, but alert might be helpful
                    }
                }
            } else {
                const { error } = await supabase
                    .from('groups')
                    .insert({
                        name: groupName,
                        department_id: selectedDeptId,
                        church_id: currentChurchId,
                        color_hex: groupColor,
                        is_new_member_group: isNewMemberGroup,
                        climbing_threshold: isNewMemberGroup ? climbingThreshold : null
                    });
                if (error) throw error;
            }
            setIsGroupModalOpen(false);
            setEditingGroup(null);
            setGroupName('');
            setGroupColor('#4f46e5');
            fetchData(currentChurchId);
        } catch (err: any) {
            console.error('Group Submit Error:', err);
            alert('오류가 발생했습니다: ' + (err.message || '알 수 없는 오류'));
        }
    };


    const handleDeleteDept = async (e: React.MouseEvent, id: string) => {
        e.preventDefault();
        e.stopPropagation();

        setConfirmModal({
            open: true,
            title: '부서 삭제',
            message: '부서를 삭제하시겠습니까? 부서에 속한 모든 조가 삭제됩니다.',
            type: 'error',
            onConfirm: async () => {
                try {
                    const { error } = await supabase.from('departments').delete().eq('id', id);
                    if (error) throw error;
                    fetchData(currentChurchId!);
                    setConfirmModal(prev => ({ ...prev, open: false }));
                } catch (err) {
                    alert('삭제 중 오류가 발생했습니다.');
                    setConfirmModal(prev => ({ ...prev, open: false }));
                }
            }
        });
    };

    const handleDeleteGroup = async (e: React.MouseEvent, id: string) => {
        e.preventDefault();
        e.stopPropagation();

        setConfirmModal({
            open: true,
            title: '조 삭제',
            message: '조를 삭제하시겠습니까? 조원 정보는 유지되나 소속 조가 없어집니다.',
            type: 'error',
            onConfirm: async () => {
                try {
                    const { error } = await supabase.from('groups').delete().eq('id', id);
                    if (error) throw error;
                    fetchData(currentChurchId!);
                    setConfirmModal(prev => ({ ...prev, open: false }));
                } catch (err) {
                    alert('삭제 중 오류가 발생했습니다.');
                    setConfirmModal(prev => ({ ...prev, open: false }));
                }
            }
        });
    };

    const filteredChurches = churches.filter(c =>
        c.name.toLowerCase().includes(churchSearch.toLowerCase())
    );

    return (
        <div className="space-y-6 sm:space-y-8 max-w-7xl mx-auto px-1">
            <header className="flex flex-col lg:flex-row lg:items-end justify-between gap-6">
                <div className="space-y-3 sm:space-y-4">
                    <div className="space-y-1">
                        <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">부서 및 조 관리</h1>
                        <p className="text-slate-500 dark:text-slate-500 font-bold text-[11px] sm:text-sm tracking-tight text-opacity-80">교회 조직 구조를 설정하고 체계적인 관리를 시작합니다.</p>
                    </div>

                    {/* Church Selection for Master Admin */}
                    {isMaster ? (
                        <div className="relative z-50">
                            <button
                                onClick={() => setIsChurchSelectOpen(!isChurchSelectOpen)}
                                className="flex items-center gap-3 px-6 py-3.5 bg-white dark:bg-slate-900 border-2 border-slate-100 dark:border-slate-800 rounded-2xl hover:border-indigo-500/50 transition-all shadow-sm group"
                            >
                                <div className="p-2 rounded-lg bg-indigo-50 dark:bg-indigo-500/10 text-indigo-600 dark:text-indigo-400">
                                    <Church className="w-5 h-5" />
                                </div>
                                <div className="text-left">
                                    <p className="text-[10px] font-black text-slate-400 dark:text-slate-600 uppercase tracking-widest leading-none mb-1">현재 선택된 교회</p>
                                    <p className="font-black text-slate-900 dark:text-white">{currentChurchName || '교회를 선택하세요'}</p>
                                </div>
                                <ChevronDown className={cn("w-5 h-5 text-slate-400 transition-transform duration-300", isChurchSelectOpen && "rotate-180")} />
                            </button>

                            {isChurchSelectOpen && (
                                <div className="absolute top-full left-0 mt-3 w-80 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-3xl shadow-2xl overflow-hidden animate-in fade-in slide-in-from-top-2 duration-200">
                                    <div className="p-4 border-b border-slate-100 dark:border-slate-800">
                                        <div className="relative">
                                            <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                                            <input
                                                type="text"
                                                placeholder="교회 검색..."
                                                value={churchSearch}
                                                onChange={(e) => setChurchSearch(e.target.value)}
                                                className="w-full pl-11 pr-4 py-2.5 bg-slate-50 dark:bg-slate-950 border-none rounded-xl focus:ring-2 focus:ring-indigo-500/20 text-sm font-bold"
                                            />
                                        </div>
                                    </div>
                                    <div className="max-h-64 overflow-y-auto p-2">
                                        {filteredChurches.map(church => (
                                            <button
                                                key={church.id}
                                                onClick={() => handleChurchChange(church.id, church.name)}
                                                className={cn(
                                                    "w-full flex items-center gap-3 px-4 py-3 rounded-xl text-left transition-colors",
                                                    currentChurchId === church.id
                                                        ? "bg-indigo-50 dark:bg-indigo-500/10 text-indigo-600 dark:text-indigo-400"
                                                        : "hover:bg-slate-50 dark:hover:bg-slate-800 text-slate-600 dark:text-slate-400"
                                                )}
                                            >
                                                <Church className="w-4 h-4" />
                                                <span className="font-bold text-sm">{church.name}</span>
                                            </button>
                                        ))}
                                    </div>
                                </div>
                            )}
                        </div>
                    ) : (
                        <div className="inline-flex items-center gap-3 px-6 py-4 bg-slate-50 dark:bg-slate-900/40 border border-slate-200 dark:border-slate-800/60 rounded-2xl">
                            <Church className="w-5 h-5 text-indigo-600 dark:text-indigo-400" />
                            <span className="font-black text-slate-900 dark:text-white tracking-tight">{currentChurchName}</span>
                        </div>
                    )}
                </div>

                {(isMaster || !assignedDeptId) && (
                    <Link
                        href="/departments/new/settings"
                        className="w-full lg:w-fit bg-indigo-600 dark:bg-indigo-500 text-white px-6 sm:px-8 py-3.5 sm:py-4 rounded-xl sm:rounded-[28px] font-black text-xs sm:text-sm hover:bg-indigo-500 dark:hover:bg-indigo-400 hover:scale-[1.02] transition-all flex items-center justify-center gap-2.5 shadow-xl shadow-indigo-600/10 active:scale-95 border border-indigo-400/20 disabled:opacity-50"
                    >
                        <PlusCircle className="w-4 sm:w-5 h-4 sm:h-5" />
                        신규 부서 추가
                    </Link>
                )}
            </header>

            {loading ? (
                <div className="p-32 flex flex-col items-center justify-center gap-6 text-center">
                    <Loader2 className="w-12 h-12 text-indigo-600 dark:text-indigo-500 animate-spin" />
                    <p className="text-slate-400 dark:text-slate-500 font-black uppercase tracking-[0.2em] text-xs">조직 구조를 불러오는 중...</p>
                </div>
            ) : departments.length === 0 ? (
                <div className="p-20 sm:p-32 flex flex-col items-center justify-center gap-6 text-center bg-white dark:bg-[#111827]/60 rounded-[40px] border border-slate-200 dark:border-slate-800/80">
                    <div className="w-20 h-20 bg-slate-50 dark:bg-slate-800/40 rounded-full flex items-center justify-center text-slate-400">
                        <LayoutGrid className="w-10 h-10" />
                    </div>
                    <div className="space-y-2">
                        <h3 className="text-xl font-black text-slate-900 dark:text-white">등록된 부서가 없습니다</h3>
                        <p className="text-slate-500 font-medium max-w-xs mx-auto text-sm">먼저 부서를 생성하여 {currentChurchName} 조직의 기초를 만들어 보세요.</p>
                    </div>
                </div>
            ) : (
                <div className="grid grid-cols-1 gap-6 sm:gap-8">
                    {departments.map((dept) => (
                        <div key={dept.id} className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/80 rounded-[28px] sm:rounded-[40px] overflow-hidden group hover:border-indigo-300 dark:hover:border-slate-700 transition-all duration-300 shadow-lg dark:shadow-none">
                            <div className="p-5 sm:p-8 border-b border-slate-100 dark:border-slate-800/60 bg-slate-50/50 dark:bg-slate-900/40 flex items-center justify-between">
                                <div className="flex items-center gap-4 sm:gap-6">
                                    <div
                                        className="w-12 sm:w-16 h-12 sm:h-16 rounded-2xl sm:rounded-3xl flex items-center justify-center border"
                                        style={{ backgroundColor: `${dept.color_hex || '#4f46e5'}15`, color: dept.color_hex || '#4f46e5', borderColor: `${dept.color_hex || '#4f46e5'}30` }}
                                    >
                                        <Layers className="w-6 sm:w-8 h-6 sm:h-8" />
                                    </div>
                                    <div>
                                        <h3 className="text-lg sm:text-2xl font-black text-slate-900 dark:text-white tracking-tight leading-tight">{dept.name}</h3>
                                        <div className="flex items-center gap-1.5 mt-1 sm:mt-1.5">
                                            <span className={cn(
                                                "text-[8px] sm:text-[10px] font-black uppercase tracking-widest px-2 py-0.5 rounded-md border",
                                                dept.profile_mode === 'couple'
                                                    ? "bg-rose-500/10 text-rose-600 border-rose-500/20"
                                                    : "bg-indigo-500/10 text-indigo-600 border-indigo-500/20"
                                            )}>
                                                {dept.profile_mode === 'couple' ? '부부/가족형' : '개인별 관리'}
                                            </span>
                                        </div>
                                    </div>
                                </div>
                                <div className="flex gap-2 sm:gap-3">
                                    <Link
                                        href={`/departments/${dept.id}/settings`}
                                        className="w-10 h-10 sm:w-12 sm:h-12 flex items-center justify-center rounded-xl sm:rounded-2xl border border-slate-100 dark:border-slate-800 text-slate-400 dark:text-slate-500 hover:text-indigo-600 dark:hover:text-white hover:bg-slate-50 dark:hover:bg-slate-800 transition-all"
                                        title="부서 및 알림 설정"
                                    >
                                        <Settings className="w-5 h-5" />
                                    </Link>
                                    {(isMaster || !assignedDeptId) && (
                                        <button
                                            onClick={(e) => handleDeleteDept(e, dept.id)}
                                            className="w-10 h-10 sm:w-12 sm:h-12 flex items-center justify-center rounded-xl sm:rounded-2xl border border-slate-100 dark:border-slate-800 text-slate-400 dark:text-slate-500 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-500/10 transition-all"
                                        >
                                            <Trash2 className="w-5 h-5" />
                                        </button>
                                    )}
                                </div>
                            </div>
                            <div className="p-6 sm:p-10 space-y-6 sm:space-y-8">
                                <div className="flex items-center justify-between">
                                    <span className="text-[10px] sm:text-[11px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest flex items-center gap-2.5">
                                        <Users className="w-3.5 h-3.5" />
                                        소속 조 관리 ({dept.groups?.length || 0})
                                    </span>
                                    <button
                                        onClick={() => {
                                            setSelectedDeptId(dept.id);
                                            setEditingGroup(null);
                                            setGroupName('');
                                            setGroupColor(dept.color_hex || '#4f46e5');
                                            setIsNewMemberGroup(false);
                                            setClimbingThreshold(4);
                                            setIsGroupModalOpen(true);
                                        }}
                                        className="text-[10px] sm:text-[11px] font-black text-indigo-600 dark:text-indigo-400 hover:text-indigo-500 transition-all flex items-center gap-2 uppercase tracking-widest bg-indigo-50 dark:bg-indigo-500/10 px-3 py-1.5 rounded-lg"
                                    >
                                        <Plus className="w-4 h-4" />
                                        조 추가
                                    </button>
                                </div>
                                <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3 sm:gap-4 max-h-[400px] sm:max-h-[500px] overflow-y-auto custom-scrollbar pr-2">
                                    {dept.groups?.map((group: any) => (
                                        <div key={group.id} className="flex items-center justify-between p-3.5 sm:p-4 bg-slate-50 dark:bg-slate-800/20 border border-slate-200 dark:border-slate-800 rounded-2xl group/item hover:bg-white dark:hover:bg-slate-800/40 transition-all border-l-4" style={{ borderLeftColor: group.color_hex || dept.color_hex || '#4f46e5' }}>
                                            <div className="flex items-center gap-3">
                                                <div className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: group.color_hex || dept.color_hex || '#4f46e5' }} />
                                                <span className="font-bold text-slate-700 dark:text-white group-hover/item:text-indigo-600 dark:group-hover/item:text-indigo-400 transition-colors text-xs sm:text-sm">{group.name}</span>
                                            </div>
                                            <div className="flex gap-1 opacity-0 group-hover/item:opacity-100 transition-opacity">
                                                <button
                                                    onClick={() => {
                                                        setEditingGroup(group);
                                                        setGroupName(group.name);
                                                        setGroupColor(group.color_hex || dept.color_hex || '#4f46e5');
                                                        setIsNewMemberGroup(group.is_new_member_group || false);
                                                        setClimbingThreshold(group.climbing_threshold || 4);
                                                        setSelectedDeptId(dept.id);
                                                        setIsGroupModalOpen(true);
                                                    }}
                                                    className="p-1 px-1.5 text-slate-400 hover:text-indigo-600 transition-colors"
                                                >
                                                    <Edit2 className="w-3 h-3" />
                                                </button>
                                                <button
                                                    onClick={(e) => handleDeleteGroup(e, group.id)}
                                                    className="p-1 px-1.5 text-slate-400 hover:text-red-500 transition-colors"
                                                >
                                                    <Trash2 className="w-3 h-3" />
                                                </button>
                                            </div>
                                        </div>
                                    ))}
                                    {(!dept.groups || dept.groups.length === 0) && (
                                        <div className="p-8 border-2 border-dashed border-slate-100 dark:border-slate-800/60 rounded-3xl flex flex-col items-center justify-center text-center gap-2">
                                            <p className="text-[10px] font-black text-slate-400 dark:text-slate-600 uppercase tracking-widest italic">등록된 조가 없습니다</p>
                                        </div>
                                    )}
                                </div>
                            </div>
                        </div>
                    ))}
                </div>
            )}


            {/* Group Modal */}
            <Modal
                isOpen={isGroupModalOpen}
                onClose={() => setIsGroupModalOpen(false)}
                title={editingGroup ? '조 정보 수정' : '신규 조 생성'}
                subtitle="소속 조의 기본 정보를 설정합니다"
                maxWidth="lg"
            >
                <form onSubmit={handleGroupSubmit} className="space-y-8 py-2">
                    <div className="bg-white dark:bg-slate-900 rounded-[2.5rem] border border-slate-100 dark:border-slate-800/60 p-7 sm:p-8 shadow-sm space-y-8">
                        <div className="flex items-center gap-3.5">
                            <div className="w-10 h-10 rounded-xl bg-indigo-50 dark:bg-indigo-500/10 flex items-center justify-center">
                                <Users className="w-5 h-5 text-indigo-600 dark:text-indigo-400" />
                            </div>
                            <h3 className="text-lg font-black text-slate-900 dark:text-white">조 설정</h3>
                        </div>

                        <div className="space-y-8">
                            {/* Group Name */}
                            <div className="space-y-2.5">
                                <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">조 이름</label>
                                <input
                                    type="text"
                                    required
                                    value={groupName}
                                    onChange={(e) => setGroupName(e.target.value)}
                                    className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 text-slate-900 dark:text-white font-black transition-all text-base"
                                    placeholder="예: 1조, 2조 등..."
                                />
                            </div>

                            {/* Theme Color Selection */}
                            <div className="space-y-3.5">
                                <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">조 테마 색상</label>
                                <div className="flex flex-wrap gap-3 items-center">
                                    {colorPalette.map((color) => (
                                        <button
                                            key={color.hex}
                                            type="button"
                                            onClick={() => setGroupColor(color.hex)}
                                            className={cn(
                                                "w-10 h-10 rounded-full flex items-center justify-center transition-all hover:scale-110 active:scale-95 border-4",
                                                groupColor === color.hex ? "border-slate-100 dark:border-slate-800 ring-4 ring-indigo-500/15 shadow-md" : "border-transparent"
                                            )}
                                            style={{ backgroundColor: color.hex }}
                                        >
                                            {groupColor === color.hex && <Check className="w-5 h-5 text-white" />}
                                        </button>
                                    ))}

                                    <div className="relative">
                                        <button
                                            type="button"
                                            className={cn(
                                                "w-10 h-10 rounded-full border-2 border-dashed border-slate-300 dark:border-slate-700 flex items-center justify-center transition-all hover:border-indigo-500 active:scale-95 overflow-hidden",
                                                !colorPalette.some(c => c.hex.toLowerCase() === groupColor.toLowerCase()) && "border-indigo-500 ring-4 ring-indigo-500/10"
                                            )}
                                            onClick={() => document.getElementById('group-custom-color-input')?.click()}
                                            style={{ backgroundColor: !colorPalette.some(c => c.hex.toLowerCase() === groupColor.toLowerCase()) ? groupColor : 'transparent' }}
                                        >
                                            {!colorPalette.some(c => c.hex.toLowerCase() === groupColor.toLowerCase()) ? (
                                                <Check className="w-5 h-5 text-white" />
                                            ) : (
                                                <Plus className="w-5 h-5 text-slate-400" />
                                            )}
                                        </button>
                                        <input
                                            id="group-custom-color-input"
                                            type="color"
                                            className="absolute inset-0 opacity-0 cursor-pointer pointer-events-none"
                                            onChange={(e) => setGroupColor(e.target.value)}
                                            tabIndex={-1}
                                        />
                                    </div>
                                </div>
                            </div>

                            {/* New Member Group Toggle */}
                            <div className="pt-4 border-t border-slate-100 dark:border-slate-800 space-y-6">
                                <div className="flex items-center justify-between p-5 bg-indigo-50/30 dark:bg-indigo-500/5 rounded-3xl border border-indigo-100/50 dark:border-indigo-500/10">
                                    <div className="space-y-0.5">
                                        <h4 className="text-sm font-black text-slate-900 dark:text-white">새가족 조 설정</h4>
                                        <p className="text-[10px] text-slate-500 font-bold">이 조를 새가족을 위한 조로 지정합니다.</p>
                                    </div>
                                    <label className="relative inline-flex items-center cursor-pointer">
                                        <input
                                            type="checkbox"
                                            className="sr-only peer"
                                            checked={isNewMemberGroup}
                                            onChange={(e) => setIsNewMemberGroup(e.target.checked)}
                                        />
                                        <div className="w-12 h-6.5 bg-slate-200 dark:bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[4px] after:left-[4px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4.5 after:w-4.5 after:transition-all peer-checked:bg-indigo-600 shadow-inner"></div>
                                    </label>
                                </div>

                                {isNewMemberGroup && (
                                    <div className="space-y-2.5 animate-in fade-in slide-in-from-top-2 duration-200">
                                        <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">등반 기준 출석 횟수</label>
                                        <div className="flex items-center gap-4">
                                            <input
                                                type="number"
                                                min="1"
                                                max="52"
                                                required={isNewMemberGroup}
                                                value={climbingThreshold}
                                                onChange={(e) => setClimbingThreshold(parseInt(e.target.value))}
                                                className="w-24 px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 text-slate-900 dark:text-white font-black transition-all text-sm"
                                            />
                                            <p className="text-xs font-bold text-slate-500">회 출석 시 등반 가능</p>
                                        </div>
                                    </div>
                                )}
                            </div>
                        </div>
                    </div>

                    <div className="flex gap-3 pt-2">
                        <button
                            type="button"
                            onClick={() => setIsGroupModalOpen(false)}
                            className="flex-1 py-4 bg-slate-100 dark:bg-slate-900 text-slate-500 font-black rounded-2xl hover:bg-slate-200 dark:hover:bg-slate-800 transition-all text-sm"
                        >
                            취소
                        </button>
                        <button
                            type="submit"
                            className="flex-1 py-4 bg-indigo-600 dark:bg-indigo-500 text-white font-black rounded-2xl hover:bg-indigo-500 hover:scale-[1.02] transition-all shadow-xl shadow-indigo-600/10 active:scale-95 text-sm"
                        >
                            {editingGroup ? '수정 완료' : '조 생성완료'}
                        </button>
                    </div>
                </form>
            </Modal>

            {/* Confirmation Modal */}
            <Modal
                isOpen={confirmModal.open}
                onClose={() => setConfirmModal(prev => ({ ...prev, open: false }))}
                title={confirmModal.title}
                maxWidth="sm"
            >
                <div className="flex flex-col items-center text-center space-y-6 py-2">
                    <div className={cn(
                        "w-14 h-14 rounded-2xl flex items-center justify-center",
                        confirmModal.type === 'error' ? "bg-rose-50 dark:bg-rose-500/10 text-rose-600" :
                            confirmModal.type === 'warning' ? "bg-amber-50 dark:bg-amber-500/10 text-amber-600" :
                                "bg-indigo-50 dark:bg-indigo-500/10 text-indigo-600"
                    )}>
                        <Bell className="w-7 h-7" />
                    </div>
                    <div className="space-y-2">
                        <h4 className="text-xl font-black text-slate-900 dark:text-white tracking-tight">{confirmModal.title}</h4>
                        <p className="text-sm text-slate-500 font-bold leading-relaxed px-4">{confirmModal.message}</p>
                    </div>
                    <div className="flex gap-3 w-full">
                        <button
                            onClick={() => setConfirmModal(prev => ({ ...prev, open: false }))}
                            className="flex-1 py-4 bg-slate-100 dark:bg-slate-900 text-slate-500 font-black rounded-2xl hover:bg-slate-200 dark:hover:bg-slate-800 transition-all text-sm"
                        >
                            취소
                        </button>
                        <button
                            onClick={confirmModal.onConfirm}
                            className={cn(
                                "flex-1 py-4 text-white font-black rounded-2xl transition-all shadow-xl active:scale-95 text-sm",
                                confirmModal.type === 'error' ? "bg-rose-600 hover:bg-rose-500 shadow-rose-600/20" :
                                    confirmModal.type === 'warning' ? "bg-amber-600 hover:bg-amber-500 shadow-amber-600/20" :
                                        "bg-indigo-600 hover:bg-indigo-500 shadow-indigo-600/20"
                            )}
                        >
                            확인
                        </button>
                    </div>
                </div>
            </Modal>

        </div>
    );
}

