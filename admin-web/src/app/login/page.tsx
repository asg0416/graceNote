'use client';

import { useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import { Church, Mail, Lock, Loader2, ArrowRight, ShieldCheck, Moon, Sun } from 'lucide-react';
import { useTheme } from 'next-themes';
import Link from 'next/link';

export default function LoginPage() {
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const { theme, setTheme } = useTheme();
    const router = useRouter();

    const handleLogin = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setError(null);

        try {
            const { data, error } = await supabase.auth.signInWithPassword({
                email,
                password,
            });

            if (error) throw error;

            if (data.user) {
                const { data: profile, error: profileError } = await supabase
                    .from('profiles')
                    .select('is_master, role, admin_status')
                    .eq('id', data.user.id)
                    .single();

                const isAuthorized = profile && (profile.is_master || (profile.role === 'admin' && profile.admin_status === 'approved'));

                if (profileError) {
                    await supabase.auth.signOut();
                    setError('로그인 정보를 불러오는 중 오류가 발생했습니다.');
                    return;
                }

                if (!isAuthorized) {
                    // If user exists but is not an admin, redirect to upgrade page
                    if (profile && profile.role !== 'admin') {
                        router.push('/upgrade');
                        return;
                    }

                    // If user is admin but not approved (pending, rejected, etc.)
                    await supabase.auth.signOut();
                    setError('관리자 권한이 없습니다. 승인 대기 중인지 확인해 주세요.');
                    return;
                }

                router.push('/');
            }
        } catch (err: any) {
            setError(err.message === 'Invalid login credentials' ? '이메일 또는 비밀번호가 잘못되었습니다.' : err.message);
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="min-h-screen flex flex-col lg:flex-row bg-slate-50 dark:bg-[#0a0f1d] transition-colors duration-500 overflow-hidden">
            {/* Left Side: Illustration / Branding */}
            <div className="hidden lg:flex lg:w-1/2 relative bg-indigo-600 items-center justify-center p-20 overflow-hidden">
                <div className="absolute inset-0 bg-gradient-to-br from-indigo-600 via-indigo-700 to-purple-800" />
                <div className="absolute top-[-10%] left-[-10%] w-[500px] h-[500px] bg-white/10 rounded-full blur-[100px]" />
                <div className="absolute bottom-[-10%] right-[-10%] w-[400px] h-[400px] bg-purple-400/20 rounded-full blur-[80px]" />

                <div className="relative z-10 max-w-lg space-y-8">
                    <div className="w-24 h-24 bg-white/20 backdrop-blur-xl rounded-[32px] flex items-center justify-center shadow-2xl border border-white/30">
                        <Church className="w-12 h-12 text-white" />
                    </div>
                    <div className="space-y-4">
                        <h2 className="text-5xl font-black text-white leading-tight tracking-tighter uppercase">
                            프리미엄 <br />
                            <span className="text-indigo-200">교회 관리 시스템</span>
                        </h2>
                        <p className="text-indigo-100/70 text-lg font-medium leading-relaxed">
                            그레이스노트 어드민 시스템에 오신 것을 환영합니다.<br />
                            효율적인 성도 관리와 투명한 운영을 위한 최적의 플랫폼입니다.
                        </p>
                    </div>
                    <div className="flex items-center gap-10 pt-10">
                        <div className="space-y-1">
                            <p className="text-white font-black text-2xl">고효율 플랫폼</p>
                            <p className="text-indigo-200/60 text-[10px] font-bold uppercase tracking-widest">자동화 시스템</p>
                        </div>
                        <div className="w-[1px] h-10 bg-white/10" />
                        <div className="space-y-1">
                            <p className="text-white font-black text-2xl">엔터프라이즈 급</p>
                            <p className="text-indigo-200/60 text-[10px] font-bold uppercase tracking-widest">강력한 보안 인프라</p>
                        </div>
                    </div>
                </div>
            </div>

            {/* Right Side: Login Form */}
            <div className="flex-1 flex items-center justify-center p-6 sm:p-12 relative animate-in fade-in duration-700">
                {/* Theme Toggle */}
                <div className="absolute top-8 right-8">
                    <button
                        onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
                        className="w-12 h-12 bg-white dark:bg-slate-800/40 border border-slate-200 dark:border-slate-800 rounded-2xl flex items-center justify-center text-slate-500 dark:text-slate-400 hover:text-indigo-600 dark:hover:text-white transition-all shadow-lg dark:shadow-none"
                    >
                        {theme === 'dark' ? <Sun className="w-5 h-5" /> : <Moon className="w-5 h-5" />}
                    </button>
                </div>

                <div className="w-full max-w-[440px] space-y-10">
                    <div className="space-y-2 lg:hidden">
                        <div className="inline-flex items-center justify-center w-16 h-16 bg-indigo-600 rounded-2xl shadow-xl shadow-indigo-600/20 mb-2">
                            <Church className="w-8 h-8 text-white" />
                        </div>
                        <h1 className="text-3xl font-black text-slate-900 dark:text-white tracking-tighter">Grace Note Admin</h1>
                    </div>

                    <div className="hidden lg:block space-y-2">
                        <h1 className="text-4xl font-black text-slate-900 dark:text-white tracking-tighter">로그인</h1>
                        <p className="text-slate-500 dark:text-slate-500 font-bold text-sm tracking-tight text-balance">시스템에 접속하기 위해 인증 정보를 입력해 주세요.</p>
                    </div>

                    <div className="bg-white/80 dark:bg-[#111827]/60 backdrop-blur-2xl p-8 sm:p-10 rounded-[40px] border border-white dark:border-slate-800/80 shadow-2xl dark:shadow-none">
                        <form onSubmit={handleLogin} className="space-y-8">
                            {error && (
                                <div className="p-4 bg-red-50 dark:bg-red-500/10 border border-red-100 dark:border-red-500/20 rounded-2xl text-red-600 dark:text-red-400 text-xs font-black text-center flex items-center justify-center gap-2 animate-shake">
                                    <ShieldCheck className="w-4 h-4" />
                                    {error}
                                </div>
                            )}

                            <div className="space-y-6">
                                <div className="space-y-2.5">
                                    <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">관리자 이메일 계정</label>
                                    <div className="relative group">
                                        <Mail className="absolute left-5 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 dark:text-slate-600 group-focus-within:text-indigo-600 dark:group-focus-within:text-indigo-400 transition-colors" />
                                        <input
                                            type="email"
                                            required
                                            value={email}
                                            onChange={(e) => setEmail(e.target.value)}
                                            className="w-full pl-14 pr-6 py-4.5 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800/60 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold placeholder:text-slate-300 dark:placeholder:text-slate-700 transition-all text-sm"
                                            placeholder="admin@gracenote.com"
                                        />
                                    </div>
                                </div>

                                <div className="space-y-2.5">
                                    <div className="flex items-center justify-between ml-1">
                                        <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em]">보안 비밀번호</label>
                                        <button type="button" className="text-[10px] font-black text-indigo-600 dark:text-indigo-400 hover:underline uppercase tracking-widest">비밀번호 찾기</button>
                                    </div>
                                    <div className="relative group">
                                        <Lock className="absolute left-5 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 dark:text-slate-600 group-focus-within:text-indigo-600 dark:group-focus-within:text-indigo-400 transition-colors" />
                                        <input
                                            type="password"
                                            required
                                            value={password}
                                            onChange={(e) => setPassword(e.target.value)}
                                            className="w-full pl-14 pr-6 py-4.5 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800/60 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold placeholder:text-slate-300 dark:placeholder:text-slate-700 transition-all text-sm"
                                            placeholder="••••••••"
                                        />
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
                                        로그인 시스템 접속
                                        <ArrowRight className="w-4 h-4" />
                                    </>
                                )}
                            </button>
                        </form>

                        <div className="mt-10 pt-8 border-t border-slate-100 dark:border-slate-800/60 text-center">
                            <p className="text-xs font-bold text-slate-500 dark:text-slate-500 mb-4">아직 관리자 계정이 없으신가요?</p>
                            <Link
                                href="/register"
                                className="inline-flex items-center gap-2 text-xs font-black text-indigo-600 dark:text-indigo-400 hover:text-indigo-700 dark:hover:text-indigo-300 transition-colors uppercase tracking-widest group"
                            >
                                관리자 권한 신청하기
                                <ArrowRight className="w-3.5 h-3.5 group-hover:translate-x-1 transition-transform" />
                            </Link>
                        </div>
                    </div>

                    <p className="text-center text-[10px] sm:text-[11px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest leading-relaxed">
                        © 2025 Grace Note Admin System. All Rights Reserved.
                    </p>
                </div>
            </div>
        </div>
    );
}
