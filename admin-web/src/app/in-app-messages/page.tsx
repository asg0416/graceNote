'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Loader2,
    MonitorSmartphone,
    Plus,
    Trash2,
    Edit,
    Bell,
    RefreshCw,
    Star,
    Clock,
    Eye,
    EyeOff,
    BarChart3,
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}

const TYPE_META: Record<string, { label: string; color: string; bgColor: string; borderColor: string; Icon: any }> = {
    announcement: {
        label: '공지',
        color: 'text-violet-600 dark:text-violet-400',
        bgColor: 'bg-violet-50 dark:bg-violet-500/10',
        borderColor: 'border-violet-200 dark:border-violet-500/20',
        Icon: Bell,
    },
    update: {
        label: '업데이트',
        color: 'text-sky-600 dark:text-sky-400',
        bgColor: 'bg-sky-50 dark:bg-sky-500/10',
        borderColor: 'border-sky-200 dark:border-sky-500/20',
        Icon: RefreshCw,
    },
    survey: {
        label: '만족도 조사',
        color: 'text-amber-600 dark:text-amber-400',
        bgColor: 'bg-amber-50 dark:bg-amber-500/10',
        borderColor: 'border-amber-200 dark:border-amber-500/20',
        Icon: Star,
    },
};

const DISPLAY_LABEL: Record<string, string> = {
    slide_up: '슬라이드업',
    modal: '모달',
};

const ROLE_LABEL: Record<string, string> = {
    all: '전체',
    leader: '리더',
    member: '성도',
};

function formatDate(iso: string | null) {
    if (!iso) return '—';
    return new Date(iso).toLocaleDateString('ko-KR', { year: 'numeric', month: '2-digit', day: '2-digit' });
}

