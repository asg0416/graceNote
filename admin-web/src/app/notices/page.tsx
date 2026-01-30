'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Loader2,
    Megaphone,
    Plus,
    Trash2,
    Edit,
    Globe,
    Church,
    Layers,
    Clock,
    User,
    Pin
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { Modal } from '@/components/Modal';

function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}

export default function NoticesPage() {
    const [loading, setLoading] = useState(true);
    const [notices, setNotices] = useState<any[]>([]);
    const [profile, setProfile] = useState<any>(null);
    const [churches, setChurches] = useState<any[]>([]);
    const [departments, setDepartments] = useState<any[]>([]);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [isSubmitting, setIsSubmitting] = useState(false);

    // Form State
    const [editingId, setEditingId] = useState<string | null>(null);
    const [title, setTitle] = useState('');
    const [content, setContent] = useState('');
    const [category, setCategory] = useState('general');
    const [isGlobal, setIsGlobal] = useState(false);
    const [targetChurchId, setTargetChurchId] = useState('');
    const [targetDeptId, setTargetDeptId] = useState('');
    const [isPinned, setIsPinned] = useState(false);

    const router = useRouter();

    useEffect(() => {
        const checkUser = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                router.push('/login');
                return;
            }

            const { data: profileData } = await supabase
                .from('profiles')
                .select('id, full_name, role, admin_status, is_master, church_id, department_id')
                .eq('id', session.user.id)
                .single();

            if (!profileData || !(profileData.is_master || (profileData.role === 'admin' && profileData.admin_status === 'approved'))) {
                router.push('/login');
                return;
            }

            setProfile(profileData);
            if (!profileData.is_master) {
                setTargetChurchId(profileData.church_id || '');
            }

            await fetchData(profileData);
            setLoading(false);
        };

        checkUser();
    }, [router]);

    const fetchData = async (userProfile: any) => {
        try {
            // Fetch Notices
            let noticesQuery = supabase
                .from('notices')
                .select(`
                    *,
                    created_by_profile:profiles!created_by(full_name),
                    church:churches(name),
                    department:departments!department_id (name)
                `);

            if (userProfile.is_master) {
                // Master: Only see notices created by themselves
                noticesQuery = noticesQuery.eq('created_by', userProfile.id);
            } else {
                // General Admin: Only see notices for their department
                // If they have no department (e.g. church-wide admin but not master?), fallback to church_id match
                if (userProfile.department_id) {
                    noticesQuery = noticesQuery.eq('department_id', userProfile.department_id);
                } else {
                    noticesQuery = noticesQuery.eq('church_id', userProfile.church_id);
                }
            }

            const { data: noticesData } = await noticesQuery
                .order('is_pinned', { ascending: false })
                .order('created_at', { ascending: false });

            setNotices(noticesData || []);

            // Fetch Churches (for Master)
            if (userProfile.is_master) {
                const { data: churchesData } = await supabase.from('churches').select('id, name');
                setChurches(churchesData || []);
            }

            // Fetch Departments
            let deptQuery = supabase.from('departments').select('id, name, church_id');
            if (!userProfile.is_master) {
                deptQuery = deptQuery.eq('church_id', userProfile.church_id);
                if (userProfile.department_id) {
                    deptQuery = deptQuery.eq('id', userProfile.department_id);
                }
            }
            const { data: deptsData } = await deptQuery;
            setDepartments(deptsData || []);

        } catch (err) {
            console.error('Data Fetch Error:', err);
        }
    };

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!title || !content) return;

        setIsSubmitting(true);
        try {
            const payload: any = {
                title,
                content,
                category,
                is_global: profile.is_master ? isGlobal : false,
                church_id: profile.is_master ? (targetChurchId || null) : profile.church_id,
                department_id: targetDeptId || null,
                created_by: profile.id,
                is_pinned: isPinned
            };

            if (editingId) {
                const { error } = await supabase.from('notices').update(payload).eq('id', editingId);
                if (error) throw error;
            } else {
                const { error } = await supabase.from('notices').insert([payload]);
                if (error) throw error;
            }

            await fetchData(profile);
            closeModal();
        } catch (err) {
            console.error('Submit Error:', err);
            alert('저장에 실패했습니다.');
        } finally {
            setIsSubmitting(false);
        }
    };

    const handleDelete = async (id: string) => {
        if (!confirm('정말 삭제하시겠습니까?')) return;
        try {
            const { error } = await supabase.from('notices').delete().eq('id', id);
            if (error) throw error;
            await fetchData(profile);
        } catch (err) {
            console.error('Delete Error:', err);
        }
    };

    const openModal = (notice?: any) => {
        if (notice) {
            setEditingId(notice.id);
            setTitle(notice.title);
            setContent(notice.content);
            setCategory(notice.category || 'general');
            setIsGlobal(notice.is_global || false);
            setTargetChurchId(notice.church_id || '');
            setTargetDeptId(notice.department_id || '');
            setIsPinned(notice.is_pinned || false);
        } else {
            setEditingId(null);
            setTitle('');
            setContent('');
            setCategory('general');
            setIsGlobal(false);
            setTargetChurchId(profile.is_master ? '' : (profile.church_id || ''));
            setTargetDeptId(profile.department_id || '');
            setIsPinned(false);
        }
        setIsModalOpen(true);
    };

    const closeModal = () => {
        setIsModalOpen(false);
        setEditingId(null);
    };

    if (loading) {
        return (
            <div className="h-[80vh] flex flex-col items-center justify-center gap-4">
                <Loader2 className="w-10 h-10 text-indigo-600 animate-spin" />
                <p className="text-slate-400 font-bold text-xs uppercase tracking-widest">공지사항 로딩 중...</p>
            </div>
        );
    }

    return (
        <div className="space-y-8 max-w-7xl mx-auto pb-20">
            <header className="flex flex-col md:flex-row md:items-center justify-between gap-6 px-2">
                <div className="space-y-2">
                    <div className="inline-flex items-center gap-2 px-3 py-1 bg-indigo-50 dark:bg-indigo-500/10 border border-indigo-100 dark:border-indigo-500/20 rounded-full">
                        <Megaphone className="w-3.5 h-3.5 text-indigo-600 dark:text-indigo-400" />
                        <span className="text-[10px] font-black text-indigo-600 dark:text-indigo-400 uppercase tracking-widest">커뮤니케이션</span>
                    </div>
                    <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">공지사항 관리</h1>
                    <p className="text-slate-500 font-bold text-xs sm:text-sm tracking-tight">전체, 교회, 부서별 공지사항을 발행하고 관리합니다.</p>
                </div>
                <button
                    onClick={() => openModal()}
                    className="flex items-center justify-center gap-2 px-6 py-4 bg-indigo-600 text-white rounded-2xl font-black text-sm hover:scale-105 active:scale-95 transition-all shadow-xl shadow-indigo-500/20"
                >
                    <Plus className="w-5 h-5" />
                    새 공지사항 작성
                </button>
            </header>

            {/* Notices List */}
            <div className="grid grid-cols-1 gap-6 px-2">
                {notices.length === 0 ? (
                    <div className="bg-white dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800 rounded-[32px] p-20 text-center space-y-4">
                        <div className="w-20 h-20 bg-slate-50 dark:bg-slate-800 rounded-full flex items-center justify-center mx-auto">
                            <Megaphone className="w-10 h-10 text-slate-300" />
                        </div>
                        <p className="text-slate-400 font-bold">등록된 공지사항이 없습니다.</p>
                    </div>
                ) : (
                    notices.map((notice) => (
                        <div key={notice.id} className="group bg-white dark:bg-[#111827]/60 backdrop-blur-xl border border-slate-200 dark:border-slate-800/60 rounded-[32px] p-6 sm:p-8 hover:border-indigo-500/50 transition-all duration-300 shadow-sm hover:shadow-2xl">
                            <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-6">
                                <div className="space-y-4 flex-1">
                                    <div className="flex flex-wrap items-center gap-2">
                                        {notice.is_global && (
                                            <span className="px-2.5 py-1 bg-rose-500 text-white text-[9px] font-black rounded-lg uppercase tracking-widest flex items-center gap-1">
                                                <Globe className="w-3 h-3" /> 전체
                                            </span>
                                        )}
                                        {notice.church && (
                                            <span className="px-2.5 py-1 bg-indigo-500 text-white text-[9px] font-black rounded-lg uppercase tracking-widest flex items-center gap-1">
                                                <Church className="w-3 h-3" /> {notice.church.name}
                                            </span>
                                        )}
                                        {notice.department && (
                                            <span className="px-2.5 py-1 bg-emerald-500 text-white text-[9px] font-black rounded-lg uppercase tracking-widest flex items-center gap-1">
                                                <Layers className="w-3 h-3" /> {notice.department.name}
                                            </span>
                                        )}
                                        <span className="px-2.5 py-1 bg-slate-100 dark:bg-slate-800 text-slate-500 dark:text-slate-400 text-[9px] font-black rounded-lg uppercase tracking-widest">
                                            {notice.category === 'general' ? '일반' : notice.category === 'event' ? '행사' : '긴급'}
                                        </span>
                                        {notice.is_pinned && (
                                            <span className="px-2.5 py-1 bg-amber-500 text-white text-[9px] font-black rounded-lg uppercase tracking-widest flex items-center gap-1">
                                                <Pin className="w-3 h-3" /> 상단 고정
                                            </span>
                                        )}
                                    </div>

                                    <h3 className="text-xl sm:text-2xl font-black text-slate-900 dark:text-white group-hover:text-indigo-600 transition-colors tracking-tight leading-tight">
                                        {notice.title}
                                    </h3>

                                    <div className="text-slate-600 dark:text-slate-400 font-medium text-sm sm:text-base leading-relaxed line-clamp-2">
                                        {notice.content}
                                    </div>

                                    <div className="flex items-center gap-4 pt-2">
                                        <div className="flex items-center gap-1.5 text-slate-400">
                                            <User className="w-3.5 h-3.5" />
                                            <span className="text-xs font-bold">
                                                {notice.is_global ? 'GraceNote 관리자' : (notice.created_by_profile?.full_name || 'GraceNote 관리자')}
                                            </span>
                                        </div>
                                        <div className="flex items-center gap-1.5 text-slate-400 border-l border-slate-200 dark:border-slate-800 pl-4">
                                            <Clock className="w-3.5 h-3.5" />
                                            <span className="text-xs font-bold">{new Date(notice.created_at).toLocaleDateString()}</span>
                                        </div>
                                    </div>
                                </div>



                                {profile?.id === notice.created_by && (
                                    <div className="flex sm:flex-col gap-2 shrink-0">
                                        <button
                                            onClick={() => openModal(notice)}
                                            className="flex-1 sm:flex-none p-3 bg-slate-50 dark:bg-slate-800 text-slate-400 hover:text-indigo-600 dark:hover:text-white hover:bg-indigo-50 dark:hover:bg-indigo-600/20 rounded-2xl transition-all border border-transparent hover:border-indigo-500/30"
                                        >
                                            <Edit className="w-5 h-5" />
                                        </button>
                                        <button
                                            onClick={() => handleDelete(notice.id)}
                                            className="flex-1 sm:flex-none p-3 bg-slate-50 dark:bg-slate-800 text-slate-400 hover:text-rose-600 dark:hover:text-white hover:bg-rose-50 dark:hover:bg-rose-600/20 rounded-2xl transition-all border border-transparent hover:border-rose-500/30"
                                        >
                                            <Trash2 className="w-5 h-5" />
                                        </button>
                                    </div>
                                )}
                            </div>
                        </div>
                    ))
                )}
            </div>

            {/* Modal */}
            {
                isModalOpen && (
                    <Modal
                        isOpen={isModalOpen}
                        onClose={closeModal}
                        title={editingId ? '공지사항 수정' : '새 공지사항 작성'}
                        subtitle="대상과 카테고리를 설정하여 정보를 전달하세요."
                        maxWidth="4xl"
                    >
                        <form id="notice-form" onSubmit={handleSubmit} className="space-y-8">
                            <div className="space-y-6">
                                {/* Title */}
                                <div className="space-y-3">
                                    <label className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em] pl-1">제목</label>
                                    <input
                                        type="text"
                                        value={title}
                                        onChange={(e) => setTitle(e.target.value)}
                                        placeholder="공지사항 제목을 입력하세요"
                                        className="w-full p-5 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20 text-slate-900 dark:text-white"
                                        required
                                    />
                                </div>

                                {/* Content */}
                                <div className="space-y-3">
                                    <label className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em] pl-1">내용</label>
                                    <textarea
                                        value={content}
                                        onChange={(e) => setContent(e.target.value)}
                                        placeholder="공지사항 상세 내용을 입력하세요"
                                        className="w-full h-64 p-5 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20 text-slate-900 dark:text-white resize-none"
                                        required
                                    />
                                </div>

                                {/* Pinned Toggle */}
                                <div className="space-y-3">
                                    <label className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em] pl-1">상단 고정 여부</label>
                                    <div
                                        onClick={() => setIsPinned(!isPinned)}
                                        className={cn(
                                            "w-full p-5 rounded-2xl font-black text-sm flex items-center justify-between cursor-pointer transition-all",
                                            isPinned ? "bg-amber-500 text-white shadow-lg shadow-amber-500/20" : "bg-slate-100 dark:bg-slate-800 text-slate-400"
                                        )}
                                    >
                                        <div className="flex items-center gap-3">
                                            <Pin className={cn("w-4 h-4", isPinned ? "text-white" : "text-slate-400")} />
                                            <span>{isPinned ? '상단 고정됨' : '일반 공지'}</span>
                                        </div>
                                        <div className={cn("w-10 h-5 rounded-full relative transition-colors", isPinned ? "bg-white/30" : "bg-slate-300 dark:bg-slate-700")}>
                                            <div className={cn("absolute top-1 w-3 h-3 bg-white rounded-full transition-all", isPinned ? "left-6" : "left-1")} />
                                        </div>
                                    </div>
                                </div>

                                <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
                                    {/* Category */}
                                    <div className="space-y-3">
                                        <label className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em] pl-1">카테고리</label>
                                        <select
                                            value={category}
                                            onChange={(e) => setCategory(e.target.value)}
                                            className="w-full p-5 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20 text-slate-900 dark:text-white appearance-none"
                                        >
                                            <option value="general">일반</option>
                                            <option value="event">행사</option>
                                            <option value="urgent">긴급</option>
                                        </select>
                                    </div>

                                    {/* Global Toggle (Master Only) */}
                                    {profile.is_master && (
                                        <div className="space-y-3">
                                            <label className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em] pl-1">전체 공지 여부</label>
                                            <div
                                                onClick={() => setIsGlobal(!isGlobal)}
                                                className={cn(
                                                    "w-full p-5 rounded-2xl font-black text-sm flex items-center justify-between cursor-pointer transition-all",
                                                    isGlobal ? "bg-rose-500 text-white shadow-lg shadow-rose-500/20" : "bg-slate-100 dark:bg-slate-800 text-slate-400"
                                                )}
                                            >
                                                <span>{isGlobal ? '전체 서비스 공지' : '특정 대상 설정'}</span>
                                                <div className={cn("w-10 h-5 rounded-full relative transition-colors", isGlobal ? "bg-white/30" : "bg-slate-300 dark:bg-slate-700")}>
                                                    <div className={cn("absolute top-1 w-3 h-3 bg-white rounded-full transition-all", isGlobal ? "left-6" : "left-1")} />
                                                </div>
                                            </div>
                                        </div>
                                    )}
                                </div>

                                {!isGlobal && (
                                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-6 pt-2">
                                        {/* Target Church */}
                                        <div className="space-y-3">
                                            <label className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em] pl-1">공지 대상 교회</label>
                                            <select
                                                value={targetChurchId}
                                                onChange={(e) => setTargetChurchId(e.target.value)}
                                                disabled={!profile.is_master}
                                                className="w-full p-5 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20 text-slate-900 dark:text-white appearance-none disabled:opacity-50"
                                            >
                                                <option value="">선택 안함</option>
                                                {churches.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                                            </select>
                                        </div>

                                        {/* Target Department */}
                                        <div className="space-y-3">
                                            <label className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em] pl-1">공지 대상 부서</label>
                                            <select
                                                value={targetDeptId}
                                                onChange={(e) => setTargetDeptId(e.target.value)}
                                                className="w-full p-5 bg-slate-100 dark:bg-slate-800 rounded-2xl font-bold border-none outline-none focus:ring-2 focus:ring-indigo-500/20 text-slate-900 dark:text-white appearance-none"
                                            >
                                                <option value="">전체 (부서 설정 안함)</option>
                                                {departments
                                                    .filter(d => !targetChurchId || d.church_id === targetChurchId)
                                                    .map(d => <option key={d.id} value={d.id}>{d.name}</option>)
                                                }
                                            </select>
                                        </div>
                                    </div>
                                )}
                            </div>

                            <div className="pt-8 border-t border-slate-100 dark:border-slate-800">
                                <button
                                    type="submit"
                                    disabled={isSubmitting}
                                    className="w-full py-6 bg-indigo-600 text-white rounded-[24px] font-black hover:bg-indigo-700 transition-all hover:scale-[1.02] active:scale-[0.98] flex items-center justify-center gap-3 shadow-2xl shadow-indigo-500/30 disabled:opacity-50"
                                >
                                    {isSubmitting ? <Loader2 className="w-6 h-6 animate-spin" /> : <Megaphone className="w-6 h-6" />}
                                    공지사항 {editingId ? '수정 완료' : '발행하기'}
                                </button>
                            </div>
                        </form>
                    </Modal>
                )
            }
        </div >
    );
}
