'use client';

import { useState, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import RichTextEditor from '@/components/RichTextEditor';
import DOMPurify from 'dompurify';
import SurveyBuilder, { type SurveyQuestion } from './SurveyBuilder';
import {
    Loader2, MonitorSmartphone, ArrowLeft, Bell, RefreshCw, Star,
    Smartphone, AlertCircle, ExternalLink, Code, Image as ImageIcon,
    Plus, Trash2, X, Upload,
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) { return twMerge(clsx(inputs)); }

// ── 상수 ────────────────────────────────────────────────────────────

const TYPE_OPTIONS = [
    { value: 'announcement', label: '공지',      Icon: Bell,       color: '#8B5CF6' },
    { value: 'update',       label: '업데이트',  Icon: RefreshCw,  color: '#0EA5E9' },
    { value: 'survey',       label: '만족도 조사', Icon: Star,      color: '#F59E0B' },
] as const;

const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif'];
const MAX_IMAGE_SIZE = 5 * 1024 * 1024; // 5MB

// ── 타입 ────────────────────────────────────────────────────────────

interface IamSlide { title: string; body: string; image_url: string; }

interface IamFormData {
    title: string;
    body: string;
    image_url: string;
    use_slides: boolean;
    slides: IamSlide[];
    type: 'announcement' | 'update' | 'survey';
    display_type: 'slide_up' | 'modal';
    target_role: 'all' | 'leader' | 'member';
    cta_label: string;
    cta_url: string;
    starts_at: string;
    expires_at: string;
    is_active: boolean;
    priority: number;
    target_scope: 'global' | 'church' | 'department';
    target_church_id: string;
    department_id: string;
    survey_questions: SurveyQuestion[];
    image_only: boolean;
}

const DEFAULT: IamFormData = {
    title: '', body: '', image_url: '',
    use_slides: false,
    slides: [{ title: '', body: '', image_url: '' }],
    type: 'announcement', display_type: 'slide_up', target_role: 'all',
    cta_label: '', cta_url: '',
    starts_at: new Date().toISOString().slice(0, 16),
    expires_at: '', is_active: true, priority: 0,
    target_scope: 'church',
    target_church_id: '',
    department_id: '',
    survey_questions: [],
    image_only: false,
};

// ── HTML 토글 에디터 ────────────────────────────────────────────────

function HtmlToggleEditor({ content, onChange, placeholder }: {
    content: string;
    onChange: (v: string) => void;
    placeholder?: string;
}) {
    const [htmlMode, setHtmlMode] = useState(false);
    return (
        <div className="relative">
            <button
                type="button"
                onClick={() => setHtmlMode(m => !m)}
                title={htmlMode ? 'WYSIWYG 모드' : 'HTML 소스 편집'}
                className={cn(
                    "absolute top-2 right-2 z-20 flex items-center gap-1.5 px-2 py-1 rounded-lg text-[10px] font-black transition-all",
                    htmlMode
                        ? "bg-violet-600 text-white"
                        : "bg-slate-100 dark:bg-slate-800 text-slate-500 hover:text-violet-600"
                )}
            >
                <Code size={11} />
                HTML
            </button>
            {htmlMode ? (
                <textarea
                    value={content}
                    onChange={e => onChange(e.target.value)}
                    placeholder={placeholder ?? ''}
                    className="w-full min-h-[140px] px-4 py-3 pt-10 bg-slate-900 text-emerald-400 font-mono text-xs border border-slate-700 rounded-2xl focus:outline-none focus:ring-2 focus:ring-violet-500/30 resize-y"
                />
            ) : (
                <div className="pt-1">
                    <RichTextEditor content={content} onChange={onChange} placeholder={placeholder} />
                </div>
            )}
        </div>
    );
}

// ── 이미지 업로더 ────────────────────────────────────────────────────

function ImageUploader({ value, onChange, label = '이미지 첨부 (선택)' }: {
    value: string;
    onChange: (url: string) => void;
    label?: string;
}) {
    const [uploading, setUploading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const inputRef = useRef<HTMLInputElement>(null);

    const upload = async (file: File) => {
        setError(null);
        if (!ALLOWED_IMAGE_TYPES.includes(file.type)) {
            setError('JPG, PNG, WebP, GIF만 업로드 가능합니다.');
            return;
        }
        if (file.size > MAX_IMAGE_SIZE) {
            setError('파일 크기는 5MB 이하여야 합니다.');
            return;
        }
        setUploading(true);
        try {
            const ext = file.name.split('.').pop() ?? 'jpg';
            const filename = `${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`;
            const { error: upErr } = await supabase.storage
                .from('iam-images')
                .upload(filename, file, { contentType: file.type });
            if (upErr) throw upErr;
            const { data: { publicUrl } } = supabase.storage
                .from('iam-images')
                .getPublicUrl(filename);
            onChange(publicUrl);
        } catch (e: any) {
            setError(e?.message ?? '업로드 실패');
        } finally {
            setUploading(false);
        }
    };

    return (
        <div className="space-y-2">
            <p className="text-xs font-bold text-slate-400">{label}</p>
            {value ? (
                <div className="relative group">
                    <img src={value} alt="preview" className="w-full h-40 object-cover rounded-xl border border-slate-200 dark:border-slate-700" />
                    <button
                        type="button"
                        onClick={() => onChange('')}
                        className="absolute top-2 right-2 p-1.5 bg-black/60 text-white rounded-lg opacity-0 group-hover:opacity-100 transition-opacity"
                    >
                        <X size={14} />
                    </button>
                </div>
            ) : (
                <button
                    type="button"
                    onClick={() => inputRef.current?.click()}
                    disabled={uploading}
                    className="w-full h-28 border-2 border-dashed border-slate-200 dark:border-slate-700 rounded-xl flex flex-col items-center justify-center gap-2 text-slate-400 hover:border-violet-400 hover:text-violet-500 transition-all disabled:opacity-50"
                >
                    {uploading
                        ? <Loader2 size={20} className="animate-spin" />
                        : <Upload size={20} />}
                    <span className="text-xs font-bold">
                        {uploading ? '업로드 중...' : '클릭하여 이미지 업로드'}
                    </span>
                    <span className="text-[10px] text-slate-300">JPG, PNG, WebP, GIF · 최대 5MB</span>
                </button>
            )}
            {error && <p className="text-xs text-rose-500 font-bold">{error}</p>}
            <input
                ref={inputRef}
                type="file"
                accept={ALLOWED_IMAGE_TYPES.join(',')}
                className="hidden"
                onChange={e => e.target.files?.[0] && upload(e.target.files[0])}
            />
        </div>
    );
}

// ── 슬라이드 에디터 ──────────────────────────────────────────────────

function SlideEditor({ slides, onChange, active, onActiveChange }: {
    slides: IamSlide[];
    onChange: (slides: IamSlide[]) => void;
    active: number;
    onActiveChange: (i: number) => void;
}) {
    const setActive = onActiveChange;

    const update = (i: number, key: keyof IamSlide, val: string) => {
        const next = slides.map((s, idx) => idx === i ? { ...s, [key]: val } : s);
        onChange(next);
    };

    const add = () => {
        onChange([...slides, { title: '', body: '', image_url: '' }]);
        setActive(slides.length);
    };

    const remove = (i: number) => {
        if (slides.length <= 1) return;
        const next = slides.filter((_, idx) => idx !== i);
        onChange(next);
        setActive(Math.min(active, next.length - 1));
    };

    const cur: IamSlide = slides[active]
        ? { title: slides[active].title ?? '', body: slides[active].body ?? '', image_url: slides[active].image_url ?? '' }
        : { title: '', body: '', image_url: '' };

    return (
        <div className="space-y-4">
            {/* 슬라이드 탭 */}
            <div className="flex items-center gap-2 flex-wrap">
                {slides.map((_, i) => (
                    <div key={i} className="flex items-center gap-1">
                        <button
                            type="button"
                            onClick={() => setActive(i)}
                            className={cn(
                                "px-3 py-1.5 rounded-xl text-xs font-black transition-all",
                                active === i
                                    ? "bg-violet-600 text-white"
                                    : "bg-slate-100 dark:bg-slate-800 text-slate-500 hover:text-violet-600"
                            )}
                        >
                            슬라이드 {i + 1}
                        </button>
                        {slides.length > 1 && (
                            <button
                                type="button"
                                onClick={() => remove(i)}
                                className="p-1 text-slate-300 hover:text-rose-500 transition-colors"
                            >
                                <X size={12} />
                            </button>
                        )}
                    </div>
                ))}
                {slides.length < 6 && (
                    <button
                        type="button"
                        onClick={add}
                        className="flex items-center gap-1 px-3 py-1.5 rounded-xl text-xs font-black bg-slate-50 dark:bg-slate-800 text-slate-400 hover:text-violet-600 hover:bg-violet-50 dark:hover:bg-violet-500/10 transition-all border border-dashed border-slate-200 dark:border-slate-700"
                    >
                        <Plus size={12} />
                        슬라이드 추가
                    </button>
                )}
            </div>

            {/* 현재 슬라이드 편집 */}
            <div className="space-y-3 p-4 bg-slate-50 dark:bg-slate-900/30 rounded-2xl border border-slate-200 dark:border-slate-800">
                <ImageUploader
                    value={cur.image_url}
                    onChange={url => update(active, 'image_url', url)}
                />
                <div>
                    <p className="text-xs font-bold text-slate-400 mb-1.5">슬라이드 {active + 1} 제목</p>
                    <input
                        type="text"
                        value={cur.title}
                        onChange={e => update(active, 'title', e.target.value)}
                        placeholder={`슬라이드 ${active + 1} 제목`}
                        maxLength={80}
                        className="w-full px-3 py-2 bg-white dark:bg-slate-900/40 border border-slate-200 dark:border-slate-700 rounded-xl text-sm font-bold text-slate-900 dark:text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-violet-500/30 focus:border-violet-400 transition-all"
                    />
                </div>
                <div>
                    <p className="text-xs font-bold text-slate-400 mb-1.5">슬라이드 {active + 1} 본문</p>
                    <HtmlToggleEditor
                        content={cur.body}
                        onChange={body => update(active, 'body', body)}
                        placeholder={`슬라이드 ${active + 1} 내용을 입력하세요...`}
                    />
                </div>
            </div>
        </div>
    );
}

// ── 앱 미리보기 ──────────────────────────────────────────────────────

function AppPreview({ form, previewSlide, onPreviewSlideChange }: {
    form: IamFormData;
    previewSlide: number;
    onPreviewSlideChange: (i: number) => void;
}) {
    const setPreviewSlide = onPreviewSlideChange;
    const [previewQIdx, setPreviewQIdx] = useState(0);

    // 질문 수 변경 시 인덱스 범위 보정
    useEffect(() => {
        const max = form.survey_questions.length - 1;
        if (previewQIdx > max) setPreviewQIdx(Math.max(0, max));
    }, [form.survey_questions.length, previewQIdx]);

    const typeMeta = TYPE_OPTIONS.find(t => t.value === form.type) ?? TYPE_OPTIONS[0];
    const badgeStyle = {
        backgroundColor: `${typeMeta.color}1A`,
        borderColor: `${typeMeta.color}40`,
        color: typeMeta.color,
    };

    const sanitize = (html: string) => typeof window !== 'undefined'
        ? DOMPurify.sanitize(html, {
            ALLOWED_TAGS: ['p', 'b', 'i', 'u', 's', 'br', 'ul', 'ol', 'li', 'h1', 'h2', 'h3', 'strong', 'em', 'span'],
            ALLOWED_ATTR: ['style'],
          })
        : html;

    const activeSlide = form.use_slides ? form.slides[previewSlide] : null;
    const hasImage = form.use_slides
        ? (activeSlide?.image_url ?? '')
        : form.image_url;

    const bodyHtml = sanitize(form.use_slides ? (activeSlide?.body ?? '') : form.body);

    const cardContent = (
        <div className="bg-white w-full">
            {/* 핸들바 (slide_up) */}
            {form.display_type === 'slide_up' && (
                <div className="flex justify-center pt-2 pb-1.5">
                    <div className="w-7 h-[3px] bg-slate-200 rounded-full" />
                </div>
            )}

            {/* [단일 모드] 상단 이미지 */}
            {!form.use_slides && hasImage && (
                <img src={hasImage} alt="" className="w-full h-[110px] object-cover" />
            )}

            {/* 배지 + 메인 제목 — imageOnly일 때 숨김 */}
            {!form.image_only && (
                <div className="px-3.5 pt-2.5 pb-0">
                    <div className="flex items-center gap-1.5">
                        <div
                            className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full border text-[8px] font-black flex-shrink-0"
                            style={badgeStyle}
                        >
                            <typeMeta.Icon size={7} />
                            {typeMeta.label}
                        </div>
                        <p className="text-[11px] font-extrabold text-slate-900 leading-snug truncate">
                            {form.title || '제목을 입력하세요'}
                        </p>
                    </div>
                </div>
            )}

            {/* [슬라이드 모드] 이미지 + 화살표 — imageOnly면 mt-2 생략 */}
            {form.use_slides && (
                <div className={`relative ${form.image_only ? '' : 'mt-2'}`}>
                    {hasImage ? (
                        <img
                            key={previewSlide}
                            src={hasImage} alt=""
                            className="w-full h-[150px] object-cover"
                        />
                    ) : (
                        <div className="w-full h-[150px] bg-gradient-to-br from-slate-100 to-slate-50 flex items-center justify-center">
                            <ImageIcon className="text-slate-300" size={18} />
                        </div>
                    )}
                    {form.slides.length > 1 && (
                        <>
                            <button
                                type="button"
                                onClick={() => setPreviewSlide((previewSlide - 1 + form.slides.length) % form.slides.length)}
                                className="absolute left-1 top-1/2 -translate-y-1/2 w-5 h-5 bg-black/40 hover:bg-black/60 rounded-full flex items-center justify-center text-white font-bold transition-all text-xs leading-none"
                            >‹</button>
                            <button
                                type="button"
                                onClick={() => setPreviewSlide((previewSlide + 1) % form.slides.length)}
                                className="absolute right-1 top-1/2 -translate-y-1/2 w-5 h-5 bg-black/40 hover:bg-black/60 rounded-full flex items-center justify-center text-white font-bold transition-all text-xs leading-none"
                            >›</button>
                        </>
                    )}
                </div>
            )}

            {/* 헤더 후 간격 — 앱의 SizedBox(10) 대응, imageOnly면 생략 */}
            {!form.image_only && <div className="h-2.5" />}

            {/* 슬라이드 소제목 + 본문 + 인디케이터 + CTA + dismiss */}
            <div className="px-3.5 pb-3">
                {/* [슬라이드 모드] 슬라이드 소제목 — imageOnly면 숨김 */}
                {form.use_slides && !form.image_only && !!form.slides[previewSlide]?.title && (
                    <p className="text-[10px] font-bold text-slate-700 leading-snug mb-1">
                        {form.slides[previewSlide].title}
                    </p>
                )}

                {/* 본문 — 비어있거나 imageOnly면 숨김 */}
                {bodyHtml && !form.image_only && (
                    <div
                        className="text-[9.5px] text-slate-500 leading-relaxed line-clamp-3 prose prose-xs max-w-none"
                        dangerouslySetInnerHTML={{ __html: bodyHtml }}
                    />
                )}

                {/* [슬라이드 모드] 인디케이터 */}
                {form.use_slides && form.slides.length > 1 && (
                    <div className="flex justify-center gap-1 py-1.5">
                        {form.slides.map((_, i) => (
                            <button
                                key={i} type="button"
                                onClick={() => setPreviewSlide(i)}
                                className="rounded-full transition-all"
                                style={{
                                    width: i === previewSlide ? 12 : 4,
                                    height: 4,
                                    backgroundColor: i === previewSlide
                                        ? '#8B5CF6'
                                        : 'rgba(139,92,246,0.25)',
                                }}
                            />
                        ))}
                    </div>
                )}

                {/* 설문 미리보기 */}
                {form.type === 'survey' && form.survey_questions.length > 0 && (() => {
                    const total = form.survey_questions.length;
                    const idx = Math.min(previewQIdx, total - 1);
                    const q = form.survey_questions[idx];
                    const isLast = idx === total - 1;
                    return (
                        <div className="mt-2 pt-2 border-t border-slate-100 space-y-1.5">
                            {/* 진행바 */}
                            <div className="flex items-center gap-1.5">
                                <div className="flex-1 h-1 bg-slate-100 rounded-full overflow-hidden">
                                    <div
                                        className="h-full bg-violet-500 rounded-full transition-all duration-300"
                                        style={{ width: `${((idx + 1) / total) * 100}%` }}
                                    />
                                </div>
                                <span className="text-[8px] font-black text-slate-400 shrink-0">{idx + 1} / {total}</span>
                            </div>
                            <p className="text-[9px] font-bold text-slate-700 leading-snug line-clamp-2">
                                {q.text || '질문 내용'}
                            </p>
                            {q.type === 'star_rating' && (
                                <div className="flex gap-0.5">
                                    {[1,2,3,4,5].map(i => (
                                        <svg key={i} width="12" height="12" viewBox="0 0 24 24" fill="#FCD34D">
                                            <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
                                        </svg>
                                    ))}
                                </div>
                            )}
                            {(q.type === 'radio' || q.type === 'checkbox') && (
                                <div className="space-y-0.5">
                                    {(q.options.length > 0 ? q.options.slice(0, 3) : ['옵션 1', '옵션 2']).map((opt, i) => (
                                        <div key={i} className="flex items-center gap-1 text-[8px] text-slate-500">
                                            <div className={`w-2 h-2 border border-slate-300 shrink-0 ${q.type === 'radio' ? 'rounded-full' : 'rounded-sm'}`} />
                                            {opt || `옵션 ${i + 1}`}
                                        </div>
                                    ))}
                                </div>
                            )}
                            {q.type === 'text' && (
                                <div className="h-6 bg-slate-50 border border-slate-200 rounded-lg" />
                            )}
                            <div className="flex gap-1 pt-0.5">
                                <button
                                    type="button"
                                    onClick={() => setPreviewQIdx(i => Math.max(0, i - 1))}
                                    disabled={idx === 0}
                                    className="flex-1 py-1 border border-slate-200 text-[7.5px] font-black text-center rounded-lg disabled:opacity-30 transition-opacity"
                                    style={{ color: '#94a3b8' }}
                                >
                                    이전
                                </button>
                                <button
                                    type="button"
                                    onClick={() => !isLast && setPreviewQIdx(i => Math.min(total - 1, i + 1))}
                                    className="flex-1 py-1 bg-violet-600 text-white text-[7.5px] font-black text-center rounded-lg transition-opacity"
                                >
                                    {isLast ? '제출하기' : '다음'}
                                </button>
                            </div>
                        </div>
                    );
                })()}
                {form.type === 'survey' && form.survey_questions.length === 0 && (
                    <div className="mt-2 pt-2 border-t border-slate-100">
                        <p className="text-[8.5px] text-slate-300 italic text-center py-2">질문을 추가하면 미리보기가 표시됩니다.</p>
                    </div>
                )}

                {/* CTA */}
                {form.cta_label && (
                    <div className="mt-2 w-full bg-violet-600 text-white text-[9px] font-black text-center py-2 rounded-lg flex items-center justify-center gap-1">
                        {form.cta_label}
                        <ExternalLink size={8} />
                    </div>
                )}

                {/* 구분선 + dismiss 버튼 */}
                <div className="mt-2 pt-1.5 border-t border-slate-100 flex items-center">
                    <span className="text-[7.5px] text-slate-400 underline font-medium">다시 보지 않기</span>
                    <div className="flex-1" />
                    <span className="text-[7.5px] text-slate-400 underline font-medium">오늘 그만보기</span>
                </div>
            </div>
        </div>
    );

    return (
        <div className="sticky top-8">
            <div className="flex items-center gap-2 mb-4">
                <Smartphone className="w-4 h-4 text-slate-400" />
                <span className="text-xs font-black text-slate-400 uppercase tracking-widest">앱 미리보기</span>
            </div>

            {/* 폰 프레임 — iPhone 비율 9:19.5 ≈ 260×564 */}
            <div
                className="mx-auto w-[260px] h-[564px] rounded-[42px] p-[5px]"
                style={{
                    background: 'linear-gradient(145deg, #2a2a2e 0%, #1a1a1c 60%, #2a2a2e 100%)',
                    boxShadow: '0 0 0 1px rgba(255,255,255,0.07), inset 0 0 0 1px rgba(0,0,0,0.5), 0 30px 60px rgba(0,0,0,0.35)',
                }}
            >
                <div className="relative w-full h-full bg-[#f2f2f7] rounded-[38px] overflow-hidden">
                    {/* 다이나믹 아일랜드 */}
                    <div className="absolute top-3 left-1/2 -translate-x-1/2 w-[72px] h-[22px] bg-black rounded-full z-20" />

                    {/* 상태바 */}
                    <div className="relative pt-9 px-5 pb-1 flex justify-between items-center z-10">
                        <span className="text-[10px] font-black text-slate-800">9:41</span>
                        <div className="flex items-center gap-1.5">
                            <svg width="12" height="9" viewBox="0 0 12 9" fill="none"><rect x="0" y="3" width="2.5" height="6" rx="0.5" fill="#1a1a1c" opacity="0.4"/><rect x="3.2" y="2" width="2.5" height="7" rx="0.5" fill="#1a1a1c" opacity="0.6"/><rect x="6.4" y="1" width="2.5" height="8" rx="0.5" fill="#1a1a1c" opacity="0.8"/><rect x="9.6" y="0" width="2.5" height="9" rx="0.5" fill="#1a1a1c"/></svg>
                            <svg width="14" height="10" viewBox="0 0 14 10" fill="none"><path d="M7 2C9.2 2 11.1 3 12.5 4.5L14 3C12.1 1.1 9.7 0 7 0C4.3 0 1.9 1.1 0 3L1.5 4.5C2.9 3 4.8 2 7 2Z" fill="#1a1a1c" opacity="0.4"/><path d="M7 5C8.5 5 9.8 5.6 10.8 6.6L12.2 5.2C10.8 3.8 8.9 3 7 3C5.1 3 3.2 3.8 1.8 5.2L3.2 6.6C4.2 5.6 5.5 5 7 5Z" fill="#1a1a1c" opacity="0.7"/><circle cx="7" cy="9" r="1.5" fill="#1a1a1c"/></svg>
                            <div className="w-[19px] h-[9px] rounded-[2px] border border-slate-700/40 p-[1.5px]">
                                <div className="h-full w-3/4 bg-slate-800 rounded-[1px]" />
                            </div>
                        </div>
                    </div>

                    {/* 앱 배경 더미 */}
                    <div className="absolute inset-0 top-16 px-4 space-y-2 z-0">
                        {[80, 60, 70, 50, 65].map((w, i) => (
                            <div key={i} className="h-2 bg-slate-200/70 rounded-full" style={{ width: `${w}%` }} />
                        ))}
                    </div>

                    {/* slide_up */}
                    {form.display_type === 'slide_up' && (
                        <div className="absolute inset-0 z-10">
                            {/* 반투명 배경 */}
                            <div className="absolute inset-0 bg-black/30 rounded-[38px]" />
                            {/* X 버튼 + 카드 */}
                            <div className="absolute bottom-0 left-0 right-0 flex flex-col items-end">
                                <div className="p-2 cursor-pointer mr-1">
                                    <X size={14} className="text-white/80 drop-shadow" />
                                </div>
                                <div className="bg-white rounded-t-[20px] shadow-[0_-4px_20px_rgba(0,0,0,0.12)] overflow-hidden w-full">
                                    {cardContent}
                                    <div className="h-3 bg-white" />
                                </div>
                            </div>
                        </div>
                    )}

                    {/* modal */}
                    {form.display_type === 'modal' && (
                        <div className="absolute inset-0 bg-black/40 flex items-center justify-center px-3 z-10">
                            <div className="relative w-full">
                                {/* X 닫기 버튼: 카드 상단 바깥, 어두운 배경 위 흰색 */}
                                <div className="absolute -top-9 right-0 z-20 p-2 cursor-pointer">
                                    <X size={15} className="text-white/85 drop-shadow" />
                                </div>
                                <div className="bg-white rounded-2xl overflow-hidden shadow-2xl w-full">
                                    {cardContent}
                                </div>
                            </div>
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}

// ── 메인 폼 ──────────────────────────────────────────────────────────

interface IamFormProps { messageId?: string; }

export default function IamForm({ messageId }: IamFormProps) {
    const router = useRouter();
    const isEdit = Boolean(messageId);

    const [form, setForm] = useState<IamFormData>(DEFAULT);
    const [loading, setLoading] = useState(isEdit);
    const [saving, setSaving] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [profile, setProfile] = useState<any>(null);
    const [activeSlide, setActiveSlide] = useState(0);
    const [churches, setChurches] = useState<Array<{id: string; name: string}>>([]);
    const [departments, setDepartments] = useState<Array<{id: string; name: string}>>([]);

    const set = <K extends keyof IamFormData>(key: K, value: IamFormData[K]) =>
        setForm(prev => ({ ...prev, [key]: value }));

    useEffect(() => {
        const init = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) { router.push('/login'); return; }

            const { data: p } = await supabase
                .from('profiles')
                .select('id, role, admin_status, is_master, church_id')
                .eq('id', session.user.id)
                .single();

            const ok = p && (p.is_master || (p.role === 'admin' && p.admin_status === 'approved'));
            if (!ok) { router.push('/login'); return; }
            setProfile(p);

            if (p.is_master) {
                const { data: churchList } = await supabase
                    .from('churches')
                    .select('id, name')
                    .order('name');
                setChurches(churchList ?? []);
            } else if (p.church_id) {
                const { data: depts } = await supabase
                    .from('departments')
                    .select('id, name')
                    .eq('church_id', p.church_id)
                    .order('name');
                setDepartments(depts ?? []);
            }

            if (isEdit && messageId) {
                const { data: msg } = await supabase
                    .from('in_app_messages')
                    .select('*')
                    .eq('id', messageId)
                    .single();

                if (msg) {
                    const rawSlides: IamSlide[] = Array.isArray(msg.slides) && msg.slides.length > 0
                        ? msg.slides.map((s: any) => ({ title: s.title ?? '', body: s.body ?? '', image_url: s.image_url ?? '' }))
                        : [{ title: '', body: '', image_url: '' }];

                    setForm({
                        title:        msg.title ?? '',
                        body:         msg.body ?? '',
                        image_url:    msg.image_url ?? '',
                        use_slides:   Array.isArray(msg.slides) && msg.slides.length > 0,
                        slides:       rawSlides,
                        type:         msg.type ?? 'announcement',
                        display_type: msg.display_type ?? 'slide_up',
                        target_role:  msg.target_role ?? 'all',
                        cta_label:    msg.cta_label ?? '',
                        cta_url:      msg.cta_url ?? '',
                        starts_at:    msg.starts_at ? msg.starts_at.slice(0, 16) : DEFAULT.starts_at,
                        expires_at:   msg.expires_at ? msg.expires_at.slice(0, 16) : '',
                        is_active:    msg.is_active ?? true,
                        priority:     msg.priority ?? 0,
                        target_scope: !msg.church_id
                            ? 'global'
                            : msg.department_id
                            ? 'department'
                            : 'church',
                        target_church_id: msg.church_id ?? '',
                        department_id: msg.department_id ?? '',
                        survey_questions: (msg.survey_questions as SurveyQuestion[]) ?? [],
                        image_only: msg.image_only ?? false,
                    });
                }
                setLoading(false);
            }
        };
        init();
    }, [messageId, isEdit, router]);

    // 마스터: 선택 교회 변경 시 부서 목록 재조회
    useEffect(() => {
        if (!profile?.is_master) return;
        if (!form.target_church_id) { setDepartments([]); return; }
        supabase
            .from('departments')
            .select('id, name')
            .eq('church_id', form.target_church_id)
            .order('name')
            .then(({ data }) => setDepartments(data ?? []));
    }, [form.target_church_id, profile?.is_master]);

    const validate = (): string | null => {
        if (!form.title.trim()) return '제목을 입력해주세요.';
        if (form.type === 'survey') {
            if (form.survey_questions.length === 0) return '설문 질문을 최소 1개 이상 추가해주세요.';
            for (const q of form.survey_questions) {
                if (!q.text.trim()) return '모든 질문에 내용을 입력해주세요.';
                if ((q.type === 'radio' || q.type === 'checkbox') && q.options.some(o => !o.trim()))
                    return '모든 옵션에 내용을 입력해주세요.';
            }
        }
        if (form.cta_url && !/^https?:\/\//i.test(form.cta_url))
            return 'CTA URL은 http:// 또는 https:// 로 시작해야 합니다.';
        if (form.cta_url && !form.cta_label) return 'CTA URL을 입력했다면 버튼 텍스트도 입력해주세요.';
        if (form.expires_at && form.expires_at <= form.starts_at) return '만료일은 시작일보다 이후여야 합니다.';
        if (profile?.is_master && form.target_scope === 'church' && !form.target_church_id)
            return '노출할 특정 교회를 선택해주세요.';
        if (form.target_scope === 'department' && !form.department_id)
            return '노출할 특정 부서를 선택해주세요.';
        return null;
    };

    const sanitizeHtml = (html: string) => DOMPurify.sanitize(html, {
        ALLOWED_TAGS: ['p', 'b', 'i', 'u', 's', 'br', 'ul', 'ol', 'li', 'h1', 'h2', 'h3', 'strong', 'em', 'span', 'a'],
        ALLOWED_ATTR: ['style', 'href', 'target', 'rel'],
    });

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        const err = validate();
        if (err) { setError(err); return; }
        if (!profile) return;
        setSaving(true);
        setError(null);

        const payload: Record<string, any> = {
            title:        form.title.trim(),
            body:         form.use_slides ? '' : sanitizeHtml(form.body),
            image_url:    (!form.use_slides && form.image_url) ? form.image_url : null,
            slides:       form.use_slides
                ? form.slides.map(s => ({ title: s.title.trim(), body: sanitizeHtml(s.body), image_url: s.image_url || null }))
                : null,
            type:         form.type,
            display_type: form.display_type,
            target_role:  form.target_role,
            cta_label:    form.cta_label.trim() || null,
            cta_url:      form.cta_url.trim() || null,
            starts_at:    new Date(form.starts_at).toISOString(),
            expires_at:   form.expires_at ? new Date(form.expires_at).toISOString() : null,
            is_active:    form.is_active,
            priority:     form.priority,
            image_only:   form.image_only,
        };

        if (form.type === 'survey') {
            payload.survey_questions = form.survey_questions.map(q => ({
                id: q.id,
                type: q.type,
                text: DOMPurify.sanitize(q.text, { ALLOWED_TAGS: [] }),
                required: q.required,
                options: q.options.map(o => DOMPurify.sanitize(o, { ALLOWED_TAGS: [] })),
            }));
        } else {
            payload.survey_questions = null;
        }

        try {
            if (isEdit && messageId) {
                if (profile.is_master) {
                    payload.church_id = form.target_scope === 'global'
                        ? null
                        : (form.target_church_id || null);
                }
                payload.department_id = form.target_scope === 'department'
                    ? (form.department_id || null)
                    : null;
                const { error: e } = await supabase
                    .from('in_app_messages')
                    .update(payload)
                    .eq('id', messageId);
                if (e) throw e;
            } else {
                const churchId = form.target_scope === 'global'
                    ? null
                    : profile.is_master
                        ? (form.target_church_id || null)
                        : (profile.church_id ?? null);
                const deptId = form.target_scope === 'department'
                    ? (form.department_id || null)
                    : null;
                const { error: e } = await supabase
                    .from('in_app_messages')
                    .insert({
                        ...payload,
                        church_id: churchId,
                        department_id: deptId,
                        created_by: profile.id,
                    });
                if (e) throw e;
            }
            router.push('/in-app-messages');
        } catch (e: any) {
            setError(e?.message ?? '저장 중 오류가 발생했습니다.');
            setSaving(false);
        }
    };

    if (loading) {
        return (
            <div className="h-[80vh] flex flex-col items-center justify-center gap-4">
                <Loader2 className="w-10 h-10 text-violet-600 animate-spin" />
                <p className="text-slate-400 font-bold text-xs uppercase tracking-widest">메시지 불러오는 중...</p>
            </div>
        );
    }

    return (
        <div className="max-w-7xl mx-auto pb-20 space-y-8">
            {/* 헤더 */}
            <header className="flex items-center gap-4 px-2">
                <button type="button" onClick={() => router.push('/in-app-messages')}
                    className="p-2.5 bg-slate-100 dark:bg-slate-800 rounded-xl text-slate-500 hover:text-slate-900 dark:hover:text-white transition-all">
                    <ArrowLeft className="w-5 h-5" />
                </button>
                <div>
                    <div className="inline-flex items-center gap-1.5 px-2.5 py-1 bg-violet-50 dark:bg-violet-500/10 border border-violet-100 dark:border-violet-500/20 rounded-full mb-1">
                        <MonitorSmartphone className="w-3 h-3 text-violet-600 dark:text-violet-400" />
                        <span className="text-[10px] font-black text-violet-600 dark:text-violet-400 uppercase tracking-widest">
                            {isEdit ? '메시지 수정' : '새 메시지'}
                        </span>
                    </div>
                    <h1 className="text-2xl font-black text-slate-900 dark:text-white tracking-tighter">
                        {isEdit ? '인앱 메시지 수정' : '인앱 메시지 작성'}
                    </h1>
                </div>
            </header>

            <form onSubmit={handleSubmit}>
                <div className="grid grid-cols-1 xl:grid-cols-[1fr_300px] gap-8 px-2">
                    {/* ── 왼쪽: 폼 필드 ── */}
                    <div className="space-y-6">

                        {/* 제목 */}
                        <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl p-6">
                            <label className="block text-xs font-black text-slate-500 dark:text-slate-400 uppercase tracking-widest mb-2">제목 *</label>
                            <input
                                type="text" value={form.title} onChange={e => set('title', e.target.value)}
                                placeholder="메시지 제목을 입력하세요" maxLength={100}
                                className="w-full px-4 py-3 bg-slate-50 dark:bg-slate-900/40 border border-slate-200 dark:border-slate-700 rounded-xl text-sm font-bold text-slate-900 dark:text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-violet-500/30 focus:border-violet-400 transition-all"
                            />
                        </div>

                        {/* 본문 / 슬라이드 / 설문 */}
                        <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl p-6 space-y-4">
                            <div className="flex items-center justify-between">
                                <label className="text-xs font-black text-slate-500 dark:text-slate-400 uppercase tracking-widest">
                                    {form.type === 'survey' ? '설문 질문' : '콘텐츠'} *
                                </label>
                                {/* 슬라이드 모드 토글 — survey 타입에서는 숨김 */}
                                {form.type !== 'survey' && (
                                    <button
                                        type="button"
                                        onClick={() => set('use_slides', !form.use_slides)}
                                        className={cn(
                                            "flex items-center gap-2 px-3 py-1.5 rounded-xl text-xs font-black transition-all border",
                                            form.use_slides
                                                ? "bg-violet-50 dark:bg-violet-500/10 text-violet-700 dark:text-violet-300 border-violet-300 dark:border-violet-500/30"
                                                : "bg-slate-50 dark:bg-slate-800 text-slate-500 border-slate-200 dark:border-slate-700 hover:border-violet-300"
                                        )}
                                    >
                                        <div className={cn("w-7 h-4 rounded-full relative transition-colors", form.use_slides ? "bg-violet-600" : "bg-slate-300")}>
                                            <div className={cn("absolute top-0.5 w-3 h-3 bg-white rounded-full transition-all shadow", form.use_slides ? "left-3.5" : "left-0.5")} />
                                        </div>
                                        슬라이드 모드
                                    </button>
                                )}
                            </div>

                            {/* survey 타입: SurveyBuilder */}
                            {form.type === 'survey' && (
                                <>
                                    <SurveyBuilder
                                        questions={form.survey_questions}
                                        onChange={questions => setForm(f => ({ ...f, survey_questions: questions }))}
                                    />
                                    <div className="pt-2 border-t border-slate-100 dark:border-slate-800">
                                        <p className="text-xs font-bold text-slate-400 mb-1.5">
                                            본문
                                            <span className="ml-1 text-[10px] font-normal text-slate-300">선택 사항 · 설문 위에 표시됩니다</span>
                                        </p>
                                        <HtmlToggleEditor
                                            content={form.body}
                                            onChange={v => set('body', v)}
                                            placeholder="설문 안내 문구를 입력하세요... (선택)"
                                        />
                                    </div>
                                </>
                            )}

                            {/* 비survey 타입: 기존 슬라이드/단일 에디터 */}
                            {form.type !== 'survey' && (
                                form.use_slides ? (
                                    <div className="space-y-3">
                                        <SlideEditor
                                            slides={form.slides}
                                            onChange={s => { set('slides', s); setActiveSlide(i => Math.min(i, s.length - 1)); }}
                                            active={activeSlide}
                                            onActiveChange={setActiveSlide}
                                        />
                                        {/* 이미지 전용 모드 토글 (슬라이드 모드) */}
                                        {form.slides.some(s => s.image_url) && (
                                            <label className="flex items-center gap-3 cursor-pointer select-none">
                                                <div
                                                    className={`relative w-9 h-5 rounded-full transition-colors flex-shrink-0 ${form.image_only ? 'bg-violet-500' : 'bg-slate-200 dark:bg-slate-700'}`}
                                                    onClick={() => set('image_only', !form.image_only)}
                                                >
                                                    <div className={`absolute top-0.5 left-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform ${form.image_only ? 'translate-x-4' : ''}`} />
                                                </div>
                                                <div>
                                                    <p className="text-xs font-bold text-slate-600 dark:text-slate-300">이미지 전용 모드</p>
                                                    <p className="text-[10px] text-slate-400">앱에서 제목·본문을 숨기고 이미지와 버튼만 표시합니다</p>
                                                </div>
                                            </label>
                                        )}
                                    </div>
                                ) : (
                                    <div className="space-y-3">
                                        <ImageUploader value={form.image_url} onChange={url => set('image_url', url)} />
                                        {/* 이미지 전용 모드 토글 */}
                                        {form.image_url && (
                                            <label className="flex items-center gap-3 cursor-pointer select-none">
                                                <div
                                                    className={`relative w-9 h-5 rounded-full transition-colors flex-shrink-0 ${form.image_only ? 'bg-violet-500' : 'bg-slate-200 dark:bg-slate-700'}`}
                                                    onClick={() => set('image_only', !form.image_only)}
                                                >
                                                    <div className={`absolute top-0.5 left-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform ${form.image_only ? 'translate-x-4' : ''}`} />
                                                </div>
                                                <div>
                                                    <p className="text-xs font-bold text-slate-600 dark:text-slate-300">이미지 전용 모드</p>
                                                    <p className="text-[10px] text-slate-400">앱에서 제목·본문을 숨기고 이미지와 버튼만 표시합니다</p>
                                                </div>
                                            </label>
                                        )}
                                        <div>
                                            <p className="text-xs font-bold text-slate-400 mb-1.5">
                                                본문
                                                <span className="ml-1 text-[10px] font-normal text-slate-300">HTML 버튼으로 소스 편집 가능</span>
                                            </p>
                                            <HtmlToggleEditor
                                                content={form.body}
                                                onChange={v => set('body', v)}
                                                placeholder="메시지 본문을 입력하세요..."
                                            />
                                        </div>
                                    </div>
                                )
                            )}
                        </div>

                        {/* 타입 / 노출 방식 / 대상 */}
                        <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl p-6 space-y-5">
                            <label className="block text-xs font-black text-slate-500 dark:text-slate-400 uppercase tracking-widest">메시지 설정</label>

                            {/* 타입 */}
                            <div>
                                <p className="text-xs font-bold text-slate-400 mb-2">메시지 유형</p>
                                <div className="grid grid-cols-3 gap-2">
                                    {TYPE_OPTIONS.map(({ value, label, Icon, color }) => (
                                        <button key={value} type="button" onClick={() => set('type', value)}
                                            className={cn(
                                                "flex flex-col items-center gap-1.5 py-3 rounded-xl border text-xs font-black transition-all",
                                                form.type === value ? "border-2 shadow-sm" : "border-slate-200 dark:border-slate-700 text-slate-400 hover:border-slate-300"
                                            )}
                                            style={form.type === value ? { borderColor: color, color, backgroundColor: `${color}0D` } : {}}
                                        >
                                            <Icon size={18} />
                                            {label}
                                        </button>
                                    ))}
                                </div>
                                {form.type === 'survey' && (
                                    <p className="mt-2 text-[10px] text-amber-600 dark:text-amber-400 font-bold bg-amber-50 dark:bg-amber-500/10 px-3 py-2 rounded-xl border border-amber-200 dark:border-amber-500/20">
                                        앱에서 질문별 슬라이드 방식으로 응답합니다. 별점·단일/다중 선택·주관식 질문을 최대 6개 구성할 수 있습니다.
                                    </p>
                                )}
                            </div>

                            {/* 노출 방식 */}
                            <div>
                                <p className="text-xs font-bold text-slate-400 mb-2">노출 방식</p>
                                <div className="grid grid-cols-2 gap-2">
                                    {[
                                        { value: 'slide_up', label: '슬라이드업', desc: '화면 하단에서 올라옴' },
                                        { value: 'modal',    label: '모달',       desc: '화면 중앙에 표시' },
                                    ].map(({ value, label, desc }) => (
                                        <button key={value} type="button" onClick={() => set('display_type', value as any)}
                                            className={cn(
                                                "flex flex-col items-start px-4 py-3 rounded-xl border text-sm font-black transition-all text-left",
                                                form.display_type === value
                                                    ? "border-violet-500 bg-violet-50 dark:bg-violet-500/10 text-violet-700 dark:text-violet-300"
                                                    : "border-slate-200 dark:border-slate-700 text-slate-500 hover:border-slate-300"
                                            )}
                                        >
                                            {label}
                                            <span className="text-[10px] font-medium mt-0.5 opacity-60">{desc}</span>
                                        </button>
                                    ))}
                                </div>
                            </div>

                            {/* 노출 범위 */}
                            <div>
                                <p className="text-xs font-bold text-slate-400 mb-2">노출 범위</p>
                                <div className={cn(
                                    "grid gap-2",
                                    profile?.is_master ? "grid-cols-3" : "grid-cols-2"
                                )}>
                                    {profile?.is_master && (
                                        <button
                                            type="button"
                                            onClick={() => { set('target_scope', 'global'); set('department_id', ''); }}
                                            className={cn(
                                                "py-2.5 rounded-xl border text-xs font-black transition-all",
                                                form.target_scope === 'global'
                                                    ? "border-violet-500 bg-violet-50 dark:bg-violet-500/10 text-violet-700 dark:text-violet-300"
                                                    : "border-slate-200 dark:border-slate-700 text-slate-400 hover:border-slate-300"
                                            )}
                                        >
                                            전체 교회
                                        </button>
                                    )}
                                    <button
                                        type="button"
                                        onClick={() => { set('target_scope', 'church'); set('department_id', ''); }}
                                        className={cn(
                                            "py-2.5 rounded-xl border text-xs font-black transition-all",
                                            form.target_scope === 'church'
                                                ? "border-violet-500 bg-violet-50 dark:bg-violet-500/10 text-violet-700 dark:text-violet-300"
                                                : "border-slate-200 dark:border-slate-700 text-slate-400 hover:border-slate-300"
                                        )}
                                    >
                                        {profile?.is_master ? '특정 교회' : '내 교회 전체'}
                                    </button>
                                    <button
                                        type="button"
                                        onClick={() => set('target_scope', 'department')}
                                        disabled={profile?.is_master ? !form.target_church_id : departments.length === 0}
                                        className={cn(
                                            "py-2.5 rounded-xl border text-xs font-black transition-all",
                                            form.target_scope === 'department'
                                                ? "border-violet-500 bg-violet-50 dark:bg-violet-500/10 text-violet-700 dark:text-violet-300"
                                                : "border-slate-200 dark:border-slate-700 text-slate-400 hover:border-slate-300",
                                            "disabled:opacity-40"
                                        )}
                                    >
                                        특정 부서
                                    </button>
                                </div>
                                {/* 마스터: 교회 선택 드롭다운 */}
                                {profile?.is_master && (form.target_scope === 'church' || form.target_scope === 'department') && (
                                    <select
                                        value={form.target_church_id}
                                        onChange={e => { set('target_church_id', e.target.value); set('department_id', ''); }}
                                        className="mt-2 w-full px-3 py-2 bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl text-xs font-bold text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                                    >
                                        <option value="">교회 선택...</option>
                                        {churches.map(c => (
                                            <option key={c.id} value={c.id}>{c.name}</option>
                                        ))}
                                    </select>
                                )}
                                {form.target_scope === 'department' && departments.length > 0 && (
                                    <select
                                        value={form.department_id}
                                        onChange={e => set('department_id', e.target.value)}
                                        className="mt-2 w-full px-3 py-2 bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl text-xs font-bold text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                                    >
                                        <option value="">부서 선택...</option>
                                        {departments.map(d => (
                                            <option key={d.id} value={d.id}>{d.name}</option>
                                        ))}
                                    </select>
                                )}
                            </div>

                            {/* 대상 역할 */}
                            <div>
                                <p className="text-xs font-bold text-slate-400 mb-2">노출 대상</p>
                                <div className="grid grid-cols-3 gap-2">
                                    {[{ value: 'all', label: '전체' }, { value: 'leader', label: '리더만' }, { value: 'member', label: '성도만' }].map(({ value, label }) => (
                                        <button key={value} type="button" onClick={() => set('target_role', value as any)}
                                            className={cn(
                                                "py-2.5 rounded-xl border text-xs font-black transition-all",
                                                form.target_role === value
                                                    ? "border-violet-500 bg-violet-50 dark:bg-violet-500/10 text-violet-700 dark:text-violet-300"
                                                    : "border-slate-200 dark:border-slate-700 text-slate-400 hover:border-slate-300"
                                            )}
                                        >
                                            {label}
                                        </button>
                                    ))}
                                </div>
                            </div>
                        </div>

                        {/* CTA */}
                        <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl p-6 space-y-4">
                            <label className="block text-xs font-black text-slate-500 dark:text-slate-400 uppercase tracking-widest">CTA 버튼 (선택)</label>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                <div>
                                    <p className="text-xs font-bold text-slate-400 mb-1.5">버튼 텍스트</p>
                                    <input type="text" value={form.cta_label} onChange={e => set('cta_label', e.target.value)}
                                        placeholder="예: 자세히 보기" maxLength={30}
                                        className="w-full px-4 py-2.5 bg-slate-50 dark:bg-slate-900/40 border border-slate-200 dark:border-slate-700 rounded-xl text-sm font-bold text-slate-900 dark:text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-violet-500/30 focus:border-violet-400 transition-all" />
                                </div>
                                <div>
                                    <p className="text-xs font-bold text-slate-400 mb-1.5">연결 URL <span className="text-[10px] font-normal">(https:// 필수)</span></p>
                                    <input type="text" value={form.cta_url} onChange={e => set('cta_url', e.target.value)}
                                        placeholder="https://example.com"
                                        className="w-full px-4 py-2.5 bg-slate-50 dark:bg-slate-900/40 border border-slate-200 dark:border-slate-700 rounded-xl text-sm font-bold text-slate-900 dark:text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-violet-500/30 focus:border-violet-400 transition-all" />
                                </div>
                            </div>
                        </div>

                        {/* 기간 / 우선순위 / 활성 */}
                        <div className="bg-white dark:bg-[#111827]/60 border border-slate-200 dark:border-slate-800/60 rounded-2xl p-6 space-y-4">
                            <label className="block text-xs font-black text-slate-500 dark:text-slate-400 uppercase tracking-widest">노출 기간 및 우선순위</label>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                <div>
                                    <p className="text-xs font-bold text-slate-400 mb-1.5">시작일시 *</p>
                                    <input type="datetime-local" value={form.starts_at} onChange={e => set('starts_at', e.target.value)}
                                        className="w-full px-4 py-2.5 bg-slate-50 dark:bg-slate-900/40 border border-slate-200 dark:border-slate-700 rounded-xl text-sm font-bold text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-violet-500/30 focus:border-violet-400 transition-all" />
                                </div>
                                <div>
                                    <p className="text-xs font-bold text-slate-400 mb-1.5">만료일시 <span className="text-[10px] font-normal">(미입력 시 무기한)</span></p>
                                    <input type="datetime-local" value={form.expires_at} onChange={e => set('expires_at', e.target.value)}
                                        className="w-full px-4 py-2.5 bg-slate-50 dark:bg-slate-900/40 border border-slate-200 dark:border-slate-700 rounded-xl text-sm font-bold text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-violet-500/30 focus:border-violet-400 transition-all" />
                                </div>
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                                <div>
                                    <p className="text-xs font-bold text-slate-400 mb-1.5">우선순위 <span className="text-[10px] font-normal">(높을수록 먼저 표시)</span></p>
                                    <input type="number" value={form.priority} onChange={e => set('priority', parseInt(e.target.value) || 0)}
                                        min={0} max={100}
                                        className="w-full px-4 py-2.5 bg-slate-50 dark:bg-slate-900/40 border border-slate-200 dark:border-slate-700 rounded-xl text-sm font-bold text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-violet-500/30 focus:border-violet-400 transition-all" />
                                </div>
                                <div className="flex flex-col justify-end pb-0.5">
                                    <button type="button" onClick={() => set('is_active', !form.is_active)}
                                        className={cn(
                                            "w-full py-2.5 rounded-xl border text-sm font-black transition-all",
                                            form.is_active
                                                ? "border-emerald-500 bg-emerald-50 dark:bg-emerald-500/10 text-emerald-700 dark:text-emerald-300"
                                                : "border-slate-200 dark:border-slate-700 text-slate-400"
                                        )}
                                    >
                                        {form.is_active ? '즉시 활성화' : '비활성 저장'}
                                    </button>
                                </div>
                            </div>
                        </div>

                        {/* 에러 */}
                        {error && (
                            <div className="flex items-center gap-3 px-5 py-4 bg-rose-50 dark:bg-rose-500/10 border border-rose-200 dark:border-rose-500/20 rounded-2xl text-rose-600 dark:text-rose-400">
                                <AlertCircle className="w-5 h-5 shrink-0" />
                                <p className="text-sm font-bold">{error}</p>
                            </div>
                        )}

                        {/* 저장 버튼 */}
                        <button type="submit" disabled={saving}
                            className="w-full flex items-center justify-center gap-2 px-6 py-4 bg-violet-600 text-white rounded-2xl font-black text-sm hover:bg-violet-700 active:scale-95 transition-all shadow-xl shadow-violet-500/20 disabled:opacity-60 disabled:cursor-not-allowed">
                            {saving && <Loader2 className="w-5 h-5 animate-spin" />}
                            {saving ? '저장 중...' : (isEdit ? '수정 완료' : '메시지 발행')}
                        </button>
                    </div>

                    {/* ── 오른쪽: 미리보기 ── */}
                    <AppPreview form={form} previewSlide={activeSlide} onPreviewSlideChange={setActiveSlide} />
                </div>
            </form>
        </div>
    );
}
