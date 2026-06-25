'use client';

import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import { Church, User, ShieldCheck, Moon, Sun, ArrowRight, Loader2, Lock } from 'lucide-react';
import { useTheme } from 'next-themes';

type SelectOption = {
    id: string;
    name: string;
};

type ExistingLoginCheck = {
    p_exists: boolean;
    p_provider: string | null;
    p_message: string | null;
};

function normalizePhone(phone: string) {
    return phone.replace(/[^0-9]/g, '');
}

function getProviderLabel(provider: string | undefined) {
    if (provider === 'kakao') return '카카오 계정';
    if (provider === 'google') return 'Google 계정';
    if (provider === 'email') return '이메일 계정';
    return '현재 로그인 계정';
}

async function getFunctionErrorMessage(error: unknown, fallback: string) {
    const maybeError = error as { message?: string; context?: Response };
    if (maybeError?.context) {
        try {
            const details = await maybeError.context.clone().json();
            if (typeof details?.message === 'string') return details.message;
            if (typeof details?.error === 'string') return details.error;
        } catch {
            // Fall through to the default message.
        }
    }
    return maybeError?.message || fallback;
}

function getErrorMessage(error: unknown) {
    if (error instanceof Error) return error.message;
    if (error && typeof error === 'object') {
        const maybeError = error as {
            message?: unknown;
            error?: unknown;
            details?: unknown;
            hint?: unknown;
            code?: unknown;
        };
        for (const value of [maybeError.message, maybeError.error, maybeError.details, maybeError.hint]) {
            if (typeof value === 'string' && value.trim()) return value;
        }
        if (typeof maybeError.code === 'string' && maybeError.code.trim()) {
            return `요청 처리 중 오류가 발생했습니다. (${maybeError.code})`;
        }
    }
    return String(error);
}

