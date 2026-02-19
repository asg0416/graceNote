'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Loader2,
    Megaphone,
    Plus,
    Trash2,
    Edit,
    Globe,
    Church,
    Layers,
    Clock,
    User,
    Pin
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}

export default function NoticesPage() {
    const [loading, setLoading] = useState(true);
    const [notices, setNotices] = useState<any[]>([]);
    const [profile, setProfile] = useState<any>(null);
    const router = useRouter();

    useEffect(() => {
        const checkUser = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                router.push('/login');
                return;
            }

            const { data: profileData } = await supabase
                .from('profiles')
                .select('id, full_name, role, admin_status, is_master, church_id, department_id')
                .eq('id', session.user.id)
                .single();

            if (!profileData || !(profileData.is_master || (profileData.role === 'admin' && profileData.admin_status === 'approved'))) {
                router.push('/login');
                return;
            }

            setProfile(profileData);
            await fetchNotices(profileData);
            setLoading(false);
        };

        checkUser();
    }, [router]);

    const fetchNotices = async (userProfile: any) => {
        try {
            let noticesQuery = supabase
                .from('notices')
                .select(`
                    *,
                    created_by_profile:profiles!created_by(full_name),
                    church:churches(name),
                    department:departments!department_id(name)
                `);

            if (userProfile.is_master) {
                noticesQuery = noticesQuery.eq('created_by', userProfile.id);
            } else {
                if (userProfile.department_id) {
                    noticesQuery = noticesQuery.or(`department_id.eq.${userProfile.department_id},target_department_ids.cs.{${userProfile.department_id}}`);
                } else {
                    noticesQuery = noticesQuery.eq('church_id', userProfile.church_id);
                }
            }

            const { data: noticesData } = await noticesQuery
                .order('is_pinned', { ascending: false })
                .order('created_at', { ascending: false });

            setNotices(noticesData || []);
        } catch (err) {
            console.error('Data Fetch Error:', err);
        }
    };

    const handleDelete = async (id: string) => {
        if (!confirm('정말 삭제하시겠습니까?')) return;
        try {
            const { error } = await supabase.from('notices').delete().eq('id', id);
            if (error) throw error;
            await fetchNotices(profile);
        } catch (err) {
            console.error('Delete Error:', err);
        }
    };

    // Build target badges from new array columns or legacy columns
    const getTargetBadges = (notice: any) => {
        const badges: { label: string; icon: 'globe' | 'church' | 'dept' }[] = [];

        if (notice.is_global) {
            badges.push({ label: '전체', icon: 'globe' });
        }
        if (notice.church) {
            badges.push({ label: notice.church.name, icon: 'church' });
        }
        if (notice.department) {
            badges.push({ label: notice.department.name, icon: 'dept' });
        }

        return badges;
    };

    if (loading) {
        return (
            <div className="h-[80vh] flex flex-col items-center justify-center gap-4">
                <Loader2 className="w-10 h-10 text-indigo-600 animate-spin" />
                <p className="text-slate-400 font-bold text-xs uppercase tracking-widest">공지사항 로딩 중...</p>
            </div>
        );
    }

    return (
        <div className="space-y-8 max-w-7xl mx-auto pb-20">
            <header className="flex flex-col md:flex-row md:items-center justify-between gap-6 px-2">
                <div className="space-y-2">
                    <div className="inline-flex items-center gap-2 px-3 py-1 bg-indigo-50 dark:bg-indigo-500/10 border border-indigo-100 dark:border-indigo-500/20 rounded-full">
                        <Megaphone className="w-3.5 h-3.5 text-indigo-600 dark:text-indigo-400" />
                        <span className="text-[10px] font-black text-indigo-600 dark:text-indigo-400 uppercase tracking-widest">커뮤니케이션</span>
                    </div>
                    <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">공지사항 관리</h1>
                    <p className="text-slate-500 font-bold text-xs sm:text-sm tracking-tight">전체, 교회, 부서별 공지사항을 발행하고 관리합니다.</p>
                </div>
                <button
                    onClick={() => router.push('/notices/new')}
                    className="flex items-center justify-center gap-2 px-6 py-4 bg-indigo-600 text-white rounded-2xl font-black text-sm hover:scale-105 active:scale-95 transition-all shadow-xl shadow-indigo-500/20"
                >
                    <Plus className="w-5 h-5" />
                    새 공지사항 작성
                </button>
            </header>

            <div className="grid grid-cols-1 gap-6 px-2">
                {notices.length === 0 ? (
                    <div className="bg-white dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800 rounded-2xl p-20 text-center space-y-4">
                        <div className="w-20 h-20 bg-slate-50 dark:bg-slate-800 rounded-full flex items-center justify-center mx-auto">
                            <Megaphone className="w-10 h-10 text-slate-300" />
                        </div>
                        <p className="text-slate-400 font-bold">등록된 공지사항이 없습니다.</p>
                    </div>
                ) : (
                    notices.map((notice) => {
                        const badges = getTargetBadges(notice);
                        return (
                            <div key={notice.id} className="group bg-white dark:bg-[#111827]/60 backdrop-blur-xl border border-slate-200 dark:border-slate-800/60 rounded-2xl p-6 sm:p-8 hover:border-indigo-500/50 transition-all duration-300 shadow-sm hover:shadow-2xl">
                                <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-6">
                                    <div className="space-y-4 flex-1">
                                        <div className="flex flex-wrap items-center gap-2">
                                            {badges.map((badge, i) => (
                                                <span key={i} className={cn(
                                                    "px-2.5 py-1 text-white text-[9px] font-black rounded-lg uppercase tracking-widest flex items-center gap-1",
                                                    badge.icon === 'globe' ? 'bg-rose-500' : badge.icon === 'church' ? 'bg-indigo-500' : 'bg-emerald-500'
                                                )}>
                                                    {badge.icon === 'globe' && <Globe className="w-3 h-3" />}
                                                    {badge.icon === 'church' && <Church className="w-3 h-3" />}
                                                    {badge.icon === 'dept' && <Layers className="w-3 h-3" />}
                                                    {badge.label}
                                                </span>
                                            ))}
                                            <span className="px-2.5 py-1 bg-slate-100 dark:bg-slate-800 text-slate-500 dark:text-slate-400 text-[9px] font-black rounded-lg uppercase tracking-widest">
                                                {notice.category === 'general' ? '일반' : notice.category === 'event' ? '행사' : '긴급'}
                                            </span>
                                            {notice.is_pinned && (
                                                <span className="px-2.5 py-1 bg-amber-500 text-white text-[9px] font-black rounded-lg uppercase tracking-widest flex items-center gap-1">
                                                    <Pin className="w-3 h-3" /> 상단 고정
                                                </span>
                                            )}
                                        </div>

                                        <h3 className="text-xl sm:text-2xl font-black text-slate-900 dark:text-white group-hover:text-indigo-600 transition-colors tracking-tight leading-tight">
                                            {notice.title}
                                        </h3>

                                        <div className="text-slate-600 dark:text-slate-400 font-medium text-sm sm:text-base leading-relaxed line-clamp-2">
                                            {notice.content?.replace(/<[^>]*>/g, '').substring(0, 120)}
                                        </div>

                                        <div className="flex items-center gap-4 pt-2">
                                            <div className="flex items-center gap-1.5 text-slate-400">
                                                <User className="w-3.5 h-3.5" />
                                                <span className="text-xs font-bold">
                                                    {notice.is_global ? 'GraceNote 관리자' : (notice.created_by_profile?.full_name || 'GraceNote 관리자')}
                                                </span>
                                            </div>
                                            <div className="flex items-center gap-1.5 text-slate-400 border-l border-slate-200 dark:border-slate-800 pl-4">
                                                <Clock className="w-3.5 h-3.5" />
                                                <span className="text-xs font-bold">{new Date(notice.created_at).toLocaleDateString()}</span>
                                            </div>
                                        </div>
                                    </div>

                                    {profile?.id === notice.created_by && (
                                        <div className="flex sm:flex-col gap-2 shrink-0">
                                            <button
                                                onClick={() => router.push(`/notices/${notice.id}/edit`)}
                                                className="flex-1 sm:flex-none p-3 bg-slate-50 dark:bg-slate-800 text-slate-400 hover:text-indigo-600 dark:hover:text-white hover:bg-indigo-50 dark:hover:bg-indigo-600/20 rounded-2xl transition-all border border-transparent hover:border-indigo-500/30"
                                            >
                                                <Edit className="w-5 h-5" />
                                            </button>
                                            <button
                                                onClick={() => handleDelete(notice.id)}
                                                className="flex-1 sm:flex-none p-3 bg-slate-50 dark:bg-slate-800 text-slate-400 hover:text-rose-600 dark:hover:text-white hover:bg-rose-50 dark:hover:bg-rose-600/20 rounded-2xl transition-all border border-transparent hover:border-rose-500/30"
                                            >
                                                <Trash2 className="w-5 h-5" />
                                            </button>
                                        </div>
                                    )}
                                </div>
                            </div>
                        );
                    })
                )}
            </div>
        </div>
    );
}
