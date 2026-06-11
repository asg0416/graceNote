'use client';

import { useEffect, useRef } from 'react';
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import { Loader2 } from 'lucide-react';
import { decideAdminAuthRedirect, type AdminAuthProfile } from '@/lib/adminAuth';

export default function AuthCallbackPage() {
    const router = useRouter();
    const hasHandledCallbackRef = useRef(false);

    useEffect(() => {
        const handleAuthCallback = async () => {
            if (hasHandledCallbackRef.current) return;
            hasHandledCallbackRef.current = true;

            const callbackUrl = new URL(window.location.href);
            const nextPath = callbackUrl.searchParams.get('next');
            const code = callbackUrl.searchParams.get('code');

            if (code) {
                const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);
                if (exchangeError) {
                    console.error('Auth callback exchange error:', exchangeError.message);
                    router.replace('/login?error=callback_failed');
                    return;
                }
            }

            const { data: { session }, error } = await supabase.auth.getSession();

            if (error) {
                console.error('Auth callback error:', error.message);
                router.replace('/login?error=callback_failed');
                return;
            }

            if (session) {
                // [RETRY LOGIC] Check user role/profile with retries
                // Trigger might be slow to create profile
                let profile: AdminAuthProfile | null = null;
                let retryCount = 0;
                const maxRetries = 3;

                while (retryCount < maxRetries) {
                    const { data } = await supabase
                        .from('profiles')
                        .select('role, admin_status, is_master')
                        .eq('id', session.user.id)
                        .maybeSingle();

                    if (data) {
                        profile = data;
                        break;
                    }

                    // Wait 1s before retry
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    retryCount++;
                }

                if (!profile) {
                    // Profile still missing after retries -> likely race condition won or system error
                    // Assume pending or not ready, prevent dashboard access
                    console.error('Profile not found after retries');
                }

                const decision = decideAdminAuthRedirect(profile, {
                    approvedPath: '/members',
                    missingProfilePath: '/upgrade',
                    upgradePath: nextPath,
                });
                if (decision.shouldSignOut) {
                    await supabase.auth.signOut();
                }
                router.replace(decision.path);
            } else {
                router.replace('/login');
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
                <p className="text-sm text-slate-500 font-bold">잠시만 기다려 주시면 이동합니다.</p>
            </div>
        </div>
    );
}
