'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Church,
    Save,
    Loader2,
    Settings,
    Smartphone,
    UserSquare2,
    Users2,
    HelpCircle,
    ShieldCheck,
    Heart,
    ChevronRight,
    Info
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}

export default function ChurchSettingsPage() {
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [church, setChurch] = useState<any>(null);
    const [message, setMessage] = useState<{ type: 'success' | 'error', text: string } | null>(null);
    const router = useRouter();

    useEffect(() => {
        fetchChurchData();
    }, []);

    const fetchChurchData = async () => {
        setLoading(true);
        try {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                router.push('/login');
                return;
            }

            const { data: profile } = await supabase
                .from('profiles')
                .select('church_id, is_master, department_id')
                .eq('id', session.user.id)
                .single();

            if (profile?.department_id && !profile?.is_master) {
                router.push('/');
                return;
            }

            if (profile?.church_id) {
                const { data: churchData } = await supabase
                    .from('churches')
                    .select('*')
                    .eq('id', profile.church_id)
                    .single();

                setChurch(churchData);
            }
        } catch (err) {
            console.error(err);
        } finally {
            setLoading(false);
        }
    };

    const handleUpdate = async (e: React.FormEvent) => {
        e.preventDefault();
        setSaving(true);
        setMessage(null);
        try {
            const { error } = await supabase
                .from('churches')
                .update({
                    name: church.name,
                    address: church.address,
                    profile_mode: church.profile_mode
                })
                .eq('id', church.id);

            if (error) throw error;
            setMessage({ type: 'success', text: '설정이 성공적으로 저장되었습니다.' });
        } catch (err) {
            setMessage({ type: 'error', text: '설정 저장 중 오류가 발생했습니다.' });
        } finally {
            setSaving(false);
        }
    };

    if (loading) {
        return (
            <div className="p-32 flex flex-col items-center justify-center gap-6 text-center">
                <Loader2 className="w-12 h-12 text-indigo-600 dark:text-indigo-500 animate-spin" />
                <p className="text-slate-400 dark:text-slate-500 font-black uppercase tracking-[0.2em] text-xs">시스템 코어에 접속 중...</p>
            </div>
        );
    }

    return (
        <div className="space-y-8 sm:space-y-10 max-w-7xl mx-auto">
            <header className="space-y-1.5">
                <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">교회 설정</h1>
                <p className="text-slate-500 dark:text-slate-500 font-bold text-xs sm:text-sm tracking-tight max-w-xl">교회 기본 정보 및 성도 프로필 관리 방식을 설정합니다.</p>
            </header>

            {message && (
                <div className={cn(
                    "p-5 rounded-2xl sm:rounded-3xl border animate-in slide-in-from-top-4 duration-300 flex items-center gap-4",
                    message.type === 'success' ? "bg-emerald-50 dark:bg-emerald-500/10 border-emerald-200 dark:border-emerald-500/20 text-emerald-700 dark:text-emerald-400" : "bg-red-50 dark:bg-red-500/10 border-red-200 dark:border-red-500/20 text-red-700 dark:text-red-400"
                )}>
                    {message.type === 'success' ? <ShieldCheck className="w-6 h-6" /> : <Info className="w-6 h-6" />}
                    <p className="font-bold text-sm tracking-tight">{message.text}</p>
                </div>
            )}

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 sm:gap-10">
                <div className="lg:col-span-2 space-y-8 sm:space-y-10">
                    {/* Basic Info */}
                    <section className="bg-white dark:bg-[#111827]/60 backdrop-blur-xl rounded-[32px] sm:rounded-[40px] border border-slate-200 dark:border-slate-800/80 shadow-xl dark:shadow-2xl overflow-hidden">
                        <div className="p-8 sm:p-10 border-b border-slate-100 dark:border-slate-800/60 bg-slate-50/50 dark:bg-slate-900/40">
                            <h3 className="text-lg sm:text-xl font-black text-slate-900 dark:text-white tracking-tight flex items-center gap-3">
                                <Church className="w-5 sm:w-6 h-5 sm:h-6 text-indigo-600 dark:text-indigo-400" />
                                교회 기본 정보
                            </h3>
                        </div>
                        <form onSubmit={handleUpdate} className="p-8 sm:p-10 space-y-6 sm:space-y-8">
                            <div className="space-y-3">
                                <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">교회 공식 명칭</label>
                                <input
                                    type="text"
                                    required
                                    value={church?.name || ''}
                                    onChange={(e) => setChurch({ ...church, name: e.target.value })}
                                    className="w-full px-6 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold transition-all"
                                />
                            </div>
                            <div className="space-y-3">
                                <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">교회 소재지 주소</label>
                                <input
                                    type="text"
                                    value={church?.address || ''}
                                    onChange={(e) => setChurch({ ...church, address: e.target.value })}
                                    className="w-full px-6 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold transition-all"
                                    placeholder="교회 주소를 입력해 주세요"
                                />
                            </div>

                            <div className="pt-4">
                                <button
                                    disabled={saving}
                                    className="w-full sm:w-fit bg-indigo-600 text-white px-10 py-4 rounded-2xl sm:rounded-3xl font-black text-sm hover:bg-indigo-500 hover:scale-105 transition-all flex items-center justify-center gap-3 shadow-xl shadow-indigo-600/20 active:scale-95 disabled:bg-slate-100 dark:disabled:bg-slate-800 disabled:text-slate-400 dark:disabled:text-slate-600"
                                >
                                    {saving ? <Loader2 className="w-5 h-5 animate-spin" /> : <Save className="w-5 h-5" />}
                                    설정 변경사항 저장
                                </button>
                            </div>
                        </form>
                    </section>

                    {/* Profile Mode Setting */}
                    <section className="bg-white dark:bg-[#111827]/60 backdrop-blur-xl rounded-[32px] sm:rounded-[40px] border border-slate-200 dark:border-slate-800/80 shadow-xl dark:shadow-2xl overflow-hidden mb-10">
                        <div className="p-8 sm:p-10 border-b border-slate-100 dark:border-slate-800/60 bg-slate-50/50 dark:bg-slate-900/40 font-bold">
                            <h3 className="text-lg sm:text-xl font-black text-slate-900 dark:text-white tracking-tight flex items-center gap-3">
                                <UserSquare2 className="w-5 sm:w-6 h-5 sm:h-6 text-indigo-600 dark:text-indigo-400" />
                                프로필 관리 모드 설정
                            </h3>
                        </div>
                        <div className="p-8 sm:p-10 space-y-8 sm:space-y-10">
                            <p className="text-slate-500 dark:text-slate-400 text-sm font-medium leading-relaxed">
                                성도들이 앱 내에서 프로필을 관리하는 방식입니다. 교회 성격에 맞춰 선택해 주세요.
                            </p>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                                <button
                                    onClick={() => setChurch({ ...church, profile_mode: 'individual' })}
                                    className={cn(
                                        "p-6 sm:p-8 rounded-[28px] sm:rounded-[36px] border-2 text-left transition-all relative group/card",
                                        church?.profile_mode === 'individual'
                                            ? "border-indigo-600 bg-indigo-50 dark:bg-indigo-500/5 text-indigo-600 dark:text-white"
                                            : "border-slate-100 dark:border-slate-800/40 bg-slate-50 dark:bg-slate-900/40 text-slate-500 dark:text-slate-500 hover:border-slate-200 dark:hover:border-slate-700 hover:text-slate-900 dark:hover:text-slate-300"
                                    )}
                                >
                                    <div className={cn("p-3 rounded-xl sm:rounded-2xl mb-5 w-fit", church?.profile_mode === 'individual' ? "bg-indigo-600 text-white" : "bg-slate-200 dark:bg-slate-800 text-slate-500 dark:text-slate-500")}>
                                        <UserSquare2 className="w-6 h-6" />
                                    </div>
                                    <h4 className="text-lg sm:text-xl font-black tracking-tight mb-2">개인별 관리</h4>
                                    <p className="text-[11px] font-bold opacity-70 leading-relaxed uppercase tracking-widest">일인 가구 또는 청년부 중심</p>
                                </button>
                                <button
                                    onClick={() => setChurch({ ...church, profile_mode: 'couple' })}
                                    className={cn(
                                        "p-6 sm:p-8 rounded-[28px] sm:rounded-[36px] border-2 text-left transition-all relative group/card",
                                        church?.profile_mode === 'couple'
                                            ? "border-indigo-600 bg-indigo-50 dark:bg-indigo-500/5 text-indigo-600 dark:text-white"
                                            : "border-slate-100 dark:border-slate-800/40 bg-slate-50 dark:bg-slate-900/40 text-slate-500 dark:text-slate-500 hover:border-slate-200 dark:hover:border-slate-700 hover:text-slate-900 dark:hover:text-slate-300"
                                    )}
                                >
                                    <div className={cn("p-3 rounded-xl sm:rounded-2xl mb-5 w-fit", church?.profile_mode === 'couple' ? "bg-indigo-600 text-white" : "bg-slate-200 dark:bg-slate-800 text-slate-500 dark:text-slate-500")}>
                                        <Users2 className="w-6 h-6" />
                                    </div>
                                    <h4 className="text-lg sm:text-xl font-black tracking-tight mb-2">부부/가족 관리</h4>
                                    <p className="text-[11px] font-bold opacity-70 leading-relaxed uppercase tracking-widest">장년부 및 가족 단위 중심</p>
                                </button>
                            </div>
                        </div>
                    </section>
                </div>

                <aside className="space-y-8 sm:space-y-10">
                    <div className="bg-indigo-600 rounded-[32px] sm:rounded-[40px] p-8 sm:p-10 text-white space-y-6 sm:space-y-8 relative overflow-hidden shadow-2xl shadow-indigo-600/20">
                        <div className="absolute -top-10 -right-10 w-40 h-40 bg-white/10 rounded-full blur-3xl" />
                        <div className="flex items-center gap-3">
                            <div className="p-2 bg-white/20 rounded-lg">
                                <HelpCircle className="w-5 h-5" />
                            </div>
                            <h4 className="text-lg sm:text-xl font-black tracking-tighter">시스템 도움말</h4>
                        </div>
                        <p className="text-indigo-100/80 font-bold text-sm leading-relaxed">
                            설정된 데이터는 모든 성도들의 모바일 앱 UI에 즉시 반영됩니다. 프로필 모드 변경 시 기존 성도들의 데이터 정합성을 확인해 주세요.
                        </p>
                        <button className="flex items-center gap-2 text-xs font-black uppercase tracking-widest hover:gap-4 transition-all">
                            자세히 보기 <ChevronRight className="w-4 h-4" />
                        </button>
                    </div>

                    <div className="bg-white dark:bg-slate-800/30 border border-slate-200 dark:border-slate-800/80 rounded-[32px] sm:rounded-[40px] p-8 sm:p-10 space-y-6 sm:space-y-8 shadow-xl dark:shadow-none">
                        <h4 className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em]">운영 상태 요약</h4>
                        <div className="space-y-6">
                            <div className="flex items-center justify-between">
                                <p className="text-sm font-black text-slate-700 dark:text-slate-300">데이터 동기화</p>
                                <span className="px-2 py-0.5 bg-emerald-100 dark:bg-emerald-500/10 text-emerald-600 dark:text-emerald-500 text-[10px] font-black rounded-md">최상</span>
                            </div>
                            <div className="flex items-center justify-between">
                                <p className="text-sm font-black text-slate-700 dark:text-slate-300">시스템 보안</p>
                                <span className="px-2 py-0.5 bg-indigo-100 dark:bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 text-[10px] font-black rounded-md">암호화 활성</span>
                            </div>
                        </div>
                    </div>
                </aside>
            </div>
        </div>
    );
}
