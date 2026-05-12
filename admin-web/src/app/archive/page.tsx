'use client';

import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
    Archive,
    Building2,
    Church,
    Loader2,
    RefreshCw,
    RotateCcw,
    Search,
    Users,
} from 'lucide-react';
import { supabase } from '@/lib/supabase';
import {
    setMemberDirectoryActiveStatus,
    setPersonDepartmentActiveStatus,
} from '@/lib/memberWriteRpc';
import { cn } from '@/lib/utils';

type Profile = {
    id: string;
    church_id: string | null;
    role: string | null;
    admin_status: string | null;
    is_master: boolean | null;
};

type ArchivedMember = {
    id: string;
    full_name: string;
    phone: string | null;
    person_id: string | null;
    church_id: string;
    department_id: string | null;
    group_name: string | null;
    left_at: string | null;
    departments?: { name?: string | null; color_hex?: string | null } | null;
    archived_group_names?: string[];
    archived_group_candidates?: ArchivedGroupCandidate[];
};

type ArchivedDepartment = {
    id: string;
    name: string;
    church_id: string;
    ended_at: string | null;
};

type ArchivedGroup = {
    id: string;
    name: string;
    church_id: string;
    department_id: string | null;
    ended_at: string | null;
    departments?: { name?: string | null } | null;
};

type MemberProfilePersonLink = {
    member_directory_id: string | null;
    person_id: string | null;
};

type ArchivedMembershipLink = {
    person_id: string | null;
    department_id: string | null;
    group_id: string | null;
    status: string | null;
    ends_at: string | null;
    archived_by_event_id: string | null;
};

type GroupNameRow = {
    id: string;
    name: string | null;
};

type ArchiveEventRow = {
    id: string;
    person_id: string;
    department_id: string;
    occurred_at: string;
};

type ArchivedGroupCandidate = {
    group_id: string;
    group_name: string;
    ends_at: string | null;
    archived_by_event_id: string | null;
};

type ArchivedMemberAffiliation = {
    key: string;
    person_id: string | null;
    church_id: string;
    department_id: string | null;
    full_name: string;
    phone: string | null;
    left_at: string | null;
    departments?: { name?: string | null; color_hex?: string | null } | null;
    archived_group_names: string[];
    archived_group_candidates: ArchivedGroupCandidate[];
    rows: ArchivedMember[];
};

type ArchiveTab = 'members' | 'departments' | 'groups';

const formatDate = (value?: string | null) => {
    if (!value) return '종료일 없음';
    return new Date(value).toLocaleDateString('ko-KR');
};

