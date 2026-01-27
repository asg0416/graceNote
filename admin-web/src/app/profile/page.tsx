'use client';

import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import { Loader2, User, Lock, Save, ArrowLeft } from 'lucide-react';

export default function ProfilePage() {
    const router = useRouter();
    const [isLoading, setIsLoading] = useState(true);
    const [isSaving, setIsSaving] = useState(false);
    const [profile, setProfile] = useState<any>(null);

    // Password Update State
    const [currentPassword, setCurrentPassword] = useState('');
    const [newPassword, setNewPassword] = useState('');
    const [confirmPassword, setConfirmPassword] = useState('');
    const [message, setMessage] = useState<{ type: 'success' | 'error', text: string } | null>(null);

    useEffect(() => {
        getProfile();
    }, []);

    const getProfile = async () => {
        try {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                router.push('/login');
                return;
            }

            const { data, error } = await supabase
                .from('profiles')
                .select('*, church:churches(name)')
                .eq('id', session.user.id)
                .single();

            if (data) {
                setProfile(data);
            }
        } catch (error) {
            console.error('Error fetching profile:', error);
        } finally {
            setIsLoading(false);
        }
    };

    const handleUpdatePassword = async (e: React.FormEvent) => {
        e.preventDefault();
        setMessage(null);

        if (newPassword.length < 6) {
            setMessage({ type: 'error', text: '비밀번호는 최소 6자 이상이어야 합니다.' });
            return;
        }

        if (newPassword !== confirmPassword) {
            setMessage({ type: 'error', text: '비밀번호가 일치하지 않습니다.' });
            return;
        }

        if (!currentPassword) {
            setMessage({ type: 'error', text: '현재 비밀번호를 입력해주세요.' });
            return;
        }

        setIsSaving(true);

        try {
            // 1. Verify Current Password
            const { error: signInError } = await supabase.auth.signInWithPassword({
                email: profile.email,
                password: currentPassword
            });

            if (signInError) {
                setMessage({ type: 'error', text: '현재 비밀번호가 일치하지 않습니다.' });
                setIsSaving(false);
                return;
            }

            // 2. Update Password
            const { error } = await supabase.auth.updateUser({
                password: newPassword
            });

            if (error) {
                if (error.code === 'same_password') {
                    throw new Error('새 비밀번호가 기존 비밀번호와 동일합니다. 다른 비밀번호를 선택해 주세요.');
                }
                throw error;
            }

            setMessage({ type: 'success', text: '비밀번호가 성공적으로 변경되었습니다.' });

            setCurrentPassword('');
            setNewPassword('');
            setConfirmPassword('');
        } catch (error: any) {
            setMessage({ type: 'error', text: error.message || '비밀번호 변경 중 오류가 발생했습니다.' });
        } finally {
            setIsSaving(false);
        }
    };

    if (isLoading) {
        return (
            <div className="flex h-screen items-center justify-center bg-slate-50 dark:bg-[#0d1221]">
                <Loader2 className="w-8 h-8 animate-spin text-indigo-500" />
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-slate-50 dark:bg-[#0d1221] p-4 sm:p-8 lg:p-12">
            <div className="max-w-2xl mx-auto space-y-8">
                {/* Header */}
                <div className="flex items-center gap-4">
                    <button
                        onClick={() => router.back()}
                        className="p-2 -ml-2 hover:bg-slate-200 dark:hover:bg-slate-800 rounded-full transition-colors"
                    >
                        <ArrowLeft className="w-5 h-5 text-slate-500" />
                    </button>
                    <div>
                        <h1 className="text-2xl font-black text-slate-900 dark:text-white tracking-tight">내 정보 관리</h1>
                        <p className="text-sm text-slate-500 mt-1">프로필 정보 확인 및 계정 설정을 관리합니다.</p>
                    </div>
                </div>

                {/* Profile Info Card */}
                <div className="bg-white dark:bg-slate-900 rounded-[32px] shadow-xl shadow-slate-200/50 dark:shadow-none overflow-hidden border border-slate-100 dark:border-slate-800">
                    <div className="p-8 space-y-8">
                        <div className="flex items-center gap-6">
                            <div className="w-20 h-20 rounded-2xl bg-gradient-to-br from-indigo-500 to-violet-600 flex items-center justify-center text-white text-3xl font-black shadow-lg shadow-indigo-500/30">
                                {profile?.full_name?.[0]}
                            </div>
                            <div>
                                <h2 className="text-xl font-bold text-slate-900 dark:text-white">{profile?.full_name}</h2>
                                <p className="text-sm font-medium text-slate-500 mt-1">
                                    {profile?.is_master ? '시스템 마스터' : '교회 관리자'}
                                    {profile?.church?.name && ` • ${profile.church.name}`}
                                </p>
                                <div className="flex items-center gap-2 mt-3">
                                    <span className={`px-2.5 py-1 rounded-full text-[10px] font-bold uppercase tracking-wide border ${profile?.admin_status === 'approved'
                                        ? 'bg-emerald-50 text-emerald-600 border-emerald-100 dark:bg-emerald-500/10 dark:border-emerald-500/20'
                                        : 'bg-amber-50 text-amber-600 border-amber-100 dark:bg-amber-500/10 dark:border-amber-500/20'
                                        }`}>
                                        {profile?.admin_status === 'approved' ? '승인됨' : '대기중'}
                                    </span>
                                </div>
                            </div>
                        </div>

                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-6 pt-6 border-t border-slate-100 dark:border-slate-800">
                            <div className="space-y-1">
                                <label className="text-xs font-bold text-slate-400 uppercase tracking-wider">이메일</label>
                                <p className="text-sm font-medium text-slate-900 dark:text-white sm:truncate" title={profile?.email}>
                                    {profile?.email || '이메일 정보 없음'}
                                </p>
                            </div>
                            <div className="space-y-1">
                                <label className="text-xs font-bold text-slate-400 uppercase tracking-wider">연락처</label>
                                <p className="text-sm font-medium text-slate-900 dark:text-white">
                                    {profile?.phone || '미등록'}
                                </p>
                            </div>
                            <div className="space-y-1">
                                <label className="text-xs font-bold text-slate-400 uppercase tracking-wider">직분/역활</label>
                                <p className="text-sm font-medium text-slate-900 dark:text-white">
                                    {profile?.role === 'admin' ? '관리자' : '일반 사용자'}
                                </p>
                            </div>
                            <div className="space-y-1">
                                <label className="text-xs font-bold text-slate-400 uppercase tracking-wider">가입일</label>
                                <p className="text-sm font-medium text-slate-900 dark:text-white">
                                    {new Date(profile?.created_at).toLocaleDateString()}
                                </p>
                            </div>
                        </div>
                    </div>
                </div>

                {/* Password Change Card */}
                <div className="bg-white dark:bg-slate-900 rounded-[32px] shadow-xl shadow-slate-200/50 dark:shadow-none overflow-hidden border border-slate-100 dark:border-slate-800">
                    <div className="p-8 border-b border-slate-100 dark:border-slate-800 bg-slate-50/50 dark:bg-slate-800/20">
                        <div className="flex items-center gap-3">
                            <div className="p-2 bg-indigo-50 dark:bg-indigo-500/10 rounded-lg">
                                <Lock className="w-5 h-5 text-indigo-500" />
                            </div>
                            <h3 className="text-lg font-bold text-slate-900 dark:text-white">비밀번호 변경</h3>
                        </div>
                    </div>

                    <form onSubmit={handleUpdatePassword} className="p-8 space-y-6">
                        <div className="space-y-4">
                            <div className="space-y-2">
                                <label className="text-xs font-bold text-slate-500 uppercase tracking-wide">현재 비밀번호</label>
                                <input
                                    type="password"
                                    value={currentPassword}
                                    onChange={(e) => setCurrentPassword(e.target.value)}
                                    placeholder="현재 사용 중인 비밀번호"
                                    className="w-full px-4 py-3 bg-slate-50 dark:bg-slate-800 border-none rounded-xl focus:ring-2 focus:ring-indigo-500 text-sm font-medium transition-all"
                                />
                            </div>
                            <div className="space-y-2">
                                <label className="text-xs font-bold text-slate-500 uppercase tracking-wide">새 비밀번호</label>
                                <input
                                    type="password"
                                    value={newPassword}
                                    onChange={(e) => setNewPassword(e.target.value)}
                                    placeholder="6자 이상 입력"
                                    className="w-full px-4 py-3 bg-slate-50 dark:bg-slate-800 border-none rounded-xl focus:ring-2 focus:ring-indigo-500 text-sm font-medium transition-all"
                                />
                            </div>
                            <div className="space-y-2">
                                <label className="text-xs font-bold text-slate-500 uppercase tracking-wide">비밀번호 확인</label>
                                <input
                                    type="password"
                                    value={confirmPassword}
                                    onChange={(e) => setConfirmPassword(e.target.value)}
                                    placeholder="한 번 더 입력해주세요"
                                    className="w-full px-4 py-3 bg-slate-50 dark:bg-slate-800 border-none rounded-xl focus:ring-2 focus:ring-indigo-500 text-sm font-medium transition-all"
                                />
                            </div>
                        </div>

                        {message && (
                            <div className={`p-4 rounded-xl text-sm font-bold flex items-center gap-2 ${message.type === 'success'
                                ? 'bg-emerald-50 text-emerald-600 dark:bg-emerald-500/10'
                                : 'bg-rose-50 text-rose-600 dark:bg-rose-500/10'
                                }`}>
                                {message.text}
                            </div>
                        )}

                        <div className="flex justify-end pt-2">
                            <button
                                type="submit"
                                disabled={isSaving || !currentPassword || !newPassword || !confirmPassword}
                                className="px-6 py-3 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl font-bold text-sm transition-all shadow-lg shadow-indigo-500/20 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
                            >
                                {isSaving ? (
                                    <Loader2 className="w-4 h-4 animate-spin" />
                                ) : (
                                    <Save className="w-4 h-4" />
                                )}
                                변경내용 저장
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    );
}