export default function InAppMessagesPage() {
    const [loading, setLoading] = useState(true);
    const [messages, setMessages] = useState<any[]>([]);
    const [profile, setProfile] = useState<any>(null);
    const [surveyStats, setSurveyStats] = useState<Record<string, { avg: number; count: number }>>({});
    const router = useRouter();

    useEffect(() => {
        const init = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) { router.push('/login'); return; }

            const { data: profileData } = await supabase
                .from('profiles')
                .select('id, role, admin_status, is_master, church_id')
                .eq('id', session.user.id)
                .single();

            const isAuthorized = profileData && (
                profileData.is_master ||
                (profileData.role === 'admin' && profileData.admin_status === 'approved')
            );
            if (!isAuthorized) { router.push('/login'); return; }

            setProfile(profileData);
            await fetchMessages(profileData);
            setLoading(false);
        };
        init();
    }, [router]);

    const fetchMessages = async (p: any) => {
        let q = supabase
            .from('in_app_messages')
            .select('*')
            .eq('is_deleted', false)
            .order('priority', { ascending: false })
            .order('created_at', { ascending: false });

        if (!p.is_master) {
            q = q.eq('church_id', p.church_id);
        }

        const { data } = await q;
        const msgs = data || [];
        setMessages(msgs);

        // survey 타입 메시지의 응답 통계 일괄 조회
        const surveyIds = msgs.filter((m: any) => m.type === 'survey').map((m: any) => m.id);
        if (surveyIds.length > 0) {
            const { data: resData } = await supabase
                .from('iam_survey_responses')
                .select('message_id, rating')
                .in('message_id', surveyIds);

            const stats: Record<string, { avg: number; count: number }> = {};
            surveyIds.forEach((id: string) => {
                const rows = (resData ?? []).filter((r: any) => r.message_id === id);
                const count = rows.length;
                const avg = count > 0
                    ? Math.round((rows.reduce((s: number, r: any) => s + r.rating, 0) / count) * 10) / 10
                    : 0;
                stats[id] = { avg, count };
            });
            setSurveyStats(stats);
        }
    };

    const handleDelete = async (id: string) => {
        if (!confirm('메시지를 삭제하시겠습니까? (설문 응답 데이터는 보존됩니다)')) return;
        await supabase
            .from('in_app_messages')
            .update({ is_deleted: true, is_active: false })
            .eq('id', id);
        if (profile) await fetchMessages(profile);
    };

    const handleToggleActive = async (id: string, current: boolean) => {
        const { error } = await supabase
            .from('in_app_messages')
            .update({ is_active: !current })
            .eq('id', id);
        if (error) {
            alert(`상태 변경 실패: ${error.message}`);
            return;
        }
        if (profile) await fetchMessages(profile);
    };

    if (loading) {
        return (
            <div className="h-[80vh] flex flex-col items-center justify-center gap-4">
                <Loader2 className="w-10 h-10 text-violet-600 animate-spin" />
                <p className="text-slate-400 font-bold text-xs uppercase tracking-widest">인앱 메시지 로딩 중...</p>
            </div>
        );
    }

    return (
        <div className="space-y-8 max-w-7xl mx-auto pb-20">
            <header className="flex flex-col md:flex-row md:items-center justify-between gap-6 px-2">
                <div className="space-y-2">
                    <div className="inline-flex items-center gap-2 px-3 py-1 bg-violet-50 dark:bg-violet-500/10 border border-violet-100 dark:border-violet-500/20 rounded-full">
                        <MonitorSmartphone className="w-3.5 h-3.5 text-violet-600 dark:text-violet-400" />
                        <span className="text-[10px] font-black text-violet-600 dark:text-violet-400 uppercase tracking-widest">앱 내 커뮤니케이션</span>
                    </div>
                    <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">인앱 메시지 발행</h1>
                    <p className="text-slate-500 font-bold text-xs sm:text-sm tracking-tight">앱 사용자에게 노출되는 공지·업데이트·만족도 조사를 관리합니다.</p>
                </div>
                <button
                    onClick={() => router.push('/in-app-messages/new')}
                    className="flex items-center justify-center gap-2 px-6 py-4 bg-violet-600 text-white rounded-2xl font-black text-sm hover:scale-105 active:scale-95 transition-all shadow-xl shadow-violet-500/20"
                >
                    <Plus className="w-5 h-5" />
                    새 메시지 작성
                </button>
            </header>

            <div className="grid grid-cols-1 gap-4 px-2">
                {messages.length === 0 ? (
                    <div className="bg-white dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800 rounded-2xl p-20 text-center space-y-4">
                        <div className="w-20 h-20 bg-slate-50 dark:bg-slate-800 rounded-full flex items-center justify-center mx-auto">
                            <MonitorSmartphone className="w-10 h-10 text-slate-300" />
                        </div>
                        <p className="text-slate-400 font-bold">등록된 인앱 메시지가 없습니다.</p>
                    </div>
                ) : (
                    messages.map((msg) => {
                        const meta = TYPE_META[msg.type] ?? TYPE_META.announcement;
                        const isExpired = msg.expires_at && new Date(msg.expires_at) < new Date();
                        return (
                            <div
                                key={msg.id}
                                className={cn(
                                    "group bg-white dark:bg-[#111827]/60 backdrop-blur-xl border rounded-2xl p-5 sm:p-6 transition-all duration-300 shadow-sm",
                                    msg.is_active && !isExpired
                                        ? "border-slate-200 dark:border-slate-800/60 hover:border-violet-500/40 hover:shadow-xl"
                                        : "border-slate-100 dark:border-slate-800/30 opacity-60"
                                )}
                            >
                                <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-4">
                                    <div className="space-y-3 flex-1 min-w-0">
                                        {/* 배지 행 */}
                                        <div className="flex flex-wrap items-center gap-2">
                                            <span className={cn(
                                                "inline-flex items-center gap-1 px-2.5 py-1 text-[10px] font-black rounded-lg border",
                                                meta.bgColor, meta.color, meta.borderColor
                                            )}>
                                                <meta.Icon className="w-3 h-3" />
                                                {meta.label}
                                            </span>
                                            <span className="px-2.5 py-1 bg-slate-100 dark:bg-slate-800 text-slate-500 dark:text-slate-400 text-[10px] font-black rounded-lg">
                                                {DISPLAY_LABEL[msg.display_type] ?? msg.display_type}
                                            </span>
                                            <span className="px-2.5 py-1 bg-slate-100 dark:bg-slate-800 text-slate-500 dark:text-slate-400 text-[10px] font-black rounded-lg">
                                                {ROLE_LABEL[msg.target_role] ?? msg.target_role}
                                            </span>
                                            {isExpired ? (
                                                <span className="px-2.5 py-1 bg-rose-50 dark:bg-rose-500/10 text-rose-500 text-[10px] font-black rounded-lg border border-rose-200 dark:border-rose-500/20">만료됨</span>
                                            ) : msg.is_active ? (
                                                <span className="px-2.5 py-1 bg-emerald-50 dark:bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 text-[10px] font-black rounded-lg border border-emerald-200 dark:border-emerald-500/20">활성</span>
                                            ) : (
                                                <span className="px-2.5 py-1 bg-slate-100 dark:bg-slate-800 text-slate-400 text-[10px] font-black rounded-lg">비활성</span>
                                            )}
                                            <span className="px-2.5 py-1 bg-slate-100 dark:bg-slate-800 text-slate-400 text-[10px] font-bold rounded-lg">
                                                우선순위 {msg.priority}
                                            </span>
                                        </div>

                                        {/* 제목 */}
                                        <h3 className="text-lg sm:text-xl font-black text-slate-900 dark:text-white tracking-tight truncate">
                                            {msg.title}
                                        </h3>

                                        {/* 날짜 */}
                                        <div className="flex items-center gap-4 text-xs font-bold text-slate-400">
                                            <span className="flex items-center gap-1.5">
                                                <Clock className="w-3.5 h-3.5" />
                                                {formatDate(msg.starts_at)}
                                                {msg.expires_at && ` ~ ${formatDate(msg.expires_at)}`}
                                            </span>
                                        </div>

                                        {/* survey 응답 통계 배지 */}
                                        {msg.type === 'survey' && surveyStats[msg.id] !== undefined && (
                                            <div className="flex items-center gap-2">
                                                <div className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-amber-50 dark:bg-amber-500/10 border border-amber-200 dark:border-amber-500/20 rounded-xl">
                                                    <Star className="w-3 h-3 text-amber-500 fill-amber-400" />
                                                    <span className="text-xs font-black text-amber-700 dark:text-amber-400">
                                                        {surveyStats[msg.id].count > 0
                                                            ? `${surveyStats[msg.id].avg}점 · ${surveyStats[msg.id].count}명 응답`
                                                            : '응답 없음'}
                                                    </span>
                                                </div>
                                                {surveyStats[msg.id].count > 0 && (
                                                    <button
                                                        onClick={() => router.push(`/in-app-messages/${msg.id}/responses`)}
                                                        className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-violet-50 dark:bg-violet-500/10 border border-violet-200 dark:border-violet-500/20 rounded-xl text-xs font-black text-violet-700 dark:text-violet-400 hover:bg-violet-100 dark:hover:bg-violet-500/20 transition-colors"
                                                    >
                                                        <BarChart3 className="w-3 h-3" />
                                                        응답 보기
                                                    </button>
                                                )}
                                            </div>
                                        )}

                                    </div>

                                    {/* 액션 버튼 */}
                                    <div className="flex sm:flex-col gap-2 shrink-0">
                                        <button
                                            onClick={() => handleToggleActive(msg.id, msg.is_active)}
                                            title={msg.is_active ? '비활성화' : '활성화'}
                                            className="p-3 bg-slate-50 dark:bg-slate-800 text-slate-400 hover:text-violet-600 dark:hover:text-white hover:bg-violet-50 dark:hover:bg-violet-600/20 rounded-2xl transition-all border border-transparent hover:border-violet-500/30"
                                        >
                                            {msg.is_active ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                                        </button>
                                        <button
                                            onClick={() => router.push(`/in-app-messages/${msg.id}/edit`)}
                                            className="p-3 bg-slate-50 dark:bg-slate-800 text-slate-400 hover:text-indigo-600 dark:hover:text-white hover:bg-indigo-50 dark:hover:bg-indigo-600/20 rounded-2xl transition-all border border-transparent hover:border-indigo-500/30"
                                        >
                                            <Edit className="w-5 h-5" />
                                        </button>
                                        <button
                                            onClick={() => handleDelete(msg.id)}
                                            className="p-3 bg-slate-50 dark:bg-slate-800 text-slate-400 hover:text-rose-600 dark:hover:text-white hover:bg-rose-50 dark:hover:bg-rose-600/20 rounded-2xl transition-all border border-transparent hover:border-rose-500/30"
                                        >
                                            <Trash2 className="w-5 h-5" />
                                        </button>
                                    </div>
                                </div>
                            </div>
                        );
                    })
                )}
            </div>
        </div>
    );
}
