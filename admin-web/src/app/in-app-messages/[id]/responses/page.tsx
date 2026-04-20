'use client';

import { useEffect, useState } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
  Loader2, ArrowLeft, Star, Users,
  MonitorSmartphone, ChevronRight, X,
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import type { SurveyQuestion } from '../../SurveyBuilder';

function cn(...inputs: ClassValue[]) { return twMerge(clsx(inputs)); }

// ── 타입 ──────────────────────────────────────────────────────────────

interface SurveyAnswer {
  question_id: string;
  value: number | string | string[];
}

interface SurveyResponse {
  id: string;
  created_at: string;
  answers: SurveyAnswer[];
  user: { full_name: string } | null;
}

interface MessageInfo {
  id: string;
  title: string;
  survey_questions: SurveyQuestion[];
}

// ── 유틸 ──────────────────────────────────────────────────────────────

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('ko-KR', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit',
  });
}

function getAnswer(answers: SurveyAnswer[], questionId: string): SurveyAnswer['value'] | null {
  return answers.find(a => a.question_id === questionId)?.value ?? null;
}

// ── 집계 계산 ──────────────────────────────────────────────────────────

function aggregateQuestion(q: SurveyQuestion, responses: SurveyResponse[]) {
  const values = responses
    .map(r => getAnswer(r.answers, q.id))
    .filter(v => v !== null);

  if (q.type === 'star_rating') {
    const nums = values.filter((v): v is number => typeof v === 'number');
    const avg = nums.length > 0
      ? Math.round((nums.reduce((s, v) => s + v, 0) / nums.length) * 10) / 10
      : 0;
    const dist = [5, 4, 3, 2, 1].map(star => ({
      star,
      count: nums.filter(v => v === star).length,
      pct: nums.length > 0
        ? Math.round((nums.filter(v => v === star).length / nums.length) * 100)
        : 0,
    }));
    return { avg, dist, count: nums.length };
  }

  if (q.type === 'radio') {
    const strs = values.filter((v): v is string => typeof v === 'string');
    return q.options.map(opt => ({
      label: opt,
      count: strs.filter(v => v === opt).length,
      pct: strs.length > 0
        ? Math.round((strs.filter(v => v === opt).length / strs.length) * 100)
        : 0,
    }));
  }

  if (q.type === 'checkbox') {
    const arrs = values.filter((v): v is string[] => Array.isArray(v)).flat();
    return q.options.map(opt => ({
      label: opt,
      count: arrs.filter(v => v === opt).length,
      pct: values.length > 0
        ? Math.round((arrs.filter(v => v === opt).length / values.length) * 100)
        : 0,
    }));
  }

  if (q.type === 'text') {
    return values.filter((v): v is string => typeof v === 'string' && v.trim().length > 0);
  }

  return null;
}

// ── 집계 카드 ──────────────────────────────────────────────────────────

