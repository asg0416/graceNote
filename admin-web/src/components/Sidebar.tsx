'use client';

import React, { useEffect, useState } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import {
    LayoutDashboard,
    Users,
    Church,
    Calendar,
    LogOut,
    Settings,
    UserPlus,
    Layers,
    ChevronRight,
    Menu,
    X,
    Sun,
    Moon,
    Megaphone,
    MessageSquare,
    LayoutGrid
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}
import { useTheme } from 'next-themes';

interface NavItem {
    label: string;
    href: string;
    icon: any;
}

export default function Sidebar() {
    const [profile, setProfile] = useState<any>(null);
    const [isOpen, setIsOpen] = useState(false);
    const [mounted, setMounted] = useState(false);
    const { theme, setTheme } = useTheme();
    const router = useRouter();
    const pathname = usePathname();
    const [unreadInquiries, setUnreadInquiries] = useState(0);

    useEffect(() => {
        setMounted(true);

        const getUnreadCount = async (profileData: any) => {
            if (!profileData) return;
            const isAuthorized = profileData.is_master || (profileData.role === 'admin' && profileData.admin_status === 'approved');
            if (!isAuthorized) return;

            let query = supabase
                .from('inquiries')
                .select('id', { count: 'exact', head: false });

            if (!profileData.is_master) {
                query = query.eq('church_id', profileData.church_id);
            }

            const { count } = await query
                .eq('is_admin_unread', true);

            setUnreadInquiries(count || 0);
        };

        const getProfileData = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) return null;

            const { data } = await supabase
                .from('profiles')
                .select('id, full_name, role, admin_status, is_master, church_id')
                .eq('id', session.user.id)
                .single();

            if (data) {
                const isAuthorized = data.is_master || (data.role === 'admin' && data.admin_status === 'approved');
                if (!isAuthorized) {
                    await supabase.auth.signOut();
                    router.push('/login?error=unauthorized');
                    return null;
                }
                setProfile(data);
                return data;
            }
            return null;
        };

        let channel: any;

        const init = async () => {
            const profileData = await getProfileData();
            if (profileData) {
                getUnreadCount(profileData);

                const isAuthorized = profileData.is_master || (profileData.role === 'admin' && profileData.admin_status === 'approved');
                if (isAuthorized) {
                    channel = supabase
                        .channel('public:inquiries:sidebar')
                        .on('postgres_changes', { event: '*', schema: 'public', table: 'inquiries' }, () => {
                            getUnreadCount(profileData);
                        })
                        .subscribe();
                }
            }
        };

        init();

        return () => {
            if (channel) supabase.removeChannel(channel);
        };
    }, []);

    const handleLogout = async () => {
        await supabase.auth.signOut();
        router.push('/login');
    };

    const isMaster = profile?.is_master;
    const isAdmin = profile?.role === 'admin' && profile?.admin_status === 'approved';
    const isLoading = !profile;

    const masterItems: NavItem[] = [
        { label: '전체 교회 관리', href: '/churches', icon: Church },
        { label: '관리자 신청 승인', href: '/admin-requests', icon: UserPlus },
        { label: '전체 공지사항 관리', href: '/notices', icon: Megaphone },
        { label: '문의 및 상담 내역', href: '/inquiries', icon: MessageSquare },
    ];

    const adminItems: NavItem[] = [
        { label: '성도 명부', href: '/members', icon: Users },
        { label: '조편성 관리', href: '/regrouping', icon: LayoutGrid },
        { label: '부서 관리', href: '/departments', icon: Layers },
        { label: '공지사항 발행', href: '/notices', icon: Megaphone },
    ];

    const commonItems: NavItem[] = [
        { label: '대시보드', href: '/', icon: LayoutDashboard },
        { label: '출석 현황', href: '/attendance', icon: Calendar },
    ];

    const renderNavItems = (items: NavItem[]) => {
        return items.map((item) => {
            const isActive = pathname === item.href;
            return (
                <Link
                    key={item.href}
                    href={item.href}
                    onClick={() => setIsOpen(false)}
                    className={cn(
                        "flex items-center gap-3 px-3 py-2.5 rounded-xl transition-all duration-300 group relative overflow-hidden",
                        isActive
                            ? "bg-indigo-600/10 text-indigo-600 dark:text-indigo-400 border border-indigo-500/20 shadow-[0_0_20px_rgba(79,70,229,0.1)]"
                            : "text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800/40 border border-transparent"
                    )}
                >
                    {isActive && (
                        <div className="absolute left-0 top-1/2 -translate-y-1/2 w-1 h-5 bg-indigo-500 rounded-r-full shadow-[0_0_10px_rgba(99,102,241,0.5)]" />
                    )}
                    <item.icon className={cn("w-5 h-5 transition-transform duration-300", isActive ? "scale-110 text-indigo-600 dark:text-indigo-400" : "group-hover:text-indigo-500")} />
                    <span className="font-bold text-sm tracking-tight">{item.label}</span>
                    {item.href === '/inquiries' && unreadInquiries > 0 && (
                        <div className="ml-2 w-2 h-2 rounded-full bg-rose-500 shadow-[0_0_10px_rgba(244,63,94,0.5)]" />
                    )}
                    {isActive && <div className="ml-auto w-1 h-1 rounded-full bg-indigo-500 dark:bg-indigo-400 animate-pulse" />}
                </Link>
            );
        });
    };

    return (
        <>
            {/* Mobile Toggle Button */}
            <button
                onClick={() => setIsOpen(!isOpen)}
                className="fixed top-2 sm:top-4 left-4 z-[160] lg:hidden w-12 h-12 bg-white dark:bg-[#0d1221] border border-slate-200 dark:border-slate-800 rounded-2xl flex items-center justify-center shadow-lg text-slate-600 dark:text-slate-400 hover:text-indigo-500 transition-all font-black"
            >
                {isOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>

            {/* Overlay */}
            {isOpen && (
                <div
                    className="fixed inset-0 top-16 sm:top-20 bg-black/60 backdrop-blur-md z-[100] lg:hidden transition-opacity"
                    onClick={() => setIsOpen(false)}
                />
            )}

            {/* Sidebar Content */}
            <aside className={cn(
                "w-64 bg-white dark:bg-[#0d1221] border-r border-slate-200 dark:border-slate-800/60 flex flex-col h-[calc(100vh-4rem)] sm:h-[calc(100vh-5rem)] fixed left-0 top-16 sm:top-20 z-[110] shadow-2xl transition-transform duration-300 lg:translate-x-0",
                isOpen ? "translate-x-0" : "-translate-x-full"
            )}>

                <div className="flex-1 overflow-y-auto p-5 py-8 space-y-10 custom-scrollbar">
                    {isLoading ? (
                        <div className="space-y-8 animate-pulse p-4">
                            <div className="space-y-3">
                                <div className="h-2 w-16 bg-slate-100 dark:bg-slate-800 rounded mx-3" />
                                <div className="space-y-2">
                                    {[1, 2].map(i => <div key={i} className="h-10 bg-slate-50 dark:bg-slate-800/40 rounded-xl" />)}
                                </div>
                            </div>
                            <div className="space-y-3">
                                <div className="h-2 w-24 bg-slate-100 dark:bg-slate-800 rounded mx-3" />
                                <div className="space-y-2">
                                    {[1, 2, 3].map(i => <div key={i} className="h-10 bg-slate-50 dark:bg-slate-800/40 rounded-xl" />)}
                                </div>
                            </div>
                        </div>
                    ) : (
                        <>
                            {/* 공통 메뉴 */}
                            <nav className="space-y-1.5">
                                <div className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.15em] px-3 mb-3">기본 메뉴</div>
                                {renderNavItems(commonItems)}
                            </nav>

                            {/* 마스터 메뉴 */}
                            {isMaster && (
                                <nav className="space-y-1.5">
                                    <div className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.15em] px-3 mb-3">시스템 관리 (Master)</div>
                                    {renderNavItems(masterItems)}
                                </nav>
                            )}

                            {/* 교회 운영 메뉴 (Admin 권한이 있거나 Master인 경우 표시) */}
                            {(isAdmin || isMaster) && (
                                <nav className="space-y-1.5">
                                    <div className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.15em] px-3 mb-3">교회 운영 (Admin)</div>
                                    {renderNavItems(isMaster ? adminItems.filter(item => item.href !== '/notices') : adminItems)}
                                </nav>
                            )}
                        </>
                    )}
                </div>

                {/* Sidebar Bottom Actions */}
                <div className="p-4 border-t border-slate-200 dark:border-slate-800/60 space-y-2">
                    {mounted && (
                        <button
                            onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
                            className="w-full flex items-center justify-between px-4 py-3 text-sm font-bold text-slate-500 dark:text-slate-400 hover:text-indigo-600 dark:hover:text-white hover:bg-slate-50 dark:hover:bg-slate-800/50 rounded-xl transition-all group"
                        >
                            <div className="flex items-center gap-3">
                                {theme === 'dark' ? (
                                    <Sun className="w-5 h-5 text-amber-500" />
                                ) : (
                                    <Moon className="w-5 h-5 text-slate-400 group-hover:text-indigo-500" />
                                )}
                                <span>{theme === 'dark' ? '라이트 모드' : '다크 모드'}</span>
                            </div>
                            <div className={cn(
                                "w-10 h-5 rounded-full relative transition-colors",
                                theme === 'dark' ? "bg-indigo-600" : "bg-slate-200 dark:bg-slate-700"
                            )}>
                                <div className={cn(
                                    "absolute top-1 w-3 h-3 bg-white rounded-full transition-all",
                                    theme === 'dark' ? "left-6" : "left-1"
                                )} />
                            </div>
                        </button>
                    )}

                    <button
                        onClick={handleLogout}
                        className="w-full flex items-center gap-3 px-4 py-3 text-sm font-bold text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-500/10 rounded-xl transition-all"
                    >
                        <LogOut className="w-5 h-5" />
                        <span>로그아웃</span>
                    </button>

                    <div className="px-4 py-2 mt-2">
                        <p className="text-[10px] font-bold text-slate-400 dark:text-slate-600 uppercase tracking-widest">© {new Date().getFullYear()} Grace Note</p>
                    </div>
                </div>
            </aside>
        </>
    );
}
