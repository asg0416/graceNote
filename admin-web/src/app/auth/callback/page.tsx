'use client';

import { useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import { Loader2 } from 'lucide-react';

export default function AuthCallbackPage() {
    const router = useRouter();

    useEffect(() => {
        const handleAuthCallback = async () => {
            // Supabase handles the hash/query params and exchanges code for session automatically
            const { data: { session }, error } = await supabase.auth.getSession();

            if (error) {
                console.error('Auth callback error:', error.message);
                router.push('/login?error=callback_failed');
                return;
            }

            if (session) {
                // Check user role/profile to redirect to appropriate page
                const { data: profile } = await supabase
                    .from('profiles')
                    .select('role, admin_status')
                    .eq('id', session.user.id)
                    .single();

                if (profile?.role === 'admin' && profile?.admin_status === 'pending') {
                    // Sign out because pending admins shouldn't access the dashboard yet
                    await supabase.auth.signOut();
                    router.push('/register/success');
                } else {
                    router.push('/members');
                }
            } else {
                router.push('/login');
            }
        };

        handleAuthCallback();
    }, [router]);

    return (
        <div className="min-h-screen flex flex-col items-center justify-center p-6 bg-slate-50 dark:bg-[#0a0f1d] gap-6 text-center">
            <div className="w-16 h-16 bg-white dark:bg-slate-800 rounded-3xl flex items-center justify-center shadow-xl">
                <Loader2 className="w-8 h-8 text-indigo-600 dark:text-indigo-400 animate-spin" />
            </div>
            <div className="space-y-2">
                <h1 className="text-xl font-black text-slate-900 dark:text-white tracking-tight">인증 처리 중...</h1>
                <p className="text-sm text-slate-500 font-bold">잠시만 기다려 주시면 로그인 페이지로 이동합니다.</p>
            </div>
        </div>
    );
}