function AggregateCard({ q, responses }: { q: SurveyQuestion; responses: SurveyResponse[] }) {
  const data = aggregateQuestion(q, responses);
  const answered = responses.filter(r => getAnswer(r.answers, q.id) !== null).length;

  return (
    <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl p-5 space-y-4">
      <div className="flex items-start justify-between gap-3">
        <p className="text-sm font-bold text-slate-700 dark:text-slate-200 leading-snug">{q.text}</p>
        <span className="text-[10px] font-black text-slate-400 shrink-0 bg-slate-100 dark:bg-slate-800 px-2 py-1 rounded-full">
          {answered}명 응답
        </span>
      </div>

      {q.type === 'star_rating' && data && 'avg' in (data as object) && (() => {
        const { avg, dist } = data as { avg: number; dist: Array<{ star: number; count: number; pct: number }> };
        return (
          <div className="space-y-2">
            <div className="flex items-center gap-3">
              <span className="text-4xl font-black text-slate-900 dark:text-white">{avg}</span>
              <div className="flex gap-0.5">
                {[1,2,3,4,5].map(i => (
                  <Star key={i} size={16} className={i <= Math.round(avg) ? 'text-amber-400 fill-amber-400' : 'text-slate-200 fill-slate-200'} />
                ))}
              </div>
            </div>
            <div className="space-y-1.5">
              {dist.map(({ star, count, pct }) => (
                <div key={star} className="flex items-center gap-2">
                  <div className="flex items-center gap-1 w-8 shrink-0">
                    <Star size={11} className="text-amber-400 fill-amber-400" />
                    <span className="text-xs font-black text-slate-500">{star}</span>
                  </div>
                  <div className="flex-1 h-2 bg-slate-100 dark:bg-slate-800 rounded-full overflow-hidden">
                    <div className="h-full bg-amber-400 rounded-full transition-all duration-500" style={{ width: `${pct}%` }} />
                  </div>
                  <span className="text-xs font-black text-slate-400 w-16 text-right shrink-0">
                    {count}명 ({pct}%)
                  </span>
                </div>
              ))}
            </div>
          </div>
        );
      })()}

      {(q.type === 'radio' || q.type === 'checkbox') && Array.isArray(data) && (
        <div className="space-y-2">
          {(data as Array<{ label: string; count: number; pct: number }>).map(({ label, count, pct }) => (
            <div key={label} className="space-y-1">
              <div className="flex justify-between text-xs font-bold text-slate-600 dark:text-slate-300">
                <span>{label}</span>
                <span className="text-slate-400">{count}명 ({pct}%)</span>
              </div>
              <div className="h-2 bg-slate-100 dark:bg-slate-800 rounded-full overflow-hidden">
                <div className="h-full bg-violet-500 rounded-full transition-all duration-500" style={{ width: `${pct}%` }} />
              </div>
            </div>
          ))}
        </div>
      )}

      {q.type === 'text' && Array.isArray(data) && (
        <div className="space-y-2">
          {(data as string[]).length === 0 && (
            <p className="text-xs text-slate-300 italic">응답 없음</p>
          )}
          {(data as string[]).slice(0, 10).map((text, i) => (
            <p key={i} className="text-sm text-slate-600 dark:text-slate-300 bg-slate-50 dark:bg-slate-800/50 rounded-xl px-3 py-2 leading-relaxed">
              {text}
            </p>
          ))}
          {(data as string[]).length > 10 && (
            <p className="text-xs text-slate-400 text-center">+{(data as string[]).length - 10}개 더</p>
          )}
        </div>
      )}
    </div>
  );
}

// ── 개별 제출 슬라이드오버 ────────────────────────────────────────────

