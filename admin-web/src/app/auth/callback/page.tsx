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
                // [RETRY LOGIC] Check user role/profile with retries
                // Trigger might be slow to create profile
                let profile = null;
                let retryCount = 0;
                const maxRetries = 3;

                while (retryCount < maxRetries) {
                    const { data } = await supabase
                        .from('profiles')
                        .select('role, admin_status')
                        .eq('id', session.user.id)
                        .single();

                    if (data) {
                        profile = data;
                        break;
                    }

                    // Wait 1s before retry
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    retryCount++;
                }

                // Decide destination
                if (profile) {
                    // Check if pending admin
                    if (profile.role === 'admin' && profile.admin_status === 'pending') {
                        // Sign out because pending admins shouldn't access the dashboard yet
                        await supabase.auth.signOut();
                        router.push('/register/success');
                    } else if (profile.role === 'admin' && profile.admin_status === 'rejected') {
                        await supabase.auth.signOut();
                        router.push('/login?error=rejected');
                    } else if (profile.role === 'admin') {
                        // Approved admin
                        router.push('/members');
                    } else {
                        // Non-admin user? Should not happen in admin web, but handle gracefully
                        // Force logout as they are not authorized for admin
                        await supabase.auth.signOut();
                        router.push('/login?error=unauthorized');
                    }
                } else {
                    // Profile still missing after retries -> likely race condition won or system error
                    // Assume pending or not ready, prevent dashboard access
                    console.error('Profile not found after retries');
                    await supabase.auth.signOut();
                    router.push('/login?error=profile_not_found'); // Or redirect to pending to be safe
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
                <p className="text-sm text-slate-500 font-bold">잠시만 기다려 주시면 이동합니다.</p>
            </div>
        </div>
    );
}
