'use client';

import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import { Church, Mail, User, ShieldCheck, Moon, Sun, ChevronLeft, ArrowRight, Loader2, Lock } from 'lucide-react';
import { useTheme } from 'next-themes';
import Link from 'next/link';

export default function UpgradePage() {
    const [fullName, setFullName] = useState('');
    const [phone, setPhone] = useState('');
    const [selectedChurchId, setSelectedChurchId] = useState('');
    const [selectedDepartmentId, setSelectedDepartmentId] = useState('');
    const [churches, setChurches] = useState<any[]>([]);
    const [departments, setDepartments] = useState<any[]>([]);

    const [loading, setLoading] = useState(false);
    const [pageLoading, setPageLoading] = useState(true);
    const [fetchingChurches, setFetchingChurches] = useState(true);
    const [fetchingDepartments, setFetchingDepartments] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [success, setSuccess] = useState(false);
    const [currentUserEmail, setCurrentUserEmail] = useState('');

    const { theme, setTheme } = useTheme();
    const router = useRouter();

    // Check session and load initial data
    useEffect(() => {
        const checkSessionAndLoad = async () => {
            try {
                const { data: { session } } = await supabase.auth.getSession();
                if (!session) {
                    router.replace('/login');
                    return;
                }
                setCurrentUserEmail(session.user.email || '');

                // Load existing profile data
                const { data: profile } = await supabase
                    .from('profiles')
                    .select('full_name, phone, church_id, department_id, role')
                    .eq('id', session.user.id)
                    .single();

                if (profile) {
                    if (profile.role === 'admin') {
                        // Already admin (maybe pending), redirect or show message?
                        // For now let them update their request if they want.
                    }
                    if (profile.full_name) setFullName(profile.full_name);
                    if (profile.phone) setPhone(profile.phone);
                    // We don't pre-fill church/dept to force them to select consciously, 
                    // unless they really want to keep it. Let's pre-fill if valid.
                    if (profile.church_id) setSelectedChurchId(profile.church_id);
                    // Note: department fetching will trigger on church_id change
                }

                // Load Churches
                const { data: churchData, error: churchError } = await supabase
                    .from('public_church_list')
                    .select('id, name')
                    .order('name');
                if (churchError) throw churchError;
                setChurches(churchData || []);

            } catch (err) {
                console.error('Error loading initial data:', err);
            } finally {
                setFetchingChurches(false);
                setPageLoading(false);
            }
        };
        checkSessionAndLoad();
    }, [router]);

    // Fetch Departments when Church changes
    useEffect(() => {
        const fetchDepartments = async () => {
            if (!selectedChurchId) {
                setDepartments([]);
                setSelectedDepartmentId('');
                return;
            }

            setFetchingDepartments(true);
            try {
                const { data, error } = await supabase
                    .from('public_department_list')
                    .select('id, name')
                    .eq('church_id', selectedChurchId)
                    .order('name');
                if (error) throw error;
                setDepartments(data || []);
            } catch (err) {
                console.error('Error fetching departments:', err);
            } finally {
                setFetchingDepartments(false);
            }
        };
        fetchDepartments();
    }, [selectedChurchId]);

    const handleUpgrade = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setError(null);

        if (!selectedChurchId) {
            setError('관리할 교회를 선택해 주세요.');
            setLoading(false);
            return;
        }

        if (!selectedDepartmentId) {
            setError('관리할 부서를 선택해 주세요.');
            setLoading(false);
            return;
        }

        if (!phone || phone.length < 10) {
            setError('올바른 휴대폰 번호를 입력해 주세요.');
            setLoading(false);
            return;
        }

        try {
            // Call the RPC to upgrade profile
            const { error: rpcError } = await supabase.rpc('submit_admin_request', {
                p_full_name: fullName,
                p_church_id: selectedChurchId,
                p_department_id: selectedDepartmentId,
                p_phone: phone
            });

            if (rpcError) throw rpcError;

            // Success: Sign out and show success message
            await supabase.auth.signOut();
            setSuccess(true);
        } catch (err: any) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    };

    if (pageLoading) {
        return (
            <div className="min-h-screen flex items-center justify-center bg-slate-50 dark:bg-[#0a0f1d]">
                <Loader2 className="w-8 h-8 animate-spin text-indigo-600" />
            </div>
        );
    }

    if (success) {
        return (
            <div className="min-h-screen flex items-center justify-center p-6 bg-slate-50 dark:bg-[#0a0f1d]">
                <div className="w-full max-w-md text-center space-y-8 bg-white dark:bg-[#111827]/60 backdrop-blur-2xl p-10 rounded-[40px] border border-white dark:border-slate-800/80 shadow-2xl">
                    <div className="inline-flex items-center justify-center w-20 h-20 bg-indigo-500 rounded-[28px] shadow-2xl shadow-indigo-500/20 mb-4">
                        <User className="w-10 h-10 text-white" />
                    </div>
                    <h2 className="text-3xl font-black text-slate-900 dark:text-white tracking-tighter">신청 완료!</h2>
                    <p className="text-slate-500 dark:text-slate-400 font-bold leading-relaxed">
                        관리자 권한 신청이 접수되었습니다.<br />
                        앱 계정이 관리자 요청 상태로 전환되었습니다.<br />
                        마스터 관리자의 승인 후 관리자 페이지 접속이 가능합니다.
                    </p>
                    <button
                        onClick={() => router.push('/login')}
                        className="w-full bg-slate-900 dark:bg-white text-white dark:text-slate-900 py-4 rounded-2xl font-black text-sm transition-all hover:scale-105 active:scale-95"
                    >
                        로그인 화면으로 돌아가기
                    </button>
                </div>
            </div>
        );
    }

    return (
        <div className="min-h-screen flex flex-col lg:flex-row bg-slate-50 dark:bg-[#0a0f1d] transition-colors duration-500 overflow-hidden">
            {/* Left Side: Branding (Hidden on mobile) */}
            <div className="hidden lg:flex lg:w-1/2 relative bg-indigo-600 items-center justify-center p-20 overflow-hidden">
                <div className="absolute inset-0 bg-gradient-to-br from-indigo-600 via-indigo-700 to-purple-800" />
                <div className="relative z-10 max-w-lg space-y-8">
                    <div className="w-24 h-24 bg-white/20 backdrop-blur-xl rounded-[32px] flex items-center justify-center shadow-2xl border border-white/30">
                        <Church className="w-12 h-12 text-white" />
                    </div>
                    <div className="space-y-4">
                        <h2 className="text-4xl font-black text-white leading-tight tracking-tighter uppercase">
                            관리자 권한 신청
                        </h2>
                        <p className="text-indigo-100/70 text-lg font-medium leading-relaxed">
                            기존 앱 계정을 사용하여 관리자 권한을 신청합니다.
                        </p>
                    </div>
                </div>
            </div>

            {/* Right Side: Form */}
            <div className="flex-1 flex items-center justify-center p-6 sm:p-12 relative">
                <div className="absolute top-8 right-8 flex items-center gap-4 z-20">
                    <button
                        onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
                        className="w-12 h-12 bg-white dark:bg-slate-800/40 border border-slate-200 dark:border-slate-800 rounded-2xl flex items-center justify-center text-slate-500 dark:text-slate-400 hover:text-indigo-600 dark:hover:text-white transition-all shadow-lg dark:shadow-none"
                    >
                        {theme === 'dark' ? <Sun className="w-5 h-5" /> : <Moon className="w-5 h-5" />}
                    </button>
                    <button
                        onClick={async () => { await supabase.auth.signOut(); router.push('/login'); }}
                        className="flex items-center gap-2 text-xs font-black text-slate-400 dark:text-slate-500 hover:text-red-500 transition-colors uppercase tracking-widest"
                    >
                        로그아웃
                    </button>
                </div>

                <div className="w-full max-w-[480px] space-y-8 animate-in fade-in slide-in-from-right-8 duration-700">
                    <div className="space-y-2">
                        <h1 className="text-4xl font-black text-slate-900 dark:text-white tracking-tighter">관리자 신청</h1>
                        <p className="text-slate-500 dark:text-slate-500 font-bold text-sm tracking-tight text-balance">
                            이미 <span className="text-indigo-600 dark:text-indigo-400">({currentUserEmail})</span> 계정으로 가입되어 있습니다.<br />관리자 권한을 위해 아래 정보를 확인해 주세요.
                        </p>
                    </div>

                    <div className="bg-indigo-600/5 dark:bg-indigo-500/5 border border-indigo-600/10 dark:border-indigo-500/10 p-6 rounded-[32px] space-y-3 relative overflow-hidden group">
                        <div className="absolute -right-4 -top-4 w-24 h-24 bg-indigo-600/5 rounded-full blur-2xl transition-all group-hover:scale-150" />
                        <div className="flex items-center gap-3 text-indigo-600 dark:text-indigo-400">
                            <ShieldCheck className="w-5 h-5" />
                            <span className="text-xs font-black uppercase tracking-widest">기존 계정 발견</span>
                        </div>
                        <p className="text-[13px] text-slate-600 dark:text-slate-400 font-bold leading-relaxed">
                            성도님, 안녕하세요! 이미 앱 계정이 있으시군요.<br />
                            관리자 시스템을 이용하시려면 추가 정보(교회/부서)를 입력하여 관리자 승인을 요청해 주세요.
                        </p>
                    </div>

                    <div className="bg-white/80 dark:bg-[#111827]/60 backdrop-blur-2xl p-8 sm:p-10 rounded-[40px] border border-white dark:border-slate-800/80 shadow-2xl dark:shadow-none relative">
                        <form onSubmit={handleUpgrade} className="space-y-6">
                            {error && (
                                <div className="p-4 bg-red-50 dark:bg-red-500/10 border border-red-100 dark:border-red-500/20 rounded-2xl text-red-600 dark:text-red-400 text-xs font-black text-center flex items-center justify-center gap-2">
                                    <ShieldCheck className="w-4 h-4" />
                                    {error}
                                </div>
                            )}

                            <div className="space-y-5">
                                <div className="space-y-2">
                                    <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">관리자 성함</label>
                                    <div className="relative group">
                                        <User className="absolute left-5 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 dark:text-slate-600 group-focus-within:text-indigo-600 dark:group-focus-within:text-indigo-400 transition-colors" />
                                        <input
                                            type="text"
                                            required
                                            value={fullName}
                                            onChange={(e) => setFullName(e.target.value)}
                                            className="w-full pl-14 pr-6 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800/60 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold placeholder:text-slate-300 dark:placeholder:text-slate-700 transition-all text-sm"
                                            placeholder="홍길동"
                                        />
                                    </div>
                                </div>

                                <div className="space-y-2">
                                    <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">휴대폰 번호</label>
                                    <div className="relative group">
                                        <Lock className="absolute left-5 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 dark:text-slate-600 group-focus-within:text-indigo-600 dark:group-focus-within:text-indigo-400 transition-colors" />
                                        <input
                                            type="tel"
                                            required
                                            value={phone}
                                            onChange={(e) => setPhone(e.target.value.replace(/[^0-9]/g, ''))}
                                            className="w-full pl-14 pr-6 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800/60 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold placeholder:text-slate-300 dark:placeholder:text-slate-700 transition-all text-sm"
                                            placeholder="01012345678"
                                        />
                                    </div>
                                </div>

                                <div className="space-y-2">
                                    <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">관리 대상 교회</label>
                                    <div className="relative group">
                                        <Church className="absolute left-5 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 dark:text-slate-600 group-focus-within:text-indigo-600 dark:group-focus-within:text-indigo-400 transition-colors pointer-events-none" />
                                        <select
                                            required
                                            value={selectedChurchId}
                                            onChange={(e) => setSelectedChurchId(e.target.value)}
                                            disabled={fetchingChurches}
                                            className="w-full pl-14 pr-10 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800/60 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold appearance-none transition-all text-sm"
                                        >
                                            <option value="" disabled>{fetchingChurches ? '로딩 중...' : '소속 교회를 선택해 주세요'}</option>
                                            {churches.map((church) => (
                                                <option key={church.id} value={church.id}>{church.name}</option>
                                            ))}
                                        </select>
                                        <div className="absolute right-5 top-1/2 -translate-y-1/2 pointer-events-none border-l pl-3 border-slate-200 dark:border-slate-700 flex items-center justify-center">
                                            <div className="w-1.5 h-1.5 rounded-full bg-slate-400 group-hover:bg-indigo-500" />
                                        </div>
                                    </div>
                                </div>

                                <div className="space-y-2">
                                    <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">관리 대상 부서</label>
                                    <div className="relative group">
                                        <ShieldCheck className="absolute left-5 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 dark:text-slate-600 group-focus-within:text-indigo-600 dark:group-focus-within:text-indigo-400 transition-colors pointer-events-none" />
                                        <select
                                            required
                                            value={selectedDepartmentId}
                                            onChange={(e) => setSelectedDepartmentId(e.target.value)}
                                            disabled={!selectedChurchId || fetchingDepartments}
                                            className="w-full pl-14 pr-10 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800/60 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold appearance-none transition-all text-sm disabled:opacity-50"
                                        >
                                            <option value="" disabled>{!selectedChurchId ? '교회를 먼저 선택해 주세요' : fetchingDepartments ? '로딩 중...' : '관리할 부서를 선택해 주세요'}</option>
                                            {departments.map((dept) => (
                                                <option key={dept.id} value={dept.id}>{dept.name}</option>
                                            ))}
                                        </select>
                                        <div className="absolute right-5 top-1/2 -translate-y-1/2 pointer-events-none border-l pl-3 border-slate-200 dark:border-slate-700 flex items-center justify-center">
                                            <div className="w-1.5 h-1.5 rounded-full bg-slate-400 group-hover:bg-indigo-500" />
                                        </div>
                                    </div>
                                </div>
                            </div>

                            <button
                                type="submit"
                                disabled={loading}
                                className="w-full bg-indigo-600 hover:bg-indigo-500 text-white py-5 rounded-2xl font-black text-sm flex items-center justify-center gap-3 transition-all shadow-xl shadow-indigo-600/20 active:scale-95 disabled:bg-slate-200 dark:disabled:bg-slate-800 disabled:text-slate-400 dark:disabled:text-slate-600"
                            >
                                {loading ? (
                                    <Loader2 className="w-5 h-5 animate-spin" />
                                ) : (
                                    <>
                                        권한 신청 제출
                                        <ArrowRight className="w-4 h-4" />
                                    </>
                                )}
                            </button>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    );
}
