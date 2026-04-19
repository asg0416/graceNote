'use client';

import { useEffect, useState } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Loader2, ArrowLeft, Star, MessageSquare,
    Users, BarChart3, MonitorSmartphone,
} from 'lucide-react';

// ── 타입 ──────────────────────────────────────────────────────────────

interface SurveyResponse {
    id: string;
    rating: number;
    comment: string | null;
    created_at: string;
    user: { full_name: string } | null;
}

interface MessageInfo {
    id: string;
    title: string;
    starts_at: string;
    expires_at: string | null;
}

// ── 유틸 ──────────────────────────────────────────────────────────────

function formatDate(iso: string) {
    return new Date(iso).toLocaleDateString('ko-KR', {
        year: 'numeric', month: '2-digit', day: '2-digit',
        hour: '2-digit', minute: '2-digit',
    });
}

function StarRow({ rating, size = 16 }: { rating: number; size?: number }) {
    return (
        <div className="flex gap-0.5">
            {[1, 2, 3, 4, 5].map(i => (
                <Star
                    key={i}
                    size={size}
                    className={i <= rating ? 'text-amber-400 fill-amber-400' : 'text-slate-200 fill-slate-200'}
                />
            ))}
        </div>
    );
}

// ── 메인 페이지 ───────────────────────────────────────────────────────