function ResponseSlideOver({
  response,
  questions,
  onClose,
}: {
  response: SurveyResponse;
  questions: SurveyQuestion[];
  onClose: () => void;
}) {
  const renderAnswer = (q: SurveyQuestion) => {
    const val = getAnswer(response.answers, q.id);
    if (val === null) return <span className="text-slate-300 italic text-xs">미응답</span>;
    if (q.type === 'star_rating') {
      return (
        <div className="flex gap-0.5 items-center">
          {[1,2,3,4,5].map(i => (
            <Star key={i} size={14} className={i <= (val as number) ? 'text-amber-400 fill-amber-400' : 'text-slate-200 fill-slate-200'} />
          ))}
          <span className="text-xs text-slate-400 ml-1">{val}점</span>
        </div>
      );
    }
    if (q.type === 'radio') {
      return <span className="text-sm text-slate-700 dark:text-slate-200">{val as string}</span>;
    }
    if (q.type === 'checkbox') {
      return (
        <div className="flex flex-wrap gap-1">
          {(val as string[]).map((v, i) => (
            <span key={i} className="text-xs bg-violet-100 dark:bg-violet-900/30 text-violet-700 dark:text-violet-300 px-2 py-0.5 rounded-full font-bold">
              {v}
            </span>
          ))}
        </div>
      );
    }
    return <p className="text-sm text-slate-600 dark:text-slate-300 leading-relaxed">{val as string}</p>;
  };

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative w-full max-w-md bg-white dark:bg-slate-900 h-full overflow-y-auto shadow-2xl p-6 space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <p className="font-black text-slate-800 dark:text-white">
              {response.user?.full_name ?? '알 수 없음'}
            </p>
            <p className="text-xs text-slate-400 mt-0.5">{formatDate(response.created_at)}</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-2 rounded-xl text-slate-400 hover:text-slate-700 dark:hover:text-white transition-colors"
          >
            <X size={18} />
          </button>
        </div>
        <div className="space-y-4">
          {questions.map((q, i) => (
            <div key={q.id} className="space-y-1.5">
              <p className="text-xs font-black text-slate-500">Q{i + 1}. {q.text}</p>
              {renderAnswer(q)}
            </div>
          ))}
        </div>
      </div>
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
  const [activeTab, setActiveTab] = useState<'aggregate' | 'individual'>('aggregate');
  const [selectedResponse, setSelectedResponse] = useState<SurveyResponse | null>(null);

  useEffect(() => {
    const init = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) { router.push('/login'); return; }

      const { data: profile } = await supabase
        .from('profiles')
        .select('is_master')
        .eq('id', session.user.id)
        .single();

      if (!profile?.is_master) { router.push('/in-app-messages'); return; }

      const { data: msg } = await supabase
        .from('in_app_messages')
        .select('id, title, survey_questions')
        .eq('id', messageId)
        .single();

      if (!msg) { router.push('/in-app-messages'); return; }

      setMessage({
        id: msg.id,
        title: msg.title,
        survey_questions: (msg.survey_questions as SurveyQuestion[]) ?? [],
      });

      const { data: rows } = await supabase
        .from('iam_survey_responses')
        .select('id, answers, created_at, user:profiles!user_id(full_name)')
        .eq('message_id', messageId)
        .order('created_at', { ascending: false });

      const normalized: SurveyResponse[] = (rows ?? []).map((r: any) => ({
        id: r.id,
        answers: r.answers ?? [],
        created_at: r.created_at,
        user: Array.isArray(r.user) ? (r.user[0] ?? null) : (r.user ?? null),
      }));

      setResponses(normalized);
      setLoading(false);
    };
    init();
  }, [messageId, router]);

  if (loading) {
    return (
      <div className="h-[80vh] flex flex-col items-center justify-center gap-4">
        <Loader2 className="w-10 h-10 text-violet-600 animate-spin" />
        <p className="text-slate-400 font-bold text-xs uppercase tracking-widest">응답 불러오는 중...</p>
      </div>
    );
  }

  const total = responses.length;
  const questions = message?.survey_questions ?? [];

  return (
    <div className="max-w-4xl mx-auto pb-20 space-y-6">
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
            <span className="text-[10px] font-black text-amber-600 dark:text-amber-400 uppercase tracking-widest">설문 결과</span>
          </div>
          <h1 className="text-2xl font-black text-slate-900 dark:text-white tracking-tighter">
            {message?.title}
          </h1>
        </div>
        <div className="ml-auto flex items-center gap-1.5 bg-slate-100 dark:bg-slate-800 rounded-xl px-3 py-2">
          <Users size={14} className="text-slate-400" />
          <span className="text-sm font-black text-slate-700 dark:text-slate-200">{total}명</span>
        </div>
      </header>

      {/* 탭 */}
      <div className="flex gap-1 bg-slate-100 dark:bg-slate-800 p-1 rounded-2xl mx-2">
        {(['aggregate', 'individual'] as const).map(tab => (
          <button
            key={tab}
            type="button"
            onClick={() => setActiveTab(tab)}
            className={cn(
              'flex-1 py-2 text-xs font-black rounded-xl transition-all',
              activeTab === tab
                ? 'bg-white dark:bg-slate-700 text-slate-800 dark:text-white shadow-sm'
                : 'text-slate-500 hover:text-slate-700 dark:hover:text-slate-200',
            )}
          >
            {tab === 'aggregate' ? '집계 요약' : `개별 제출 (${total})`}
          </button>
        ))}
      </div>

      {total === 0 ? (
        <div className="bg-white dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800 rounded-2xl p-20 text-center">
          <p className="text-slate-400 font-bold">아직 응답이 없습니다.</p>
        </div>
      ) : (
        <>
          {activeTab === 'aggregate' && (
            <div className="space-y-4 px-2">
              {questions.map(q => (
                <AggregateCard key={q.id} q={q} responses={responses} />
              ))}
            </div>
          )}

          {activeTab === 'individual' && (
            <div className="space-y-2 px-2">
              {responses.map(r => (
                <button
                  key={r.id}
                  type="button"
                  onClick={() => setSelectedResponse(r)}
                  className="w-full flex items-center gap-4 p-4 bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl hover:border-violet-300 dark:hover:border-violet-700 transition-all text-left"
                >
                  <div className="w-9 h-9 rounded-full bg-violet-100 dark:bg-violet-900/30 flex items-center justify-center shrink-0">
                    <span className="text-xs font-black text-violet-600 dark:text-violet-300">
                      {r.user?.full_name?.[0] ?? '?'}
                    </span>
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-black text-slate-700 dark:text-slate-200">
                      {r.user?.full_name ?? '알 수 없음'}
                    </p>
                    <p className="text-[10px] text-slate-400 mt-0.5">{formatDate(r.created_at)}</p>
                  </div>
                  <ChevronRight size={16} className="text-slate-300 shrink-0" />
                </button>
              ))}
            </div>
          )}
        </>
      )}

      {selectedResponse && (
        <ResponseSlideOver
          response={selectedResponse}
          questions={questions}
          onClose={() => setSelectedResponse(null)}
        />
      )}
    </div>
  );
}
