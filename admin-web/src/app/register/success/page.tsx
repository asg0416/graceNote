'use client';

import { ShieldCheck, ArrowRight } from 'lucide-react';
import { useRouter } from 'next/navigation';

export default function RegisterSuccessPage() {
    const router = useRouter();

    return (
        <div className="min-h-screen flex items-center justify-center p-6 bg-slate-50 dark:bg-[#0a0f1d]">
            <div className="w-full max-w-md text-center space-y-8 bg-white dark:bg-[#111827]/60 backdrop-blur-2xl p-10 rounded-[40px] border border-white dark:border-slate-800/80 shadow-2xl animate-in zoom-in duration-500">
                <div className="inline-flex items-center justify-center w-20 h-20 bg-emerald-500 rounded-[28px] shadow-2xl shadow-emerald-500/20 mb-4 animate-bounce-slow">
                    <ShieldCheck className="w-10 h-10 text-white" />
                </div>

                <div className="space-y-3">
                    <h2 className="text-3xl font-black text-slate-900 dark:text-white tracking-tighter">신청 완료!</h2>
                    <p className="text-slate-500 dark:text-slate-400 font-bold leading-relaxed">
                        관리자 승인 요청이 성공적으로 접수되었습니다.<br />
                        마스터 관리자의 승인 후 로그인이 가능합니다.
                    </p>
                </div>

                <button
                    onClick={() => router.push('/login')}
                    className="w-full bg-slate-900 dark:bg-white text-white dark:text-slate-900 py-4.5 rounded-2xl font-black text-sm flex items-center justify-center gap-2 transition-all hover:scale-[1.02] active:scale-95 group shadow-xl dark:shadow-none"
                >
                    로그인 화면으로 돌아가기
                    <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
                </button>

                <p className="text-[10px] font-bold text-slate-400 dark:text-slate-600 uppercase tracking-widest">
                    Grace Note Admin System
                </p>
            </div>
        </div>
    );
}
