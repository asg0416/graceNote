export type AdminAuthProfile = {
  role?: string | null;
  admin_status?: string | null;
  is_master?: boolean | null;
};

export type AdminAuthDecision = {
  path: string;
  shouldSignOut: boolean;
};

export type AdminSocialAuthProvider = 'google' | 'kakao';

export const ADMIN_SOCIAL_AUTH_PROVIDERS: Array<{
  provider: AdminSocialAuthProvider;
  label: string;
}> = [
  { provider: 'google', label: 'Google 계정으로 계속하기' },
  { provider: 'kakao', label: '카카오 계정으로 계속하기' },
];

const DEFAULT_UPGRADE_PATH = '/upgrade';

export function normalizeAdminNextPath(
  nextPath: string | null | undefined,
  fallback = DEFAULT_UPGRADE_PATH
) {
  if (!nextPath || !nextPath.startsWith('/') || nextPath.startsWith('//') || nextPath.includes('\\')) {
    return fallback;
  }

  try {
    const parsed = new URL(nextPath, 'https://admin.local');
    if (parsed.origin !== 'https://admin.local') return fallback;
    return `${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch {
    return fallback;
  }
}

export function buildAdminOAuthRedirectTo(
  origin: string,
  nextPath = DEFAULT_UPGRADE_PATH
) {
  const callbackUrl = new URL('/auth/callback', origin);
  callbackUrl.searchParams.set('next', normalizeAdminNextPath(nextPath));
  return callbackUrl.toString();
}

export function getAdminOAuthQueryParams(provider: AdminSocialAuthProvider) {
  if (provider !== 'kakao') return undefined;

  return {
    scope: 'profile_nickname,profile_image',
  };
}

export function decideAdminAuthRedirect(
  profile: AdminAuthProfile | null | undefined,
  options: { approvedPath?: string; upgradePath?: string | null } = {}
): AdminAuthDecision {
  if (!profile) {
    return { path: '/login?error=profile_not_found', shouldSignOut: true };
  }

  const isApprovedAdmin =
    profile.is_master || (profile.role === 'admin' && profile.admin_status === 'approved');

  if (isApprovedAdmin) {
    return { path: options.approvedPath ?? '/', shouldSignOut: false };
  }

  if (profile.role === 'admin' && profile.admin_status === 'pending') {
    return { path: '/register/success', shouldSignOut: true };
  }

  if (profile.role === 'admin' && profile.admin_status === 'rejected') {
    return { path: '/login?error=rejected', shouldSignOut: true };
  }

  return { path: normalizeAdminNextPath(options.upgradePath, DEFAULT_UPGRADE_PATH), shouldSignOut: false };
}
