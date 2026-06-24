import { existsSync } from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { NextResponse } from 'next/server';

export const runtime = 'nodejs';

const DEV_DB_URL_FILE = '/private/tmp/gracenote_dev_db_url';

function getRepoRoot() {
  return process.cwd().endsWith(`${path.sep}admin-web`)
    ? path.dirname(process.cwd())
    : process.cwd();
}

function isLocalHost(value: string) {
  const host = value.split(',')[0]?.trim().toLowerCase() ?? '';
  return (
    host === 'localhost' ||
    host.startsWith('localhost:') ||
    host === '127.0.0.1' ||
    host.startsWith('127.0.0.1:') ||
    host === '[::1]' ||
    host.startsWith('[::1]:') ||
    host === '::1'
  );
}

function isDevToolAllowed(req: Request) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  const host = req.headers.get('host') ?? '';
  const forwardedHost = req.headers.get('x-forwarded-host') ?? '';
  return (
    process.env.NODE_ENV !== 'production' &&
    supabaseUrl.includes('eftdf') &&
    isLocalHost(host) &&
    (!forwardedHost || isLocalHost(forwardedHost))
  );
}

function isValidEmail(email: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function isValidUuid(value: string) {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(value);
}

export async function POST(req: Request) {
  if (!isDevToolAllowed(req)) {
    return NextResponse.json(
      { error: '이 기능은 eftdf 개발 서버의 로컬 개발 환경에서만 사용할 수 있습니다.' },
      { status: 403 }
    );
  }

  if (!existsSync(DEV_DB_URL_FILE)) {
    return NextResponse.json(
      { error: '/private/tmp/gracenote_dev_db_url 파일이 없습니다. dev DB URL을 먼저 저장해 주세요.' },
      { status: 400 }
    );
  }

  const body = await req.json().catch(() => null);
  const target = typeof body?.target === 'string'
    ? body.target.trim()
    : typeof body?.email === 'string'
      ? body.email.trim()
      : '';

  const isEmail = isValidEmail(target);
  const isUuid = isValidUuid(target);

  if (!isEmail && !isUuid) {
    return NextResponse.json({ error: '이메일 또는 Auth User ID(UUID)를 입력해 주세요.' }, { status: 400 });
  }

  const repoRoot = getRepoRoot();
  const scriptPath = path.join(repoRoot, 'scripts', 'dev-social-auth-smoke-state.mjs');
  const args = [
    scriptPath,
    '--db-url-file',
    DEV_DB_URL_FILE,
    '--confirm-dev-withdraw',
  ];
  if (isUuid) {
    args.push('--withdraw-user-id', target);
  } else {
    args.push('--withdraw-email', target.toLowerCase());
  }

  const result = spawnSync(process.execPath, args, {
    cwd: repoRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  if (result.status !== 0) {
    return NextResponse.json(
      {
        error: 'dev smoke 탈퇴 처리 중 오류가 발생했습니다.',
        detail: (result.stderr || result.stdout || '').trim(),
      },
      { status: 500 }
    );
  }

  return NextResponse.json({
    success: true,
    output: result.stdout.trim(),
  });
}
