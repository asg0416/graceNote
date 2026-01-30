'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Plus,
    Edit2,
    Trash2,
    Loader2,
    Layers,
    Users,
    PlusCircle,
    X,
    LayoutGrid,
    Church,
    ChevronDown,
    Search
} from 'lucide-react';
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

    const [isDeptModalOpen, setIsDeptModalOpen] = useState(false);
    const [isGroupModalOpen, setIsGroupModalOpen] = useState(false);
    const [editingDept, setEditingDept] = useState<any>(null);
    const [editingGroup, setEditingGroup] = useState<any>(null);
    const [selectedDeptId, setSelectedDeptId] = useState<string | null>(null);

    const [deptName, setDeptName] = useState('');
    const [profileMode, setProfileMode] = useState<'individual' | 'couple'>('individual');
    const [deptColor, setDeptColor] = useState('#4f46e5');
    const [groupName, setGroupName] = useState('');
    const [groupColor, setGroupColor] = useState('#4f46e5');

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

    const handleDeptSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!currentChurchId) return;

        try {
            if (editingDept) {
                const { error } = await supabase
                    .from('departments')
                    .update({
                        name: deptName,
                        profile_mode: profileMode,
                        color_hex: deptColor
                    })
                    .eq('id', editingDept.id);
                if (error) throw error;
            } else {
                const { error } = await supabase
                    .from('departments')
                    .insert({
                        name: deptName,
                        profile_mode: profileMode,
                        church_id: currentChurchId,
                        color_hex: deptColor
                    });
                if (error) throw error;
            }
            setIsDeptModalOpen(false);
            setEditingDept(null);
            setDeptName('');
            setProfileMode('individual');
            setDeptColor('#4f46e5');
            fetchData(currentChurchId);
        } catch (err: any) {
            console.error('Dept Submit Error:', err);
            alert('오류가 발생했습니다: ' + (err.message || '알 수 없는 오류'));
        }
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
                        color_hex: groupColor
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
                        color_hex: groupColor
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

    const handleDeleteDept = async (id: string) => {
        if (!confirm('부서를 삭제하시겠습니까? 부서에 속한 모든 조가 삭제됩니다.')) return;
        try {
            const { error } = await supabase.from('departments').delete().eq('id', id);
            if (error) throw error;
            fetchData(currentChurchId!);
        } catch (err) {
            alert('삭제 중 오류가 발생했습니다.');
        }
    };

    const handleDeleteGroup = async (id: string) => {
        if (!confirm('조를 삭제하시겠습니까?')) return;
        try {
            const { error } = await supabase.from('groups').delete().eq('id', id);
            if (error) throw error;
            fetchData(currentChurchId!);
        } catch (err) {
            alert('삭제 중 오류가 발생했습니다.');
        }
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
                    <button
                        onClick={() => {
                            setEditingDept(null);
                            setDeptName('');
                            setDeptColor('#4f46e5');
                            setProfileMode('individual');
                            setIsDeptModalOpen(true);
                        }}
                        disabled={!currentChurchId}
                        className="w-full lg:w-fit bg-indigo-600 dark:bg-indigo-500 text-white px-6 sm:px-8 py-3.5 sm:py-4 rounded-xl sm:rounded-[28px] font-black text-xs sm:text-sm hover:bg-indigo-500 dark:hover:bg-indigo-400 hover:scale-[1.02] transition-all flex items-center justify-center gap-2.5 shadow-xl shadow-indigo-600/10 active:scale-95 border border-indigo-400/20 disabled:opacity-50"
                    >
                        <PlusCircle className="w-4 sm:w-5 h-4 sm:h-5" />
                        신규 부서 추가
                    </button>
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
                                    <button
                                        onClick={() => {
                                            setEditingDept(dept);
                                            setDeptName(dept.name);
                                            setProfileMode(dept.profile_mode || 'individual');
                                            setDeptColor(dept.color_hex || '#4f46e5');
                                            setIsDeptModalOpen(true);
                                        }}
                                        className="w-10 h-10 sm:w-12 sm:h-12 flex items-center justify-center rounded-xl sm:rounded-2xl border border-slate-100 dark:border-slate-800 text-slate-400 dark:text-slate-500 hover:text-indigo-600 dark:hover:text-white hover:bg-slate-50 dark:hover:bg-slate-800 transition-all"
                                    >
                                        <Edit2 className="w-5 h-5" />
                                    </button>
                                    {(isMaster || !assignedDeptId) && (
                                        <button
                                            onClick={() => handleDeleteDept(dept.id)}
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
                                                        setSelectedDeptId(dept.id);
                                                        setIsGroupModalOpen(true);
                                                    }}
                                                    className="p-1 px-1.5 text-slate-400 hover:text-indigo-600 transition-colors"
                                                >
                                                    <Edit2 className="w-3 h-3" />
                                                </button>
                                                <button
                                                    onClick={() => handleDeleteGroup(group.id)}
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

            {/* Department Modal */}
            <Modal
                isOpen={isDeptModalOpen}
                onClose={() => setIsDeptModalOpen(false)}
                title={editingDept ? '부서 정보 수정' : '신규 부서 생성'}
                subtitle="설정 및 관리 패널"
                maxWidth="lg"
            >
                <form onSubmit={handleDeptSubmit} className="space-y-6 sm:space-y-8">
                    <div className="space-y-6">
                        <div className="space-y-2.5">
                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">부서 이름</label>
                            <input
                                type="text"
                                required
                                value={deptName}
                                onChange={(e) => setDeptName(e.target.value)}
                                className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl focus:outline-none focus:border-indigo-500 text-slate-900 dark:text-white font-bold transition-all text-sm"
                                placeholder="교구, 청년부 등..."
                            />
                        </div>

                        <div className="space-y-2.5">
                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">부서 테마 색상</label>
                            <div className="flex flex-wrap gap-2.5">
                                {colorPalette.map(color => (
                                    <button
                                        key={color.hex}
                                        type="button"
                                        onClick={() => setDeptColor(color.hex)}
                                        className={cn(
                                            "w-8 h-8 rounded-full border-2 transition-all p-0.5",
                                            deptColor === color.hex ? "border-slate-900 dark:border-white scale-110" : "border-transparent"
                                        )}
                                    >
                                        <div className="w-full h-full rounded-full" style={{ backgroundColor: color.hex }} />
                                    </button>
                                ))}
                                <div className="relative">
                                    <input
                                        type="color"
                                        id="dept-custom-color"
                                        className="sr-only"
                                        value={deptColor}
                                        onChange={(e) => setDeptColor(e.target.value)}
                                    />
                                    <label
                                        htmlFor="dept-custom-color"
                                        className={cn(
                                            "w-8 h-8 rounded-full border-2 transition-all p-0.5 flex items-center justify-center cursor-pointer relative",
                                            !colorPalette.some(c => c.hex.toLowerCase() === deptColor.toLowerCase())
                                                ? "border-slate-900 dark:border-white scale-110"
                                                : "border-dashed border-slate-300 dark:border-slate-700 bg-slate-50/50 dark:bg-slate-900/50"
                                        )}
                                    >
                                        {!colorPalette.some(c => c.hex.toLowerCase() === deptColor.toLowerCase()) && (
                                            <div className="absolute inset-0.5 rounded-full" style={{ backgroundColor: deptColor }} />
                                        )}
                                        <Plus className={cn(
                                            "w-3.5 h-3.5 relative z-10 transition-colors",
                                            !colorPalette.some(c => c.hex.toLowerCase() === deptColor.toLowerCase())
                                                ? "text-white drop-shadow-sm"
                                                : "text-slate-400"
                                        )} />
                                    </label>
                                </div>
                            </div>
                        </div>

                        <div className="space-y-2.5">
                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">성도 관리 모드</label>
                            <div className="grid grid-cols-2 gap-3">
                                <button
                                    type="button"
                                    onClick={() => setProfileMode('individual')}
                                    className={cn(
                                        "p-4 rounded-xl border-2 transition-all flex flex-col gap-1.5 items-start text-left",
                                        profileMode === 'individual'
                                            ? "bg-indigo-50/50 border-indigo-500/50 dark:bg-indigo-500/10"
                                            : "border-slate-100 dark:border-slate-800 hover:border-slate-200 dark:hover:border-slate-700"
                                    )}
                                >
                                    <Users className={cn("w-4 h-4", profileMode === 'individual' ? "text-indigo-600" : "text-slate-400")} />
                                    <div>
                                        <p className={cn("font-black text-[13px]", profileMode === 'individual' ? "text-indigo-900 dark:text-indigo-100" : "text-slate-900 dark:text-slate-400")}>개인형</p>
                                        <p className="text-[9px] text-slate-500 font-bold opacity-70">1인 1프로필 관리</p>
                                    </div>
                                </button>
                                <button
                                    type="button"
                                    onClick={() => setProfileMode('couple')}
                                    className={cn(
                                        "p-4 rounded-xl border-2 transition-all flex flex-col gap-1.5 items-start text-left",
                                        profileMode === 'couple'
                                            ? "bg-indigo-50/50 border-indigo-500/50 dark:bg-indigo-500/10"
                                            : "border-slate-100 dark:border-slate-800 hover:border-slate-200 dark:hover:border-slate-700"
                                    )}
                                >
                                    <LayoutGrid className={cn("w-4 h-4", profileMode === 'couple' ? "text-indigo-600" : "text-slate-400")} />
                                    <div>
                                        <p className={cn("font-black text-[13px]", profileMode === 'couple' ? "text-indigo-900 dark:text-indigo-100" : "text-slate-900 dark:text-slate-400")}>부부형</p>
                                        <p className="text-[9px] text-slate-500 font-bold opacity-70">부부/가족 단위 정렬 강조</p>
                                    </div>
                                </button>
                            </div>
                        </div>
                    </div>

                    <div className="flex gap-3 pt-2">
                        <button
                            type="button"
                            onClick={() => setIsDeptModalOpen(false)}
                            className="flex-1 py-3.5 bg-slate-100 dark:bg-slate-900 text-slate-500 font-black rounded-xl hover:bg-slate-200 dark:hover:bg-slate-800/60 transition-all text-sm"
                        >
                            취소
                        </button>
                        <button
                            type="submit"
                            className="flex-1 py-3.5 bg-indigo-600 dark:bg-indigo-500 text-white font-black rounded-xl hover:bg-indigo-500 hover:scale-[1.02] transition-all shadow-lg shadow-indigo-600/10 active:scale-95 text-sm"
                        >
                            실행 완료
                        </button>
                    </div>
                </form>
            </Modal>

            {/* Group Modal */}
            <Modal
                isOpen={isGroupModalOpen}
                onClose={() => setIsGroupModalOpen(false)}
                title={editingGroup ? '조 정보 수정' : '신규 조 생성'}
                subtitle="설정 및 관리 패널"
                maxWidth="lg"
            >
                <form onSubmit={handleGroupSubmit} className="space-y-6 sm:space-y-8">
                    <div className="space-y-6">
                        <div className="space-y-2.5">
                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">조 이름</label>
                            <input
                                type="text"
                                required
                                value={groupName}
                                onChange={(e) => setGroupName(e.target.value)}
                                className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl focus:outline-none focus:border-indigo-500 text-slate-900 dark:text-white font-bold transition-all text-sm"
                                placeholder="1조, 2조 등..."
                            />
                        </div>

                        <div className="space-y-2.5">
                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">조 테마 색상</label>
                            <div className="flex flex-wrap gap-2.5">
                                {colorPalette.map(color => (
                                    <button
                                        key={color.hex}
                                        type="button"
                                        onClick={() => setGroupColor(color.hex)}
                                        className={cn(
                                            "w-8 h-8 rounded-full border-2 transition-all p-0.5",
                                            groupColor === color.hex ? "border-slate-900 dark:border-white scale-110" : "border-transparent"
                                        )}
                                    >
                                        <div className="w-full h-full rounded-full" style={{ backgroundColor: color.hex }} />
                                    </button>
                                ))}
                                <div className="relative">
                                    <input
                                        type="color"
                                        id="group-custom-color"
                                        className="sr-only"
                                        value={groupColor}
                                        onChange={(e) => setGroupColor(e.target.value)}
                                    />
                                    <label
                                        htmlFor="group-custom-color"
                                        className={cn(
                                            "w-8 h-8 rounded-full border-2 transition-all p-0.5 flex items-center justify-center cursor-pointer relative",
                                            !colorPalette.some(c => c.hex.toLowerCase() === groupColor.toLowerCase())
                                                ? "border-slate-900 dark:border-white scale-110"
                                                : "border-dashed border-slate-300 dark:border-slate-700 bg-slate-50/50 dark:bg-slate-900/50"
                                        )}
                                    >
                                        {!colorPalette.some(c => c.hex.toLowerCase() === groupColor.toLowerCase()) && (
                                            <div className="absolute inset-0.5 rounded-full" style={{ backgroundColor: groupColor }} />
                                        )}
                                        <Plus className={cn(
                                            "w-3.5 h-3.5 relative z-10 transition-colors",
                                            !colorPalette.some(c => c.hex.toLowerCase() === groupColor.toLowerCase())
                                                ? "text-white drop-shadow-sm"
                                                : "text-slate-400"
                                        )} />
                                    </label>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div className="flex gap-3 pt-2">
                        <button
                            type="button"
                            onClick={() => setIsGroupModalOpen(false)}
                            className="flex-1 py-3.5 bg-slate-100 dark:bg-slate-900 text-slate-500 font-black rounded-xl hover:bg-slate-200 dark:hover:bg-slate-800/60 transition-all text-sm"
                        >
                            취소
                        </button>
                        <button
                            type="submit"
                            className="flex-1 py-3.5 bg-indigo-600 dark:bg-indigo-500 text-white font-black rounded-xl hover:bg-indigo-500 hover:scale-[1.02] transition-all shadow-lg shadow-indigo-600/10 active:scale-95 text-sm"
                        >
                            실행 완료
                        </button>
                    </div>
                </form>
            </Modal>
        </div>
    );
}