export default function SurveyResponsesPage() {
    const router = useRouter();
    const params = useParams();
    const messageId = params.id as string;

    const [loading, setLoading] = useState(true);
    const [message, setMessage] = useState<MessageInfo | null>(null);
    const [responses, setResponses] = useState<SurveyResponse[]>([]);

    useEffect(() => {
        const init = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) { router.push('/login'); return; }

            const { data: profile } = await supabase
                .from('profiles')
                .select('id, role, admin_status, is_master')
                .eq('id', session.user.id)
                .single();

            const ok = profile && (
                profile.is_master ||
                (profile.role === 'admin' && profile.admin_status === 'approved')
            );
            if (!ok) { router.push('/login'); return; }

            // 메시지 정보
            const { data: msg } = await supabase
                .from('in_app_messages')
                .select('id, title, starts_at, expires_at, type')
                .eq('id', messageId)
                .single();

            if (!msg || msg.type !== 'survey') {
                router.push('/in-app-messages');
                return;
            }
            setMessage(msg);

            // 응답 목록 (profiles join)
            const { data: rows } = await supabase
                .from('iam_survey_responses')
                .select(`
                    id,
                    rating,
                    comment,
                    created_at,
                    user:profiles!user_id(full_name)
                `)
                .eq('message_id', messageId)
                .order('created_at', { ascending: false });

            // Supabase join은 배열로 반환 → 첫 번째 요소로 정규화
            const normalized: SurveyResponse[] = (rows ?? []).map((r: any) => ({
                id: r.id,
                rating: r.rating,
                comment: r.comment,
                created_at: r.created_at,
                user: Array.isArray(r.user) ? (r.user[0] ?? null) : (r.user ?? null),
            }));
            setResponses(normalized);
            setLoading(false);
        };
        init();
    }, [messageId, router]);

    // ── 통계 계산 ──────────────────────────────────────────────────────

    const total = responses.length;
    const avg = total > 0
        ? Math.round((responses.reduce((s, r) => s + r.rating, 0) / total) * 10) / 10
        : 0;
    const distribution = [5, 4, 3, 2, 1].map(star => ({
        star,
        count: responses.filter(r => r.rating === star).length,
        pct: total > 0
            ? Math.round((responses.filter(r => r.rating === star).length / total) * 100)
            : 0,
    }));
    const withComment = responses.filter(r => r.comment);

    // ── 로딩 ──────────────────────────────────────────────────────────

    if (loading) {
        return (
            <div className="h-[80vh] flex flex-col items-center justify-center gap-4">
                <Loader2 className="w-10 h-10 text-violet-600 animate-spin" />
                <p className="text-slate-400 font-bold text-xs uppercase tracking-widest">응답 불러오는 중...</p>
            </div>
        );
    }

    return (
        <div className="max-w-4xl mx-auto pb-20 space-y-8">
            {/* 헤더 */}
            <header className="flex items-center gap-4 px-2">
                <button
                    type="button"
                    onClick={() => router.push('/in-app-messages')}
                    className="p-2.5 bg-slate-100 dark:bg-slate-800 rounded-xl text-slate-500 hover:text-slate-900 dark:hover:text-white transition-all"
                >
                    <ArrowLeft className="w-5 h-5" />
                </button>
                <div>
                    <div className="inline-flex items-center gap-1.5 px-2.5 py-1 bg-amber-50 dark:bg-amber-500/10 border border-amber-100 dark:border-amber-500/20 rounded-full mb-1">
                        <MonitorSmartphone className="w-3 h-3 text-amber-600 dark:text-amber-400" />
                        <span className="text-[10px] font-black text-amber-600 dark:text-amber-400 uppercase tracking-widest">만족도 조사 결과</span>
                    </div>
                    <h1 className="text-2xl font-black text-slate-900 dark:text-white tracking-tighter">
                        {message?.title}
                    </h1>
                </div>
            </header>

            {total === 0 ? (
                <div className="bg-white dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800 rounded-2xl p-20 text-center space-y-4">
                    <div className="w-16 h-16 bg-amber-50 dark:bg-amber-500/10 rounded-full flex items-center justify-center mx-auto">
                        <Star className="w-8 h-8 text-amber-300" />
                    </div>
                    <p className="text-slate-400 font-bold">아직 응답이 없습니다.</p>
                </div>
            ) : (
                <>
                    {/* 요약 카드 */}
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 px-2">
                        {/* 평균 별점 */}
                        <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl p-6 flex flex-col items-center justify-center gap-2">
                            <p className="text-xs font-black text-slate-400 uppercase tracking-widest">평균 별점</p>
                            <p className="text-5xl font-black text-slate-900 dark:text-white tracking-tighter">{avg}</p>
                            <StarRow rating={Math.round(avg)} size={18} />
                        </div>
                        {/* 총 응답 수 */}
                        <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl p-6 flex flex-col items-center justify-center gap-2">
                            <p className="text-xs font-black text-slate-400 uppercase tracking-widest">총 응답</p>
                            <div className="flex items-end gap-1.5">
                                <p className="text-5xl font-black text-slate-900 dark:text-white tracking-tighter">{total}</p>
                                <p className="text-base font-black text-slate-400 pb-1.5">명</p>
                            </div>
                            <Users className="w-5 h-5 text-slate-300" />
                        </div>
                        {/* 텍스트 의견 수 */}
                        <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl p-6 flex flex-col items-center justify-center gap-2">
                            <p className="text-xs font-black text-slate-400 uppercase tracking-widest">텍스트 의견</p>
                            <div className="flex items-end gap-1.5">
                                <p className="text-5xl font-black text-slate-900 dark:text-white tracking-tighter">{withComment.length}</p>
                                <p className="text-base font-black text-slate-400 pb-1.5">건</p>
                            </div>
                            <MessageSquare className="w-5 h-5 text-slate-300" />
                        </div>
                    </div>

                    {/* 별점 분포 */}
                    <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl p-6 mx-2">
                        <div className="flex items-center gap-2 mb-5">
                            <BarChart3 className="w-4 h-4 text-slate-400" />
                            <p className="text-xs font-black text-slate-500 uppercase tracking-widest">별점 분포</p>
                        </div>
                        <div className="space-y-3">
                            {distribution.map(({ star, count, pct }) => (
                                <div key={star} className="flex items-center gap-3">
                                    <div className="flex items-center gap-1 w-12 shrink-0">
                                        <Star size={13} className="text-amber-400 fill-amber-400" />
                                        <span className="text-xs font-black text-slate-600 dark:text-slate-300">{star}</span>
                                    </div>
                                    <div className="flex-1 h-2.5 bg-slate-100 dark:bg-slate-800 rounded-full overflow-hidden">
                                        <div
                                            className="h-full bg-amber-400 rounded-full transition-all duration-500"
                                            style={{ width: `${pct}%` }}
                                        />
                                    </div>
                                    <span className="text-xs font-black text-slate-400 w-16 text-right shrink-0">
                                        {count}명 ({pct}%)
                                    </span>
                                </div>
                            ))}
                        </div>
                    </div>

                    {/* 전체 응답 목록 */}
                    <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl p-6 mx-2">
                        <div className="flex items-center gap-2 mb-5">
                            <MessageSquare className="w-4 h-4 text-slate-400" />
                            <p className="text-xs font-black text-slate-500 uppercase tracking-widest">
                                전체 응답 ({total}건)
                            </p>
                        </div>
                        <div className="space-y-3">
                            {responses.map(r => (
                                <div
                                    key={r.id}
                                    className="flex flex-col sm:flex-row sm:items-start gap-3 p-4 bg-slate-50 dark:bg-slate-900/40 rounded-xl border border-slate-100 dark:border-slate-800"
                                >
                                    {/* 별점 + 이름 */}
                                    <div className="flex items-center gap-3 sm:w-44 shrink-0">
                                        <div className="w-8 h-8 rounded-full bg-amber-100 dark:bg-amber-500/20 flex items-center justify-center shrink-0">
                                            <span className="text-xs font-black text-amber-600 dark:text-amber-400">
                                                {r.user?.full_name?.[0] ?? '?'}
                                            </span>
                                        </div>
                                        <div>
                                            <p className="text-xs font-black text-slate-700 dark:text-slate-200">
                                                {r.user?.full_name ?? '알 수 없음'}
                                            </p>
                                            <StarRow rating={r.rating} size={11} />
                                        </div>
                                    </div>
                                    {/* 의견 + 날짜 */}
                                    <div className="flex-1">
                                        {r.comment ? (
                                            <p className="text-sm text-slate-600 dark:text-slate-300 leading-relaxed">
                                                {r.comment}
                                            </p>
                                        ) : (
                                            <p className="text-xs text-slate-300 dark:text-slate-600 italic">의견 없음</p>
                                        )}
                                        <p className="text-[10px] text-slate-300 dark:text-slate-600 font-bold mt-1.5">
                                            {formatDate(r.created_at)}
                                        </p>
                                    </div>
                                </div>
                            ))}
                        </div>
                    </div>
                </>
            )}
        </div>
    );
}