export default function UpgradePage() {
    const [fullName, setFullName] = useState('');
    const [phone, setPhone] = useState('');
    const [selectedChurchId, setSelectedChurchId] = useState('');
    const [selectedDepartmentId, setSelectedDepartmentId] = useState('');
    const [churches, setChurches] = useState<SelectOption[]>([]);
    const [departments, setDepartments] = useState<SelectOption[]>([]);

    const [loading, setLoading] = useState(false);
    const [pageLoading, setPageLoading] = useState(true);
    const [fetchingChurches, setFetchingChurches] = useState(true);
    const [fetchingDepartments, setFetchingDepartments] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [success, setSuccess] = useState(false);
    const [currentAccountLabel, setCurrentAccountLabel] = useState('현재 로그인 계정');
    const [verificationCode, setVerificationCode] = useState('');
    const [isCodeSent, setIsCodeSent] = useState(false);
    const [verifiedPhone, setVerifiedPhone] = useState('');
    const [verificationMessage, setVerificationMessage] = useState<string | null>(null);
    const [existingLoginMessage, setExistingLoginMessage] = useState<string | null>(null);
    const [sendingCode, setSendingCode] = useState(false);
    const [verifyingCode, setVerifyingCode] = useState(false);

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

                const provider = session.user.app_metadata?.provider as string | undefined;
                const displayName =
                    typeof session.user.user_metadata?.full_name === 'string'
                        ? session.user.user_metadata.full_name
                        : typeof session.user.user_metadata?.name === 'string'
                            ? session.user.user_metadata.name
                            : null;
                setCurrentAccountLabel(session.user.email || displayName || getProviderLabel(provider));

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
                    if (profile.department_id) setSelectedDepartmentId(profile.department_id);
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

    useEffect(() => {
        const sanitizedPhone = normalizePhone(phone);
        if (verifiedPhone && verifiedPhone !== sanitizedPhone) {
            setVerifiedPhone('');
            setVerificationCode('');
            setIsCodeSent(false);
            setVerificationMessage('휴대폰 번호가 변경되었습니다. 다시 인증해 주세요.');
            setExistingLoginMessage(null);
        }
    }, [phone, verifiedPhone]);

    useEffect(() => {
        setExistingLoginMessage(null);
    }, [fullName, selectedChurchId]);

    const checkExistingLogin = async (sanitizedPhone: string) => {
        if (!fullName.trim() || !selectedChurchId || !sanitizedPhone) return null;

        const { data, error: checkError } = await supabase.rpc('check_admin_existing_login', {
            p_full_name: fullName.trim(),
            p_church_id: selectedChurchId,
            p_phone: sanitizedPhone,
        });

        if (checkError) throw checkError;

        const result = Array.isArray(data) ? data[0] as ExistingLoginCheck | undefined : null;
        if (result?.p_exists) {
            return result.p_message || '이미 가입된 계정이 있습니다. 기존 로그인 방식으로 로그인해 주세요.';
        }

        return null;
    };

    const handleSendSms = async () => {
        const sanitizedPhone = normalizePhone(phone);
        setError(null);
        setVerificationMessage(null);
        setExistingLoginMessage(null);

        if (!sanitizedPhone || sanitizedPhone.length < 10) {
            setError('올바른 휴대폰 번호를 입력해 주세요.');
            return;
        }

        setSendingCode(true);
        try {
            const { error: functionError } = await supabase.functions.invoke('send-sms', {
                body: {
                    phone: sanitizedPhone,
                    purpose: 'admin_upgrade',
                },
            });

            if (functionError) {
                throw new Error(await getFunctionErrorMessage(functionError, '인증번호 발송에 실패했습니다.'));
            }

            setIsCodeSent(true);
            setVerificationCode('');
            setVerifiedPhone('');
            setVerificationMessage('인증번호를 발송했습니다. 3분 안에 입력해 주세요.');
        } catch (err) {
            setError(getErrorMessage(err));
        } finally {
            setSendingCode(false);
        }
    };

    const handleVerifySms = async () => {
        const sanitizedPhone = normalizePhone(phone);
        setError(null);
        setVerificationMessage(null);

        if (!sanitizedPhone || sanitizedPhone.length < 10) {
            setError('올바른 휴대폰 번호를 입력해 주세요.');
            return;
        }

        if (verificationCode.trim().length < 4) {
            setError('인증번호를 입력해 주세요.');
            return;
        }

        setVerifyingCode(true);
        try {
            const { error: functionError } = await supabase.functions.invoke('verify-sms', {
                body: {
                    phone: sanitizedPhone,
                    code: verificationCode.trim(),
                    ...(fullName.trim() ? { fullName: fullName.trim() } : {}),
                },
            });

            if (functionError) {
                throw new Error(await getFunctionErrorMessage(functionError, '인증번호 확인에 실패했습니다.'));
            }

            setVerifiedPhone(sanitizedPhone);
            const existingLogin = await checkExistingLogin(sanitizedPhone);
            if (existingLogin) {
                setVerifiedPhone('');
                setExistingLoginMessage(existingLogin);
                setVerificationMessage(null);
                return;
            }

            setVerificationMessage('휴대폰 인증이 완료되었습니다.');
        } catch (err) {
            setError(getErrorMessage(err));
        } finally {
            setVerifyingCode(false);
        }
    };

    const handleUpgrade = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setError(null);
        setExistingLoginMessage(null);

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

        const sanitizedPhone = normalizePhone(phone);

        if (!sanitizedPhone || sanitizedPhone.length < 10) {
            setError('올바른 휴대폰 번호를 입력해 주세요.');
            setLoading(false);
            return;
        }

        if (verifiedPhone !== sanitizedPhone) {
            setError('관리자 신청 전에 휴대폰 인증을 완료해 주세요.');
            setLoading(false);
            return;
        }

        try {
            const existingLogin = await checkExistingLogin(sanitizedPhone);
            if (existingLogin) {
                setExistingLoginMessage(existingLogin);
                setLoading(false);
                return;
            }

            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                router.replace('/login');
                return;
            }

            // Call the RPC to upgrade profile
            const { error: rpcError } = await supabase.rpc('submit_admin_request', {
                p_full_name: fullName,
                p_church_id: selectedChurchId,
                p_department_id: selectedDepartmentId,
                p_phone: sanitizedPhone
            });

            if (rpcError) throw rpcError;

            // Success: Sign out and show success message
            await supabase.auth.signOut();
            setSuccess(true);
        } catch (err) {
            setError(getErrorMessage(err));
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
                <div className="w-full max-w-md text-center space-y-8 bg-white dark:bg-[#111827]/60 backdrop-blur-2xl p-10 rounded-3xl border border-white dark:border-slate-800/80 shadow-2xl">
                    <div className="inline-flex items-center justify-center w-20 h-20 bg-indigo-500 rounded-2xl shadow-2xl shadow-indigo-500/20 mb-4">
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
                    <div className="w-24 h-24 bg-white/20 backdrop-blur-xl rounded-2xl flex items-center justify-center shadow-2xl border border-white/30">
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
                            <span className="text-indigo-600 dark:text-indigo-400">{currentAccountLabel}</span>으로 관리자 가입을 진행합니다.<br />관리자 권한을 위해 아래 정보를 확인해 주세요.
                        </p>
                    </div>

                    <div className="bg-indigo-600/5 dark:bg-indigo-500/5 border border-indigo-600/10 dark:border-indigo-500/10 p-6 rounded-2xl space-y-3 relative overflow-hidden group">
                        <div className="absolute -right-4 -top-4 w-24 h-24 bg-indigo-600/5 rounded-full blur-2xl transition-all group-hover:scale-150" />
                        <div className="flex items-center gap-3 text-indigo-600 dark:text-indigo-400">
                            <ShieldCheck className="w-5 h-5" />
                            <span className="text-xs font-black uppercase tracking-widest">휴대폰 본인 확인</span>
                        </div>
                        <p className="text-[13px] text-slate-600 dark:text-slate-400 font-bold leading-relaxed">
                            입력한 휴대폰 번호로 본인 확인을 완료한 뒤 관리자 권한을 신청합니다.<br />
                            같은 이름과 인증 번호로 이미 가입된 계정이 있으면 기존 로그인 방식을 안내합니다.
                        </p>
                    </div>

                    <div className="bg-white/80 dark:bg-[#111827]/60 backdrop-blur-2xl p-8 sm:p-10 rounded-3xl border border-white dark:border-slate-800/80 shadow-2xl dark:shadow-none relative">
                        <form onSubmit={handleUpgrade} className="space-y-6">
                            {error && (
                                <div className="p-4 bg-red-50 dark:bg-red-500/10 border border-red-100 dark:border-red-500/20 rounded-2xl text-red-600 dark:text-red-400 text-xs font-black text-center flex items-center justify-center gap-2">
                                    <ShieldCheck className="w-4 h-4" />
                                    {error}
                                </div>
                            )}

                            {existingLoginMessage && (
                                <div className="space-y-4 rounded-2xl border border-amber-200 bg-amber-50 p-5 dark:border-amber-500/20 dark:bg-amber-500/10">
                                    <div className="flex items-start gap-3">
                                        <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-amber-600 dark:text-amber-300" />
                                        <div className="space-y-1">
                                            <p className="text-sm font-black text-amber-900 dark:text-amber-100">기존 계정이 있습니다</p>
                                            <p className="text-xs font-bold leading-5 text-amber-800 dark:text-amber-200">
                                                {existingLoginMessage}
                                            </p>
                                        </div>
                                    </div>
                                    <button
                                        type="button"
                                        onClick={async () => {
                                            await supabase.auth.signOut();
                                            router.push('/login');
                                        }}
                                        className="w-full rounded-xl bg-amber-900 px-4 py-3 text-xs font-black text-white transition hover:bg-amber-800 dark:bg-amber-300 dark:text-amber-950"
                                    >
                                        기존 방식으로 로그인하기
                                    </button>
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
                                    <div className="flex gap-2">
                                        <div className="relative group flex-1">
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
                                        <button
                                            type="button"
                                            onClick={handleSendSms}
                                            disabled={sendingCode || loading || normalizePhone(phone).length < 10}
                                            className="min-w-[112px] px-4 rounded-2xl bg-slate-900 dark:bg-white text-white dark:text-slate-900 text-xs font-black disabled:opacity-40 disabled:cursor-not-allowed flex items-center justify-center"
                                        >
                                            {sendingCode ? <Loader2 className="w-4 h-4 animate-spin" /> : verifiedPhone === normalizePhone(phone) ? '인증 완료' : isCodeSent ? '재발송' : '인증요청'}
                                        </button>
                                    </div>
                                    {isCodeSent && verifiedPhone !== normalizePhone(phone) && (
                                        <div className="flex gap-2">
                                            <input
                                                type="text"
                                                inputMode="numeric"
                                                value={verificationCode}
                                                onChange={(e) => setVerificationCode(e.target.value.replace(/[^0-9]/g, '').slice(0, 6))}
                                                className="flex-1 px-5 py-4 bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800/60 rounded-2xl focus:outline-none focus:border-indigo-500/50 text-slate-900 dark:text-white font-bold placeholder:text-slate-300 dark:placeholder:text-slate-700 transition-all text-sm"
                                                placeholder="인증번호 6자리"
                                            />
                                            <button
                                                type="button"
                                                onClick={handleVerifySms}
                                                disabled={verifyingCode || verificationCode.length < 4}
                                                className="min-w-[112px] px-4 rounded-2xl bg-indigo-600 text-white text-xs font-black disabled:opacity-40 disabled:cursor-not-allowed flex items-center justify-center"
                                            >
                                                {verifyingCode ? <Loader2 className="w-4 h-4 animate-spin" /> : '확인'}
                                            </button>
                                        </div>
                                    )}
                                    {verificationMessage && (
                                        <p className={`text-xs font-bold ml-1 ${verifiedPhone === normalizePhone(phone) ? 'text-emerald-600 dark:text-emerald-400' : 'text-slate-500 dark:text-slate-400'}`}>
                                            {verificationMessage}
                                            {normalizePhone(phone) === '01000000000' && verifiedPhone !== normalizePhone(phone) ? ' 테스트 번호 인증번호는 123456입니다.' : ''}
                                        </p>
                                    )}
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
                                disabled={loading || verifiedPhone !== normalizePhone(phone)}
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
