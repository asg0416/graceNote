'use client';

import { useState, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import RichTextEditor from '@/components/RichTextEditor';
import {
    Loader2,
    Megaphone,
    ArrowLeft,
    Pin,
    Globe,
    Church,
    Layers,
    Check,
    ChevronDown,
    X,
    AlertCircle
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}

// --- Multi-Select Dropdown Component ---
interface MultiSelectOption {
    id: string;
    label: string;
    sublabel?: string;
}

function MultiSelectDropdown({
    options,
    selected,
    onChange,
    placeholder,
    disabled = false,
    icon,
}: {
    options: MultiSelectOption[];
    selected: string[];
    onChange: (ids: string[]) => void;
    placeholder: string;
    disabled?: boolean;
    icon?: React.ReactNode;
}) {
    const [open, setOpen] = useState(false);
    const ref = useRef<HTMLDivElement>(null);

    useEffect(() => {
        const handler = (e: MouseEvent) => {
            if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
        };
        document.addEventListener('mousedown', handler);
        return () => document.removeEventListener('mousedown', handler);
    }, []);

    const toggle = (id: string) => {
        onChange(selected.includes(id) ? selected.filter(s => s !== id) : [...selected, id]);
    };

    const removeTag = (id: string, e: React.MouseEvent) => {
        e.stopPropagation();
        onChange(selected.filter(s => s !== id));
    };

    const selectedLabels = selected.map(id => options.find(o => o.id === id)).filter(Boolean) as MultiSelectOption[];

    return (
        <div ref={ref} className="relative">
            <div
                onClick={() => !disabled && setOpen(!open)}
                className={cn(
                    "w-full min-h-[42px] px-3 py-2 rounded-xl border text-sm font-bold flex items-center gap-2 cursor-pointer transition-all",
                    disabled
                        ? "bg-slate-100 dark:bg-slate-800/60 border-slate-200 dark:border-slate-700 cursor-default opacity-70"
                        : open
                            ? "bg-white dark:bg-slate-900/60 border-indigo-400 ring-2 ring-indigo-500/10"
                            : "bg-white dark:bg-slate-900/40 border-slate-200 dark:border-slate-800 hover:border-slate-300"
                )}
            >
                {icon && <span className="shrink-0">{icon}</span>}
                <div className="flex-1 flex flex-wrap gap-1.5 min-w-0">
                    {selectedLabels.length === 0 ? (
                        <span className="text-slate-400 text-sm">{placeholder}</span>
                    ) : (
                        selectedLabels.map(opt => (
                            <span key={opt.id} className="inline-flex items-center gap-1 px-2 py-0.5 bg-indigo-50 dark:bg-indigo-500/10 text-indigo-700 dark:text-indigo-300 text-xs font-bold rounded-md border border-indigo-100 dark:border-indigo-500/20">
                                {opt.label}
                                {!disabled && (
                                    <X className="w-3 h-3 cursor-pointer hover:text-rose-500 transition-colors" onClick={(e) => removeTag(opt.id, e)} />
                                )}
                            </span>
                        ))
                    )}
                </div>
                {!disabled && <ChevronDown className={cn("w-4 h-4 text-slate-400 shrink-0 transition-transform", open && "rotate-180")} />}
            </div>

            {open && !disabled && (
                <div className="absolute z-50 mt-1 w-full bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl shadow-xl max-h-60 overflow-y-auto">
                    {options.length === 0 ? (
                        <div className="px-4 py-3 text-sm text-slate-400 font-bold">항목이 없습니다</div>
                    ) : (
                        options.map(opt => {
                            const isSelected = selected.includes(opt.id);
                            return (
                                <div
                                    key={opt.id}
                                    onClick={() => toggle(opt.id)}
                                    className={cn(
                                        "px-4 py-2.5 flex items-center gap-3 cursor-pointer transition-colors text-sm font-bold",
                                        isSelected
                                            ? "bg-indigo-50 dark:bg-indigo-500/10 text-indigo-700 dark:text-indigo-300"
                                            : "text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800"
                                    )}
                                >
                                    <div className={cn(
                                        "w-4 h-4 rounded border-2 flex items-center justify-center shrink-0 transition-all",
                                        isSelected ? "bg-indigo-600 border-indigo-600" : "border-slate-300 dark:border-slate-600"
                                    )}>
                                        {isSelected && <Check className="w-3 h-3 text-white" />}
                                    </div>
                                    <span className="flex-1">{opt.label}</span>
                                    {opt.sublabel && <span className="text-xs text-slate-400">{opt.sublabel}</span>}
                                </div>
                            );
                        })
                    )}
                </div>
            )}
        </div>
    );
}

// --- Main Form ---
interface NoticeFormProps {
    noticeId?: string;
}

export default function NoticeForm({ noticeId }: NoticeFormProps) {
    const router = useRouter();
    const [loading, setLoading] = useState(true);
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [profile, setProfile] = useState<any>(null);
    const [churches, setChurches] = useState<any[]>([]);
    const [allDepartments, setAllDepartments] = useState<any[]>([]);

    const [title, setTitle] = useState('');
    const [content, setContent] = useState('');
    const [category, setCategory] = useState('general');
    const [isPinned, setIsPinned] = useState(false);
    const [isGlobal, setIsGlobal] = useState(false);
    const [selectedChurchIds, setSelectedChurchIds] = useState<string[]>([]);
    const [selectedDeptIds, setSelectedDeptIds] = useState<string[]>([]);

    const isEditing = !!noticeId;

    // Validation
    const needsChurch = profile?.is_master && !isGlobal && selectedChurchIds.length === 0;
    const canSubmit = !!title && !!content && !needsChurch;

    useEffect(() => {
        const init = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) { router.push('/login'); return; }

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

            if (profileData.is_master) {
                const { data: churchesData } = await supabase.from('churches').select('id, name');
                setChurches(churchesData || []);
            }

            let deptQuery = supabase.from('departments').select('id, name, church_id').eq('is_active', true);
            if (!profileData.is_master) {
                deptQuery = deptQuery.eq('church_id', profileData.church_id);
            }
            const { data: deptsData } = await deptQuery;
            setAllDepartments(deptsData || []);

            if (noticeId) {
                const { data: notice } = await supabase.from('notices').select('*').eq('id', noticeId).single();
                if (notice) {
                    setTitle(notice.title);
                    setContent(notice.content);
                    setCategory(notice.category || 'general');
                    setIsPinned(notice.is_pinned || false);
                    setIsGlobal(notice.is_global || false);
                    if (notice.target_church_ids?.length) setSelectedChurchIds(notice.target_church_ids);
                    else if (notice.church_id) setSelectedChurchIds([notice.church_id]);
                    if (notice.target_department_ids?.length) setSelectedDeptIds(notice.target_department_ids);
                    else if (notice.department_id) setSelectedDeptIds([notice.department_id]);
                }
            } else if (!profileData.is_master) {
                if (profileData.church_id) setSelectedChurchIds([profileData.church_id]);
                if (profileData.department_id) setSelectedDeptIds([profileData.department_id]);
            }

            setLoading(false);
        };
        init();
    }, [noticeId, router]);

    const filteredDepartments = allDepartments.filter(
        d => selectedChurchIds.length === 0 || selectedChurchIds.includes(d.church_id)
    );

    useEffect(() => {
        const validDeptIds = new Set(filteredDepartments.map(d => d.id));
        setSelectedDeptIds(prev => prev.filter(id => validDeptIds.has(id)));
    }, [selectedChurchIds, allDepartments]);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!canSubmit) return;

        setIsSubmitting(true);
        try {
            const payload: any = {
                title,
                content,
                category,
                is_pinned: isPinned,
                is_global: profile.is_master ? isGlobal : false,
                created_by: profile.id,
                church_id: selectedChurchIds[0] || (profile.is_master ? null : profile.church_id),
                department_id: selectedDeptIds[0] || null,
                target_church_ids: profile.is_master && !isGlobal ? selectedChurchIds : [],
                target_department_ids: profile.is_master && !isGlobal ? selectedDeptIds : [],
            };

            if (!profile.is_master) {
                payload.church_id = profile.church_id;
                payload.department_id = profile.department_id || null;
                payload.target_church_ids = [];
                payload.target_department_ids = [];
            }

            if (isEditing) {
                const { error } = await supabase.from('notices').update(payload).eq('id', noticeId);
                if (error) throw error;
            } else {
                const { error } = await supabase.from('notices').insert([payload]);
                if (error) throw error;
            }

            router.push('/notices');
        } catch (err) {
            console.error('Submit Error:', err);
            alert('저장에 실패했습니다.');
        } finally {
            setIsSubmitting(false);
        }
    };

    const churchOptions: MultiSelectOption[] = churches.map(c => ({ id: c.id, label: c.name }));
    const deptOptions: MultiSelectOption[] = filteredDepartments.map(d => ({
        id: d.id,
        label: d.name,
        sublabel: churches.length > 1 ? churches.find(c => c.id === d.church_id)?.name : undefined,
    }));

    if (loading) {
        return (
            <div className="h-[80vh] flex flex-col items-center justify-center gap-4">
                <Loader2 className="w-10 h-10 text-indigo-600 animate-spin" />
                <p className="text-slate-400 font-bold text-xs uppercase tracking-widest">
                    {isEditing ? '공지사항 로딩 중...' : '준비 중...'}
                </p>
            </div>
        );
    }

    return (
        <div className="max-w-7xl mx-auto pb-20">
            {/* Header with Submit Button */}
            <header className="flex items-center gap-4 mb-8 px-2">
                <button
                    onClick={() => router.push('/notices')}
                    className="p-2 rounded-xl text-slate-400 hover:text-indigo-600 hover:bg-indigo-50 dark:hover:bg-indigo-500/10 transition-all"
                >
                    <ArrowLeft className="w-5 h-5" />
                </button>
                <div className="flex-1">
                    <h1 className="text-2xl font-black text-slate-900 dark:text-white tracking-tight">
                        {isEditing ? '공지사항 수정' : '새 공지사항 작성'}
                    </h1>
                    <p className="text-xs font-bold text-slate-400 mt-0.5">대상과 내용을 설정하여 공지사항을 발행합니다.</p>
                </div>
                <button
                    onClick={handleSubmit as any}
                    disabled={isSubmitting || !canSubmit}
                    className="px-6 py-2.5 bg-indigo-600 text-white rounded-xl font-black text-sm hover:bg-indigo-700 transition-all flex items-center gap-2 shadow-lg shadow-indigo-500/20 disabled:opacity-40 disabled:cursor-not-allowed"
                >
                    {isSubmitting ? <Loader2 className="w-4 h-4 animate-spin" /> : <Megaphone className="w-4 h-4" />}
                    {isEditing ? '수정 완료' : '발행하기'}
                </button>
            </header>

            <form onSubmit={handleSubmit} className="px-2">
                <div className="flex flex-col lg:flex-row gap-6">
                    {/* ===== Left: Main Content (65~70%) ===== */}
                    <div className="flex-1 lg:basis-[65%] space-y-5 min-w-0">
                        {/* Title */}
                        <div className="space-y-2">
                            <label className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em] px-1">제목 <span className="text-rose-400">*</span></label>
                            <input
                                type="text"
                                value={title}
                                onChange={(e) => setTitle(e.target.value)}
                                placeholder="공지사항 제목을 입력하세요"
                                className="w-full px-5 py-4 bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800 rounded-2xl font-black text-lg outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400 text-slate-900 dark:text-white transition-all placeholder:text-slate-300 placeholder:font-bold"
                                required
                            />
                        </div>

                        {/* Content */}
                        <div className="space-y-2">
                            <label className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em] px-1">내용 <span className="text-rose-400">*</span></label>
                            <div className="[&_.ProseMirror]:min-h-[60vh]">
                                <RichTextEditor
                                    content={content}
                                    onChange={setContent}
                                    placeholder="공지사항 내용을 입력하세요..."
                                />
                            </div>
                        </div>
                    </div>

                    {/* ===== Right: Sidebar (30~35%) ===== */}
                    <div className="lg:basis-[35%] lg:max-w-[380px] space-y-5">
                        {/* Card: Category */}
                        <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800 rounded-2xl p-5 space-y-3 shadow-sm">
                            <div className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em]">카테고리</div>
                            <div className="flex gap-1.5">
                                {[
                                    { value: 'general', label: '일반' },
                                    { value: 'event', label: '행사' },
                                    { value: 'urgent', label: '긴급' },
                                ].map(opt => (
                                    <button
                                        key={opt.value}
                                        type="button"
                                        onClick={() => setCategory(opt.value)}
                                        className={cn(
                                            "flex-1 py-2 rounded-lg font-bold text-xs transition-all",
                                            category === opt.value
                                                ? "bg-indigo-600 text-white shadow-sm"
                                                : "bg-slate-50 dark:bg-slate-800/60 text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 border border-slate-200 dark:border-slate-700"
                                        )}
                                    >
                                        {opt.label}
                                    </button>
                                ))}
                            </div>
                        </div>

                        {/* Card: Target */}
                        <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800 rounded-2xl p-5 space-y-4 shadow-sm">
                            <div className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em]">공지 대상</div>

                            {/* Global Toggle (Master only) */}
                            {profile.is_master && (
                                <div
                                    onClick={() => setIsGlobal(!isGlobal)}
                                    className={cn(
                                        "py-2.5 px-3 rounded-lg font-bold text-xs flex items-center justify-between cursor-pointer transition-all border",
                                        isGlobal
                                            ? "bg-rose-50 dark:bg-rose-500/10 text-rose-700 dark:text-rose-400 border-rose-200 dark:border-rose-500/20"
                                            : "bg-slate-50 dark:bg-slate-800/60 text-slate-500 border-slate-200 dark:border-slate-700"
                                    )}
                                >
                                    <div className="flex items-center gap-2">
                                        <Globe className="w-3.5 h-3.5" />
                                        <span>{isGlobal ? '전체 공지' : '특정 대상'}</span>
                                    </div>
                                    <div className={cn("w-8 h-4 rounded-full relative transition-colors", isGlobal ? "bg-rose-400" : "bg-slate-300 dark:bg-slate-600")}>
                                        <div className={cn("absolute top-0.5 w-3 h-3 bg-white rounded-full transition-all shadow-sm", isGlobal ? "left-4" : "left-0.5")} />
                                    </div>
                                </div>
                            )}

                            {!isGlobal && (
                                <div className="space-y-3">
                                    {/* Church */}
                                    <div className="space-y-1.5">
                                        <label className="text-xs font-bold text-slate-500 flex items-center gap-1.5">
                                            <Church className="w-3.5 h-3.5 text-indigo-500" />
                                            교회
                                            {profile.is_master && <span className="text-rose-400">*</span>}
                                        </label>
                                        {profile.is_master ? (
                                            <>
                                                <MultiSelectDropdown
                                                    options={churchOptions}
                                                    selected={selectedChurchIds}
                                                    onChange={setSelectedChurchIds}
                                                    placeholder="교회를 선택하세요"
                                                    icon={<Church className="w-3.5 h-3.5 text-slate-400" />}
                                                />
                                                {needsChurch && (
                                                    <p className="text-xs font-bold text-rose-500 flex items-center gap-1 mt-1">
                                                        <AlertCircle className="w-3 h-3" />
                                                        교회를 선택해주세요.
                                                    </p>
                                                )}
                                            </>
                                        ) : (
                                            <AdminFixedField profileId={profile.church_id} tableName="churches" />
                                        )}
                                    </div>

                                    {/* Departments */}
                                    {(profile.is_master ? selectedChurchIds.length > 0 : true) && (
                                        <div className="space-y-1.5">
                                            <label className="text-xs font-bold text-slate-500 flex items-center gap-1.5">
                                                <Layers className="w-3.5 h-3.5 text-emerald-500" />
                                                부서
                                                {profile.is_master && (
                                                    <span className="text-[10px] font-bold text-slate-300 ml-1">선택사항</span>
                                                )}
                                            </label>
                                            {profile.is_master ? (
                                                <MultiSelectDropdown
                                                    options={deptOptions}
                                                    selected={selectedDeptIds}
                                                    onChange={setSelectedDeptIds}
                                                    placeholder="미선택 시 교회 전체 대상"
                                                    icon={<Layers className="w-3.5 h-3.5 text-slate-400" />}
                                                />
                                            ) : (
                                                <AdminFixedField profileId={profile.department_id} tableName="departments" />
                                            )}
                                        </div>
                                    )}
                                </div>
                            )}
                        </div>

                        {/* Card: Pin */}
                        <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800 rounded-2xl p-5 shadow-sm">
                            <div
                                onClick={() => setIsPinned(!isPinned)}
                                className={cn(
                                    "py-2.5 px-3 rounded-lg font-bold text-xs flex items-center justify-between cursor-pointer transition-all border",
                                    isPinned
                                        ? "bg-amber-50 dark:bg-amber-500/10 text-amber-700 dark:text-amber-400 border-amber-200 dark:border-amber-500/20"
                                        : "bg-slate-50 dark:bg-slate-800/60 text-slate-400 border-slate-200 dark:border-slate-700"
                                )}
                            >
                                <div className="flex items-center gap-2">
                                    <Pin className="w-3.5 h-3.5" />
                                    <span>{isPinned ? '상단 고정됨' : '상단 고정 안함'}</span>
                                </div>
                                <div className={cn("w-8 h-4 rounded-full relative transition-colors", isPinned ? "bg-amber-400" : "bg-slate-300 dark:bg-slate-600")}>
                                    <div className={cn("absolute top-0.5 w-3 h-3 bg-white rounded-full transition-all shadow-sm", isPinned ? "left-4" : "left-0.5")} />
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </form>
        </div>
    );
}

function AdminFixedField({ profileId, tableName }: { profileId: string | null; tableName: string }) {
    const [name, setName] = useState('');

    useEffect(() => {
        if (!profileId) {
            setName(tableName === 'departments' ? '전체 (부서 미지정)' : '미지정');
            return;
        }
        supabase.from(tableName).select('name').eq('id', profileId).single()
            .then(({ data }) => setName(data?.name || ''));
    }, [profileId, tableName]);

    return (
        <div className="px-3 py-2.5 bg-slate-50 dark:bg-slate-800/60 rounded-xl font-bold text-sm text-slate-600 dark:text-slate-300 border border-slate-200 dark:border-slate-700 flex items-center gap-2">
            <span>{name || '...'}</span>
            <span className="ml-auto text-[9px] font-black text-slate-400 bg-slate-100 dark:bg-slate-700 px-1.5 py-0.5 rounded">고정</span>
        </div>
    );
}