export default function ArchivePage() {
    const router = useRouter();
    const [profile, setProfile] = useState<Profile | null>(null);
    const [loading, setLoading] = useState(true);
    const [restoringId, setRestoringId] = useState<string | null>(null);
    const [activeTab, setActiveTab] = useState<ArchiveTab>('members');
    const [query, setQuery] = useState('');
    const [members, setMembers] = useState<ArchivedMember[]>([]);
    const [departments, setDepartments] = useState<ArchivedDepartment[]>([]);
    const [groups, setGroups] = useState<ArchivedGroup[]>([]);
    const [restoreGroupSelections, setRestoreGroupSelections] = useState<Record<string, string[]>>({});

    const fetchArchive = async (userProfile: Profile) => {
        setLoading(true);
        try {
            const churchFilter = userProfile.is_master ? null : userProfile.church_id;

            let memberQuery = supabase
                .from('member_directory')
                .select(`
                    id,
                    full_name,
                    phone,
                    person_id,
                    church_id,
                    department_id,
                    group_name,
                    left_at,
                    departments!department_id(name, color_hex)
                `)
                .eq('is_active', false)
                .order('left_at', { ascending: false, nullsFirst: false });
            if (churchFilter) memberQuery = memberQuery.eq('church_id', churchFilter);

            let departmentQuery = supabase
                .from('departments')
                .select('id, name, church_id, ended_at')
                .eq('is_active', false)
                .order('ended_at', { ascending: false, nullsFirst: false });
            if (churchFilter) departmentQuery = departmentQuery.eq('church_id', churchFilter);

            let groupQuery = supabase
                .from('groups')
                .select('id, name, church_id, department_id, ended_at, departments!department_id(name)')
                .eq('is_active', false)
                .order('ended_at', { ascending: false, nullsFirst: false });
            if (churchFilter) groupQuery = groupQuery.eq('church_id', churchFilter);

            const [memberResult, departmentResult, groupResult] = await Promise.all([
                memberQuery,
                departmentQuery,
                groupQuery,
            ]);

            if (memberResult.error) throw memberResult.error;
            if (departmentResult.error) throw departmentResult.error;
            if (groupResult.error) throw groupResult.error;

            const archivedMembers = (memberResult.data || []) as unknown as ArchivedMember[];
            const missingPersonDirectoryIds = archivedMembers
                .filter(member => !member.person_id)
                .map(member => member.id);

            if (missingPersonDirectoryIds.length > 0) {
                const { data: profileLinks, error: profileLinkError } = await supabase
                    .from('member_profiles')
                    .select('member_directory_id, person_id')
                    .in('member_directory_id', missingPersonDirectoryIds);

                if (profileLinkError) throw profileLinkError;

                const personByDirectoryId = new Map(
                    ((profileLinks || []) as MemberProfilePersonLink[])
                        .filter(link => link.member_directory_id && link.person_id)
                        .map(link => [link.member_directory_id as string, link.person_id as string])
                );

                archivedMembers.forEach(member => {
                    if (!member.person_id) {
                        member.person_id = personByDirectoryId.get(member.id) || null;
                    }
                });
            }

            const personIds = Array.from(new Set(archivedMembers.map(member => member.person_id).filter(Boolean))) as string[];
            const departmentIds = Array.from(new Set(archivedMembers.map(member => member.department_id).filter(Boolean))) as string[];

            if (personIds.length > 0 && departmentIds.length > 0) {
                const { data: membershipLinks, error: membershipLinkError } = await supabase
                    .from('memberships')
                    .select('person_id, department_id, group_id, status, ends_at, archived_by_event_id')
                    .in('person_id', personIds)
                    .in('department_id', departmentIds)
                    .in('status', ['active', 'inactive', 'ended']);

                if (membershipLinkError) throw membershipLinkError;

                const { data: archiveEvents, error: archiveEventsError } = await supabase
                    .from('person_department_lifecycle_events')
                    .select('id, person_id, department_id, occurred_at')
                    .eq('action', 'archive')
                    .in('person_id', personIds)
                    .in('department_id', departmentIds);

                if (archiveEventsError) throw archiveEventsError;

                const activeAffiliationKeys = new Set(
                    ((membershipLinks || []) as ArchivedMembershipLink[])
                        .filter(link => link.status === 'active' && link.person_id && link.department_id)
                        .map(link => `${link.person_id}:${link.department_id}`)
                );

                const groupIds = Array.from(new Set(
                    ((membershipLinks || []) as ArchivedMembershipLink[])
                        .filter(link => link.status !== 'active')
                        .map(link => link.group_id)
                        .filter(Boolean)
                )) as string[];

                const groupNames = new Map<string, string>();
                if (groupIds.length > 0) {
                    const { data: groupRows, error: groupRowsError } = await supabase
                        .from('groups')
                        .select('id, name')
                        .in('id', groupIds);

                    if (groupRowsError) throw groupRowsError;

                    ((groupRows || []) as GroupNameRow[]).forEach(group => {
                        if (group.id && group.name) groupNames.set(group.id, group.name);
                    });
                }

                const archivedGroupsByAffiliation = new Map<string, Set<string>>();
                const archivedCandidatesByAffiliation = new Map<string, ArchivedGroupCandidate[]>();
                const latestEventByAffiliation = new Map<string, ArchiveEventRow>();
                const latestEndsAtByAffiliation = new Map<string, number>();

                ((archiveEvents || []) as ArchiveEventRow[]).forEach(event => {
                    if (!event.person_id || !event.department_id) return;
                    const key = `${event.person_id}:${event.department_id}`;
                    const existing = latestEventByAffiliation.get(key);
                    if (!existing || event.occurred_at > existing.occurred_at) {
                        latestEventByAffiliation.set(key, event);
                    }
                });

                ((membershipLinks || []) as ArchivedMembershipLink[]).forEach(link => {
                    if (link.status === 'active') return;
                    if (!link.person_id || !link.department_id || !link.ends_at) return;
                    const key = `${link.person_id}:${link.department_id}`;
                    const timestamp = new Date(link.ends_at).getTime();
                    const existing = latestEndsAtByAffiliation.get(key);
                    if (!existing || timestamp > existing) {
                        latestEndsAtByAffiliation.set(key, timestamp);
                    }
                });

                ((membershipLinks || []) as ArchivedMembershipLink[]).forEach(link => {
                    if (link.status === 'active') return;
                    if (!link.person_id || !link.department_id || !link.group_id) return;
                    const groupName = groupNames.get(link.group_id);
                    if (!groupName) return;
                    const key = `${link.person_id}:${link.department_id}`;
                    const latestEvent = latestEventByAffiliation.get(key);
                    const latestEndsAt = latestEndsAtByAffiliation.get(key);
                    const isLatestArchiveCandidate = latestEvent
                        ? link.archived_by_event_id === latestEvent.id
                        : !latestEndsAt || !link.ends_at || new Date(link.ends_at).getTime() >= latestEndsAt - 5000;
                    const names = archivedGroupsByAffiliation.get(key) || new Set<string>();
                    names.add(groupName);
                    archivedGroupsByAffiliation.set(key, names);

                    if (!isLatestArchiveCandidate) return;

                    const candidates = archivedCandidatesByAffiliation.get(key) || [];
                    if (!candidates.some(candidate => candidate.group_id === link.group_id)) {
                        candidates.push({
                            group_id: link.group_id,
                            group_name: groupName,
                            ends_at: link.ends_at,
                            archived_by_event_id: link.archived_by_event_id,
                        });
                    }
                    archivedCandidatesByAffiliation.set(key, candidates);
                });

                archivedMembers.forEach(member => {
                    if (!member.person_id || !member.department_id) return;
                    const key = `${member.person_id}:${member.department_id}`;
                    const names = archivedGroupsByAffiliation.get(key);
                    const candidates = archivedCandidatesByAffiliation.get(key);
                    member.archived_group_names = names ? Array.from(names).sort((a, b) => a.localeCompare(b, 'ko')) : [];
                    member.archived_group_candidates = candidates
                        ? [...candidates].sort((a, b) => a.group_name.localeCompare(b.group_name, 'ko'))
                        : [];
                });

                for (let index = archivedMembers.length - 1; index >= 0; index -= 1) {
                    const member = archivedMembers[index];
                    if (!member.person_id || !member.department_id) continue;
                    if (activeAffiliationKeys.has(`${member.person_id}:${member.department_id}`)) {
                        archivedMembers.splice(index, 1);
                    }
                }
            }

            setMembers(archivedMembers);
            setDepartments((departmentResult.data || []) as ArchivedDepartment[]);
            setGroups((groupResult.data || []) as unknown as ArchivedGroup[]);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        const init = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                router.push('/login');
                return;
            }

            const { data } = await supabase
                .from('profiles')
                .select('id, church_id, role, admin_status, is_master')
                .eq('id', session.user.id)
                .single();

            const isAuthorized = data?.is_master || (data?.role === 'admin' && data?.admin_status === 'approved');
            if (!isAuthorized) {
                router.push('/login?error=unauthorized');
                return;
            }

            setProfile(data);
            await fetchArchive(data);
        };

        init();
    }, [router]);

    const memberAffiliations = useMemo(() => {
        const groupsByKey = new Map<string, ArchivedMemberAffiliation>();

        members.forEach(member => {
            const key = member.person_id && member.department_id
                ? `${member.person_id}:${member.department_id}`
                : member.id;
            const existing = groupsByKey.get(key);

            if (!existing) {
                groupsByKey.set(key, {
                    key,
                    person_id: member.person_id,
                    church_id: member.church_id,
                    department_id: member.department_id,
                    full_name: member.full_name,
                    phone: member.phone,
                    left_at: member.left_at,
                    departments: member.departments,
                    archived_group_names: member.archived_group_names || [],
                    archived_group_candidates: member.archived_group_candidates || [],
                    rows: [member],
                });
                return;
            }

            existing.rows.push(member);
            existing.archived_group_names = Array.from(new Set([
                ...existing.archived_group_names,
                ...(member.archived_group_names || []),
            ])).sort((a, b) => a.localeCompare(b, 'ko'));
            existing.archived_group_candidates = [
                ...existing.archived_group_candidates,
                ...(member.archived_group_candidates || []),
            ].filter((candidate, index, candidates) =>
                candidates.findIndex(item => item.group_id === candidate.group_id) === index
            ).sort((a, b) => a.group_name.localeCompare(b.group_name, 'ko'));

            if (member.left_at && (!existing.left_at || member.left_at > existing.left_at)) {
                existing.left_at = member.left_at;
            }
        });

        return Array.from(groupsByKey.values()).sort((a, b) => {
            const leftCompare = (b.left_at || '').localeCompare(a.left_at || '');
            if (leftCompare !== 0) return leftCompare;
            return a.full_name.localeCompare(b.full_name, 'ko');
        });
    }, [members]);

    const filteredMembers = useMemo(() => {
        const keyword = query.trim().toLowerCase();
        if (!keyword) return memberAffiliations;
        return memberAffiliations.filter(member =>
            member.full_name.toLowerCase().includes(keyword) ||
            member.phone?.includes(keyword) ||
            member.departments?.name?.toLowerCase().includes(keyword) ||
            member.archived_group_names.some(groupName => groupName.toLowerCase().includes(keyword))
        );
    }, [memberAffiliations, query]);

    useEffect(() => {
        setRestoreGroupSelections(previous => {
            const next = { ...previous };
            const validKeys = new Set(memberAffiliations.map(member => member.key));

            Object.keys(next).forEach(key => {
                if (!validKeys.has(key)) delete next[key];
            });

            memberAffiliations.forEach(member => {
                if (next[member.key]) return;
                next[member.key] = member.archived_group_candidates.map(candidate => candidate.group_id);
            });

            return next;
        });
    }, [memberAffiliations]);

    const filteredDepartments = useMemo(() => {
        const keyword = query.trim().toLowerCase();
        if (!keyword) return departments;
        return departments.filter(department => department.name.toLowerCase().includes(keyword));
    }, [departments, query]);

    const filteredGroups = useMemo(() => {
        const keyword = query.trim().toLowerCase();
        if (!keyword) return groups;
        return groups.filter(group =>
            group.name.toLowerCase().includes(keyword) ||
            group.departments?.name?.toLowerCase().includes(keyword)
        );
    }, [groups, query]);

    const refresh = async () => {
        if (profile) await fetchArchive(profile);
    };

    const toggleRestoreGroup = (memberKey: string, groupId: string) => {
        setRestoreGroupSelections(previous => {
            const current = previous[memberKey] || [];
            const next = current.includes(groupId)
                ? current.filter(id => id !== groupId)
                : [...current, groupId];

            return {
                ...previous,
                [memberKey]: next,
            };
        });
    };

    const restoreMember = async (member: ArchivedMemberAffiliation) => {
        if (!member.department_id) {
            alert('부서 정보가 없어 복구할 수 없습니다.');
            return;
        }

        const selectedGroupIds = restoreGroupSelections[member.key] || [];
        const restoreLabel = member.archived_group_candidates.length > 0
            ? selectedGroupIds.length > 0
                ? `${selectedGroupIds.length}개 조`
                : '조 없이 부서 소속만'
            : '부서 소속';

        if (!confirm(`${member.full_name}님의 ${member.departments?.name || '부서'} 소속을 ${restoreLabel}으로 복구하시겠습니까?`)) return;

        setRestoringId(member.key);
        try {
            if (member.person_id) {
                await setPersonDepartmentActiveStatus(supabase, {
                    personId: member.person_id,
                    churchId: member.church_id,
                    departmentId: member.department_id,
                    isActive: true,
                    restoreGroupIds: selectedGroupIds,
                });
            } else {
                await setMemberDirectoryActiveStatus(supabase, member.rows[0].id, true);
            }
            await refresh();
        } catch (error) {
            alert(error instanceof Error ? error.message : '성도 소속 복구 중 오류가 발생했습니다.');
        } finally {
            setRestoringId(null);
        }
    };

    const restoreDepartment = async (department: ArchivedDepartment) => {
        if (!confirm(`${department.name} 부서를 복구하시겠습니까?`)) return;
        setRestoringId(department.id);
        try {
            const { error } = await supabase
                .from('departments')
                .update({ is_active: true, ended_at: null })
                .eq('id', department.id);
            if (error) throw error;
            await refresh();
        } catch (error) {
            alert(error instanceof Error ? error.message : '부서 복구 중 오류가 발생했습니다.');
        } finally {
            setRestoringId(null);
        }
    };

    const restoreGroup = async (group: ArchivedGroup) => {
        if (!confirm(`${group.name} 조를 복구하시겠습니까?`)) return;
        setRestoringId(group.id);
        try {
            const { error } = await supabase
                .from('groups')
                .update({ is_active: true, ended_at: null })
                .eq('id', group.id);
            if (error) throw error;
            await refresh();
        } catch (error) {
            alert(error instanceof Error ? error.message : '조 복구 중 오류가 발생했습니다.');
        } finally {
            setRestoringId(null);
        }
    };

    const tabClass = (tab: ArchiveTab) => cn(
        'px-4 py-2 rounded-2xl text-xs font-black transition-all border',
        activeTab === tab
            ? 'bg-indigo-600 text-white border-indigo-600 shadow-lg shadow-indigo-600/20'
            : 'bg-white dark:bg-slate-900 text-slate-500 dark:text-slate-400 border-slate-200 dark:border-slate-800 hover:border-indigo-200'
    );

    return (
        <div className="max-w-7xl mx-auto space-y-8 pb-20">
            <header className="flex flex-col lg:flex-row lg:items-end justify-between gap-6">
                <div className="space-y-3">
                    <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-500 dark:text-slate-400 text-[10px] font-black uppercase tracking-widest">
                        <Archive className="w-3.5 h-3.5" />
                        Archive Management
                    </div>
                    <div>
                        <h1 className="text-4xl font-black text-slate-900 dark:text-white tracking-tighter">휴지통</h1>
                        <p className="text-sm font-bold text-slate-400 mt-2">
                            비활성화된 성도 소속, 종료된 부서와 조를 확인하고 복구합니다.
                        </p>
                    </div>
                </div>
                <button
                    onClick={refresh}
                    disabled={loading}
                    className="inline-flex items-center gap-2 px-4 py-3 rounded-2xl bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 text-xs font-black text-slate-600 dark:text-slate-300 hover:border-indigo-200 transition-all"
                >
                    {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <RefreshCw className="w-4 h-4" />}
                    새로고침
                </button>
            </header>

            <section className="bg-white dark:bg-[#111827]/70 border border-slate-200 dark:border-slate-800 rounded-[2rem] shadow-xl p-5 sm:p-6 space-y-6">
                <div className="flex flex-col xl:flex-row xl:items-center justify-between gap-4">
                    <div className="flex flex-wrap gap-2">
                        <button type="button" onClick={() => setActiveTab('members')} className={tabClass('members')}>
                            성도 소속 {memberAffiliations.length}
                        </button>
                        <button type="button" onClick={() => setActiveTab('departments')} className={tabClass('departments')}>
                            부서 {departments.length}
                        </button>
                        <button type="button" onClick={() => setActiveTab('groups')} className={tabClass('groups')}>
                            조 {groups.length}
                        </button>
                    </div>
                    <div className="relative w-full xl:w-80">
                        <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                        <input
                            value={query}
                            onChange={event => setQuery(event.target.value)}
                            placeholder="이름, 전화번호, 부서, 조 검색"
                            className="w-full pl-11 pr-4 py-3 rounded-2xl bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800 text-sm font-bold text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-500/20"
                        />
                    </div>
                </div>

                {loading ? (
                    <div className="py-20 flex items-center justify-center text-slate-400">
                        <Loader2 className="w-8 h-8 animate-spin" />
                    </div>
                ) : activeTab === 'members' ? (
                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                        {filteredMembers.map(member => (
                            <article key={member.key} className="p-5 rounded-3xl border border-slate-200 dark:border-slate-800 bg-slate-50/70 dark:bg-slate-950/30 space-y-4">
                                <div className="flex items-start justify-between gap-4">
                                    <div className="flex items-start gap-3">
                                        <div className="w-11 h-11 rounded-2xl bg-indigo-50 dark:bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 flex items-center justify-center font-black">
                                            {member.full_name?.[0]}
                                        </div>
                                        <div>
                                            <h3 className="text-lg font-black text-slate-900 dark:text-white">{member.full_name}</h3>
                                            <p className="text-xs font-bold text-slate-400">
                                                {member.phone || '전화번호 없음'}
                                                {member.rows.length > 1 ? ` / 보관 row ${member.rows.length}개` : ''}
                                            </p>
                                        </div>
                                    </div>
                                    <button
                                        onClick={() => restoreMember(member)}
                                        disabled={restoringId === member.key}
                                        className="inline-flex items-center gap-2 px-3 py-2 rounded-xl bg-emerald-600 text-white text-[10px] font-black hover:bg-emerald-500 transition-all disabled:opacity-50"
                                    >
                                        {restoringId === member.key ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <RotateCcw className="w-3.5 h-3.5" />}
                                        복구
                                    </button>
                                </div>
                                <div className="flex flex-wrap gap-2">
                                    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 text-[10px] font-black text-slate-600 dark:text-slate-300">
                                        <Building2 className="w-3 h-3" />
                                        {member.departments?.name || '부서 없음'}
                                    </span>
                                    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 text-[10px] font-black text-slate-600 dark:text-slate-300">
                                        <Users className="w-3 h-3" />
                                        {member.archived_group_candidates.length > 0
                                            ? '복구할 조 선택'
                                            : member.archived_group_names.length > 0
                                                ? `과거 조: ${member.archived_group_names.join(', ')}`
                                                : '조 없음'}
                                    </span>
                                    <span className="px-2.5 py-1 rounded-lg bg-slate-200/70 dark:bg-slate-800 text-[10px] font-black text-slate-500 dark:text-slate-400">
                                        {formatDate(member.left_at)}
                                    </span>
                                </div>
                                {member.archived_group_candidates.length > 0 && (
                                    <div className="space-y-2">
                                        <p className="text-[10px] font-black uppercase tracking-widest text-slate-400">
                                            복구할 조
                                        </p>
                                        <div className="flex flex-wrap gap-2">
                                            {member.archived_group_candidates.map(candidate => {
                                                const selectedGroupIds = restoreGroupSelections[member.key] || [];
                                                const isSelected = selectedGroupIds.includes(candidate.group_id);

                                                return (
                                                    <button
                                                        key={candidate.group_id}
                                                        type="button"
                                                        onClick={() => toggleRestoreGroup(member.key, candidate.group_id)}
                                                        className={cn(
                                                            'px-3 py-1.5 rounded-xl border text-[11px] font-black transition-all',
                                                            isSelected
                                                                ? 'bg-emerald-50 border-emerald-200 text-emerald-700 dark:bg-emerald-500/10 dark:border-emerald-500/30 dark:text-emerald-300'
                                                                : 'bg-white border-slate-200 text-slate-400 dark:bg-slate-900 dark:border-slate-800 dark:text-slate-500'
                                                        )}
                                                    >
                                                        {isSelected ? '복구 ' : '제외 '}
                                                        {candidate.group_name}
                                                    </button>
                                                );
                                            })}
                                        </div>
                                        {member.archived_group_names.length > member.archived_group_candidates.length && (
                                            <p className="text-[10px] font-bold text-slate-400">
                                                오래된 이력: {member.archived_group_names
                                                    .filter(name => !member.archived_group_candidates.some(candidate => candidate.group_name === name))
                                                    .join(', ')}
                                            </p>
                                        )}
                                    </div>
                                )}
                            </article>
                        ))}
                        {filteredMembers.length === 0 && (
                            <EmptyState label="비활성 성도 소속이 없습니다." />
                        )}
                    </div>
                ) : activeTab === 'departments' ? (
                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                        {filteredDepartments.map(department => (
                            <ArchiveRow
                                key={department.id}
                                title={department.name}
                                subtitle={`종료일: ${formatDate(department.ended_at)}`}
                                icon={<Building2 className="w-5 h-5" />}
                                isLoading={restoringId === department.id}
                                onRestore={() => restoreDepartment(department)}
                            />
                        ))}
                        {filteredDepartments.length === 0 && <EmptyState label="종료된 부서가 없습니다." />}
                    </div>
                ) : (
                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                        {filteredGroups.map(group => (
                            <ArchiveRow
                                key={group.id}
                                title={group.name}
                                subtitle={`${group.departments?.name || '부서 없음'} / 종료일: ${formatDate(group.ended_at)}`}
                                icon={<Users className="w-5 h-5" />}
                                isLoading={restoringId === group.id}
                                onRestore={() => restoreGroup(group)}
                            />
                        ))}
                        {filteredGroups.length === 0 && <EmptyState label="종료된 조가 없습니다." />}
                    </div>
                )}
            </section>
        </div>
    );
}

