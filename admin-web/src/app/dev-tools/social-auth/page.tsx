'use client';

import { useState } from 'react';
import { AlertTriangle, CheckCircle2, Loader2, RotateCcw, ShieldAlert } from 'lucide-react';

function getErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

export default function DevSocialAuthToolPage() {
  const [target, setTarget] = useState('');
  const [confirmText, setConfirmText] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const canSubmit = target.trim().length > 0 && confirmText === 'DEV 탈퇴';

  const handleWithdraw = async () => {
    if (!canSubmit) return;

    setLoading(true);
    setMessage(null);
    setError(null);

    try {
      const res = await fetch('/api/dev/social-auth/withdraw', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ target }),
      });

      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        const detail = typeof json.detail === 'string' && json.detail.trim()
          ? `\n${json.detail.trim()}`
          : '';
        throw new Error(`${json.error || '요청이 실패했습니다.'}${detail}`);
      }

      setMessage(json.output || 'dev smoke 탈퇴 처리가 완료되었습니다.');
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="min-h-screen bg-slate-950 text-white">
      <div className="mx-auto flex min-h-screen w-full max-w-5xl flex-col justify-center px-6 py-12">
        <div className="mb-8 inline-flex w-fit items-center gap-2 rounded-full border border-amber-400/30 bg-amber-400/10 px-4 py-2 text-sm font-black text-amber-200">
          <ShieldAlert className="h-4 w-4" />
          개발 서버 전용 도구
        </div>

        <div className="grid gap-8 lg:grid-cols-[1.1fr_0.9fr]">
          <section className="rounded-[2rem] border border-white/10 bg-white/[0.06] p-8 shadow-2xl shadow-black/30">
            <div className="space-y-4">
              <p className="text-sm font-black uppercase tracking-[0.28em] text-blue-300">Social Auth Smoke</p>
              <h1 className="text-4xl font-black tracking-tight">테스트 계정 탈퇴 상태 만들기</h1>
              <p className="max-w-2xl text-base font-semibold leading-7 text-slate-300">
                소셜 로그인 재가입 smoke를 위해 특정 auth/profile을 개발 DB에서 격리합니다.
                교회 소속, 기도, 출석, 조편성 이력은 삭제하지 않습니다.
              </p>
            </div>

            <div className="mt-8 space-y-5">
              <label className="block">
                <span className="mb-2 block text-xs font-black uppercase tracking-[0.22em] text-slate-400">대상 계정</span>
                <input
                  value={target}
                  onChange={(event) => setTarget(event.target.value)}
                  className="w-full rounded-2xl border border-white/10 bg-slate-900 px-5 py-4 text-lg font-black text-white outline-none transition focus:border-blue-400"
                  placeholder="user@example.com 또는 Auth User ID"
                  type="text"
                />
                <span className="mt-2 block text-xs font-bold leading-5 text-slate-500">
                  Kakao처럼 이메일이 없는 계정은 Supabase Authentication의 User ID(UUID)를 입력하세요.
                </span>
              </label>

              <label className="block">
                <span className="mb-2 block text-xs font-black uppercase tracking-[0.22em] text-slate-400">확인 문구</span>
                <input
                  value={confirmText}
                  onChange={(event) => setConfirmText(event.target.value)}
                  className="w-full rounded-2xl border border-white/10 bg-slate-900 px-5 py-4 text-lg font-black text-white outline-none transition focus:border-amber-300"
                  placeholder="DEV 탈퇴"
                />
              </label>

              <button
                type="button"
                onClick={handleWithdraw}
                disabled={!canSubmit || loading}
                className="inline-flex w-full items-center justify-center gap-3 rounded-2xl bg-blue-500 px-6 py-4 text-base font-black text-white shadow-xl shadow-blue-950/40 transition hover:bg-blue-400 disabled:cursor-not-allowed disabled:bg-slate-700 disabled:text-slate-400"
              >
                {loading ? <Loader2 className="h-5 w-5 animate-spin" /> : <RotateCcw className="h-5 w-5" />}
                dev smoke 탈퇴 처리
              </button>
            </div>

            {message && (
              <pre className="mt-6 max-h-72 overflow-auto rounded-2xl border border-emerald-400/20 bg-emerald-400/10 p-5 text-sm font-bold leading-6 text-emerald-100">
                <CheckCircle2 className="mb-3 h-5 w-5" />
                {message}
              </pre>
            )}

            {error && (
              <div className="mt-6 rounded-2xl border border-red-400/20 bg-red-500/10 p-5 text-sm font-black leading-6 text-red-100">
                <AlertTriangle className="mb-3 h-5 w-5" />
                {error}
              </div>
            )}
          </section>

          <aside className="rounded-[2rem] border border-white/10 bg-slate-900 p-8">
            <h2 className="text-xl font-black">이 버튼이 하는 일</h2>
            <div className="mt-6 space-y-4 text-sm font-semibold leading-6 text-slate-300">
              <p>1. 입력한 이메일 또는 Auth User ID의 auth user를 삭제하지 않고 로그인 불가 상태로 바꿉니다.</p>
              <p>2. profile의 이메일/전화/person 연결을 끊어 같은 전화번호로 재가입 테스트가 가능하게 합니다.</p>
              <p>3. 기존 성도 이력 데이터인 기도, 출석, 조편성, 소속 이력은 삭제하지 않습니다.</p>
              <p>4. 실제 회원 탈퇴 기능이 아닙니다. 운영용 탈퇴는 별도 정책과 테이블 설계가 필요합니다.</p>
            </div>

            <div className="mt-8 rounded-2xl bg-amber-400/10 p-5 text-sm font-bold leading-6 text-amber-100">
              로컬 개발 서버에서만 사용하세요. `/private/tmp/gracenote_dev_db_url`이 dev DB를 가리키고 있어야 합니다.
            </div>
          </aside>
        </div>
      </div>
    </main>
  );
}
