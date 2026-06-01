'use client';

import { useState } from 'react';
import { Chrome, Loader2, MessageCircle } from 'lucide-react';
import { supabase } from '@/lib/supabase';
import {
  ADMIN_SOCIAL_AUTH_PROVIDERS,
  buildAdminOAuthRedirectTo,
  getAdminOAuthQueryParams,
  type AdminSocialAuthProvider,
} from '@/lib/adminAuth';

type AdminSocialAuthButtonsProps = {
  disabled?: boolean;
  label?: string;
  nextPath?: string;
  onError?: (message: string | null) => void;
};

export default function AdminSocialAuthButtons({
  disabled = false,
  label = '소셜 계정으로 계속하기',
  nextPath = '/upgrade',
  onError,
}: AdminSocialAuthButtonsProps) {
  const [socialLoading, setSocialLoading] = useState<AdminSocialAuthProvider | null>(null);

  const handleSocialAuth = async (provider: AdminSocialAuthProvider) => {
    setSocialLoading(provider);
    onError?.(null);

    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider,
        options: {
          redirectTo: buildAdminOAuthRedirectTo(window.location.origin, nextPath),
          queryParams: getAdminOAuthQueryParams(provider),
        },
      });

      if (error) throw error;
    } catch (err) {
      const error = err as { message?: string };
      onError?.(error.message || '소셜 로그인 중 오류가 발생했습니다.');
      setSocialLoading(null);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-4">
        <div className="h-px flex-1 bg-slate-100 dark:bg-slate-800/70" />
        <span className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em]">
          {label}
        </span>
        <div className="h-px flex-1 bg-slate-100 dark:bg-slate-800/70" />
      </div>

      <div className="grid grid-cols-1 gap-3">
        {ADMIN_SOCIAL_AUTH_PROVIDERS.map(({ provider, label: providerLabel }) => {
          const Icon = provider === 'google' ? Chrome : MessageCircle;
          const isLoading = socialLoading === provider;

          return (
            <button
              key={provider}
              type="button"
              disabled={disabled || Boolean(socialLoading)}
              onClick={() => handleSocialAuth(provider)}
              className="h-12 w-full rounded-2xl border border-slate-200 dark:border-slate-800/80 bg-white dark:bg-slate-900/40 text-slate-700 dark:text-slate-200 hover:border-indigo-500/40 hover:bg-slate-50 dark:hover:bg-slate-800/60 transition-all flex items-center justify-center gap-3 text-xs font-black disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {isLoading ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Icon className="h-4 w-4" />
              )}
              {providerLabel}
            </button>
          );
        })}
      </div>
    </div>
  );
}
