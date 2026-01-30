'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { Loader2, Users, Church, Calendar, AlertCircle, ArrowUpRight, TrendingUp, Bell } from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export default function DashboardPage() {
  const [loading, setLoading] = useState(true);
  const [profile, setProfile] = useState<any>(null);
  const [stats, setStats] = useState({
    totalMembers: 0,
    totalChurches: 0,
    pendingAdmins: 0,
    totalGroups: 0,
    pendingInquiries: 0,
    churchName: '',
    unassignedMembers: 0,
  });
  const [recentMembers, setRecentMembers] = useState<any[]>([]);
  const router = useRouter();

  useEffect(() => {
    const checkUser = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        router.push('/login');
        return;
      }

      const { data } = await supabase
        .from('profiles')
        .select('id, full_name, role, admin_status, is_master, church_id, department_id')
        .eq('id', session.user.id)
        .single();

      const isAuthorized = data && (data.is_master || (data.role === 'admin' && data.admin_status === 'approved'));

      if (!isAuthorized) {
        await supabase.auth.signOut();
        router.push('/login?error=unauthorized');
        return;
      }

      setProfile(data);
      await fetchDashboardData(data);
      setLoading(false);
    };

    checkUser();
  }, [router]);

  const fetchDashboardData = async (userProfile: any) => {
    try {
      let totalMembers = 0;
      let totalChurches = 0;
      let pendingAdmins = 0;
      let totalGroups = 0;
      let churchName = '(전체)';

      // Fetch church name if not master
      if (userProfile.church_id) {
        const { data: church } = await supabase
          .from('churches')
          .select('name')
          .eq('id', userProfile.church_id)
          .single();
        if (church) churchName = church.name;
      }

      let unassignedMembers = 0;
      if (userProfile.is_master) {
        // Master Global Stats
        const { count: memberCount } = await supabase.from('member_directory').select('*', { count: 'exact', head: true });
        const { count: churchCount } = await supabase.from('churches').select('*', { count: 'exact', head: true });
        const { count: pendingCount } = await supabase.from('profiles').select('*', { count: 'exact', head: true }).eq('admin_status', 'pending');
        const { count: groupCount } = await supabase.from('groups').select('*', { count: 'exact', head: true });

        totalMembers = memberCount || 0;
        totalChurches = churchCount || 0;
        pendingAdmins = pendingCount || 0;
        totalGroups = groupCount || 0;
      } else {
        // Church Admin Specific Stats
        let memberQuery = supabase.from('member_directory').select('*', { count: 'exact', head: true }).eq('church_id', userProfile.church_id);
        let pendingQuery = supabase.from('profiles').select('*', { count: 'exact', head: true }).eq('church_id', userProfile.church_id).eq('admin_status', 'pending');
        let groupQuery = supabase.from('groups').select('*', { count: 'exact', head: true }).eq('church_id', userProfile.church_id);
        let unassignedQuery = supabase.from('member_directory').select('*', { count: 'exact', head: true }).eq('church_id', userProfile.church_id).or('group_name.is.null,group_name.eq.""');

        if (userProfile.department_id) {
          memberQuery = memberQuery.eq('department_id', userProfile.department_id);
          pendingQuery = pendingQuery.eq('department_id', userProfile.department_id);
          groupQuery = groupQuery.eq('department_id', userProfile.department_id);
          unassignedQuery = unassignedQuery.eq('department_id', userProfile.department_id);
        }

        const { count: memberCount } = await memberQuery;
        const { count: pendingCount } = await pendingQuery;
        const { count: groupCount } = await groupQuery;
        const { count: unassignedCount } = await unassignedQuery;

        totalMembers = memberCount || 0;
        totalChurches = 1; // Only their church
        pendingAdmins = pendingCount || 0;
        totalGroups = groupCount || 0;
        unassignedMembers = unassignedCount || 0;
      }

      // Inquiries count (pending)
      let inquiryCount = 0;
      if (userProfile.is_master) {
        const { count } = await supabase
          .from('inquiries')
          .select('*', { count: 'exact', head: true })
          .neq('status', 'closed');
        inquiryCount = count || 0;
      }

      setStats({
        totalMembers,
        totalChurches,
        pendingAdmins,
        totalGroups,
        pendingInquiries: inquiryCount,
        churchName,
        unassignedMembers,
      });

      // Recent Members
      const memberQuery = supabase
        .from('member_directory')
        .select('full_name, created_at, role_in_group')
        .order('created_at', { ascending: false })
        .limit(5);

      if (!userProfile.is_master) {
        memberQuery.eq('church_id', userProfile.church_id);
        if (userProfile.department_id) memberQuery.eq('department_id', userProfile.department_id);
      }

      const { data: members } = await memberQuery;
      setRecentMembers(members || []);

    } catch (err) {
      console.error('Dashboard Data Fetch Error:', err);
    }
  };



  return (
    <div className="space-y-8 sm:space-y-12 max-w-7xl mx-auto">
      <header className="flex flex-col sm:flex-row sm:items-center justify-between gap-6 sm:gap-0">
        <div className="space-y-2">
          <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">
            안녕하세요, <span className="text-indigo-600 dark:text-indigo-400">{profile?.full_name}</span>님
          </h1>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
            <p className="text-slate-500 dark:text-slate-500 font-bold text-xs sm:text-sm tracking-tight text-left">
              {profile?.is_master ? '시스템 마스터' : `${stats.churchName} 관리자`} 모드로 안전하게 연결됨
            </p>
          </div>
        </div>
        <div className="flex items-center gap-4">
          <div className="h-10 sm:h-12 w-[1px] bg-slate-200 dark:bg-slate-800 mx-1 sm:mx-2" />
          <div className="text-left sm:text-right hidden xs:block">
            <p className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest">오늘의 날짜</p>
            <p className="text-xs sm:text-sm font-bold text-slate-900 dark:text-white mt-0.5">{new Date().toLocaleDateString('ko-KR', { month: 'long', day: 'numeric', weekday: 'long' })}</p>
          </div>
        </div>
      </header>

      {/* Hero Highlight */}
      <div className="relative group overflow-hidden rounded-[32px] sm:rounded-[40px]">
        <div className="absolute -inset-1 bg-gradient-to-r from-indigo-500 to-purple-600 rounded-[32px] sm:rounded-[40px] blur opacity-10 dark:opacity-20 group-hover:opacity-20 dark:group-hover:opacity-30 transition duration-1000 group-hover:duration-200" />
        <div className="relative bg-white dark:bg-[#111827]/80 backdrop-blur-xl border border-slate-200 dark:border-slate-800/60 rounded-[32px] sm:rounded-[40px] p-6 sm:p-10 flex flex-col lg:flex-row lg:items-center justify-between overflow-hidden gap-10">
          <div className="absolute top-[-50%] right-[-10%] w-64 sm:w-96 h-64 sm:h-96 bg-indigo-600/5 dark:bg-indigo-600/10 rounded-full blur-[60px] sm:blur-[100px]" />
          <div className="relative z-10 space-y-4 sm:space-y-6 max-w-xl">
            <div className="inline-flex items-center gap-2 px-3 sm:px-4 py-1.5 bg-indigo-50 dark:bg-indigo-500/10 border border-indigo-100 dark:border-indigo-500/20 rounded-full">
              <TrendingUp className="w-3.5 sm:w-4 h-3.5 sm:h-4 text-indigo-600 dark:text-indigo-400" />
              <span className="text-[10px] font-black text-indigo-600 dark:text-indigo-400 uppercase tracking-wider">시스템 통찰</span>
            </div>
            <h2 className="text-2xl sm:text-3xl font-black text-slate-900 dark:text-white leading-tight tracking-tight">
              관리자님, 현재 <span className="text-indigo-600 dark:text-transparent dark:bg-clip-text dark:bg-gradient-to-r dark:from-indigo-400 dark:to-purple-400 underline decoration-indigo-200 dark:decoration-indigo-500/30">{stats.churchName}</span>의 시스템이 원활하게 운영되고 있습니다.
            </h2>
            <p className="text-slate-500 dark:text-slate-400 font-medium leading-relaxed text-sm sm:text-base">
              성도 명부와 조직 구조가 최신 상태로 유지되고 있습니다.
              새로운 출석 보고서와 활동 내역을 아래에서 확인해 보세요.
            </p>
            <button
              onClick={() => router.push('/members')}
              className="w-full sm:w-fit bg-slate-950 dark:bg-white text-white dark:text-slate-950 px-8 py-4 rounded-2xl sm:rounded-3xl font-black text-sm hover:scale-105 active:scale-95 transition-all shadow-xl shadow-slate-950/10 dark:shadow-white/5 mt-4"
            >
              성도 명부 바로가기
            </button>
          </div>
          <div className="relative z-10 grid grid-cols-2 gap-4 lg:w-1/3">
            <div className="p-4 sm:p-6 bg-slate-50 dark:bg-slate-500/5 border border-slate-200 dark:border-slate-400/10 rounded-2xl sm:rounded-3xl backdrop-blur-md">
              <p className="text-[10px] font-bold text-slate-400 dark:text-slate-500 mb-1 uppercase tracking-widest">실시간 연동</p>
              <h4 className="text-xl sm:text-2xl font-black text-slate-900 dark:text-white">Active</h4>
            </div>
            <div className="p-4 sm:p-6 bg-indigo-50 dark:bg-indigo-500/10 border border-indigo-100 dark:border-indigo-400/10 rounded-2xl sm:rounded-3xl backdrop-blur-md">
              <p className="text-[10px] font-bold text-indigo-400 dark:text-indigo-400 mb-1 uppercase tracking-widest">응답 속도</p>
              <h4 className="text-xl sm:text-2xl font-black text-indigo-600 dark:text-white">0.1s</h4>
            </div>
          </div>
        </div>
      </div>

      {loading ? (
        <div className="h-64 flex flex-col items-center justify-center gap-4">
          <Loader2 className="w-10 h-10 text-indigo-600 animate-spin" />
          <p className="text-slate-400 font-black text-xs uppercase tracking-widest">데이터 로딩 중...</p>
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 sm:gap-8 mb-12 sm:mb-16">
            <StatsCard
              title={profile?.is_master ? "전체 성도" : "우리 교회 성도"}
              value={stats.totalMembers.toLocaleString()}
              change="Total"
              icon={Users}
              color="indigo"
              onClick={() => router.push('/members')}
            />
            {profile?.is_master ? (
              <StatsCard
                title="등록 교회"
                value={stats.totalChurches.toLocaleString()}
                change="Active"
                icon={() => (
                  <div className="w-6 h-6 flex items-center justify-center overflow-hidden">
                    <img src="/logo-icon.png" alt="Church" className="w-5 h-5 object-contain" />
                  </div>
                )}
                color="slate"
                onClick={() => router.push('/churches')}
              />
            ) : (
              <StatsCard
                title="미배정 성도"
                value={stats.unassignedMembers.toLocaleString()}
                change="Review"
                icon={Users}
                color="rose"
                isWarning={stats.unassignedMembers > 0}
                onClick={() => router.push('/regrouping')}
              />
            )}
            {profile?.is_master && (
              <StatsCard
                title={profile?.is_master ? "전체 승인 대기" : "관리자 승인 대기"}
                value={stats.pendingAdmins.toLocaleString()}
                change="Wait"
                icon={AlertCircle}
                color="amber"
                isWarning={stats.pendingAdmins > 0}
                onClick={profile?.is_master ? () => router.push('/admin-requests') : undefined}
              />
            )}
            <StatsCard
              title="운영 조"
              value={stats.totalGroups.toLocaleString()}
              change="Active"
              icon={Calendar}
              color="emerald"
              onClick={() => router.push('/departments')}
            />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 sm:gap-10 pb-10">
            <div className={cn(
              "bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 backdrop-blur-xl rounded-[32px] sm:rounded-[40px] p-6 sm:p-10 shadow-xl dark:shadow-2xl space-y-8",
              !profile?.is_master && "lg:col-span-2"
            )}>
              <div className="flex items-center justify-between">
                <h3 className="text-lg sm:text-xl font-black text-slate-900 dark:text-white tracking-tighter flex items-center gap-3">
                  <span className="w-1.5 h-6 sm:h-7 bg-indigo-600 dark:bg-indigo-500 rounded-full" />
                  {profile?.is_master ? "플랫폼 최근 가입자" : "교회 최근 가입자"}
                </h3>
                <button onClick={() => router.push('/members')} className="text-[10px] font-black text-indigo-600 dark:text-indigo-400 hover:text-indigo-500 dark:hover:text-indigo-300 transition-colors uppercase tracking-widest">전체보기</button>
              </div>
              <div className={cn(
                "grid grid-cols-1 gap-6 sm:gap-8",
                !profile?.is_master && "md:grid-cols-2"
              )}>
                {recentMembers.map((m, idx) => (
                  <ActivityItem
                    key={idx}
                    title={m.full_name}
                    desc={m.role_in_group === 'leader' ? '조장으로 등록됨' : '성도로 등록됨'}
                    time={new Date(m.created_at).toLocaleDateString()}
                    dotColor={m.role_in_group === 'leader' ? 'bg-amber-500' : 'bg-indigo-500'}
                  />
                ))}
                {recentMembers.length === 0 && (
                  <p className="text-center text-slate-400 font-bold py-10 col-span-full">최근 활동 내역이 없습니다.</p>
                )}
              </div>
            </div>

            {profile?.is_master && (
              <div className="space-y-6 flex flex-col">
                <div className="bg-gradient-to-br from-indigo-700 to-purple-800 rounded-[32px] sm:rounded-[40px] p-6 sm:p-10 flex flex-col justify-between h-full relative overflow-hidden group shadow-2xl shadow-indigo-500/20">
                  <div className="absolute top-0 right-0 p-8">
                    <Bell className={cn("w-10 h-10 text-white/20 transition-all", stats.pendingInquiries > 0 && "animate-bounce text-rose-300/40")} />
                  </div>
                  <div className="space-y-4 sm:space-y-6">
                    <div className="inline-flex items-center gap-2 px-3 py-1 bg-white/10 border border-white/20 rounded-full">
                      <span className="w-2 h-2 rounded-full bg-rose-400 animate-pulse" />
                      <span className="text-[10px] font-black text-white uppercase tracking-wider">상담 및 문의 관리</span>
                    </div>
                    <h3 className="text-xl sm:text-2xl font-black text-white leading-tight">
                      {stats.pendingInquiries > 0
                        ? `${stats.pendingInquiries}건의 문의가\n답변을 기다리고 있습니다.`
                        : "새로운 문의가\n현재 없습니다."}
                    </h3>
                    <p className="text-white/70 font-medium text-xs sm:text-sm max-w-[240px]">
                      성도님들의 궁금증과 불편사항을 실시간으로 확인하고 신속하게 답변해 보세요.
                    </p>
                  </div>
                  <button
                    onClick={() => router.push('/inquiries')}
                    className="w-full sm:w-fit bg-white text-slate-950 px-8 py-4 rounded-2xl sm:rounded-3xl font-black text-xs hover:bg-slate-50 transition-all border border-white/50 mt-8"
                  >
                    문의 관리 바로가기
                  </button>
                </div>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}


function StatsCard({ title, value, change, icon: Icon, color, isWarning, onClick }: any) {
  const colorMap: any = {
    indigo: "from-indigo-600/10 to-indigo-600/[0.02] dark:from-indigo-500/20 dark:to-indigo-500/5 text-indigo-600 dark:text-indigo-400 border-indigo-200 dark:border-indigo-500/20",
    blue: "from-blue-600/10 to-blue-600/[0.02] dark:from-blue-500/20 dark:to-blue-500/5 text-blue-600 dark:text-blue-400 border-blue-200 dark:border-blue-500/20",
    amber: "from-amber-600/10 to-amber-600/[0.02] dark:from-amber-500/20 dark:to-amber-500/5 text-amber-600 dark:text-amber-400 border-amber-200 dark:border-amber-500/20",
    emerald: "from-emerald-600/10 to-emerald-600/[0.02] dark:from-emerald-500/20 dark:to-emerald-500/5 text-emerald-600 dark:text-emerald-400 border-emerald-200 dark:border-emerald-500/20",
    rose: "from-rose-600/10 to-rose-600/[0.02] dark:from-rose-500/20 dark:to-rose-500/5 text-rose-600 dark:text-rose-400 border-rose-200 dark:border-rose-500/20",
  };

  return (
    <button
      onClick={onClick}
      disabled={!onClick}
      className={cn(
        "bg-white dark:bg-[#111827]/60 backdrop-blur-xl p-6 rounded-[32px] sm:rounded-[40px] border border-slate-200 dark:border-slate-800/80 transition-all duration-300 group shadow-lg dark:shadow-none text-left w-full cursor-pointer overflow-hidden relative",
        onClick ? "hover:border-indigo-300 dark:hover:border-slate-700 hover:scale-[1.02] active:scale-[0.98]" : "cursor-default"
      )}
    >
      <div className="flex items-center justify-between mb-8">
        <div className={cn("p-4 rounded-2xl bg-gradient-to-br border shadow-sm dark:shadow-lg group-hover:scale-110 transition-transform duration-300", colorMap[color])}>
          <Icon className="w-6 h-6" />
        </div>
        <div className={cn(
          "px-3 py-1.5 rounded-xl text-[10px] font-black tracking-widest uppercase",
          isWarning ? "bg-red-500/10 text-red-500 border border-red-500/20" : "bg-emerald-500/10 text-emerald-500 border border-emerald-500/20"
        )}>
          {change}
        </div>
      </div>

      <div className="space-y-1">
        <p className="text-[10px] font-black text-slate-400 dark:text-slate-500 tracking-[0.2em] uppercase truncate">{title}</p>
        <h4 className="text-3xl font-black text-slate-900 dark:text-white tracking-tighter">{value}</h4>
      </div>
    </button>
  );
}

function ActivityItem({ title, desc, time, dotColor }: any) {
  return (
    <div className="flex items-start gap-4 sm:gap-6 group cursor-pointer">
      <div className={cn("w-2 h-2 rounded-full mt-2 outline outline-4 sm:outline-8 outline-slate-100 dark:outline-white/5", dotColor)} />
      <div className="flex-1 space-y-1">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1 sm:gap-0">
          <h5 className="font-black text-slate-900 dark:text-white text-sm group-hover:text-indigo-600 dark:group-hover:text-indigo-400 transition-colors tracking-tight">{title}</h5>
          <span className="text-[9px] sm:text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest">{time}</span>
        </div>
        <p className="text-xs text-slate-500 dark:text-slate-400 font-medium leading-relaxed group-hover:text-slate-700 dark:group-hover:text-slate-300 transition-colors">{desc}</p>
      </div>
    </div>
  );
}