function ArchiveRow({
    title,
    subtitle,
    icon,
    isLoading,
    onRestore,
}: {
    title: string;
    subtitle: string;
    icon: React.ReactNode;
    isLoading: boolean;
    onRestore: () => void;
}) {
    return (
        <article className="p-5 rounded-3xl border border-slate-200 dark:border-slate-800 bg-slate-50/70 dark:bg-slate-950/30 flex items-center justify-between gap-4">
            <div className="flex items-center gap-3">
                <div className="w-11 h-11 rounded-2xl bg-indigo-50 dark:bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 flex items-center justify-center">
                    {icon}
                </div>
                <div>
                    <h3 className="text-lg font-black text-slate-900 dark:text-white">{title}</h3>
                    <p className="text-xs font-bold text-slate-400">{subtitle}</p>
                </div>
            </div>
            <button
                onClick={onRestore}
                disabled={isLoading}
                className="inline-flex items-center gap-2 px-3 py-2 rounded-xl bg-emerald-600 text-white text-[10px] font-black hover:bg-emerald-500 transition-all disabled:opacity-50"
            >
                {isLoading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <RotateCcw className="w-3.5 h-3.5" />}
                복구
            </button>
        </article>
    );
}

function EmptyState({ label }: { label: string }) {
    return (
        <div className="col-span-full py-16 flex flex-col items-center justify-center gap-3 text-slate-400">
            <Church className="w-8 h-8" />
            <p className="text-sm font-black">{label}</p>
        </div>
    );
}
