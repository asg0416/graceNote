'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Plus,
    Search,
    Church,
    Edit2,
    Trash2,
    Loader2,
    Users,
    MapPin,
    X,
    PlusCircle,
    MoreHorizontal,
    ArrowUpRight,
    Activity,
    UserCheck
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Modal } from '@/components/Modal';

export default function ChurchesPage() {
    const [loading, setLoading] = useState(true);
    const [churches, setChurches] = useState<any[]>([]);
    const [searchTerm, setSearchTerm] = useState('');
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [editingChurch, setEditingChurch] = useState<any>(null);
    const [newChurchName, setNewChurchName] = useState('');
    const [newChurchLocation, setNewChurchLocation] = useState('');
    const router = useRouter();

    useEffect(() => {
        const checkUser = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                router.push('/login');
                return;
            }

            const { data: profile } = await supabase
                .from('profiles')
                .select('is_master')
                .eq('id', session.user.id)
                .single();

            if (!profile?.is_master) {
                router.push('/');
                return;
            }

            fetchChurches();
        };
        checkUser();
    }, []);

    const fetchChurches = async () => {
        setLoading(true);
        try {
            const { data, error } = await supabase.from('churches').select('*').order('name');
            if (error) throw error;

            // Fetch real counts for each church
            const churchesWithStats = await Promise.all(data.map(async (c) => {
                const { count: memberCount } = await supabase
                    .from('profiles')
                    .select('id', { count: 'exact', head: true })
                    .eq('church_id', c.id);

                const { count: deptCount } = await supabase
                    .from('departments')
                    .select('*', { count: 'exact', head: true })
                    .eq('church_id', c.id);

                // Find an admin for this church if any
                const { data: adminData } = await supabase
                    .from('profiles')
                    .select('full_name')
                    .eq('church_id', c.id)
                    .eq('role', 'admin')
                    .limit(1);

                return {
                    ...c,
                    memberCount: memberCount || 0,
                    deptCount: deptCount || 0,
                    adminName: adminData?.[0]?.full_name || '관리자 미지정',
                    status: 'active'
                };
            }));

            setChurches(churchesWithStats);
        } catch (err) {
            console.error(err);
        } finally {
            setLoading(false);
        }
    };

    const handleCreateOrUpdate = async (e: React.FormEvent) => {
        e.preventDefault();
        try {
            if (editingChurch) {
                const { error } = await supabase
                    .from('churches')
                    .update({ name: newChurchName, address: newChurchLocation })
                    .eq('id', editingChurch.id);
                if (error) throw error;
            } else {
                const { error } = await supabase
                    .from('churches')
                    .insert({ name: newChurchName, address: newChurchLocation });
                if (error) throw error;
            }
            setIsModalOpen(false);
            setEditingChurch(null);
            setNewChurchName('');
            setNewChurchLocation('');
            fetchChurches();
        } catch (err) {
            alert('오류가 발생했습니다.');
        }
    };

    const handleDelete = async (id: string) => {
        if (!confirm('정말로 이 교회를 삭제하시겠습니까? 관련 데이터가 모두 삭제될 수 있습니다.')) return;
        try {
            const { error } = await supabase.from('churches').delete().eq('id', id);
            if (error) throw error;
            fetchChurches();
        } catch (err) {
            alert('삭제 중 오류가 발생했습니다.');
        }
    };

    const filteredChurches = churches.filter(c =>
        c.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        (c.address && c.address.toLowerCase().includes(searchTerm.toLowerCase()))
    );

    return (
        <div className="space-y-8 sm:space-y-10 max-w-7xl mx-auto">
            <header className="flex flex-col sm:flex-row sm:items-center justify-between gap-6">
                <div className="space-y-1.5">
                    <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">전체 교회 관리</h1>
                    <p className="text-slate-500 dark:text-slate-500 font-bold text-xs sm:text-sm tracking-tight max-w-xl">시스템에 등록된 모든 교회를 통합 관리하고 데이터를 분석합니다.</p>
                </div>
                <button
                    onClick={() => {
                        setEditingChurch(null);
                        setNewChurchName('');
                        setNewChurchLocation('');
                        setIsModalOpen(true);
                    }}
                    className="w-full sm:w-fit bg-indigo-600 text-white px-8 py-4 rounded-2xl sm:rounded-[28px] font-black text-sm hover:bg-indigo-500 hover:scale-105 transition-all flex items-center justify-center gap-2.5 shadow-xl shadow-indigo-600/20 active:scale-95 border border-indigo-400/20"
                >
                    <PlusCircle className="w-5 h-5" />
                    신규 교회 등록
                </button>
            </header>

            {/* Stats Summary */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
                <StatsSummaryCard title="총 등록 교회" value={churches.length.toString()} unit="개" icon={Church} color="slate" />
                <StatsSummaryCard title="총 활성 성도" value="1.2k" unit="명" isPrimary icon={Users} color="indigo" />
                <StatsSummaryCard title="이번 달 신규 교회" value="3" unit="곳" icon={Activity} color="emerald" />
            </div>

            {/* Search and Filters */}
            <div className="group">
                <div className="relative">
                    <Search className="absolute left-5 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 dark:text-slate-50 group-focus-within:text-indigo-600 dark:group-focus-within:text-indigo-400 transition-colors" />
                    <input
                        type="text"
                        placeholder="교회 이름 또는 주소로 검색..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        className="w-full pl-14 pr-6 py-4 bg-white dark:bg-[#111827]/60 backdrop-blur-xl border border-slate-200 dark:border-slate-800/80 rounded-[28px] focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold placeholder:text-slate-400 dark:placeholder:text-slate-600 transition-all shadow-lg dark:shadow-none"
                    />
                </div>
            </div>

            {/* Church List */}
            <div className="bg-white dark:bg-[#111827]/60 backdrop-blur-xl rounded-[32px] sm:rounded-[40px] border border-slate-200 dark:border-slate-800/80 overflow-hidden shadow-xl dark:shadow-2xl">
                {loading ? (
                    <div className="p-32 flex flex-col items-center justify-center gap-6 text-center">
                        <Loader2 className="w-12 h-12 text-indigo-600 dark:text-indigo-500 animate-spin" />
                        <p className="text-slate-400 dark:text-slate-500 font-black uppercase tracking-[0.2em] text-xs">Loading Databases...</p>
                    </div>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full">
                            <thead>
                                <tr className="bg-slate-50 dark:bg-slate-900/40 border-b border-slate-200 dark:border-slate-800/60">
                                    <th className="px-6 sm:px-8 py-5 sm:py-6 text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] text-left">교회 프로필</th>
                                    <th className="px-6 sm:px-8 py-5 sm:py-6 text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] text-left hidden md:table-cell">상세 정보</th>
                                    <th className="px-6 sm:px-8 py-5 sm:py-6 text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] text-left hidden lg:table-cell">통계 분석</th>
                                    <th className="px-6 sm:px-8 py-5 sm:py-6 text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] text-right">관리</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100 dark:divide-slate-800/40">
                                {filteredChurches.map((church) => (
                                    <tr key={church.id} className="hover:bg-indigo-50 dark:hover:bg-indigo-500/[0.02] transition-colors group">
                                        <td className="px-6 sm:px-8 py-6 sm:py-7">
                                            <div className="flex items-center gap-4 sm:gap-5">
                                                <div className="w-12 h-12 sm:w-14 sm:h-14 rounded-xl sm:rounded-2xl bg-indigo-50 dark:bg-indigo-500/10 border border-indigo-100 dark:border-indigo-500/20 flex items-center justify-center text-indigo-600 dark:text-indigo-400 group-hover:scale-110 group-hover:bg-indigo-100 dark:group-hover:bg-indigo-500/20 transition-all duration-300">
                                                    <Church className="w-6 sm:w-7 h-6 sm:h-7" />
                                                </div>
                                                <div>
                                                    <p className="font-black text-slate-900 dark:text-white text-base sm:text-lg tracking-tight">{church.name}</p>
                                                    <div className="flex items-center gap-2 mt-0.5">
                                                        <div className={cn("w-1.5 h-1.5 rounded-full", church.status === 'active' ? "bg-emerald-500" : "bg-slate-300 dark:bg-slate-700")} />
                                                        <span className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest">{church.status === 'active' ? '운영 중' : '중지됨'}</span>
                                                    </div>
                                                </div>
                                            </div>
                                        </td>
                                        <td className="px-6 sm:px-8 py-6 sm:py-7 hidden md:table-cell">
                                            <div className="space-y-1.5">
                                                <div className="flex items-center gap-2 text-slate-500 dark:text-slate-400">
                                                    <MapPin className="w-3.5 h-3.5" />
                                                    <span className="text-xs font-bold truncate max-w-[180px]">{church.address || '주소 미등록'}</span>
                                                </div>
                                                <div className="flex items-center gap-2 text-indigo-600 dark:text-indigo-400">
                                                    <UserCheck className="w-3.5 h-3.5" />
                                                    <span className="text-[10px] font-black uppercase tracking-tight">{church.adminName}</span>
                                                </div>
                                            </div>
                                        </td>
                                        <td className="px-6 sm:px-8 py-6 sm:py-7 hidden lg:table-cell">
                                            <div className="flex items-center gap-6">
                                                <div className="text-center">
                                                    <p className="text-base sm:text-lg font-black text-slate-900 dark:text-white">{church.memberCount}</p>
                                                    <p className="text-[9px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest">성도 수</p>
                                                </div>
                                                <div className="w-[1px] h-8 bg-slate-100 dark:bg-slate-800" />
                                                <div className="text-center">
                                                    <p className="text-base sm:text-lg font-black text-slate-900 dark:text-white">{church.deptCount}</p>
                                                    <p className="text-[9px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest">부서</p>
                                                </div>
                                            </div>
                                        </td>
                                        <td className="px-6 sm:px-8 py-6 sm:py-7 text-right">
                                            <div className="flex items-center justify-end gap-2 sm:gap-2.5">
                                                <button
                                                    onClick={() => {
                                                        setEditingChurch(church);
                                                        setNewChurchName(church.name);
                                                        setNewChurchLocation(church.address || '');
                                                        setIsModalOpen(true);
                                                    }}
                                                    className="w-10 h-10 flex items-center justify-center text-slate-400 dark:text-slate-500 hover:text-indigo-600 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-800/80 rounded-xl transition-all border border-transparent hover:border-slate-200 dark:hover:border-slate-700"
                                                >
                                                    <Edit2 className="w-4 h-4" />
                                                </button>
                                                <button
                                                    onClick={() => handleDelete(church.id)}
                                                    className="w-10 h-10 flex items-center justify-center text-slate-400 dark:text-slate-500 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-500/10 rounded-xl transition-all border border-transparent hover:border-red-100 dark:hover:border-red-500/20"
                                                >
                                                    <Trash2 className="w-4 h-4" />
                                                </button>
                                            </div>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>

            {/* Modal - Responsive */}
            <Modal
                isOpen={isModalOpen}
                onClose={() => setIsModalOpen(false)}
                title={editingChurch ? '교회 정보 수정' : '신규 교회 등록'}
                subtitle="Administrative Action"
                maxWidth="xl"
            >
                <form onSubmit={handleCreateOrUpdate} className="space-y-6 sm:space-y-8">
                    <div className="space-y-3">
                        <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">Church Name</label>
                        <input
                            type="text"
                            required
                            value={newChurchName}
                            onChange={(e) => setNewChurchName(e.target.value)}
                            className="w-full px-6 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold transition-all"
                            placeholder="은혜로운 교회"
                        />
                    </div>

                    <div className="space-y-3">
                        <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">Location Details</label>
                        <input
                            type="text"
                            value={newChurchLocation}
                            onChange={(e) => setNewChurchLocation(e.target.value)}
                            className="w-full px-6 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold transition-all"
                            placeholder="서울특별시 강남구..."
                        />
                    </div>

                    <div className="flex flex-col sm:flex-row gap-4 pt-4">
                        <button
                            type="button"
                            onClick={() => setIsModalOpen(false)}
                            className="w-full sm:flex-1 py-4 bg-slate-100 dark:bg-slate-900 text-slate-500 font-black rounded-2xl sm:rounded-3xl hover:bg-slate-200 dark:hover:bg-slate-800 transition-all border border-slate-200 dark:border-slate-800 order-2 sm:order-1"
                        >
                            취소
                        </button>
                        <button
                            type="submit"
                            className="w-full sm:flex-1 py-4 bg-indigo-600 text-white font-black rounded-2xl sm:rounded-3xl hover:bg-indigo-500 transition-all shadow-xl shadow-indigo-600/10 border border-indigo-400/20 active:scale-95 order-1 sm:order-2"
                        >
                            {editingChurch ? '정보 업데이트' : '신규 등록 완료'}
                        </button>
                    </div>
                </form>
            </Modal>
        </div>
    );
}

function StatsSummaryCard({ title, value, unit, isPrimary, icon: Icon, color }: any) {
    return (
        <div className={cn(
            "p-6 sm:p-8 rounded-[32px] sm:rounded-[40px] border relative overflow-hidden group transition-all duration-300 shadow-lg dark:shadow-none",
            isPrimary
                ? "bg-gradient-to-br from-indigo-600 to-indigo-800 border-indigo-400/20 shadow-indigo-600/10"
                : "bg-white dark:bg-[#111827]/60 backdrop-blur-xl border-slate-200 dark:border-slate-800/80 hover:border-indigo-200 dark:hover:border-slate-700"
        )}>
            <div className="flex flex-col h-full justify-between gap-4">
                <div className="flex items-center justify-between">
                    <p className={cn("text-[10px] font-black uppercase tracking-[0.2em]", isPrimary ? "text-indigo-100/60" : "text-slate-400 dark:text-slate-500")}>
                        {title}
                    </p>
                    <div className={cn("p-2 rounded-lg", isPrimary ? "bg-white/10 text-white" : "bg-slate-50 dark:bg-slate-800 text-slate-400 dark:text-slate-500")}>
                        <Icon className="w-4 h-4" />
                    </div>
                </div>
                <div className="flex items-baseline gap-2">
                    <h4 className={cn("text-3xl sm:text-4xl font-black tracking-tighter", isPrimary ? "text-white" : "text-slate-900 dark:text-white")}>{value}</h4>
                    <span className={cn("text-sm font-bold", isPrimary ? "text-indigo-200" : "text-slate-400 dark:text-slate-500")}>{unit}</span>
                </div>
            </div>
        </div>
    );
}
