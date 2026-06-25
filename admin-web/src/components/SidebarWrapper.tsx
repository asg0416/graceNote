'use client';

import { usePathname } from 'next/navigation';
import Sidebar from '@/components/Sidebar';
import Header from '@/components/Header';

export default function SidebarWrapper({ children }: { children: React.ReactNode }) {
    const pathname = usePathname();
    const authPagePrefixes = [
        '/auth/callback',
        '/login',
        '/register',
        '/upgrade',
        '/update-password',
        '/dev-tools',
    ];
    const isAuthPage = authPagePrefixes.some((prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`));

    if (isAuthPage) {
        return <main className="min-h-screen w-full bg-slate-50 dark:bg-[#0a0f1d] transition-colors duration-300">{children}</main>;
    }

    return (
        <div className="flex min-h-screen">
            <Sidebar />
            <div className="flex-1 flex flex-col min-h-screen min-w-0 max-w-full">
                <Header />
                <main className="flex-1 lg:pl-64 pt-16 sm:pt-20 lg:pt-20 min-w-0 max-w-full">
                    <div className="p-4 sm:p-6 lg:p-10 w-full min-w-0">
                        {children}
                    </div>
                </main>
            </div>
        </div>
    );
}
