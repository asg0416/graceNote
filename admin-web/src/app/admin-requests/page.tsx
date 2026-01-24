'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    UserCheck,
    Search,
    Loader2,
    Mail,
    Clock,
    CheckCircle2,
    XCircle,
    ShieldCheck,
    Phone,
    Building2,
    Calendar,
    ChevronDown,
    ChevronUp
} from 'lucide-react';
import { cn } from '@/lib/utils';

interface RequestItem {
    id: string;
    full_name: string;
    email: string | null;
    phone: string | null;
    admin_status: 'pending' | 'approved' | 'rejected' | 'none';
    role: string;
    is_master: boolean;
    church_id: string | null;
    created_at: string;
    churches?: { name: string };
    departments?: { name: string };
}

export default function AdminRequestsPage() {
    const [loading, setLoading] = useState(true);
    const [requests, setRequests] = useState<RequestItem[]>([]);
    const [searchTerm, setSearchTerm] = useState('');
    const [activeTab, setActiveTab] = useState<'pending' | 'completed'>('pending');
    const [profile, setProfile] = useState<RequestItem | null>(null);
    const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());
    const router = useRouter();

    const toggleRow = (id: string) => {
        const newSet = new Set(expandedRows);
        if (newSet.has(id)) {
            newSet.delete(id);
        } else {
            newSet.add(id);
        }
        setExpandedRows(newSet);
    };

    const fetchRequests = React.useCallback(async (currentProfile: RequestItem) => {
        setLoading(true);
        try {
            let query = supabase
                .from('profiles')
                .select(`
                    *,
                    churches (name),
                    departments (name)
                `)
                .neq('admin_status', 'none');

            if (currentProfile.role === 'admin' && !currentProfile.is_master) {
                query = query.eq('church_id', currentProfile.church_id);
            }

            const { data, error } = await query.order('created_at', { ascending: false });

            if (error) throw error;
            setRequests(data || []);
        } catch (error) {
            console.error('Error fetching requests:', error);
        } finally {
            setLoading(false);
        }
    }, []);

    const init = React.useCallback(async () => {
        const { data: { session } } = await supabase.auth.getSession();
        if (!session) {
            router.push('/login');
            return;
        }

        const { data: profile } = await supabase
            .from('profiles')
            .select('*')
            .eq('id', session.user.id)
            .single();

        if (!profile || !profile.is_master) {
            router.push('/login?error=unauthorized');
            return;
        }

        setProfile(profile);
        await fetchRequests(profile);
    }, [router, fetchRequests]);

    useEffect(() => {
        init();
    }, [init]);

    const handleStatusChange = async (targetId: string, newStatus: 'approved' | 'rejected') => {
        try {
            const { error } = await supabase
                .from('profiles')
                .update({
                    admin_status: newStatus,
                    role: newStatus === 'approved' ? 'admin' : 'member'
                })
                .eq('id', targetId);

            if (error) throw error;
            if (profile) await fetchRequests(profile);
        } catch (error) {
            console.error('Error updating status:', error);
            alert('상태 업데이트 중 오류가 발생했습니다.');
        }
    };

    const filteredRequests = requests.filter(req => {
        const matchesTab = activeTab === 'pending'
            ? req.admin_status === 'pending'
            : (req.admin_status === 'approved' || req.admin_status === 'rejected');

        const matchesSearch =
            req.full_name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
            req.email?.toLowerCase().includes(searchTerm.toLowerCase()) ||
            req.churches?.name?.toLowerCase().includes(searchTerm.toLowerCase());

        return matchesTab && matchesSearch;
    });

    return (
        <div className="space-y-8 sm:space-y-12 max-w-7xl mx-auto">
            <header className="space-y-8">
                <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
                    <div className="space-y-1.5">
                        <div className="inline-flex items-center gap-2 px-3 py-1 bg-indigo-600/10 dark:bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 rounded-full text-[10px] font-black uppercase tracking-widest border border-indigo-600/20 mb-2">
                            <UserCheck className="w-3.5 h-3.5" />
                            Admin Management
                        </div>
                        <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">
                            관리자 권한 요청 <span className="text-indigo-600 dark:text-indigo-400">내역</span>
                        </h1>
                        <p className="text-slate-500 dark:text-slate-500 font-bold text-xs sm:text-sm tracking-tight">
                            {profile?.is_master
                                ? '전체 교회의 관리자 권한 신청 내역을 검토하고 승인할 수 있습니다.'
                                : `${profile?.churches?.name || '소속 교회'}의 관리자 권한 신청 내역입니다.`}
                        </p>
                    </div>

                    <div className="flex bg-white dark:bg-[#111827]/40 p-1 rounded-2xl border border-slate-200 dark:border-slate-800 shadow-sm min-w-[240px]">
                        <button
                            onClick={() => setActiveTab('pending')}
                            className={cn(
                                "flex-1 px-4 py-2 rounded-xl text-xs font-black transition-all duration-300",
                                activeTab === 'pending'
                                    ? "bg-indigo-600 text-white shadow-lg shadow-indigo-200 dark:shadow-none"
                                    : "text-slate-400 hover:text-slate-600 dark:hover:text-slate-300"
                            )}
                        >
                            대기 중인 요청
                        </button>
                        <button
                            onClick={() => setActiveTab('completed')}
                            className={cn(
                                "flex-1 px-4 py-2 rounded-xl text-xs font-black transition-all duration-300",
                                activeTab === 'completed'
                                    ? "bg-indigo-600 text-white shadow-lg shadow-indigo-200 dark:shadow-none"
                                    : "text-slate-400 hover:text-slate-600 dark:hover:text-slate-300"
                            )}
                        >
                            처리 완료
                        </button>
                    </div>
                </div>

                <div className="relative group">
                    <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-300 group-focus-within:text-indigo-500 transition-colors" />
                    <input
                        type="text"
                        placeholder="이름, 이메일, 교회명으로 검색..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        className="w-full h-[56px] pl-12 pr-6 bg-white dark:bg-[#111827]/40 border border-slate-200 dark:border-slate-800 rounded-2xl text-slate-700 dark:text-slate-200 font-bold text-sm focus:outline-none focus:ring-4 focus:ring-indigo-500/10 focus:border-indigo-500 transition-all shadow-sm group-hover:border-slate-300 dark:group-hover:border-slate-700"
                    />
                </div>
            </header>

            <div className="bg-white dark:bg-[#111827]/60 backdrop-blur-xl border border-slate-200 dark:border-slate-800/60 rounded-[32px] sm:rounded-[40px] shadow-xl dark:shadow-2xl overflow-hidden mb-12">
                {loading ? (
                    <div className="py-20 flex flex-col items-center justify-center gap-6">
                        <div className="relative">
                            <div className="w-16 h-16 border-4 border-indigo-600/20 border-t-indigo-600 rounded-full animate-spin" />
                            <Loader2 className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-6 h-6 text-indigo-600 animate-pulse" />
                        </div>
                        <p className="text-slate-400 font-black text-xs uppercase tracking-[0.3em] animate-pulse">Requesting Data...</p>
                    </div>
                ) : filteredRequests.length === 0 ? (
                    <div className="py-20 flex flex-col items-center justify-center gap-8 text-center px-10">
                        <div className="w-24 h-24 bg-gradient-to-b from-slate-50 to-slate-100 dark:from-slate-800/50 dark:to-slate-900/50 border border-slate-200/50 dark:border-slate-700/50 rounded-full flex items-center justify-center shadow-inner">
                            <ShieldCheck className="w-12 h-12 text-slate-300 dark:text-slate-600" />
                        </div>
                        <div className="space-y-3">
                            <h3 className="text-2xl font-black text-slate-900 dark:text-white tracking-tight">표시할 요청이 없습니다</h3>
                            <p className="text-slate-500 font-medium max-w-sm mx-auto text-sm leading-relaxed">
                                현재 선택된 항목에 해당하는 권한 요청 내역이 없습니다. 다른 탭을 확인하거나 검색어를 지워보세요.
                            </p>
                        </div>
                    </div>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full border-separate border-spacing-y-0">
                            <thead>
                                <tr className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] bg-slate-50/50 dark:bg-slate-800/20">
                                    <th className="pl-6 sm:pl-10 py-5 text-left">신청자</th>
                                    <th className="px-6 py-5 text-left hidden md:table-cell">소속 요약</th>
                                    <th className="px-6 py-5 text-center">진행 상태</th>
                                    <th className="pr-6 sm:pr-10 py-5 text-right">관리 제어</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100 dark:divide-slate-800/50">
                                {filteredRequests.map((req) => {
                                    const isExpanded = expandedRows.has(req.id);
                                    return (
                                        <React.Fragment key={req.id}>
                                            <tr
                                                onClick={() => toggleRow(req.id)}
                                                className={cn(
                                                    "group cursor-pointer transition-all duration-300",
                                                    isExpanded
                                                        ? "bg-indigo-50/50 dark:bg-indigo-500/5 shadow-sm"
                                                        : "hover:bg-slate-50 dark:hover:bg-slate-800/40"
                                                )}
                                            >
                                                <td className="pl-6 sm:pl-10 py-5">
                                                    <div className="flex items-center gap-4">
                                                        <div className="w-10 h-10 rounded-xl bg-slate-100 dark:bg-slate-800/40 flex items-center justify-center text-slate-400 font-black group-hover:scale-105 group-hover:bg-indigo-600 group-hover:text-white transition-all duration-300 text-sm">
                                                            {req.full_name?.[0] || 'U'}
                                                        </div>
                                                        <div>
                                                            <p className="font-black text-slate-900 dark:text-white text-base tracking-tight hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors leading-none mb-1">{req.full_name}</p>
                                                            <p className="text-[9px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest leading-none">{req.email}</p>
                                                        </div>
                                                    </div>
                                                </td>
                                                <td className="px-6 py-5 hidden md:table-cell text-left">
                                                    <div className="flex flex-col">
                                                        <span className="text-xs font-bold text-slate-600 dark:text-slate-300">{req.churches?.name}</span>
                                                        {req.departments?.name && (
                                                            <span className="text-[10px] text-slate-400 font-bold">
                                                                {req.departments.name}
                                                            </span>
                                                        )}
                                                    </div>
                                                </td>
                                                <td className="px-6 py-5 text-center">
                                                    {req.admin_status === 'pending' ? (
                                                        <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-yellow-50 dark:bg-yellow-500/5 border border-yellow-200/50 dark:border-yellow-500/20 text-yellow-600 dark:text-yellow-500 text-[10px] font-black uppercase tracking-wider rounded-lg">
                                                            <Clock className="w-3 h-3" />
                                                            대기중
                                                        </span>
                                                    ) : req.admin_status === 'approved' ? (
                                                        <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-emerald-50 dark:bg-emerald-500/5 border border-emerald-200/50 dark:border-emerald-500/20 text-emerald-600 dark:text-emerald-500 text-[10px] font-black uppercase tracking-wider rounded-lg">
                                                            <CheckCircle2 className="w-3 h-3" />
                                                            승인됨
                                                        </span>
                                                    ) : (
                                                        <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-rose-50 dark:bg-rose-500/5 border border-rose-200/50 dark:border-rose-500/20 text-rose-600 dark:text-rose-500 text-[10px] font-black uppercase tracking-wider rounded-lg">
                                                            <XCircle className="w-3 h-3" />
                                                            거절됨
                                                        </span>
                                                    )}
                                                </td>
                                                <td className="pr-6 sm:pr-10 py-5 text-right">
                                                    <div className="flex items-center justify-end gap-2">
                                                        {req.admin_status === 'pending' && (
                                                            <div className="flex items-center gap-2 animate-in fade-in slide-in-from-right-2 duration-200">
                                                                <button
                                                                    onClick={(e) => { e.stopPropagation(); handleStatusChange(req.id, 'rejected'); }}
                                                                    className="h-8 px-3 text-[10px] font-black text-rose-600 bg-rose-50 dark:bg-rose-500/10 border border-rose-200/50 dark:border-rose-500/20 rounded-lg hover:bg-rose-600 hover:text-white transition-all"
                                                                >
                                                                    거절
                                                                </button>
                                                                <button
                                                                    onClick={(e) => { e.stopPropagation(); handleStatusChange(req.id, 'approved'); }}
                                                                    className="h-8 px-4 text-[10px] font-black text-white bg-indigo-600 rounded-lg hover:bg-indigo-700 shadow-sm transition-all"
                                                                >
                                                                    승인
                                                                </button>
                                                            </div>
                                                        )}
                                                        <button
                                                            className="w-8 h-8 rounded-lg flex items-center justify-center hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-slate-400"
                                                            title="상세 정보"
                                                        >
                                                            {isExpanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                                                        </button>
                                                    </div>
                                                </td>
                                            </tr>
                                            {isExpanded && (
                                                <tr className="animate-in slide-in-from-top-2 duration-300">
                                                    <td colSpan={4} className="px-6 pb-6 pt-2">
                                                        <div className="grid grid-cols-1 md:grid-cols-3 gap-8 p-8 bg-slate-50/50 dark:bg-slate-900/50 rounded-[32px] border border-slate-200/50 dark:border-slate-800/50">
                                                            <div className="space-y-4">
                                                                <h4 className="text-[10px] font-black text-slate-400 uppercase tracking-widest px-1">기본 연락 정보</h4>
                                                                <div className="space-y-3">
                                                                    <div className="flex items-center gap-3 group/info">
                                                                        <div className="w-8 h-8 rounded-lg bg-slate-50 dark:bg-slate-800 flex items-center justify-center text-slate-400 group-hover/info:text-indigo-500 transition-colors">
                                                                            <Mail className="w-4 h-4" />
                                                                        </div>
                                                                        <div>
                                                                            <p className="text-[10px] font-bold text-slate-400 leading-none mb-1">E-mail</p>
                                                                            <p className="text-xs font-bold text-slate-700 dark:text-slate-300">{req.email || '미등록'}</p>
                                                                        </div>
                                                                    </div>
                                                                    <div className="flex items-center gap-3 group/info">
                                                                        <div className="w-8 h-8 rounded-lg bg-slate-50 dark:bg-slate-800 flex items-center justify-center text-slate-400 group-hover/info:text-indigo-500 transition-colors">
                                                                            <Phone className="w-4 h-4" />
                                                                        </div>
                                                                        <div>
                                                                            <p className="text-[10px] font-bold text-slate-400 leading-none mb-1">Phone</p>
                                                                            <p className="text-xs font-bold text-slate-700 dark:text-slate-300">{req.phone || '미등록'}</p>
                                                                        </div>
                                                                    </div>
                                                                </div>
                                                            </div>

                                                            <div className="space-y-4">
                                                                <h4 className="text-[10px] font-black text-slate-400 uppercase tracking-widest px-1">상세 소속 정보</h4>
                                                                <div className="space-y-3">
                                                                    <div className="flex items-center gap-3 group/info">
                                                                        <div className="w-8 h-8 rounded-lg bg-slate-50 dark:bg-slate-800 flex items-center justify-center text-slate-400 group-hover/info:text-indigo-500 transition-colors">
                                                                            <Building2 className="w-4 h-4" />
                                                                        </div>
                                                                        <div>
                                                                            <p className="text-[10px] font-bold text-slate-400 leading-none mb-1">Church Name</p>
                                                                            <p className="text-xs font-bold text-slate-700 dark:text-slate-300">{req.churches?.name || '정보 없음'}</p>
                                                                        </div>
                                                                    </div>
                                                                    <div className="flex items-center gap-3 group/info">
                                                                        <div className="w-8 h-8 rounded-lg bg-slate-50 dark:bg-slate-800 flex items-center justify-center text-slate-400 group-hover/info:text-indigo-500 transition-colors">
                                                                            <ShieldCheck className="w-4 h-4" />
                                                                        </div>
                                                                        <div>
                                                                            <p className="text-[10px] font-bold text-slate-400 leading-none mb-1">Department</p>
                                                                            <p className="text-xs font-bold text-slate-700 dark:text-slate-300">{req.departments?.name || '정보 없음'}</p>
                                                                        </div>
                                                                    </div>
                                                                </div>
                                                            </div>

                                                            <div className="space-y-4">
                                                                <h4 className="text-[10px] font-black text-slate-400 uppercase tracking-widest px-1">신청 타임라인</h4>
                                                                <div className="space-y-3">
                                                                    <div className="flex items-center gap-3 group/info">
                                                                        <div className="w-8 h-8 rounded-lg bg-slate-50 dark:bg-slate-800 flex items-center justify-center text-slate-400 group-hover/info:text-indigo-500 transition-colors">
                                                                            <Calendar className="w-4 h-4" />
                                                                        </div>
                                                                        <div>
                                                                            <p className="text-[10px] font-bold text-slate-400 leading-none mb-1">Request Date</p>
                                                                            <p className="text-xs font-bold text-slate-700 dark:text-slate-300">
                                                                                {new Date(req.created_at).toLocaleDateString('ko-KR', { month: 'long', day: 'numeric', year: 'numeric' })}
                                                                            </p>
                                                                        </div>
                                                                    </div>
                                                                    <div className="flex items-center gap-3 group/info">
                                                                        <div className="w-8 h-8 rounded-lg bg-slate-50 dark:bg-slate-800 flex items-center justify-center text-slate-400 group-hover/info:text-indigo-500 transition-colors">
                                                                            <Clock className="w-4 h-4" />
                                                                        </div>
                                                                        <div>
                                                                            <p className="text-[10px] font-bold text-slate-400 leading-none mb-1">Time</p>
                                                                            <p className="text-xs font-bold text-slate-700 dark:text-slate-300">
                                                                                {new Date(req.created_at).toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' })}
                                                                            </p>
                                                                        </div>
                                                                    </div>
                                                                </div>
                                                            </div>
                                                        </div>
                                                    </td>
                                                </tr>
                                            )}
                                        </React.Fragment>
                                    );
                                })}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>

        </div>
    );
}
