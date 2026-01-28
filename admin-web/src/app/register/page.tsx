'use client';

import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import { Church, Mail, Lock, Loader2, ArrowRight, User, ShieldCheck, Moon, Sun, ChevronLeft } from 'lucide-react';
import { useTheme } from 'next-themes';
import Link from 'next/link';

export default function RegisterPage() {
    const [fullName, setFullName] = useState('');
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [confirmPassword, setConfirmPassword] = useState('');
    const [phone, setPhone] = useState('');
    const [selectedChurchId, setSelectedChurchId] = useState('');
    const [selectedDepartmentId, setSelectedDepartmentId] = useState('');
    const [churches, setChurches] = useState<{ id: string; name: string }[]>([]);
    const [departments, setDepartments] = useState<{ id: string; name: string }[]>([]);
    const [loading, setLoading] = useState(false);
    const [fetchingChurches, setFetchingChurches] = useState(true);
    const [fetchingDepartments, setFetchingDepartments] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [success, setSuccess] = useState(false);
    const [otpSent, setOtpSent] = useState(false);
    const [otp, setOtp] = useState('');
    const [resendCooldown, setResendCooldown] = useState(0);

    // Password validation states
    const [passwordChecks, setPasswordChecks] = useState({
        minLength: false,
        uppercase: false,
        lowercase: false,
        digit: false,
        specialChar: false,
    });

    useEffect(() => {
        setPasswordChecks({
            minLength: password.length >= 6,
            uppercase: /[A-Z]/.test(password),
            lowercase: /[a-z]/.test(password),
            digit: /[0-9]/.test(password),
            specialChar: /[!@#$%^&*(),.?":{}|<>]/.test(password),
        });
    }, [password]);

    useEffect(() => {
        let timer: NodeJS.Timeout;
        if (resendCooldown > 0) {
            timer = setInterval(() => {
                setResendCooldown((prev) => prev - 1);
            }, 1000);
        }
        return () => clearInterval(timer);
    }, [resendCooldown]);

    const isPasswordValid = Object.values(passwordChecks).every(Boolean);

    const { theme, setTheme } = useTheme();
    const router = useRouter();

    useEffect(() => {
        const fetchChurches = async () => {
            try {
                const { data, error } = await supabase
                    .from('public_church_list')
                    .select('id, name')
                    .order('name');
                if (error) throw error;
                setChurches(data || []);
            } catch (err) {
                console.error('Error fetching churches:', err);
            } finally {
                setFetchingChurches(false);
            }
        };
        fetchChurches();
    }, []);

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

    const handleRegister = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setError(null);

        if (password !== confirmPassword) {
            setError('비밀번호가 일치하지 않습니다.');
            setLoading(false);
            return;
        }

        if (!isPasswordValid) {
            setError('비밀번호 보안 규칙을 모두 충족해야 합니다.');
            setLoading(false);
            return;
        }

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

        const sanitizedPhone = phone.replace(/[^0-9]/g, '');

        if (!sanitizedPhone || sanitizedPhone.length < 10) {
            setError('올바른 휴대폰 번호를 입력해 주세요.');
            setLoading(false);
            return;
        }

        try {
            // Check if phone number is already registered using a secure RPC
            let phoneCheckData: { p_exists: boolean; p_full_name: string; p_masked_email: string | null }[] | null = null;
            let phoneCheckError: { message: string; code?: string } | null = null;

            try {
                const response = await supabase.rpc('check_phone_exists', { p_phone: sanitizedPhone });
                phoneCheckData = response.data;
                phoneCheckError = response.error;
            } catch (err) {
                console.error('Phone check RPC call failed:', err);
            }

            if (phoneCheckError && phoneCheckError.code !== 'PGRST202') {
                setError('본인 인증 확인 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.');
                setLoading(false);
                return;
            }

            const result = phoneCheckData && phoneCheckData[0];
            if (result && result.p_exists) {
                const masked = result.p_masked_email;
                if (masked) {
                    setError(`이미 등록된 전화번호입니다: ${result.p_full_name} (${masked}). 해당 계정으로 로그인 후 관리자 권한을 신청해 주세요.`);
                } else {
                    setError(`이미 등록된 전화번호입니다: ${result.p_full_name}. 해당 계정으로 로그인 후 관리자 권한을 신청해 주세요.`);
                }
                setLoading(false);
                return;
            }

            const { data, error: signUpError } = await supabase.auth.signUp({
                email,
                password,
                options: {
                    data: {
                        full_name: fullName,
                        role_request: 'admin',
                        church_id: selectedChurchId,
                        department_id: selectedDepartmentId,
                        phone: sanitizedPhone,
                    },
                    emailRedirectTo: 'https://admin.gracenote.io.kr/auth/callback'
                }
            });

            if (signUpError) throw signUpError;

            if (data.user) {
                setOtpSent(true);
            }
        } catch (err) {
            const error = err as { message: string };
            const msg = error.message;
            if (msg.includes('User already registered') || msg.includes('already been registered')) {
                setError('이미 가입된 계정입니다. 로그인 후 관리자 권한을 신청해 주세요.');
            } else {
                setError(msg);
            }
        } finally {
            setLoading(false);
        }
    };

    const handleVerifyOTP = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setError(null);

        try {
            const { error: verifyError } = await supabase.auth.verifyOtp({
                email,
                token: otp,
                type: 'signup'
            });

            if (verifyError) throw verifyError;

            await supabase.auth.signOut();
            setSuccess(true);
        } catch (err) {
            const error = err as { message: string };
            setError(error.message || '인증 번호가 올바르지 않습니다.');
        } finally {
            setLoading(false);
        }
    };

    const handleResendOTP = async () => {
        if (resendCooldown > 0) return;

        setError(null);
        setLoading(true);
        try {
            const { error: resendError } = await supabase.auth.resend({
                type: 'signup',
                email: email,
                options: {
                    emailRedirectTo: 'https://admin.gracenote.io.kr/auth/callback'
                }
            });
            if (resendError) throw resendError;
            setResendCooldown(60);
        } catch (err) {
            const error = err as { message: string };
            setError(error.message || '인증 번호 재발송 중 오류가 발생했습니다.');
        } finally {
            setLoading(false);
        }
    };

    if (success) {
        return (
            <div className="min-h-screen flex items-center justify-center p-6 bg-slate-50 dark:bg-[#0a0f1d]">
                <div className="w-full max-w-md text-center space-y-8 bg-white dark:bg-[#111827]/60 backdrop-blur-2xl p-10 rounded-[40px] border border-white dark:border-slate-800/80 shadow-2xl">
                    <div className="inline-flex items-center justify-center w-20 h-20 bg-emerald-500 rounded-[28px] shadow-2xl shadow-emerald-500/20 mb-4">
                        <ShieldCheck className="w-10 h-10 text-white" />
                    </div>
                    <h2 className="text-3xl font-black text-slate-900 dark:text-white tracking-tighter">신청 완료!</h2>
                    <p className="text-slate-500 dark:text-slate-400 font-bold leading-relaxed">
                        관리자 승인 요청이 성공적으로 접수되었습니다.<br />
                        마스터 관리자의 승인 후 로그인이 가능합니다.
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
                            성장을 돕는 <br />
                            <span className="text-indigo-200">커뮤니티 파트너</span>
                        </h2>
                        <p className="text-indigo-100/70 text-lg font-medium leading-relaxed">
                            그레이스노트 관리자 시스템은 성도 관리부터 조 편성까지, 교회의 모든 효율을 극대화하는 스마트 솔루션입니다.
                        </p>
                    </div>
                    <div className="grid grid-cols-2 gap-6 pt-10">
                        <div className="p-6 bg-white/5 backdrop-blur-lg border border-white/10 rounded-[28px]">
                            <p className="text-white font-black text-2xl">99.9%</p>
                            <p className="text-indigo-200/60 text-xs font-bold uppercase tracking-widest mt-1">Uptime SLA</p>
                        </div>
                        <div className="p-6 bg-white/5 backdrop-blur-lg border border-white/10 rounded-[28px]">
                            <p className="text-white font-black text-2xl">24/7</p>
                            <p className="text-indigo-200/60 text-xs font-bold uppercase tracking-widest mt-1">Security Monitoring</p>
                        </div>
                    </div>
                </div>
            </div>

            <div className="flex-1 flex items-center justify-center p-6 sm:p-12 relative">
                <div className="absolute top-8 right-8 flex items-center gap-4 z-20">
                    <button
                        onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
                        className="w-12 h-12 bg-white dark:bg-slate-800/40 border border-slate-200 dark:border-slate-800 rounded-2xl flex items-center justify-center text-slate-500 dark:text-slate-400 hover:text-indigo-600 dark:hover:text-white transition-all shadow-lg dark:shadow-none"
                    >
                        {theme === 'dark' ? <Sun className="w-5 h-5" /> : <Moon className="w-5 h-5" />}
                    </button>
                    <Link
                        href="/login"
                        className="flex items-center gap-2 text-xs font-black text-slate-400 dark:text-slate-500 hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors uppercase tracking-widest"
                    >
                        <ChevronLeft className="w-4 h-4" /> 로그인으로 돌아가기
                    </Link>
                </div>

                <div className="w-full max-w-[480px] space-y-10 animate-in fade-in slide-in-from-right-8 duration-1000">
                    <div className="space-y-2 lg:hidden">
                        <div className="inline-flex items-center justify-center w-16 h-16 bg-indigo-600 rounded-2xl shadow-xl shadow-indigo-600/20 mb-2">
                            <Church className="w-8 h-8 text-white" />
                        </div>
                        <h1 className="text-3xl font-black text-slate-900 dark:text-white tracking-tighter">관리자 계정 신청</h1>
                    </div>

                    <div className="hidden lg:block space-y-2">
                        <h1 className="text-4xl font-black text-slate-900 dark:text-white tracking-tighter">{otpSent ? '인증 번호 입력' : '관리자 신청'}</h1>
                        <p className="text-slate-500 dark:text-slate-500 font-bold text-sm tracking-tight">
                            {otpSent ? '이메일로 발송된 6자리 번호를 입력해 주세요.' : '교회 운영을 위한 관리자 권한을 신청합니다.'}
                        </p>
                    </div>

                    <div className="bg-white/80 dark:bg-[#111827]/60 backdrop-blur-2xl p-8 sm:p-10 rounded-[40px] border border-white dark:border-slate-800/80 shadow-2xl dark:shadow-none relative">
                        {otpSent ? (
                            <form onSubmit={handleVerifyOTP} className="space-y-6">
                                {error && (
                                    <div className="p-4 bg-red-50 dark:bg-red-500/10 border border-red-100 dark:border-red-500/20 rounded-2xl text-red-600 dark:text-red-400 text-xs font-black text-center flex items-center justify-center gap-2">
                                        <ShieldCheck className="w-4 h-4" />
                                        {error}
                                    </div>
                                )}
                                <div className="space-y-2">
                                    <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">인증 번호 (6자리)</label>
                                    <div className="relative group">
                                        <ShieldCheck className="absolute left-5 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 dark:text-slate-600 group-focus-within:text-indigo-600 dark:group-focus-within:text-indigo-400 transition-colors" />
                                        <input
                                            type="text"
                                            required
                                            value={otp}
                                            onChange={(e) => setOtp(e.target.value.replace(/[^0-9]/g, ''))}
                                            maxLength={6}
                                            className="w-full pl-14 pr-6 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800/60 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-black text-center tracking-[1em] placeholder:text-slate-300 dark:placeholder:text-slate-700 transition-all text-xl"
                                            placeholder="000000"
                                        />
                                    </div>
                                </div>
                                <button
                                    type="submit"
                                    disabled={loading || otp.length < 6}
                                    className="w-full bg-indigo-600 hover:bg-indigo-500 text-white py-5 rounded-2xl font-black text-sm flex items-center justify-center gap-3 transition-all shadow-xl shadow-indigo-600/20 active:scale-95 disabled:bg-slate-200 dark:disabled:bg-slate-800 disabled:text-slate-400 dark:disabled:text-slate-600"
                                >
                                    {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : '인증 완료 및 가입 승인 대기'}
                                </button>

                                <div className="flex flex-col gap-4">
                                    <button
                                        type="button"
                                        onClick={handleResendOTP}
                                        disabled={loading || resendCooldown > 0}
                                        className="w-full text-[11px] font-black text-indigo-600 dark:text-indigo-400 uppercase tracking-widest hover:underline disabled:text-slate-300 dark:disabled:text-slate-700 disabled:no-underline"
                                    >
                                        {resendCooldown > 0 ? `인증 번호 재전송 (${resendCooldown}초)` : '인증 번호를 받지 못하셨나요? 재전송하기'}
                                    </button>

                                    <button
                                        type="button"
                                        onClick={() => setOtpSent(false)}
                                        className="w-full text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest hover:text-indigo-600 transition-colors"
                                    >
                                        이메일 주소 수정하기
                                    </button>
                                </div>
                            </form>
                        ) : (
                            <form onSubmit={handleRegister} className="space-y-6">
                                {error && (
                                    <div className="space-y-4">
                                        <div className="p-4 bg-red-50 dark:bg-red-500/10 border border-red-100 dark:border-red-500/20 rounded-2xl text-red-600 dark:text-red-400 text-xs font-black text-center flex items-center justify-center gap-2">
                                            <ShieldCheck className="w-4 h-4" />
                                            {error}
                                        </div>
                                        {error.includes('이미 가입된 계정') && (
                                            <button
                                                type="button"
                                                onClick={() => router.push('/login')}
                                                className="w-full py-3 bg-indigo-50 dark:bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 rounded-xl text-[11px] font-black uppercase tracking-wider hover:bg-indigo-100 transition-all flex items-center justify-center gap-2"
                                            >
                                                해당 계정으로 로그인하여 신청하기
                                                <ArrowRight className="w-3 h-3" />
                                            </button>
                                        )}
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
                                        <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">관리자 이메일 주소</label>
                                        <div className="relative group">
                                            <Mail className="absolute left-5 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 dark:text-slate-600 group-focus-within:text-indigo-600 dark:group-focus-within:text-indigo-400 transition-colors" />
                                            <input
                                                type="email"
                                                required
                                                value={email}
                                                onChange={(e) => setEmail(e.target.value)}
                                                className="w-full pl-14 pr-6 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800/60 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold placeholder:text-slate-300 dark:placeholder:text-slate-700 transition-all text-sm"
                                                placeholder="admin@church.com"
                                            />
                                        </div>
                                    </div>

                                    <div className="space-y-2">
                                        <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">휴대폰 번호 (앱 본인 인증용)</label>
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

                                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                        <div className="space-y-2">
                                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">비밀번호 설정</label>
                                            <div className="relative group">
                                                <Lock className="absolute left-5 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 dark:text-slate-600 group-focus-within:text-indigo-600 dark:group-focus-within:text-indigo-400 transition-colors" />
                                                <input
                                                    type="password"
                                                    required
                                                    value={password}
                                                    onChange={(e) => setPassword(e.target.value)}
                                                    className="w-full pl-14 pr-6 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800/60 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold placeholder:text-slate-300 transition-all text-sm"
                                                    placeholder="••••••••"
                                                />
                                            </div>
                                        </div>
                                        <div className="space-y-2">
                                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">비밀번호 재확인</label>
                                            <div className="relative group">
                                                <Lock className="absolute left-5 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 dark:text-slate-600 group-focus-within:text-indigo-600 dark:group-focus-within:text-indigo-400 transition-colors" />
                                                <input
                                                    type="password"
                                                    required
                                                    value={confirmPassword}
                                                    onChange={(e) => setConfirmPassword(e.target.value)}
                                                    className="w-full pl-14 pr-6 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800/60 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold placeholder:text-slate-300 transition-all text-sm"
                                                    placeholder="••••••••"
                                                />
                                            </div>
                                        </div>
                                    </div>

                                    {/* Password Requirements Checklist */}
                                    <div className="p-5 bg-slate-50 dark:bg-slate-900/30 rounded-[28px] border border-slate-100 dark:border-slate-800/40 space-y-3">
                                        <h4 className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest flex items-center gap-2">
                                            <ShieldCheck className="w-3 h-3" />
                                            비밀번호 보안 규칙
                                        </h4>
                                        <div className="grid grid-cols-2 gap-x-4 gap-y-2">
                                            <PasswordRequirementItem label="6자 이상" met={passwordChecks.minLength} />
                                            <PasswordRequirementItem label="대문자 포함" met={passwordChecks.uppercase} />
                                            <PasswordRequirementItem label="소문자 포함" met={passwordChecks.lowercase} />
                                            <PasswordRequirementItem label="숫자 포함" met={passwordChecks.digit} />
                                            <PasswordRequirementItem label="특수문자 포함" met={passwordChecks.specialChar} />
                                        </div>
                                    </div>
                                </div>

                                <button
                                    type="submit"
                                    disabled={loading || !isPasswordValid}
                                    className="w-full bg-indigo-600 hover:bg-indigo-500 text-white py-5 rounded-2xl font-black text-sm flex items-center justify-center gap-3 transition-all shadow-xl shadow-indigo-600/20 active:scale-95 disabled:bg-slate-200 dark:disabled:bg-slate-800 disabled:text-slate-400 dark:disabled:text-slate-600"
                                >
                                    {loading ? (
                                        <Loader2 className="w-5 h-5 animate-spin" />
                                    ) : (
                                        <>
                                            신청 완료 및 검토 요청
                                            <ArrowRight className="w-4 h-4" />
                                        </>
                                    )}
                                </button>
                            </form>
                        )}
                    </div>

                    <p className="text-center text-[10px] sm:text-[11px] font-bold text-slate-400 dark:text-slate-600 uppercase tracking-widest leading-relaxed">
                        계정 신청 시 이용 약관 및 개인정보 처리 방침에 동의하는 것으로 간주됩니다.
                    </p>
                </div>
            </div>
        </div>
    );
}

function PasswordRequirementItem({ label, met }: { label: string; met: boolean }) {
    return (
        <div className={`flex items-center gap-2 transition-all duration-300 ${met ? 'opacity-100' : 'opacity-40'}`}>
            <div className={`w-3.5 h-3.5 rounded-full flex items-center justify-center transition-all ${met ? 'bg-emerald-500 rotate-0' : 'bg-slate-300 dark:bg-slate-700 rotate-90'}`}>
                {met && <ShieldCheck className="w-2 h-2 text-white" />}
            </div>
            <span className={`text-[10px] font-black tracking-tight ${met ? 'text-emerald-600 dark:text-emerald-400' : 'text-slate-400 dark:text-slate-600'}`}>
                {label}
            </span>
        </div>
    );
}
