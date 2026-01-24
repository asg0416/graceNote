'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Sun,
    Moon,
    LogOut,
    User,
    ChevronDown,
    Settings,
    Bell,
    Church,
    MessageSquare
} from 'lucide-react';
import { useTheme } from 'next-themes';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}

export default function Header() {
    const [profile, setProfile] = useState<any>(null);
    const [isProfileOpen, setIsProfileOpen] = useState(false);
    const [mounted, setMounted] = useState(false);
    const { theme, setTheme } = useTheme();
    const [unreadInquiries, setUnreadInquiries] = useState(0);
    const [unreadList, setUnreadList] = useState<any[]>([]);
    const [isNotificationOpen, setIsNotificationOpen] = useState(false);
    const router = useRouter();

    const getUnreadCount = async (currentUserProfile?: any) => {
        const up = currentUserProfile || profile;
        if (!up) return;

        // If not master, they must have church_id
        if (!up.is_master && !up.church_id) return;

        const { data: { session } } = await supabase.auth.getSession();
        if (!session) return;

        let query = supabase
            .from('inquiries')
            .select('*, user:profiles!user_id(full_name, church_id)', { count: 'exact' });

        // If not master, only show inquiries for their church
        if (!up.is_master) {
            query = query.eq('church_id', up.church_id);
        }

        const { data, count, error } = await query
            .eq('is_admin_unread', true)
            .order('updated_at', { ascending: false })
            .limit(5);

        if (!error) {
            setUnreadInquiries(count || 0);
            setUnreadList(data || []);
        } else {
            console.error('getUnreadCount Error:', error);
        }
    };

    useEffect(() => {
        setMounted(true);
        const getProfile = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) return;

            const { data } = await supabase
                .from('profiles')
                .select('id, full_name, role, admin_status, is_master, church_id')
                .eq('id', session.user.id)
                .single();

            if (data) {
                setProfile(data);
                getUnreadCount(data);
            }
        };

        getProfile();
    }, []);

    useEffect(() => {
        if (!profile) return;
        const isAuthorized = profile.is_master || (profile.role === 'admin' && profile.admin_status === 'approved');
        if (!isAuthorized) return;

        const channel = supabase
            .channel('public:inquiries:header')
            .on('postgres_changes', { event: '*', schema: 'public', table: 'inquiries' }, () => {
                getUnreadCount(profile);
            })
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
    }, [profile]);

    const handleLogout = async () => {
        await supabase.auth.signOut();
        router.push('/login');
    };

    if (!mounted) return null;

    return (
        <header className="fixed top-0 right-0 left-0 h-16 sm:h-20 bg-white/80 dark:bg-[#0d1221]/80 backdrop-blur-xl border-b border-slate-200 dark:border-slate-800/60 z-[150] transition-all duration-300">
            <div className="h-full px-4 sm:px-8 flex items-center justify-between relative">
                {/* Logo Section - Hidden on Mobile */}
                <div className="hidden lg:flex items-center gap-3">
                    <div className="w-12 h-12 flex items-center justify-center overflow-hidden">
                        <img src="/logo-icon.png" alt="Logo" className="w-11 h-11 object-contain drop-shadow-sm" />
                    </div>
                    <div className="flex flex-col">
                        <span className="text-lg font-black tracking-tight text-slate-900 dark:text-white leading-none">Grace Note</span>
                        <span className="text-[10px] font-bold text-indigo-500 uppercase tracking-widest mt-1">Admin Service</span>
                    </div>
                </div>

                {/* Mobile Title - Centered */}
                <div className="lg:hidden absolute left-1/2 -translate-x-1/2 flex flex-col items-center">
                    <span className="text-base font-black tracking-tight text-slate-900 dark:text-white leading-none">Grace Note</span>
                    <span className="text-[8px] font-bold text-indigo-500 uppercase tracking-[0.2em] mt-1">Admin</span>
                </div>

                <div className="flex items-center gap-3 sm:gap-6 ml-auto lg:ml-0">

                    {/* User Profile Dropdown */}
                    {profile && (
                        <div className="flex items-center gap-2 sm:gap-4">
                            {/* User Profile Dropdown */}
                            <div className="relative">
                                <button
                                    onClick={() => setIsProfileOpen(!isProfileOpen)}
                                    className="flex items-center gap-2.5 pl-2.5 pr-1.5 py-1.5 hover:bg-slate-50 dark:hover:bg-slate-800/40 rounded-2xl transition-all border border-transparent hover:border-slate-200 dark:hover:border-slate-800"
                                >
                                    <div className="hidden sm:block text-right">
                                        <p className="text-sm font-black text-slate-900 dark:text-white leading-none tracking-tight">{profile.full_name}</p>
                                        <p className="text-[10px] font-bold text-slate-500 mt-1 uppercase tracking-tighter">
                                            {profile.is_master ? '시스템 마스터' : '교회 관리자'}
                                        </p>
                                    </div>
                                    <div className="w-9 h-9 sm:w-10 sm:h-10 rounded-xl bg-gradient-to-br from-indigo-500 to-indigo-700 flex items-center justify-center text-white font-black shadow-lg shadow-indigo-500/20">
                                        {profile.full_name?.[0] || 'A'}
                                    </div>
                                    <ChevronDown className={cn("w-4 h-4 text-slate-400 transition-transform", isProfileOpen && "rotate-180")} />
                                </button>

                                {isProfileOpen && (
                                    <>
                                        <div className="fixed inset-0 z-10" onClick={() => setIsProfileOpen(false)} />
                                        <div className="absolute top-full mt-3 right-0 w-64 bg-white dark:bg-[#0d1221] border border-slate-200 dark:border-slate-800 rounded-[24px] shadow-2xl z-20 overflow-hidden animate-in fade-in slide-in-from-top-2">
                                            <div className="p-5 border-b border-slate-100 dark:border-slate-800/60 bg-slate-50/50 dark:bg-slate-900/20">
                                                <p className="text-[10px] font-black text-slate-400 uppercase tracking-widest mb-3">사용자 프로필</p>
                                                <div className="flex items-center gap-3">
                                                    <div className="w-12 h-12 rounded-2xl bg-indigo-600 flex items-center justify-center text-white font-black text-xl shadow-lg shadow-indigo-500/10">
                                                        {profile.full_name?.[0]}
                                                    </div>
                                                    <div>
                                                        <p className="text-base font-black text-slate-900 dark:text-white leading-tight">{profile.full_name}</p>
                                                        <p className="text-xs font-bold text-slate-500 mt-0.5">{profile.is_master ? '시스템 마스터' : '교회 관리자'}</p>
                                                    </div>
                                                </div>
                                            </div>
                                            <div className="p-2">
                                                <button className="w-full flex items-center gap-3 px-4 py-3 text-sm font-bold text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800/60 rounded-xl transition-all group">
                                                    <Settings className="w-4.5 h-4.5 text-slate-400 group-hover:text-indigo-500 transition-colors" />
                                                    시스템 설정
                                                </button>
                                                <button
                                                    onClick={handleLogout}
                                                    className="w-full flex items-center gap-3 px-4 py-3 text-sm font-bold text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-500/5 rounded-xl transition-all group"
                                                >
                                                    <LogOut className="w-4.5 h-4.5 text-rose-400 group-hover:text-rose-600 transition-colors" />
                                                    로그아웃
                                                </button>
                                            </div>
                                        </div>
                                    </>
                                )}
                            </div>

                            {/* Inquiry Notification Popover (Far Right) - Master Only */}
                            {profile.is_master && (
                                <div className="relative">
                                    <button
                                        onClick={() => setIsNotificationOpen(!isNotificationOpen)}
                                        className="relative p-2.5 hover:bg-slate-50 dark:hover:bg-slate-800/40 rounded-xl transition-all border border-transparent hover:border-slate-200 dark:hover:border-slate-800 group"
                                    >
                                        <Bell className={cn("w-5.5 h-5.5 transition-colors", isNotificationOpen ? "text-indigo-600" : "text-slate-500 group-hover:text-indigo-500")} />
                                        {unreadInquiries > 0 && (
                                            <span className="absolute top-2.5 right-2.5 w-2 h-2 bg-rose-500 rounded-full border-2 border-white dark:border-[#0d1221]" />
                                        )}
                                    </button>

                                    {isNotificationOpen && (
                                        <>
                                            <div className="fixed inset-0 z-10" onClick={() => setIsNotificationOpen(false)} />
                                            <div className="absolute top-full mt-3 right-0 w-80 bg-white dark:bg-[#0d1221] border border-slate-200 dark:border-slate-800 rounded-[28px] shadow-2xl z-20 overflow-hidden animate-in fade-in slide-in-from-top-2">
                                                <div className="p-5 border-b border-slate-100 dark:border-slate-800/60 bg-slate-50/50 dark:bg-slate-900/20 flex items-center justify-between">
                                                    <h4 className="text-xs font-black text-slate-900 dark:text-white uppercase tracking-widest">새로운 문의 알림</h4>
                                                    {unreadInquiries > 0 && <span className="px-2 py-0.5 bg-rose-500 text-white text-[9px] font-black rounded-full">{unreadInquiries}</span>}
                                                </div>
                                                <div className="max-h-80 overflow-y-auto custom-scrollbar">
                                                    {unreadList.length === 0 ? (
                                                        <div className="p-8 text-center space-y-2">
                                                            <MessageSquare className="w-8 h-8 text-slate-200 mx-auto" />
                                                            <p className="text-xs font-bold text-slate-400">새로운 문의가 없습니다.</p>
                                                        </div>
                                                    ) : (
                                                        <div className="divide-y divide-slate-50 dark:divide-slate-800/50">
                                                            {unreadList.map((inq) => (
                                                                <button
                                                                    key={inq.id}
                                                                    onClick={() => {
                                                                        setIsNotificationOpen(false);
                                                                        router.push('/inquiries');
                                                                    }}
                                                                    className="w-full p-4 text-left hover:bg-slate-50 dark:hover:bg-slate-800/40 transition-all flex gap-3 group"
                                                                >
                                                                    <div className="w-8 h-8 rounded-lg bg-indigo-50 dark:bg-indigo-500/10 flex items-center justify-center shrink-0">
                                                                        <User className="w-4 h-4 text-indigo-500" />
                                                                    </div>
                                                                    <div className="min-w-0 flex-1 space-y-0.5">
                                                                        <div className="flex items-center justify-between">
                                                                            <p className="text-[10px] font-black text-indigo-600 dark:text-indigo-400 uppercase">{inq.user?.full_name}</p>
                                                                            <p className="text-[9px] font-bold text-slate-400">{new Date(inq.updated_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</p>
                                                                        </div>
                                                                        <p className="text-xs font-black text-slate-900 dark:text-white truncate group-hover:text-indigo-600 transition-colors">{inq.title}</p>
                                                                        <p className="text-[10px] text-slate-500 truncate">{inq.content}</p>
                                                                    </div>
                                                                </button>
                                                            ))}
                                                        </div>
                                                    )}
                                                </div>
                                                <button
                                                    onClick={() => {
                                                        setIsNotificationOpen(false);
                                                        router.push('/inquiries');
                                                    }}
                                                    className="w-full p-4 bg-slate-50 dark:bg-slate-800/40 text-[10px] font-black text-slate-500 hover:text-indigo-600 dark:hover:text-indigo-400 transition-all text-center border-t border-slate-100 dark:border-slate-800 uppercase tracking-widest"
                                                >
                                                    모든 문의 내역 보기
                                                </button>
                                            </div>
                                        </>
                                    )}
                                </div>
                            )}
                        </div>
                    )}

                </div>
            </div>
        </header>
    );
}
