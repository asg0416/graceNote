'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Loader2,
    Calendar,
    Download,
    Search,
    ChevronDown,
    CheckCircle2,
    XCircle,
    AlertCircle,
    Users,
    Church as ChurchIcon,
    Layers,
    Trophy,
    HeartPulse,
    TrendingUp,
    ChevronLeft,
    ChevronRight,
    Filter,
    BarChart3,
    PieChart,
    CalendarDays
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Modal } from '@/components/Modal';
import { Tooltip } from '@/components/Tooltip';
import * as XLSX from 'xlsx';

export default function AttendancePage() {
    const [loading, setLoading] = useState(true);
    const [profile, setProfile] = useState<any>(null);

    // Selection States
    const [churches, setChurches] = useState<any[]>([]);
    const [selectedChurchId, setSelectedChurchId] = useState<string>('');
    const [departments, setDepartments] = useState<any[]>([]);
    const [selectedDeptId, setSelectedDeptId] = useState<string>('');
    const [weeks, setWeeks] = useState<any[]>([]);
    const [selectedWeekId, setSelectedWeekId] = useState<string>('');

    // Data States
    const [attendanceData, setAttendanceData] = useState<any[]>([]);
    const [groupStats, setGroupStats] = useState<any[]>([]);

    // Monthly/Weekly View States
    const [monthWeeks, setMonthWeeks] = useState<any[]>([]);
    const [monthlyStats, setMonthlyStats] = useState<any[]>([]);

    // Stats View States
    const [statsPeriod, setStatsPeriod] = useState<'quarter' | 'year'>('quarter');
    const [hallOfFame, setHallOfFame] = useState<any[]>([]);
    const [careList, setCareList] = useState<any[]>([]);

    const [selectedYear, setSelectedYear] = useState<number>(new Date().getFullYear());
    const [selectedMonth, setSelectedMonth] = useState<number>(new Date().getMonth() + 1);
    const [weeklyTrendData, setWeeklyTrendData] = useState<any[]>([]);
    const [isTrendLoading, setIsTrendLoading] = useState(false);

    // Insight Report Specific States (Independent)
    const [insightYear, setInsightYear] = useState<number>(new Date().getFullYear());
    const [insightQuarter, setInsightQuarter] = useState<number>(Math.floor(new Date().getMonth() / 3) + 1);
    const [groupRankings, setGroupRankings] = useState<any[]>([]);

    // Hall of Fame & Care List Filter Settings
    const [hallOfFameTarget, setHallOfFameTarget] = useState<'rate' | 'count'>('rate');
    const [hallOfFameValue, setHallOfFameValue] = useState<number>(80);
    const [careTarget, setCareTarget] = useState<'rate' | 'consecutive'>('consecutive');
    const [careValue, setCareValue] = useState<number>(3); // 3 weeks or 30%

    // Detail View Toggle
    const [isDetailExpanded, setIsDetailExpanded] = useState(false);

    // Export States
    const [isExportModalOpen, setIsExportModalOpen] = useState(false);
    const [startYear, setStartYear] = useState(new Date().getFullYear());
    const [startMonth, setStartMonth] = useState(1);
    const [endYear, setEndYear] = useState(new Date().getFullYear());
    const [endMonth, setEndMonth] = useState(new Date().getMonth() + 1);
    const [isExportLoading, setIsExportLoading] = useState(false);
    const [isInsightsLoading, setIsInsightsLoading] = useState(false);
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

            // Master: Load Churches, Admin: Set Church and Load Departments
            if (data.is_master) {
                const { data: churchList } = await supabase.from('churches').select('*').order('name');
                setChurches(churchList || []);
                if (churchList && churchList.length > 0) {
                    setSelectedChurchId(churchList[0].id);
                }
            } else {
                setSelectedChurchId(data.church_id);
            }

            setLoading(false);
        };

        checkUser();
    }, [router]);

    // Handle Church Change
    useEffect(() => {
        if (selectedChurchId) {
            const fetchData = async () => {
                // 1. Load Departments
                let deptQuery = supabase
                    .from('departments')
                    .select('*')
                    .eq('church_id', selectedChurchId);

                if (profile?.department_id) {
                    deptQuery = deptQuery.eq('id', profile.department_id);
                }

                const { data: deptList } = await deptQuery.order('name');
                setDepartments(deptList || []);

                if (profile?.department_id) {
                    setSelectedDeptId(profile.department_id);
                } else if (deptList && deptList.length > 0) {
                    setSelectedDeptId(deptList[0].id);
                } else {
                    setSelectedDeptId('');
                }

                // 2. Load Weeks
                const { data: weekList } = await supabase
                    .from('weeks')
                    .select('*')
                    .eq('church_id', selectedChurchId)
                    .order('week_date', { ascending: false });

                const sortedWeeks = weekList || [];
                setWeeks(sortedWeeks);

                if (sortedWeeks.length > 0) {
                    // Group by Month for Tabs
                    const groups: any = {};
                    sortedWeeks.forEach(w => {
                        const m = w.week_date.substring(0, 7); // YYYY-MM
                        if (!groups[m]) groups[m] = [];
                        groups[m].push(w);
                    });

                    const mList = Object.keys(groups).sort().reverse();
                    setMonthWeeks(mList.map(m => ({ month: m, weeks: groups[m].reverse() })));

                    // Initial Selection: Latest Month, Latest Week
                    setSelectedWeekId(sortedWeeks[0].id);
                } else {
                    setSelectedWeekId('');
                    setMonthWeeks([]);
                }
            };
            fetchData();
        }
    }, [selectedChurchId]);

    // Handle Dept/Year/Month Change -> Update Weeks and Trend
    useEffect(() => {
        if (selectedChurchId && selectedDeptId) {
            const fetchTrendAndWeeks = async () => {
                setIsTrendLoading(true);
                // 1. Fetch weeks for the selected year/month
                const startOfMonth = `${selectedYear}-${selectedMonth.toString().padStart(2, '0')}-01`;
                const endOfMonth = `${selectedYear}-${selectedMonth.toString().padStart(2, '0')}-31`;

                const { data: monthWeeksList } = await supabase
                    .from('weeks')
                    .select('*')
                    .eq('church_id', selectedChurchId)
                    .gte('week_date', startOfMonth)
                    .lte('week_date', endOfMonth)
                    .order('week_date', { ascending: true });

                setWeeks(monthWeeksList || []);
                if (monthWeeksList && monthWeeksList.length > 0) {
                    setSelectedWeekId(monthWeeksList[monthWeeksList.length - 1].id);
                } else {
                    setSelectedWeekId('');
                }

                // 2. Fetch Weekly Trend (Last 5 weeks for the vertical chart)
                const { data: trendWeeks } = await supabase
                    .from('weeks')
                    .select('id, week_date')
                    .eq('church_id', selectedChurchId)
                    .gte('week_date', startOfMonth)
                    .lte('week_date', endOfMonth)
                    .order('week_date', { ascending: true });

                // [NEW] 안정적인 통계를 위해 부서 전체 활성 멤버 수 조회
                const { count: totalDeptMembers } = await supabase
                    .from('member_directory')
                    .select('*', { count: 'exact', head: true })
                    .eq('department_id', selectedDeptId)
                    .eq('is_active', true);

                if (trendWeeks && trendWeeks.length > 0) {
                    const trendData = await Promise.all(trendWeeks.map(async (w) => {
                        // 스냅샷 방식: 해당 부서 내의 조들로 기록된 특정 주차의 데이터를 모두 조회
                        const { data: weekAtt } = await supabase
                            .from('attendance')
                            .select('status, groups!inner(department_id)')
                            .eq('week_id', w.id)
                            .eq('groups.department_id', selectedDeptId);

                        const present = (weekAtt as any[])?.filter(a => a.status === 'present').length || 0;
                        const total = totalDeptMembers || (weekAtt as any[])?.length || 0;

                        return {
                            id: w.id,
                            date: w.week_date.substring(5), // MM-DD
                            present,
                            total
                        };
                    }));
                    setWeeklyTrendData(trendData);
                } else {
                    setWeeklyTrendData([]);
                }
                setIsTrendLoading(false);
            };
            fetchTrendAndWeeks();
        }
    }, [selectedChurchId, selectedDeptId, selectedYear, selectedMonth]);

    const prevMonth = () => {
        if (selectedMonth === 1) {
            setSelectedYear(prev => prev - 1);
            setSelectedMonth(12);
        } else {
            setSelectedMonth(prev => prev - 1);
        }
    };

    const nextMonth = () => {
        const now = new Date();
        const nowYear = now.getFullYear();
        const nowMonth = now.getMonth() + 1;
        if (selectedYear === nowYear && selectedMonth === nowMonth) return;

        if (selectedMonth === 12) {
            setSelectedYear(prev => prev + 1);
            setSelectedMonth(1);
        } else {
            setSelectedMonth(prev => prev + 1);
        }
    };

    // Handle Week Change
    useEffect(() => {
        if (selectedWeekId) {
            fetchAttendance();
        } else {
            setAttendanceData([]);
            setGroupStats([]);
        }
    }, [selectedWeekId]);

    const fetchAttendance = async () => {
        if (!selectedDeptId || !selectedWeekId) return;

        try {
            // 1. Fetch current members (to get names for matching records)
            const { data: members, error: mError } = await supabase
                .from('member_directory')
                .select('*')
                .eq('department_id', selectedDeptId);

            if (mError) throw mError;

            // 2. Fetch Attendance + Groups (Snapshot) for this week
            // 해당 부서의 조들에 속한 모든 출석 기록을 가져옴
            const { data: attendance, error: aError } = await supabase
                .from('attendance')
                .select(`
                    *,
                    groups!inner(id, name, department_id)
                `)
                .eq('week_id', selectedWeekId)
                .eq('groups.department_id', selectedDeptId);

            if (aError) throw aError;

            // 3. Merge & Reconstruct Data
            // 부서 내 전체 조 목록 조회 (미제출 조 표시용)
            const { data: deptGroups } = await supabase
                .from('groups')
                .select('*')
                .eq('department_id', selectedDeptId);

            // 실시간 명단(members) 기준이 아니라, 실제 기록(attendance) 기준으로 명단 재구성
            // 단, 미제출된 성도는 members 명단에서 보충하되, "이미 제출된 조"는 건드리지 않음
            const snapshotIds = new Set((attendance || []).map(a => a.directory_member_id));
            const submittedGroupIds = new Set((attendance || []).map(a => a.group_id || (a as any).groups?.id).filter(Boolean));
            const submittedGroupNames = new Set((attendance || []).map(a => (a as any).groups?.name).filter(Boolean));

            const mergedSnapshot = (attendance || []).map(att => {
                const memberInfo = members?.find(m => m.id === att.directory_member_id);
                return {
                    id: att.directory_member_id,
                    name: memberInfo?.full_name || '이동/비활성 성도',
                    department: departments.find(d => d.id === selectedDeptId)?.name || '부서 없음',
                    group: att.groups?.name || '조 없음',
                    role: memberInfo?.role_in_group || '성도',
                    status: att.status || 'absent',
                    updatedAt: att.updated_at
                };
            });

            // 스냅샷에 없지만 현재 활성 상태인 멤버들 추가 (출석 미체크 조/멤버)
            // 중요: 이미 출석이 '조별로' 제출된 조는 명단 보충에서 제외 (스냅샷 보호)
            const missingMembers = (members || [])
                .filter(m => {
                    const isNotChecked = !snapshotIds.has(m.id);
                    // ID 또는 이름 기반으로 이미 제출된 조인지 확인
                    const isNotSubmittedGroup = !submittedGroupIds.has(m.group_id) && !submittedGroupNames.has(m.group_name);
                    return isNotChecked && isNotSubmittedGroup && m.is_active;
                })
                .map(m => ({
                    id: m.id,
                    name: m.full_name,
                    department: departments.find(d => d.id === selectedDeptId)?.name || '부서 없음',
                    group: m.group_name || '조 없음',
                    role: m.role_in_group || '성도',
                    status: 'absent',
                    updatedAt: null
                }));

            const finalMerged = [...mergedSnapshot, ...missingMembers];
            setAttendanceData(finalMerged);

            // 4. Calculate Group Stats (All Groups in Dept)
            const groupsMap = new Map();
            // 먼저 부서 내 모든 조를 0으로 초기화
            deptGroups?.forEach(g => {
                groupsMap.set(g.name, { name: g.name, total: 0, present: 0 });
            });

            finalMerged.forEach(item => {
                if (!groupsMap.has(item.group)) {
                    groupsMap.set(item.group, { name: item.group, total: 0, present: 0 });
                }
                const g = groupsMap.get(item.group);
                g.total++;
                if (item.status === 'present' || item.status === 'late') g.present++;
            });

            const stats = Array.from(groupsMap.values());
            setGroupStats(stats.sort((a, b) => (b.total > 0 ? b.present / b.total : 0) - (a.total > 0 ? a.present / a.total : 0)));

            fetchInsights();
        } catch (err) {
            console.error('Attendance Fetch Error:', err);
        }
    };

    const fetchInsights = async () => {
        if (!selectedDeptId) return;
        setIsInsightsLoading(true);
        try {
            let startDate = `${insightYear}-01-01`;
            let endDate = `${insightYear}-12-31`;

            if (statsPeriod === 'quarter') {
                const qStartMonth = (insightQuarter - 1) * 3 + 1;
                const qEndMonth = insightQuarter * 3;
                startDate = `${insightYear}-${qStartMonth.toString().padStart(2, '0')}-01`;
                endDate = `${insightYear}-${qEndMonth.toString().padStart(2, '0')}-31`;
            }

            // Fetch weeks in the period
            const { data: periodWeeks } = await supabase
                .from('weeks')
                .select('*')
                .eq('church_id', selectedChurchId)
                .gte('week_date', startDate)
                .lte('week_date', endDate)
                .order('week_date', { ascending: false });

            if (!periodWeeks || periodWeeks.length === 0) return;

            // Fetch all members
            const { data: members } = await supabase
                .from('member_directory')
                .select('id, full_name, group_name')
                .eq('department_id', selectedDeptId);

            if (!members) return;

            // Fetch all attendance for this department for the period
            const { data: allAtt } = await supabase
                .from('attendance')
                .select('directory_member_id, status, week_id')
                .in('week_id', periodWeeks.map(w => w.id));

            if (!allAtt) return;

            // Analyze
            const report = members.map(m => {
                const myAtt = allAtt.filter(a => a.directory_member_id === m.id);
                const presentCount = myAtt.filter(a => a.status === 'present').length;
                const rate = periodWeeks.length > 0 ? (presentCount / periodWeeks.length) * 100 : 0;

                // Check consecutive absences (last 3 weeks of the period)
                const last3Weeks = periodWeeks.slice(0, 3);
                const consecutiveAbsences = last3Weeks.length >= 3 && last3Weeks.every(w => {
                    const found = myAtt.find(a => a.week_id === w.id);
                    return !found || found.status === 'absent';
                });

                return {
                    ...m,
                    presentCount,
                    rate,
                    consecutiveAbsences,
                    totalWeeks: periodWeeks.length
                };
            });

            setHallOfFame(report.filter(r =>
                hallOfFameTarget === 'rate' ? r.rate >= hallOfFameValue : r.presentCount >= hallOfFameValue
            ).sort((a, b) => b.rate - a.rate));

            setCareList(report.filter(r => {
                if (careTarget === 'consecutive') return r.consecutiveAbsences;
                return r.rate <= careValue;
            }).sort((a, b) => a.rate - b.rate));

            // [NEW] Calculate Group Rankings
            const groupsMap = new Map();
            report.forEach(r => {
                if (!groupsMap.has(r.group_name)) {
                    groupsMap.set(r.group_name, { name: r.group_name, presentSum: 0, totalAttCount: 0 });
                }
                const g = groupsMap.get(r.group_name);
                g.presentSum += r.presentCount;
                g.totalAttCount += periodWeeks.length;
            });

            const rankings = Array.from(groupsMap.values())
                .map((g: any) => ({
                    ...g,
                    rate: g.totalAttCount > 0 ? (g.presentSum / g.totalAttCount) * 100 : 0
                }))
                .filter(g => g.name && g.name !== '조 없음')
                .sort((a, b) => b.rate - a.rate);

            setGroupRankings(rankings);

        } catch (err) {
            console.error('Insights Error:', err);
        } finally {
            setIsInsightsLoading(false);
        }
    };

    useEffect(() => {
        fetchInsights();
    }, [statsPeriod, selectedDeptId, insightYear, insightQuarter, hallOfFameTarget, hallOfFameValue, careTarget, careValue]);

    const downloadRangeExcel = async () => {
        setIsExportLoading(true);
        try {
            // 1. Get all weeks in target range
            const startStr = `${startYear}-${startMonth.toString().padStart(2, '0')}-01`;
            const endStr = `${endYear}-${endMonth.toString().padStart(2, '0')}-31`;

            const { data: rangeWeeks } = await supabase
                .from('weeks')
                .select('*')
                .eq('church_id', selectedChurchId)
                .gte('week_date', startStr)
                .lte('week_date', endStr)
                .order('week_date', { ascending: true });

            if (!rangeWeeks || rangeWeeks.length === 0) {
                alert('해당 기간에 등록된 주차 정보가 없습니다.');
                return;
            }

            // 2. Fetch all members
            const { data: members } = await supabase
                .from('member_directory')
                .select('*')
                .eq('department_id', selectedDeptId)
                .order('group_name', { ascending: true })
                .order('full_name', { ascending: true });

            if (!members) return;

            // 3. Fetch all attendance for these weeks
            const { data: allAtt } = await supabase
                .from('attendance')
                .select('*')
                .in('week_id', rangeWeeks.map(w => w.id));

            if (!allAtt) return;

            // 4. Transform to Excel data (Rows: Members, Columns: Weeks)
            const exportData = members.map(m => {
                const row: any = {
                    '조': m.group_name || '조 없음',
                    '이름': m.full_name,
                    '역할': m.role_in_group || '성도'
                };

                rangeWeeks.forEach(w => {
                    const att = allAtt.find(a => a.directory_member_id === m.id && a.week_id === w.id);
                    row[w.week_date] = att ? (att.status === 'present' ? 'O' : (att.status === 'absent' ? 'X' :
                        att.status === 'late' ? 'L' : att.status === 'excused' ? 'E' : '-')) : '-';
                });

                const myAtts = allAtt.filter(a => a.directory_member_id === m.id);
                const presentCount = myAtts.filter(a => a.status === 'present').length;
                row['출석률'] = `${Math.round((presentCount / rangeWeeks.length) * 100)}%`;

                return row;
            });

            const worksheet = XLSX.utils.json_to_sheet(exportData);
            const workbook = XLSX.utils.book_new();
            XLSX.utils.book_append_sheet(workbook, worksheet, `출석현황`);

            const title = `GraceNote_${startYear}${startMonth}_${endYear}${endMonth}_출석.xlsx`;
            XLSX.writeFile(workbook, title);
            setIsExportModalOpen(false);
        } catch (err) {
            console.error('Export Error:', err);
        } finally {
            setIsExportLoading(false);
        }
    };

    const downloadExcel = () => {
        setIsExportModalOpen(true);
    };

    const getStatusIcon = (status: string) => {
        switch (status) {
            case 'present': return <CheckCircle2 className="w-5 h-5 text-emerald-500" />;
            default: return <XCircle className="w-5 h-5 text-rose-500" />;
        }
    };

    const getStatusLabel = (status: string) => {
        switch (status) {
            case 'present': return '출석';
            default: return '결석';
        }
    };



    return (
        <div className="space-y-8 sm:space-y-10 max-w-7xl mx-auto">
            {/* Header Area */}
            <header className="space-y-8 px-2">
                <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
                    <div className="flex items-center gap-4">
                        <div className="w-12 h-12 bg-indigo-600 dark:bg-indigo-500 rounded-2xl flex items-center justify-center shadow-2xl shadow-indigo-500/20 rotate-3 group-hover:rotate-0 transition-transform shrink-0">
                            <BarChart3 className="w-6 h-6 text-white" />
                        </div>
                        <div className="space-y-1">
                            <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">
                                출석 인사이트
                            </h1>
                            <p className="text-xs font-bold text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em]">Attendance Analytics</p>
                        </div>
                    </div>

                    <div className="flex items-center gap-3">
                        <Tooltip content="선택된 기간의 전체 출석 현황을 엑셀 파일로 추출합니다.">
                            <button
                                onClick={downloadExcel}
                                className="flex items-center gap-2 bg-slate-900 dark:bg-white text-white dark:text-slate-900 px-6 py-3.5 rounded-2xl font-black text-sm hover:scale-105 active:scale-95 transition-all shadow-xl shadow-slate-950/10 dark:shadow-white/5 border border-slate-800 dark:border-slate-100 cursor-pointer"
                            >
                                <Download className="w-4 h-4" />
                                리포트 추출
                            </button>
                        </Tooltip>
                    </div>
                </div>
            </header>

            {/* Horizontal Filter Bar - Compact & Glassy */}
            <div className="sticky top-20 z-[40] bg-white/70 dark:bg-[#0d1221]/70 backdrop-blur-2xl border border-slate-200/60 dark:border-slate-800/60 p-3 sm:p-4 rounded-[32px] shadow-lg flex flex-wrap items-center gap-4">
                <div className="flex flex-wrap items-center gap-3 flex-1">
                    {profile?.is_master && (
                        <div className="relative group min-w-[160px]">
                            <select
                                value={selectedChurchId}
                                onChange={(e) => setSelectedChurchId(e.target.value)}
                                className="w-full pl-10 pr-10 py-2.5 bg-slate-50 dark:bg-slate-800/50 border border-slate-100 dark:border-slate-700/50 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 outline-none focus:ring-2 focus:ring-indigo-500/20 transition-all appearance-none cursor-pointer"
                            >
                                {churches.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                            </select>
                            <ChurchIcon className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                            <ChevronDown className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                        </div>
                    )}

                    <div className="relative group min-w-[160px]">
                        <select
                            value={selectedDeptId}
                            onChange={(e) => setSelectedDeptId(e.target.value)}
                            className="w-full pl-10 pr-10 py-2.5 bg-slate-50 dark:bg-slate-800/50 border border-slate-100 dark:border-slate-700/50 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 outline-none focus:ring-2 focus:ring-indigo-500/20 transition-all appearance-none cursor-pointer"
                        >
                            {departments.map(d => <option key={d.id} value={d.id}>{d.name}</option>)}
                        </select>
                        <Layers className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                        <ChevronDown className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                    </div>

                    <div className="h-6 w-px bg-slate-200 dark:bg-slate-800 mx-1 hidden sm:block" />

                    <div className="flex items-center gap-2">
                        <div className="relative group w-32">
                            <select
                                value={selectedYear}
                                onChange={(e) => setSelectedYear(parseInt(e.target.value))}
                                className="w-full pl-10 pr-10 py-2.5 bg-slate-50 dark:bg-slate-800/50 border border-slate-100 dark:border-slate-700/50 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 outline-none focus:ring-2 focus:ring-indigo-500/20 transition-all appearance-none cursor-pointer"
                            >
                                {[2024, 2025, 2026].map(y => <option key={y} value={y}>{y}년</option>)}
                            </select>
                            <CalendarDays className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                            <ChevronDown className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                        </div>

                        <div className="relative group w-28">
                            <select
                                value={selectedMonth}
                                onChange={(e) => setSelectedMonth(parseInt(e.target.value))}
                                className="w-full pl-10 pr-10 py-2.5 bg-slate-50 dark:bg-slate-800/50 border border-slate-100 dark:border-slate-700/50 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 outline-none focus:ring-2 focus:ring-indigo-500/20 transition-all appearance-none cursor-pointer"
                            >
                                {Array.from({ length: 12 }, (_, i) => i + 1).map(m => <option key={m} value={m}>{m}월</option>)}
                            </select>
                            <Calendar className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                            <ChevronDown className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                        </div>
                    </div>
                </div>

                <div className="flex items-center gap-2">
                    {weeks.length > 0 ? (
                        <div className="relative group min-w-[140px]">
                            <select
                                value={selectedWeekId}
                                onChange={(e) => setSelectedWeekId(e.target.value)}
                                className="w-full pl-10 pr-10 py-2.5 bg-slate-900 dark:bg-white text-white dark:text-slate-900 border-none rounded-2xl font-black text-xs outline-none focus:ring-2 focus:ring-indigo-500/40 transition-all appearance-none cursor-pointer"
                            >
                                {weeks.map((w, idx) => (
                                    <option key={w.id} value={w.id}>{idx + 1}주차 ({w.week_date.substring(5)})</option>
                                ))}
                            </select>
                            <Filter className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-white/40 dark:text-slate-400" />
                            <ChevronDown className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-white/40 dark:text-slate-400" />
                        </div>
                    ) : (
                        <div className="px-4 py-2 bg-slate-100 dark:bg-slate-800/50 rounded-2xl text-[10px] font-black text-slate-400">
                            기간 내 주차 정보 없음
                        </div>
                    )}
                </div>
            </div>

            {/* Quick Summary Stats Row */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 px-1">
                <div className="bg-white dark:bg-slate-800/40 p-6 rounded-[32px] border border-slate-100 dark:border-slate-800/50 shadow-sm flex items-center justify-between group hover:border-indigo-500/30 transition-all">
                    <div>
                        <p className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest mb-1">전체 구성원</p>
                        <h4 className="text-3xl font-black text-slate-900 dark:text-white tracking-tighter">{attendanceData.length}</h4>
                    </div>
                    <div className="w-12 h-12 rounded-2xl bg-slate-50 dark:bg-slate-700/50 flex items-center justify-center text-slate-400 group-hover:bg-indigo-500 group-hover:text-white transition-all">
                        <Users className="w-6 h-6" />
                    </div>
                </div>
                <div className="bg-white dark:bg-slate-800/40 p-6 rounded-[32px] border border-slate-100 dark:border-slate-800/50 shadow-sm flex items-center justify-between group hover:border-emerald-500/30 transition-all">
                    <div>
                        <p className="text-[10px] font-black text-emerald-600 dark:text-emerald-400 uppercase tracking-widest mb-1">금주 출석</p>
                        <h4 className="text-3xl font-black text-emerald-600 dark:text-emerald-400 tracking-tighter">
                            {attendanceData.filter(a => a.status === 'present').length}
                        </h4>
                    </div>
                    <div className="w-12 h-12 rounded-2xl bg-emerald-50 dark:bg-emerald-500/10 flex items-center justify-center text-emerald-500 group-hover:bg-emerald-500 group-hover:text-white transition-all">
                        <CheckCircle2 className="w-6 h-6" />
                    </div>
                </div>
                <div className="bg-white dark:bg-slate-800/40 p-6 rounded-[32px] border border-slate-100 dark:border-slate-800/50 shadow-sm flex items-center justify-between group hover:border-rose-500/30 transition-all">
                    <div>
                        <p className="text-[10px] font-black text-rose-600 dark:text-rose-400 uppercase tracking-widest mb-1">금주 결석</p>
                        <h4 className="text-3xl font-black text-rose-600 dark:text-rose-400 tracking-tighter">
                            {attendanceData.length - attendanceData.filter(a => a.status === 'present').length}
                        </h4>
                    </div>
                    <div className="w-12 h-12 rounded-2xl bg-rose-50 dark:bg-rose-500/10 flex items-center justify-center text-rose-500 group-hover:bg-rose-500 group-hover:text-white transition-all">
                        <XCircle className="w-6 h-6" />
                    </div>
                </div>
                <div className="bg-indigo-600 p-6 rounded-[32px] shadow-xl shadow-indigo-500/20 flex items-center justify-between group hover:scale-[1.02] transition-all">
                    <div>
                        <p className="text-[10px] font-black text-indigo-100/60 uppercase tracking-widest mb-1">종합 출석률</p>
                        <h4 className="text-3xl font-black text-white tracking-tighter">
                            {attendanceData.length > 0 ? Math.round((attendanceData.filter(a => a.status === 'present').length / attendanceData.length) * 100) : 0}%
                        </h4>
                    </div>
                    <div className="w-12 h-12 rounded-2xl bg-white/10 flex items-center justify-center text-white">
                        <TrendingUp className="w-6 h-6" />
                    </div>
                </div>
            </div>

            <div className="grid grid-cols-1 xl:grid-cols-12 gap-8 mt-4 px-1">
                {/* Main Content Column (Left/Center) */}
                <div className="xl:col-span-8 space-y-8">
                    {loading ? (
                        <div className="h-64 flex flex-col items-center justify-center bg-white dark:bg-slate-800/40 rounded-[32px] border border-slate-100 dark:border-slate-800/50">
                            <Loader2 className="w-8 h-8 text-indigo-600 animate-spin" />
                            <p className="text-xs font-bold text-slate-400 mt-4 uppercase tracking-widest">데이터 동기화 중...</p>
                        </div>
                    ) : (
                        <>
                            <div className="bg-white dark:bg-slate-800/40 p-8 rounded-[40px] border border-slate-100 dark:border-slate-800/50 shadow-sm space-y-8 relative overflow-hidden">
                                <div className="flex items-center justify-between relative z-10">
                                    <div className="flex items-center gap-2">
                                        <TrendingUp className="w-5 h-5 text-indigo-500" />
                                        <h3 className="text-xl font-black text-slate-900 dark:text-white tracking-tight">주차별 출석 변화</h3>
                                    </div>
                                    <div className="flex items-center gap-3">
                                        <div className="flex items-center gap-1 bg-slate-50 dark:bg-slate-900/50 p-1 rounded-xl border border-slate-100 dark:border-slate-800/50">
                                            <button
                                                onClick={prevMonth}
                                                className="p-1 px-2 hover:bg-white dark:hover:bg-slate-800 rounded-lg transition-all text-slate-400 hover:text-indigo-600"
                                                title="이전 달"
                                            >
                                                <ChevronLeft className="w-4 h-4" />
                                            </button>
                                            <button
                                                onClick={nextMonth}
                                                disabled={selectedYear === new Date().getFullYear() && selectedMonth === new Date().getMonth() + 1}
                                                className="p-1 px-2 hover:bg-white dark:hover:bg-slate-800 rounded-lg transition-all text-slate-400 hover:text-indigo-600 disabled:opacity-20 disabled:hover:text-slate-400"
                                                title="다음 달"
                                            >
                                                <ChevronRight className="w-4 h-4" />
                                            </button>
                                        </div>
                                        <p className="text-[10px] font-bold text-slate-400 uppercase tracking-widest hidden sm:block">Trend</p>
                                    </div>
                                </div>

                                <div className="relative h-48 mt-4 flex items-center justify-center">
                                    {isTrendLoading ? (
                                        <div className="flex flex-col items-center gap-3">
                                            <Loader2 className="w-8 h-8 text-indigo-500 animate-spin opacity-50" />
                                            <p className="text-[10px] font-black text-slate-400 animate-pulse uppercase tracking-widest">분석 중...</p>
                                        </div>
                                    ) : weeklyTrendData.length === 0 ? (
                                        <div className="flex flex-col items-center gap-2 opacity-40">
                                            <CalendarDays className="w-10 h-10 text-slate-400" />
                                            <p className="text-sm font-bold text-slate-500">선택한 월의 출석 데이터가 없습니다.</p>
                                        </div>
                                    ) : (
                                        <>
                                            {/* Y-Axis Scale & Grids */}
                                            <div className="absolute inset-0 flex flex-col justify-between pointer-events-none pr-2">
                                                {[100, 75, 50, 25, 0].map((tick) => (
                                                    <div key={tick} className="w-full flex items-center gap-3 group/grid">
                                                        <span className="text-[9px] font-black text-slate-300 dark:text-slate-600 w-6 text-right transition-colors group-hover/grid:text-indigo-400">{tick}%</span>
                                                        <div className="flex-1 h-[1px] bg-slate-100 dark:bg-slate-800/50 relative">
                                                            <div className="absolute inset-0 bg-indigo-500/10 opacity-0 group-hover/grid:opacity-100 transition-opacity" />
                                                        </div>
                                                    </div>
                                                ))}
                                            </div>

                                            <div className="absolute inset-0 flex items-stretch justify-between gap-4 pl-10 pr-4">
                                                {weeklyTrendData.map((data, idx) => (
                                                    <div
                                                        key={idx}
                                                        className={cn(
                                                            "flex-1 flex flex-col items-center gap-3 group cursor-pointer transition-all",
                                                            selectedWeekId === data.id ? "scale-105" : "hover:scale-105"
                                                        )}
                                                        onClick={() => setSelectedWeekId(data.id)}
                                                    >
                                                        <div className="relative w-full flex flex-col items-center justify-end flex-1">
                                                            {/* Bar BG */}
                                                            <div className={cn(
                                                                "w-3 sm:w-5 rounded-full h-full absolute inset-0 mx-auto transition-colors",
                                                                selectedWeekId === data.id ? "bg-indigo-100 dark:bg-indigo-900/30" : "bg-slate-100 dark:bg-slate-800/50"
                                                            )} />
                                                            {/* Bar Fill */}
                                                            <div
                                                                className={cn(
                                                                    "w-3 sm:w-5 rounded-full transition-all duration-1000 ease-out relative z-10",
                                                                    selectedWeekId === data.id ? "bg-indigo-700 dark:bg-indigo-400 shadow-[0_0_15px_rgba(79,70,229,0.4)]" : "bg-indigo-600 dark:bg-indigo-500 group-hover:bg-indigo-700"
                                                                )}
                                                                style={{ height: `${(data.present / (data.total || 1)) * 100}%` }}
                                                            >
                                                                <div className="absolute top-1.5 inset-x-0 h-1 bg-white/20 rounded-full mx-1" />
                                                                {/* Number Label */}
                                                                <div className="absolute -top-6 left-1/2 -translate-x-1/2 text-[10px] font-black text-indigo-600 dark:text-indigo-400">
                                                                    {data.present}
                                                                </div>
                                                                {/* Tooltip */}
                                                                <div className="absolute -top-10 left-1/2 -translate-x-1/2 opacity-0 group-hover:opacity-100 transition-all bg-slate-900 dark:bg-slate-700 text-white text-[10px] font-black px-2.5 py-1.5 rounded-xl z-20 whitespace-nowrap shadow-xl pointer-events-none">
                                                                    {data.present}명 / {data.total}명
                                                                </div>
                                                            </div>
                                                        </div>
                                                        <span className={cn(
                                                            "text-[10px] font-black transition-colors shrink-0",
                                                            selectedWeekId === data.id ? "text-indigo-600 dark:text-indigo-400" : "text-slate-400 group-hover:text-indigo-600"
                                                        )}>
                                                            {data.date}
                                                        </span>
                                                    </div>
                                                ))}
                                            </div>
                                        </>
                                    )}
                                </div>
                            </div>

                            {/* Overall Progress - Segmented Bars */}
                            <div className="bg-white dark:bg-slate-800/40 p-8 rounded-[40px] border border-slate-100 dark:border-slate-800/50 shadow-sm space-y-8">
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-2">
                                        <BarChart3 className="w-5 h-5 text-indigo-500" />
                                        <h3 className="text-xl font-black text-slate-900 dark:text-white tracking-tight">전체 조별 출석 현황</h3>
                                    </div>
                                    <button
                                        onClick={() => setIsDetailExpanded(!isDetailExpanded)}
                                        className="text-[11px] font-black text-indigo-600 dark:text-indigo-400 hover:scale-105 transition-all bg-indigo-50 dark:bg-indigo-500/10 px-4 py-2 rounded-xl"
                                    >
                                        {isDetailExpanded ? '요약 보기' : '상세 명단 보기'}
                                    </button>
                                </div>

                                <div className="space-y-6">
                                    {groupStats.length === 0 ? (
                                        <div className="flex flex-col items-center justify-center py-12 gap-3 opacity-40">
                                            <AlertCircle className="w-8 h-8 text-slate-400" />
                                            <p className="text-sm font-bold text-slate-500">선택된 주차의 출석 데이터가 없습니다.</p>
                                        </div>
                                    ) : isDetailExpanded ? (
                                        <div className="space-y-10">
                                            {groupStats.map(gs => {
                                                const groupMembers = attendanceData.filter(a => a.group === gs.name);
                                                return (
                                                    <div key={gs.name} className="space-y-4">
                                                        <div className="flex items-center justify-between border-l-4 border-indigo-500 pl-4 py-1">
                                                            <h4 className="font-black text-slate-900 dark:text-white uppercase tracking-tight">{gs.name}</h4>
                                                            <div className="text-[10px] font-bold text-slate-400">
                                                                출석: <span className="text-indigo-600">{gs.present}</span> / 전체: {gs.total}
                                                            </div>
                                                        </div>
                                                        <div className="flex flex-wrap gap-2">
                                                            {groupMembers.map(m => (
                                                                <div
                                                                    key={m.id}
                                                                    className={cn(
                                                                        "px-3 py-1.5 rounded-xl border flex items-center gap-1.5 transition-all text-[11px] font-bold",
                                                                        m.status === 'present'
                                                                            ? "bg-emerald-50 dark:bg-emerald-500/10 border-emerald-100 dark:border-emerald-500/20 text-emerald-600 dark:text-emerald-400"
                                                                            : "bg-slate-50 dark:bg-slate-800/30 border-slate-100 dark:border-slate-700/50 text-slate-400"
                                                                    )}
                                                                >
                                                                    {m.status === 'present' ? (
                                                                        <CheckCircle2 className="w-3 h-3" />
                                                                    ) : (
                                                                        <XCircle className="w-3 h-3" />
                                                                    )}
                                                                    {m.name}
                                                                </div>
                                                            ))}
                                                        </div>
                                                    </div>
                                                );
                                            })}
                                        </div>
                                    ) : (
                                        groupStats.map(gs => (
                                            <div key={gs.name} className="group/bar relative">
                                                <div className="flex items-end justify-between mb-3">
                                                    <span className="text-xs font-black text-slate-700 dark:text-slate-300 group-hover/bar:text-indigo-500 transition-colors uppercase tracking-widest flex items-center gap-2">
                                                        {gs.name}
                                                        {(gs.present / gs.total) >= 0.9 && <Trophy className="w-3.5 h-3.5 text-amber-500" />}
                                                    </span>
                                                    <span className="text-[10px] font-black text-slate-400 tracking-tight">
                                                        <span className="text-slate-900 dark:text-white text-sm mr-1">{gs.present}</span>/ {gs.total} 명 ({Math.round((gs.present / gs.total) * 100)}%)
                                                    </span>
                                                </div>
                                                <div className="flex gap-1 h-3">
                                                    {Array.from({ length: gs.total }).map((_, i) => (
                                                        <div
                                                            key={i}
                                                            className={cn(
                                                                "flex-1 rounded-sm transition-all duration-500",
                                                                i < gs.present
                                                                    ? ((gs.present / gs.total) > 0.8 ? "bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.3)]" :
                                                                        (gs.present / gs.total) > 0.5 ? "bg-indigo-500 shadow-[0_0_8px_rgba(99,102,241,0.3)]" :
                                                                            "bg-rose-500 shadow-[0_0_8px_rgba(244,63,94,0.3)]")
                                                                    : "bg-slate-100 dark:bg-slate-800/50"
                                                            )}
                                                        />
                                                    ))}
                                                </div>
                                            </div>
                                        ))
                                    )}
                                </div>
                            </div>
                        </>
                    )}
                </div>

                {/* Sidebar Column (Right) */}
                <div className="xl:col-span-4 space-y-6">
                    <div className="bg-white/60 dark:bg-[#111827]/40 backdrop-blur-2xl rounded-[40px] p-8 border border-white dark:border-slate-800/50 shadow-xl relative overflow-hidden">
                        <div className="absolute top-0 right-0 w-48 h-48 bg-indigo-500/5 rounded-full -mr-24 -mt-24 blur-3xl" />

                        <div className="flex items-center justify-between mb-8 relative">
                            <div className="space-y-4 w-full">
                                <h3 className="text-sm font-black text-slate-400 dark:text-slate-500 tracking-widest uppercase">인사이트 리포트</h3>

                                <div className="flex flex-wrap items-center gap-2">
                                    <div className="flex items-center gap-1 p-1 bg-slate-100 dark:bg-slate-800/50 rounded-xl">
                                        <button
                                            onClick={() => setStatsPeriod('quarter')}
                                            className={cn(
                                                "px-4 py-1.5 rounded-lg text-[10px] font-black transition-all",
                                                statsPeriod === 'quarter' ? "bg-white dark:bg-slate-700 text-slate-900 dark:text-white shadow-sm" : "text-slate-400 hover:text-slate-600"
                                            )}
                                        >
                                            분기
                                        </button>
                                        <button
                                            onClick={() => setStatsPeriod('year')}
                                            className={cn(
                                                "px-4 py-1.5 rounded-lg text-[10px] font-black transition-all",
                                                statsPeriod === 'year' ? "bg-white dark:bg-slate-700 text-slate-900 dark:text-white shadow-sm" : "text-slate-400 hover:text-slate-600"
                                            )}
                                        >
                                            년도
                                        </button>
                                    </div>

                                    <div className="flex items-center gap-2">
                                        <select
                                            value={insightYear}
                                            onChange={(e) => setInsightYear(parseInt(e.target.value))}
                                            className="px-3 py-1.5 bg-slate-100 dark:bg-slate-800/50 rounded-xl text-[10px] font-black text-slate-600 dark:text-slate-400 outline-none border-none cursor-pointer"
                                        >
                                            {[2024, 2025, 2026].map(y => <option key={y} value={y}>{y}년</option>)}
                                        </select>

                                        {statsPeriod === 'quarter' && (
                                            <select
                                                value={insightQuarter}
                                                onChange={(e) => setInsightQuarter(parseInt(e.target.value))}
                                                className="px-3 py-1.5 bg-slate-100 dark:bg-slate-800/50 rounded-xl text-[10px] font-black text-slate-600 dark:text-slate-400 outline-none border-none cursor-pointer"
                                            >
                                                {[1, 2, 3, 4].map(q => <option key={q} value={q}>{q}분기</option>)}
                                            </select>
                                        )}
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div className="space-y-8 relative">
                            {/* Hall of Fame - Compact */}
                            <div className="space-y-5">
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-2">
                                        <div className="w-6 h-6 rounded-lg bg-amber-500/10 flex items-center justify-center">
                                            <Trophy className="w-3.5 h-3.5 text-amber-500" />
                                        </div>
                                        <span className="text-[11px] font-black text-slate-700 dark:text-slate-300 uppercase tracking-widest">출석 우수자 (Top 5)</span>
                                    </div>
                                    <div className="flex items-center gap-1.5 bg-slate-100 dark:bg-slate-800/50 p-1 rounded-xl">
                                        <button
                                            onClick={() => setHallOfFameValue(v => Math.max(0, v - 5))}
                                            className="w-6 h-6 flex items-center justify-center bg-white dark:bg-slate-700 rounded-lg text-slate-400 hover:text-indigo-600 transition-colors shadow-sm"
                                        >
                                            -
                                        </button>
                                        <span className="text-[10px] font-black text-slate-900 dark:text-white min-w-[32px] text-center">
                                            {hallOfFameTarget === 'rate' ? `${hallOfFameValue}%` : `${hallOfFameValue}회`}
                                        </span>
                                        <button
                                            onClick={() => setHallOfFameValue(v => Math.min(100, v + 5))}
                                            className="w-6 h-6 flex items-center justify-center bg-white dark:bg-slate-700 rounded-lg text-slate-400 hover:text-indigo-600 transition-colors shadow-sm"
                                        >
                                            +
                                        </button>
                                    </div>
                                </div>
                                <div className="space-y-3">
                                    {hallOfFame.length > 0 ? (
                                        hallOfFame.slice(0, 5).map((member, idx) => (
                                            <div key={member.id} className="flex items-center justify-between p-4 rounded-3xl bg-slate-50/50 dark:bg-slate-800/30 border border-slate-100/50 dark:border-slate-700/30 hover:bg-white dark:hover:bg-slate-800 transition-all group">
                                                <div className="flex items-center gap-4">
                                                    <div className="w-9 h-9 rounded-xl bg-amber-500/10 flex items-center justify-center text-xs font-black text-amber-500">
                                                        {idx + 1}
                                                    </div>
                                                    <div>
                                                        <p className="text-xs font-black text-slate-900 dark:text-white">{member.full_name}</p>
                                                        <p className="text-[10px] font-bold text-slate-400">{member.group_name}</p>
                                                    </div>
                                                </div>
                                                <div className="text-right">
                                                    <p className="text-xs font-black text-amber-500">{Math.round(member.rate)}%</p>
                                                    <p className="text-[9px] font-bold text-slate-400">{member.presentCount}주 출석</p>
                                                </div>
                                            </div>
                                        ))
                                    ) : (
                                        <div className="py-8 text-center bg-slate-50 dark:bg-slate-800/20 rounded-[32px] border border-dashed border-slate-200 dark:border-slate-800">
                                            <p className="text-[10px] font-bold text-slate-400 uppercase tracking-tight">기준({hallOfFameTarget === 'rate' ? hallOfFameValue + '%' : hallOfFameValue + '회'}) 이상인 성도가 없습니다.</p>
                                        </div>
                                    )}
                                </div>
                            </div>

                            <div className="h-px bg-slate-100 dark:bg-slate-800" />

                            {/* Group Rankings - [NEW] */}
                            <div className="space-y-5">
                                <div className="flex items-center gap-2">
                                    <div className="w-6 h-6 rounded-lg bg-indigo-500/10 flex items-center justify-center">
                                        <BarChart3 className="w-3.5 h-3.5 text-indigo-500" />
                                    </div>
                                    <span className="text-[11px] font-black text-slate-700 dark:text-slate-300 uppercase tracking-widest">조별 출석 순위 (Top 3)</span>
                                </div>
                                <div className="space-y-3">
                                    {groupRankings.length > 0 ? (
                                        groupRankings.slice(0, 3).map((group, idx) => (
                                            <div key={group.name} className="relative overflow-hidden p-4 rounded-3xl bg-indigo-500/[0.03] dark:bg-indigo-500/[0.05] border border-indigo-100 dark:border-indigo-500/10 group/item">
                                                <div className="flex items-center justify-between relative z-10">
                                                    <div className="flex items-center gap-4">
                                                        <div className={cn(
                                                            "w-9 h-9 rounded-xl flex items-center justify-center text-xs font-black shadow-sm",
                                                            idx === 0 ? "bg-amber-400 text-white" :
                                                                idx === 1 ? "bg-slate-300 text-slate-700" :
                                                                    "bg-orange-300 text-orange-800"
                                                        )}>
                                                            {idx + 1}
                                                        </div>
                                                        <div>
                                                            <p className="text-xs font-black text-slate-900 dark:text-white uppercase tracking-tight">{group.name}</p>
                                                            <p className="text-[10px] font-bold text-indigo-500/60 uppercase">{Math.round(group.rate)}% 출석</p>
                                                        </div>
                                                    </div>
                                                    <div className="w-10 h-10 rounded-full border-2 border-indigo-500/20 flex items-center justify-center relative">
                                                        <svg className="w-full h-full -rotate-90">
                                                            <circle
                                                                cx="20"
                                                                cy="20"
                                                                r="16"
                                                                fill="transparent"
                                                                stroke="currentColor"
                                                                strokeWidth="3"
                                                                className="text-indigo-500/10"
                                                            />
                                                            <circle
                                                                cx="20"
                                                                cy="20"
                                                                r="16"
                                                                fill="transparent"
                                                                stroke="currentColor"
                                                                strokeWidth="3"
                                                                strokeDasharray={`${2 * Math.PI * 16}`}
                                                                strokeDashoffset={`${2 * Math.PI * 16 * (1 - group.rate / 100)}`}
                                                                className="text-indigo-500"
                                                            />
                                                        </svg>
                                                    </div>
                                                </div>
                                            </div>
                                        ))
                                    ) : (
                                        <div className="py-8 text-center bg-slate-50 dark:bg-slate-800/20 rounded-[32px] border border-dashed border-slate-200 dark:border-slate-800">
                                            <p className="text-[10px] font-bold text-slate-400 uppercase tracking-tight">출석 데이터가 없습니다.</p>
                                        </div>
                                    )}
                                </div>
                            </div>

                            <div className="h-px bg-slate-100 dark:bg-slate-800" />

                            {/* Care List - Compact */}
                            <div className="space-y-5">
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-2">
                                        <div className="w-6 h-6 rounded-lg bg-rose-500/10 flex items-center justify-center">
                                            <HeartPulse className="w-3.5 h-3.5 text-rose-500" />
                                        </div>
                                        <span className="text-[11px] font-black text-slate-700 dark:text-slate-300 uppercase tracking-widest">집중 보살핌 (Care)</span>
                                    </div>
                                </div>
                                <div className="space-y-3">
                                    {careList.length > 0 ? (
                                        careList.slice(0, 6).map(member => (
                                            <div key={member.id} className="flex items-center justify-between p-4 rounded-3xl bg-rose-500/5 border border-rose-500/10 hover:bg-rose-500/10 transition-all group cursor-pointer" onClick={() => router.push(`/members/${member.id}`)}>
                                                <div className="flex items-center gap-4">
                                                    <div className="w-9 h-9 rounded-xl bg-rose-500/10 flex items-center justify-center">
                                                        <AlertCircle className="w-4 h-4 text-rose-500" />
                                                    </div>
                                                    <div>
                                                        <p className="text-xs font-black text-slate-900 dark:text-white group-hover:text-rose-500 transition-colors">{member.full_name}</p>
                                                        <p className="text-[10px] font-bold text-rose-500/60 uppercase tracking-tighter">
                                                            {member.consecutiveAbsences ? '3주 연속 결석' : '출석률 저조'}
                                                        </p>
                                                    </div>
                                                </div>
                                                <ChevronRight className="w-4 h-4 text-slate-300 group-hover:text-rose-500 transition-all" />
                                            </div>
                                        ))
                                    ) : (
                                        <div className="py-8 text-center bg-rose-50/30 dark:bg-rose-900/10 rounded-[32px] border border-dashed border-rose-200/50 dark:border-rose-900/30">
                                            <p className="text-[10px] font-bold text-rose-400 uppercase tracking-tight">관리가 필요한 성도가 없습니다.</p>
                                        </div>
                                    )}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            {/* Modal - Responsive */}
            <Modal
                isOpen={isExportModalOpen}
                onClose={() => setIsExportModalOpen(false)}
                title="통합 출석부 추출"
                maxWidth="md"
            >
                <div className="space-y-8">
                    {/* Start Range */}
                    <div className="space-y-3">
                        <label className="text-xs font-black text-slate-400 uppercase tracking-widest pl-1">시작 기간</label>
                        <div className="flex gap-2">
                            <select
                                value={startYear}
                                onChange={(e) => setStartYear(parseInt(e.target.value))}
                                className="flex-1 p-4 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20"
                            >
                                {[2024, 2025, 2026].map(y => <option key={y} value={y}>{y}년</option>)}
                            </select>
                            <select
                                value={startMonth}
                                onChange={(e) => setStartMonth(parseInt(e.target.value))}
                                className="flex-1 p-4 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20"
                            >
                                {Array.from({ length: 12 }, (_, i) => i + 1).map(m => <option key={m} value={m}>{m}월</option>)}
                            </select>
                        </div>
                    </div>

                    {/* End Range */}
                    <div className="space-y-3">
                        <label className="text-xs font-black text-slate-400 uppercase tracking-widest pl-1">종료 기간</label>
                        <div className="flex gap-2">
                            <select
                                value={endYear}
                                onChange={(e) => setEndYear(parseInt(e.target.value))}
                                className="flex-1 p-4 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20"
                            >
                                {[2024, 2025, 2026].map(y => <option key={y} value={y}>{y}년</option>)}
                            </select>
                            <select
                                value={endMonth}
                                onChange={(e) => setEndMonth(parseInt(e.target.value))}
                                className="flex-1 p-4 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20"
                            >
                                {Array.from({ length: 12 }, (_, i) => i + 1).map(m => <option key={m} value={m}>{m}월</option>)}
                            </select>
                        </div>
                    </div>

                    <div className="pt-4">
                        <button
                            onClick={downloadRangeExcel}
                            disabled={isExportLoading}
                            className="w-full py-5 bg-indigo-600 text-white rounded-3xl font-black hover:bg-indigo-700 transition-all hover:scale-[1.02] active:scale-[0.98] flex items-center justify-center gap-3 shadow-xl shadow-indigo-500/20 disabled:opacity-50 disabled:scale-100"
                        >
                            {isExportLoading ? <Loader2 className="w-6 h-6 animate-spin" /> : <Download className="w-6 h-6" />}
                            출석부 데이터 생성 및 다운로드
                        </button>
                        <p className="text-[10px] text-center text-slate-400 font-bold mt-4 tracking-tight">
                            선택한 기간 내의 모든 주차 데이터가 하나의 시트로 통합됩니다.
                        </p>
                    </div>
                </div>
            </Modal>
        </div>
    );
}

