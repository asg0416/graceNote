'use client';

import { useEffect, useState, use } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    ArrowLeft,
    User,
    Phone,
    Users,
    Layers,
    Calendar,
    Heart,
    Baby,
    StickyNote,
    History,
    Save,
    Loader2,
    CheckCircle2,
    MessageSquare,
    Sparkles,
    ChevronRight,
    Clock,
    Type
} from 'lucide-react';
import RichTextEditor from '@/components/RichTextEditor';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}

export default function MemberDetailPage({ params }: { params: Promise<{ id: string }> }) {
    const { id } = use(params);
    const [loading, setLoading] = useState(true);
    const [member, setMember] = useState<any>(null);
    const [profile, setProfile] = useState<any>(null);
    const [prayers, setPrayers] = useState<any[]>([]);
    const [isEditingNote, setIsEditingNote] = useState(false);
    const [isEditingProfile, setIsEditingProfile] = useState(false);
    const [isEditingFamily, setIsEditingFamily] = useState(false);
    const [note, setNote] = useState('');
    const [isSaving, setIsSaving] = useState(false);
    const [editingMember, setEditingMember] = useState<any>(null);
    const [isPrayersLoading, setIsPrayersLoading] = useState(false);
    const [hasMorePrayers, setHasMorePrayers] = useState(true);
    const [page, setPage] = useState(0);
    const PAGE_SIZE = 10;
    const [directoryIds, setDirectoryIds] = useState<string[]>([]);
    const [profileIds, setProfileIds] = useState<string[]>([]);

    const router = useRouter();

    useEffect(() => {
        const fetchMemberData = async () => {
            setLoading(true);
            try {
                const { data: { session } } = await supabase.auth.getSession();
                if (!session) {
                    router.push('/login');
                    return;
                }

                const { data: currentProfile } = await supabase
                    .from('profiles')
                    .select('church_id, is_master, role, admin_status')
                    .eq('id', session.user.id)
                    .single();

                const isAuthorized = currentProfile && (currentProfile.is_master || (currentProfile.role === 'admin' && currentProfile.admin_status === 'approved'));
                if (!isAuthorized) {
                    router.push('/login?error=unauthorized');
                    return;
                }

                // 1. Fetch current directory info
                const { data: memberData, error: memberError } = await supabase
                    .from('member_directory')
                    .select(`
                        *,
                        departments!department_id (name, color_hex)
                    `)
                    .eq('id', id)
                    .single();

                if (memberError) throw memberError;

                // Restrict Church Admin to their own church
                if (memberData && !currentProfile.is_master && memberData.church_id !== currentProfile.church_id) {
                    router.push('/members');
                    return;
                }

                // 2. Fetch all affiliations for the same person (using person_id or fallback to name+phone)
                let relatedQuery = supabase
                    .from('member_directory')
                    .select('id, profile_id, group_name, phone, departments!department_id(name, color_hex)');

                if (memberData.person_id) {
                    relatedQuery = relatedQuery.eq('person_id', memberData.person_id);
                } else {
                    relatedQuery = relatedQuery
                        .eq('full_name', memberData.full_name)
                        .eq('phone', memberData.phone)
                        .eq('church_id', memberData.church_id);
                }

                const { data: allAffiliations } = await relatedQuery;

                const directoryIds = allAffiliations?.map(m => m.id) || [id];
                const profileIds = Array.from(new Set([
                    memberData.profile_id,
                    ...(allAffiliations?.map(m => m.profile_id) || [])
                ])).filter(Boolean);

                // Attach affiliations to member object
                (memberData as any)._affiliations = allAffiliations || [];

                setMember(memberData);
                setNote(memberData.notes || '');

                if (memberData.profile_id) {
                    const { data } = await supabase.from('profiles').select('*').eq('id', memberData.profile_id).maybeSingle();
                    if (data) setProfile(data);
                }

                setDirectoryIds(directoryIds);
                setProfileIds(profileIds);
                setPage(0);
                setPrayers([]);
                setHasMorePrayers(true);

            } catch (err) {
                console.error('Error fetching member details:', err);
            } finally {
                setLoading(false);
            }
        };

        fetchMemberData();
    }, [id]);

    useEffect(() => {
        if (directoryIds.length === 0 && profileIds.length === 0) return;

        const fetchPrayers = async () => {
            setIsPrayersLoading(true);
            try {
                const fetchWithJoin = async (targetId: string, isDirectory: boolean) => {
                    const { data, error } = await supabase
                        .from('prayer_entries')
                        .select('*, weeks(week_date)')
                        .eq(isDirectory ? 'directory_member_id' : 'member_id', targetId)
                        .order('week_date', { foreignTable: 'weeks', ascending: false })
                        .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

                    if (error) {
                        console.warn(`Join query failed for ${isDirectory ? 'Directory' : 'Profile'} ID ${targetId}:`, error.message);
                        return supabase
                            .from('prayer_entries')
                            .select('*')
                            .eq(isDirectory ? 'directory_member_id' : 'member_id', targetId)
                            .order('updated_at', { ascending: false })
                            .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);
                    }
                    return { data, error };
                };

                const results = await Promise.all([
                    ...directoryIds.map(dId => fetchWithJoin(dId, true)),
                    ...profileIds.map(pId => fetchWithJoin(pId, false))
                ]);

                const newPrayers = results.flatMap(r => r.data || []);
                if (newPrayers.length < PAGE_SIZE && directoryIds.length + profileIds.length === 1) {
                    // This logic is slightly flawed for multiple IDs but works for single common cases
                    // A better way is to compare to PAGE_SIZE total
                }

                setPrayers(prev => {
                    const combined = [...prev, ...newPrayers];
                    const unique = Array.from(new Map(combined.map(p => [p.id, p])).values());

                    // Sort by week_date (from weeks join) primarily, then by updated_at
                    unique.sort((a, b) => {
                        const dateA = a.weeks?.week_date || a.updated_at || '0';
                        const dateB = b.weeks?.week_date || b.updated_at || '0';
                        if (dateA !== dateB) return dateB.localeCompare(dateA);
                        return (b.updated_at || '0').localeCompare(a.updated_at || '0');
                    });
                    return unique;
                });

                if (newPrayers.length === 0) {
                    setHasMorePrayers(false);
                }
            } catch (err) {
                console.error('Error fetching prayers:', err);
            } finally {
                setIsPrayersLoading(false);
            }
        };

        fetchPrayers();
    }, [page, directoryIds, profileIds]);

    const handleSaveDetail = async (field: string, value: any) => {
        setIsSaving(true);
        try {
            const { error } = await supabase
                .from('member_directory')
                .update({ [field]: value })
                .eq('id', id);

            if (error) throw error;
            setMember({ ...member, [field]: value });
        } catch (err: any) {
            console.error('Error saving detail:', err);
            alert('정보 저장 중 오류가 발생했습니다: ' + (err.message || '알 수 없는 오류'));
        } finally {
            setIsSaving(false);
        }
    };

    const handleLinkAccount = async () => {
        if (!member || !profile) return;
        setIsSaving(true);
        try {
            const { error } = await supabase
                .from('member_directory')
                .update({ is_linked: true, profile_id: profile.id })
                .eq('id', member.id);

            if (error) throw error;
            setMember({ ...member, is_linked: true, profile_id: profile.id });
            alert('계정 연동이 성공적으로 완료되었습니다.');
        } catch (err: any) {
            console.error('Error linking account:', err);
            alert('계정 연동 중 오류가 발생했습니다: ' + (err.message || '알 수 없는 오류'));
        } finally {
            setIsSaving(false);
        }
    };

    const handleUpdateMember = async (section: 'profile' | 'family') => {
        setIsSaving(true);
        try {
            const updateData: any = {};
            if (section === 'profile') {
                updateData.full_name = editingMember.full_name;
                updateData.phone = editingMember.phone;
                updateData.birth_date = editingMember.birth_date;
                updateData.wedding_anniversary = editingMember.wedding_anniversary;
            } else if (section === 'family') {
                updateData.spouse_name = editingMember.spouse_name;
                updateData.children_info = editingMember.children_info;
            }

            const { error } = await supabase
                .from('member_directory')
                .update(updateData)
                .eq('id', id);

            if (error) throw error;
            setMember({ ...member, ...updateData });
            if (section === 'profile') setIsEditingProfile(false);
            if (section === 'family') setIsEditingFamily(false);
            alert('정보가 수정되었습니다.');
        } catch (err: any) {
            console.error(err);
            alert('수정 중 오류가 발생했습니다: ' + (err.message || '알 수 없는 오류'));
        } finally {
            setIsSaving(false);
        }
    };

    const handleToggleActive = async () => {
        const newStatus = member.is_active === false;
        if (!confirm(`이 성도를 ${newStatus ? '활성화' : '비활성화'} 하시겠습니까?`)) return;

        setIsSaving(true);
        try {
            const { error } = await supabase
                .from('member_directory')
                .update({ is_active: newStatus })
                .eq('id', id);
            if (error) throw error;
            setMember({ ...member, is_active: newStatus });
            alert(`${newStatus ? '활성화' : '비활성화'} 되었습니다.`);
        } catch (err) {
            alert('오류 발생');
        } finally {
            setIsSaving(false);
        }
    };

    if (loading) {
        return (
            <div className="min-h-[60vh] flex flex-col items-center justify-center gap-6">
                <Loader2 className="w-12 h-12 text-indigo-600 animate-spin" />
                <p className="text-slate-400 font-black uppercase tracking-widest text-xs">성도 정보 불러오는 중...</p>
            </div>
        );
    }

    if (!member) {
        return (
            <div className="p-20 text-center space-y-4">
                <p className="text-slate-500 font-bold">성도 정보를 찾을 수 없습니다.</p>
                <button onClick={() => router.back()} className="text-indigo-600 font-black flex items-center gap-2 mx-auto">
                    <ArrowLeft className="w-4 h-4" /> 뒤로 가기
                </button>
            </div>
        );
    }

    return (
        <div className="max-w-5xl mx-auto space-y-8 pb-20">
            {/* Header / Navigation */}
            <div className="flex items-center justify-between">
                <button
                    onClick={() => router.back()}
                    className="flex items-center gap-2 text-slate-500 hover:text-indigo-600 transition-colors font-black text-sm group"
                >
                    <div className="w-10 h-10 rounded-xl bg-slate-100 dark:bg-slate-800 flex items-center justify-center group-hover:bg-indigo-50 dark:group-hover:bg-indigo-500/10 transition-all">
                        <ArrowLeft className="w-5 h-5" />
                    </div>
                    뒤로 가기
                </button>
                <div className="flex items-center gap-3">
                    {member.is_active === false ? (
                        <button
                            onClick={handleToggleActive}
                            disabled={isSaving}
                            className="px-4 py-2 bg-emerald-600 text-white text-[10px] font-black rounded-2xl hover:bg-emerald-500 transition-all uppercase tracking-widest flex items-center gap-2 shadow-lg shadow-emerald-600/20"
                        >
                            <CheckCircle2 className="w-3.5 h-3.5" /> 다시 활성화
                        </button>
                    ) : (
                        <button
                            onClick={handleToggleActive}
                            disabled={isSaving}
                            className="px-4 py-2 bg-rose-50 dark:bg-rose-500/10 text-rose-600 dark:text-rose-400 text-[10px] font-black rounded-2xl border border-rose-100 dark:border-rose-500/20 hover:bg-rose-100 transition-all uppercase tracking-widest flex items-center gap-2 shadow-sm"
                        >
                            <Users className="w-3.5 h-3.5" /> 비활성화
                        </button>
                    )}
                    <div className="w-px h-6 bg-slate-200 dark:bg-slate-800 mx-1" />
                    {member.is_linked ? (
                        <span className="px-4 py-2 bg-emerald-50 dark:bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 text-[10px] font-black rounded-2xl border border-emerald-100 dark:border-emerald-500/20 uppercase tracking-widest flex items-center gap-2">
                            <CheckCircle2 className="w-4 h-4" /> 연동 완료
                        </span>
                    ) : (
                        <div className="flex items-center gap-3">
                            <span className="px-4 py-2 bg-slate-100 dark:bg-slate-800 text-slate-400 text-[10px] font-black rounded-2xl border border-slate-200 dark:border-slate-700 uppercase tracking-widest">
                                앱 미사용
                            </span>
                            {profile && (
                                <button
                                    onClick={handleLinkAccount}
                                    disabled={isSaving}
                                    className="px-4 py-2 bg-indigo-600 text-white text-[10px] font-black rounded-2xl hover:bg-indigo-500 transition-all uppercase tracking-widest flex items-center gap-2 shadow-lg shadow-indigo-600/20"
                                >
                                    {isSaving ? <Loader2 className="w-3 h-3 animate-spin" /> : <Save className="w-3.5 h-3.5" />}
                                    강제 연동
                                </button>
                            )}
                        </div>
                    )}
                </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
                {/* Left Column: Profile Card */}
                <div className="lg:col-span-1 space-y-6">
                    <div className="bg-white dark:bg-[#111827]/60 rounded-[40px] border border-slate-200 dark:border-slate-800 shadow-xl overflow-hidden group/profile">
                        <div className="p-10 flex flex-col items-center text-center space-y-6">
                            <div className="w-24 h-24 rounded-[32px] bg-gradient-to-br from-indigo-500 to-violet-600 flex items-center justify-center text-white text-4xl font-black shadow-2xl shadow-indigo-500/20">
                                {member.full_name?.[0]}
                            </div>
                            <div className="w-full relative">
                                {!isEditingProfile ? (
                                    <>
                                        <h1 className="text-3xl font-black text-slate-900 dark:text-white tracking-tighter">{member.full_name}</h1>
                                        <p className="text-indigo-600 dark:text-indigo-400 font-black text-xs uppercase tracking-widest mt-2">성도상세 프로필</p>
                                        <button
                                            onClick={() => {
                                                setEditingMember({ ...member });
                                                setIsEditingProfile(true);
                                            }}
                                            className="absolute -top-2 -right-2 px-3 py-1 bg-slate-50 dark:bg-slate-800 text-[10px] font-black text-slate-400 rounded-lg opacity-0 group-hover/profile:opacity-100 transition-all hover:text-indigo-600 cursor-pointer"
                                        >
                                            수정
                                        </button>
                                    </>
                                ) : (
                                    <div className="space-y-3">
                                        <input
                                            type="text"
                                            value={editingMember?.full_name || ''}
                                            onChange={e => setEditingMember({ ...editingMember, full_name: e.target.value })}
                                            className="w-full bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl px-4 py-2 font-black text-center text-xl focus:outline-none focus:ring-2 focus:ring-indigo-500/20"
                                            placeholder="성함"
                                        />
                                        <div className="flex gap-2">
                                            <button onClick={() => setIsEditingProfile(false)} className="flex-1 py-2 text-[10px] font-black text-slate-400 hover:bg-slate-100 rounded-lg cursor-pointer"
                                            >취소</button>
                                            <button onClick={() => handleUpdateMember('profile')} className="flex-1 py-2 text-[10px] font-black bg-indigo-600 text-white rounded-lg cursor-pointer"
                                            >저장</button>
                                        </div>
                                    </div>
                                )}
                            </div>

                            <div className="w-full pt-8 space-y-4 border-t border-slate-100 dark:border-slate-800/60">
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-3 text-slate-400">
                                        <div className="w-8 h-8 rounded-lg bg-slate-50 dark:bg-slate-800/40 flex items-center justify-center">
                                            <Phone className="w-4 h-4" />
                                        </div>
                                        <span className="text-[10px] font-black uppercase tracking-widest">연락처</span>
                                    </div>
                                    {isEditingProfile ? (
                                        <input
                                            type="text"
                                            value={editingMember?.phone || ''}
                                            onChange={e => setEditingMember({ ...editingMember, phone: e.target.value })}
                                            className="w-32 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-lg px-2 py-1 text-right text-sm font-bold focus:outline-none"
                                        />
                                    ) : (
                                        <span className="text-sm font-bold text-slate-700 dark:text-slate-200">{member.phone || '없음'}</span>
                                    )}
                                </div>
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-3 text-slate-400">
                                        <div className="w-8 h-8 rounded-lg bg-slate-50 dark:bg-slate-800/40 flex items-center justify-center">
                                            <Calendar className="w-4 h-4" />
                                        </div>
                                        <span className="text-[10px] font-black uppercase tracking-widest">생년월일</span>
                                    </div>
                                    {isEditingProfile ? (
                                        <input
                                            type="date"
                                            value={editingMember?.birth_date || ''}
                                            onChange={e => setEditingMember({ ...editingMember, birth_date: e.target.value })}
                                            className="bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-lg px-2 py-1 text-right text-xs font-bold focus:outline-none"
                                        />
                                    ) : (
                                        <span className="text-sm font-bold text-slate-700 dark:text-slate-200">{member.birth_date || '미등록'}</span>
                                    )}
                                </div>
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-3 text-slate-400">
                                        <div className="w-8 h-8 rounded-lg bg-slate-50 dark:bg-slate-800/40 flex items-center justify-center">
                                            <Sparkles className="w-4 h-4" />
                                        </div>
                                        <span className="text-[10px] font-black uppercase tracking-widest">결혼기념일</span>
                                    </div>
                                    {isEditingProfile ? (
                                        <input
                                            type="date"
                                            value={editingMember?.wedding_anniversary || ''}
                                            onChange={e => setEditingMember({ ...editingMember, wedding_anniversary: e.target.value })}
                                            className="bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-lg px-2 py-1 text-right text-xs font-bold focus:outline-none"
                                        />
                                    ) : (
                                        <span className="text-sm font-bold text-slate-700 dark:text-slate-200">{member.wedding_anniversary || '미등록'}</span>
                                    )}
                                </div>
                            </div>
                        </div>
                    </div>

                    {/* Affiliations Info Card - Separated */}
                    <div className="bg-slate-50 dark:bg-[#111827]/40 rounded-[40px] border border-slate-200/60 dark:border-slate-800/60 p-8 space-y-6">
                        <div className="flex items-center justify-between px-2">
                            <h3 className="text-xs font-black text-slate-400 uppercase tracking-[0.2em] flex items-center gap-3">
                                <Layers className="w-4 h-4 text-indigo-600" /> 소속 정보
                            </h3>
                            <p className="text-[8px] font-black text-slate-300 uppercase tracking-widest">Affiliations Info</p>
                        </div>
                        <div className="grid grid-cols-1 gap-2">
                            {member._affiliations?.length > 0 ? (
                                member._affiliations.map((aff: any) => (
                                    <div
                                        key={aff.id}
                                        className="flex items-center justify-between p-3.5 bg-white dark:bg-slate-800/40 rounded-2xl border border-slate-100 dark:border-slate-800/60 group/aff"
                                    >
                                        <div className="flex items-center gap-2">
                                            <div className="w-1.5 h-1.5 rounded-full bg-indigo-500" />
                                            <span className="text-[11px] font-black text-slate-800 dark:text-slate-200 uppercase tracking-tighter">
                                                {aff.departments?.name}
                                            </span>
                                        </div>
                                        <div className="px-2 py-0.5 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-700 rounded-lg shadow-sm">
                                            <span className="text-[10px] font-black text-indigo-600 dark:text-indigo-400">
                                                {aff.group_name} 조
                                            </span>
                                        </div>
                                    </div>
                                ))
                            ) : (
                                <div className="p-3.5 bg-white dark:bg-slate-800/40 rounded-2xl border border-slate-100 dark:border-slate-800/60">
                                    <span className="text-xs font-bold text-slate-500 dark:text-slate-400 text-center block">
                                        {member.departments?.name} | {member.group_name || '미정'}
                                    </span>
                                </div>
                            )}
                        </div>
                    </div>

                    {/* Family Info Card */}
                    <div className="bg-slate-50 dark:bg-[#111827]/40 rounded-[40px] border border-slate-200/60 dark:border-slate-800/60 p-8 space-y-6 group/family">
                        <div className="flex items-center justify-between px-2">
                            <h3 className="text-xs font-black text-slate-400 uppercase tracking-[0.2em] flex items-center gap-3">
                                <Heart className="w-4 h-4 text-rose-500" /> 가족 정보
                            </h3>
                            <p className="text-[8px] font-black text-slate-300 uppercase tracking-widest">Family Info</p>
                            {!isEditingFamily ? (
                                <button
                                    onClick={() => {
                                        setEditingMember({ ...member });
                                        setIsEditingFamily(true);
                                    }}
                                    className="px-3 py-1 bg-white dark:bg-slate-800 text-[10px] font-black text-slate-400 rounded-lg opacity-0 group-hover/family:opacity-100 transition-all hover:text-rose-500 cursor-pointer"
                                >
                                    수정
                                </button>
                            ) : (
                                <div className="flex gap-2">
                                    <button onClick={() => setIsEditingFamily(false)} className="px-2 py-1 text-[10px] font-black text-slate-400">취소</button>
                                    <button onClick={() => handleUpdateMember('family')} className="px-2 py-1 text-[10px] font-black bg-indigo-600 text-white rounded-lg">저장</button>
                                </div>
                            )}
                        </div>
                        <div className="space-y-4 px-2">
                            <div className="space-y-1">
                                <p className="text-[10px] font-black text-slate-400 uppercase tracking-widest">배우자</p>
                                {isEditingFamily ? (
                                    <input
                                        type="text"
                                        value={editingMember?.spouse_name || ''}
                                        onChange={e => setEditingMember({ ...editingMember, spouse_name: e.target.value })}
                                        className="w-full bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-lg px-2 py-1 text-sm font-bold"
                                    />
                                ) : (
                                    <p className="text-sm font-bold text-slate-700 dark:text-slate-200">{member.spouse_name || '정보 없음'}</p>
                                )}
                            </div>
                            <div className="space-y-1">
                                <p className="text-[10px] font-black text-slate-400 uppercase tracking-widest">자녀</p>
                                {isEditingFamily ? (
                                    <textarea
                                        value={editingMember?.children_info || ''}
                                        onChange={e => setEditingMember({ ...editingMember, children_info: e.target.value })}
                                        rows={2}
                                        className="w-full bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-lg px-2 py-1 text-sm font-bold leading-relaxed"
                                    />
                                ) : (
                                    <p className="text-sm font-bold text-slate-700 dark:text-slate-200 leading-relaxed">{member.children_info || '정보 없음'}</p>
                                )}
                            </div>
                        </div>
                    </div>
                </div>

                {/* Right Column: Detailed Info & Timeline */}
                <div className="lg:col-span-2 space-y-8">
                    {/* Notes Section */}
                    <div className="bg-white dark:bg-[#111827]/60 rounded-[40px] border border-slate-200 dark:border-slate-800 shadow-xl overflow-hidden group/notes">
                        <div className="p-8 border-b border-slate-100 dark:border-slate-800/60 flex items-center justify-between">
                            <div className="flex items-center gap-4">
                                <div className="w-10 h-10 rounded-2xl bg-amber-50 dark:bg-amber-500/10 flex items-center justify-center text-amber-500">
                                    <StickyNote className="w-5 h-5" />
                                </div>
                                <div>
                                    <h2 className="text-xl font-black text-slate-900 dark:text-white tracking-tighter">기타 사항 (메모)</h2>
                                    <p className="text-[10px] font-black text-slate-400 uppercase tracking-widest mt-0.5">메모 및 특이사항</p>
                                </div>
                            </div>
                            {!isEditingNote ? (
                                <button
                                    onClick={() => setIsEditingNote(true)}
                                    className="px-4 py-2 bg-slate-50 dark:bg-slate-800 text-slate-500 dark:text-slate-400 text-xs font-black rounded-xl hover:bg-slate-100 transition-all opacity-0 group-hover/notes:opacity-100"
                                >
                                    수정하기
                                </button>
                            ) : (
                                <div className="flex items-center gap-2">
                                    <button onClick={() => { setNote(member.notes || ''); setIsEditingNote(false); }} className="text-xs font-bold text-slate-400 hover:text-slate-600 transition-colors">취소</button>
                                    <button
                                        disabled={isSaving}
                                        onClick={() => handleSaveDetail('notes', note).then(() => setIsEditingNote(false))}
                                        className="px-5 py-2.5 bg-indigo-600 text-white text-xs font-black rounded-xl hover:bg-indigo-500 transition-all flex items-center gap-2 shadow-lg shadow-indigo-600/20"
                                    >
                                        {isSaving ? <Loader2 className="w-3 h-3 animate-spin" /> : <Save className="w-3.5 h-3.5" />}
                                        저장
                                    </button>
                                </div>
                            )}
                        </div>
                        <div className="p-8">
                            <RichTextEditor
                                content={note}
                                onChange={setNote}
                                editable={isEditingNote}
                                placeholder="아직 기록된 메모가 없습니다. 특이사항이나 심방 내용 등을 기록해 보세요."
                            />
                        </div>
                    </div>

                    {/* Prayer Timeline */}
                    <div className="bg-white dark:bg-[#111827]/60 rounded-[40px] border border-slate-200 dark:border-slate-800 shadow-xl overflow-hidden">
                        <div className="p-8 border-b border-slate-100 dark:border-slate-800/60 flex items-center justify-between">
                            <div className="flex items-center gap-4">
                                <div className="w-10 h-10 rounded-2xl bg-indigo-50 dark:bg-indigo-500/10 flex items-center justify-center text-indigo-600">
                                    <History className="w-5 h-5" />
                                </div>
                                <div>
                                    <h2 className="text-xl font-black text-slate-900 dark:text-white tracking-tighter">기도 제목 타임라인</h2>
                                    <p className="text-[10px] font-black text-slate-400 uppercase tracking-widest mt-0.5">기도 제목 히스토리</p>
                                </div>
                            </div>
                            <div className="flex items-center gap-2 px-3 py-1.5 bg-slate-50 dark:bg-slate-800/40 rounded-xl">
                                <span className="text-[10px] font-black text-slate-500 uppercase">{prayers.length}건 기록됨</span>
                            </div>
                        </div>

                        <div className="p-8">
                            {prayers.length === 0 && !isPrayersLoading ? (
                                <div className="py-20 text-center space-y-4">
                                    <div className="w-16 h-16 rounded-3xl bg-slate-100 dark:bg-slate-800 flex items-center justify-center mx-auto text-slate-400">
                                        <MessageSquare className="w-8 h-8 opacity-20" />
                                    </div>
                                    <div className="space-y-1">
                                        <p className="text-sm font-black text-slate-900 dark:text-white">기록된 기도 제목이 없습니다.</p>
                                        <p className="text-xs text-slate-500 font-bold">조장님이 앱에서 입력하시거나,<br />성도가 직접 작성한 내역이 여기에 표시됩니다.</p>
                                    </div>
                                </div>
                            ) : (
                                <div className="max-h-[700px] overflow-y-auto pr-4 custom-scrollbar">
                                    <div className="space-y-6 relative before:absolute before:left-[19px] before:top-4 before:bottom-4 before:w-0.5 before:bg-slate-100 dark:before:bg-slate-800">
                                        {prayers.map((prayer, idx) => {
                                            const currentDate = new Date(prayer.weeks?.week_date || prayer.updated_at || 0);
                                            const prevDate = idx > 0 ? new Date(prayers[idx - 1].weeks?.week_date || prayers[idx - 1].updated_at || 0) : null;

                                            const showIndicator = !prevDate ||
                                                currentDate.getFullYear() !== prevDate.getFullYear() ||
                                                currentDate.getMonth() !== prevDate.getMonth();

                                            return (
                                                <div key={prayer.id}>
                                                    {showIndicator && (
                                                        <div className="relative pl-12 mb-6 mt-8 first:mt-2">
                                                            <div className="absolute left-[14px] top-1/2 -translate-y-1/2 w-3 h-3 rounded-full bg-white dark:bg-slate-900 border-2 border-indigo-500 z-20" />
                                                            <div className="flex items-center gap-3">
                                                                <span className="text-lg font-black text-slate-900 dark:text-white">
                                                                    {currentDate.getFullYear()}년 {currentDate.getMonth() + 1}월
                                                                </span>
                                                                <div className="h-px flex-1 bg-gradient-to-r from-slate-200 dark:from-slate-800 to-transparent" />
                                                            </div>
                                                        </div>
                                                    )}
                                                    <div className="relative pl-12 group mb-6">
                                                        <div className="absolute left-0 top-1 w-10 h-10 rounded-2xl bg-white dark:bg-slate-900 border-2 border-slate-100 dark:border-slate-800 flex items-center justify-center z-10 transition-colors group-hover:border-indigo-500">
                                                            <div className="w-2 h-2 rounded-full bg-indigo-500" />
                                                        </div>
                                                        <div className="bg-slate-50/50 dark:bg-slate-900/40 border border-slate-100 dark:border-slate-800/40 rounded-3xl p-6 transition-all hover:border-indigo-100 dark:hover:border-indigo-500/20 hover:bg-white dark:hover:bg-slate-800 group-hover:shadow-lg group-hover:shadow-indigo-500/[0.02]">
                                                            <div className="flex items-center justify-between mb-4">
                                                                <div className="flex items-center gap-3">
                                                                    <span className="text-[10px] font-black text-indigo-600 dark:text-indigo-400 uppercase tracking-widest bg-indigo-50 dark:bg-indigo-500/10 px-2 py-1 rounded-lg border border-indigo-100 dark:border-indigo-500/20">
                                                                        {prayer.weeks?.name || (prayer.weeks?.week_date ? new Date(prayer.weeks.week_date).toLocaleDateString() : '날짜 미상')}
                                                                    </span>
                                                                    {/** Group Origin Indicator **/}
                                                                    {prayer.directory_member_id && member._affiliations?.find((a: any) => a.id === prayer.directory_member_id) && (
                                                                        <span className="text-[9px] font-black text-emerald-600 dark:text-emerald-400 uppercase tracking-tighter bg-emerald-50 dark:bg-emerald-500/10 px-2 py-0.5 rounded-md border border-emerald-100 dark:border-emerald-500/20">
                                                                            {member._affiliations.find((a: any) => a.id === prayer.directory_member_id).group_name} 조
                                                                        </span>
                                                                    )}
                                                                    <span className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">{prayer.updated_at ? new Date(prayer.updated_at).toLocaleDateString() : '-'}</span>
                                                                </div>
                                                                {prayer.ai_refined_content && (
                                                                    <div className="flex items-center gap-1.5 text-[9px] font-black text-violet-500 uppercase tracking-widest">
                                                                        <Sparkles className="w-3 h-3" />
                                                                        AI Refined
                                                                    </div>
                                                                )}
                                                            </div>
                                                            <div className="space-y-4">
                                                                <div className="space-y-2">
                                                                    <p className="text-[9px] font-black text-slate-300 uppercase tracking-widest">Original Content</p>
                                                                    <p className="text-sm font-bold text-slate-700 dark:text-slate-200 leading-relaxed">{prayer.content}</p>
                                                                </div>
                                                                {prayer.ai_refined_content && (
                                                                    <div className="pt-4 border-t border-slate-100 dark:border-slate-800/60 space-y-2">
                                                                        <p className="text-[9px] font-black text-violet-400 uppercase tracking-widest">AI 정리본</p>
                                                                        <p className="text-sm font-bold text-violet-600/80 dark:text-violet-400 leading-relaxed italic">{prayer.ai_refined_content}</p>
                                                                    </div>
                                                                )}
                                                            </div>
                                                        </div>
                                                    </div>
                                                </div>
                                            );
                                        })}
                                    </div>

                                    {hasMorePrayers && (
                                        <div className="mt-8 mb-4 flex justify-center">
                                            <button
                                                disabled={isPrayersLoading}
                                                onClick={() => setPage(prev => prev + 1)}
                                                className="px-6 py-3 bg-slate-50 dark:bg-slate-800/60 text-slate-500 dark:text-slate-400 text-xs font-black rounded-2xl border border-slate-100 dark:border-slate-700/50 hover:bg-indigo-50 dark:hover:bg-indigo-500/10 hover:text-indigo-600 transition-all flex items-center gap-2 group"
                                            >
                                                {isPrayersLoading ? (
                                                    <Loader2 className="w-4 h-4 animate-spin" />
                                                ) : (
                                                    <>
                                                        더 많은 기록 보기
                                                        <ChevronRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
                                                    </>
                                                )}
                                            </button>
                                        </div>
                                    )}

                                    {isPrayersLoading && page > 0 && (
                                        <div className="py-8 flex justify-center">
                                            <Loader2 className="w-6 h-6 text-indigo-500 animate-spin opacity-40" />
                                        </div>
                                    )}
                                </div>
                            )}
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
