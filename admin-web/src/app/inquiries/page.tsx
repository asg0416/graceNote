'use client';

import { useEffect, useState, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Loader2,
    MessageSquare,
    Search,
    CheckCircle2,
    Clock,
    User,
    Send,
    ArrowLeft,
    XCircle,
    ChevronRight,
    Tag,
    AlertCircle,
    Church,
    Image as ImageIcon
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}

export default function InquiriesPage() {
    const [loading, setLoading] = useState(true);
    const [inquiries, setInquiries] = useState<any[]>([]);
    const [profile, setProfile] = useState<any>(null);
    const [selectedInquiry, setSelectedInquiry] = useState<any>(null);
    const [responses, setResponses] = useState<any[]>([]);
    const [replyContent, setReplyContent] = useState('');
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [filterStatus, setFilterStatus] = useState<'all' | 'pending' | 'in_progress' | 'completed'>('all');
    const [filterCategory, setFilterCategory] = useState<'all' | 'question' | 'bug' | 'suggestion'>('all');
    const [previewImage, setPreviewImage] = useState<string | null>(null);
    const [replyImages, setReplyImages] = useState<File[]>([]);
    const fileInputRef = useRef<HTMLInputElement>(null);
    const chatContainerRef = useRef<HTMLDivElement>(null);

    // Lock body scroll when lightbox is open
    useEffect(() => {
        if (previewImage) {
            document.body.style.overflow = 'hidden';
        } else {
            document.body.style.overflow = 'unset';
        }
        return () => {
            document.body.style.overflow = 'unset';
        };
    }, [previewImage]);

    const scrollToBottom = () => {
        if (chatContainerRef.current) {
            chatContainerRef.current.scrollTop = chatContainerRef.current.scrollHeight;
        }
    };

    const markAsRead = async (inquiryId: string) => {
        try {
            await supabase
                .from('inquiries')
                .update({
                    admin_last_read_at: new Date().toISOString(),
                    is_admin_unread: false
                })
                .eq('id', inquiryId);
        } catch (err) {
            console.error('Error marking as read:', err);
        }
    };

    useEffect(() => {
        if (selectedInquiry) {
            scrollToBottom();
        }
    }, [responses]);

    useEffect(() => {
        if (selectedInquiry) {
            fetchResponses(selectedInquiry.id);
            if (selectedInquiry.is_admin_unread) {
                markAsRead(selectedInquiry.id);
            }
        }
    }, [selectedInquiry]);

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

            if (!profileData || !profileData.is_master) {
                router.push('/');
                return;
            }

            setProfile(profileData);
            await fetchInquiries();
            setLoading(false);
        };

        checkUser();
    }, [router]);

    // Realtime subscription for Inquiry List
    useEffect(() => {
        const channel = supabase
            .channel('public:inquiries')
            .on('postgres_changes', { event: '*', schema: 'public', table: 'inquiries' }, () => {
                fetchInquiries();
            })
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
    }, []);

    // Realtime subscription for Selected Inquiry Responses
    useEffect(() => {
        if (!selectedInquiry) return;

        const channel = supabase
            .channel(`public:inquiry_responses:${selectedInquiry.id}`)
            .on('postgres_changes', {
                event: 'INSERT',
                schema: 'public',
                table: 'inquiry_responses',
                filter: `inquiry_id=eq.${selectedInquiry.id}`
            }, (payload) => {
                fetchResponses(selectedInquiry.id);
            })
            .on('postgres_changes', {
                event: 'UPDATE',
                schema: 'public',
                table: 'inquiries',
                filter: `id=eq.${selectedInquiry.id}`
            }, (payload) => {
                setSelectedInquiry(payload.new);
            })
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
    }, [selectedInquiry?.id]);

    const fetchInquiries = async () => {
        try {
            const { data: sessionData } = await supabase.auth.getSession();
            if (!sessionData.session) return;

            const { data: profileData } = await supabase
                .from('profiles')
                .select('is_master, church_id, department_id')
                .eq('id', sessionData.session.user.id)
                .single();

            let query = supabase
                .from('inquiries')
                .select(`
                    *,
                    user:profiles!user_id(
                        full_name, 
                        church_id,
                        church:churches(name),
                        department:departments!department_id (name)
                    )
                `);

            if (profileData && !profileData.is_master) {
                if (profileData.church_id) {
                    query = query.eq('user.church_id', profileData.church_id);
                }
                if (profileData.department_id) {
                    query = query.eq('user.department_id', profileData.department_id);
                }
            }

            const { data, error } = await query.order('created_at', { ascending: false });
            if (error) throw error;
            setInquiries(data || []);
        } catch (err) {
            console.error('Inquiries Fetch Error:', err);
        }
    };

    const fetchResponses = async (inquiryId: string) => {
        try {
            const { data } = await supabase
                .from('inquiry_responses')
                .select(`
                    *,
                    admin:profiles!admin_id(full_name)
                `)
                .eq('inquiry_id', inquiryId)
                .order('created_at', { ascending: true });
            setResponses(data || []);
        } catch (err) {
            console.error('Responses Fetch Error:', err);
        }
    };

    const handleSelectInquiry = async (inquiry: any) => {
        setSelectedInquiry(inquiry);
    };

    const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
        if (e.target.files) {
            const files = Array.from(e.target.files);
            setReplyImages(prev => [...prev, ...files].slice(0, 5)); // Limit to 5
        }
    };

    const removeReplyImage = (index: number) => {
        setReplyImages(prev => prev.filter((_, i) => i !== index));
    };

    const handleSendReply = async (e: React.FormEvent) => {
        e.preventDefault();
        if ((!replyContent && replyImages.length === 0) || !selectedInquiry) return;

        setIsSubmitting(true);
        try {
            // 0. Upload images if any
            const imageUrls: string[] = [];
            if (replyImages.length > 0) {
                for (const file of replyImages) {
                    const fileExt = file.name.split('.').pop();
                    const fileName = `${selectedInquiry.user_id}/${Date.now()}_${Math.random().toString(36).substring(7)}.${fileExt}`;
                    const { error: uploadError } = await supabase.storage
                        .from('inquiry_images')
                        .upload(fileName, file);

                    if (uploadError) throw uploadError;

                    const { data: { publicUrl } } = supabase.storage
                        .from('inquiry_images')
                        .getPublicUrl(fileName);
                    imageUrls.push(publicUrl);
                }
            }

            // 1. Insert reply
            const { error: replyError } = await supabase
                .from('inquiry_responses')
                .insert([{
                    inquiry_id: selectedInquiry.id,
                    admin_id: profile.id,
                    content: replyContent,
                    images: imageUrls
                }]);

            if (replyError) throw replyError;

            // 2. Automatically change status to in_progress if it was pending
            const updatePayload: any = {
                admin_last_read_at: new Date().toISOString(),
                is_admin_unread: false,
                updated_at: new Date().toISOString()
            };

            if (selectedInquiry.status === 'pending') {
                updatePayload.status = 'in_progress';
            }

            const { error: updateError } = await supabase
                .from('inquiries')
                .update(updatePayload)
                .eq('id', selectedInquiry.id);

            if (updateError) console.error('Status Update Error:', updateError);

            setReplyContent('');
            setReplyImages([]);
            await fetchResponses(selectedInquiry.id);
            await fetchInquiries();
        } catch (err) {
            console.error('Reply Error:', err);
            alert('답변 전송에 실패했습니다.');
        } finally {
            setIsSubmitting(false);
        }
    };

    const handleCompleteInquiry = async () => {
        if (!selectedInquiry || !confirm('상담을 종료하시겠습니까? 종료 후에는 추가 메시지를 보낼 수 없습니다.')) return;

        setIsSubmitting(true);
        try {
            const { error } = await supabase
                .from('inquiries')
                .update({
                    status: 'completed',
                    updated_at: new Date().toISOString(),
                    admin_last_read_at: new Date().toISOString(),
                    is_admin_unread: false
                })
                .eq('id', selectedInquiry.id);

            if (error) throw error;
            await fetchInquiries();
            setSelectedInquiry({ ...selectedInquiry, status: 'completed' });
        } catch (err) {
            console.error('Complete Inquiry Error:', err);
            alert('상담 종료 처리 중 오류가 발생했습니다.');
        } finally {
            setIsSubmitting(false);
        }
    };

    if (loading) {
        return (
            <div className="h-[80vh] flex flex-col items-center justify-center gap-4">
                <Loader2 className="w-10 h-10 text-indigo-600 animate-spin" />
                <p className="text-slate-400 font-bold text-xs uppercase tracking-widest">문의 내역 로딩 중...</p>
            </div>
        );
    }

    const filteredInquiries = inquiries.filter(i => {
        const matchesStatus = filterStatus === 'all' || i.status === filterStatus;
        const matchesCategory = filterCategory === 'all' || i.category === filterCategory;
        return matchesStatus && matchesCategory;
    });

    return (
        <div className="space-y-8 sm:space-y-10 max-w-7xl mx-auto">
            <header className="space-y-8 px-2">
                <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
                    <div className="space-y-2">
                        <div className="inline-flex items-center gap-2 px-3 py-1 bg-amber-50 dark:bg-amber-500/10 border border-amber-100 dark:border-amber-500/20 rounded-full">
                            <MessageSquare className="w-3.5 h-3.5 text-amber-600 dark:text-amber-400" />
                            <span className="text-[10px] font-black text-amber-600 dark:text-amber-400 uppercase tracking-widest">고객 지원</span>
                        </div>
                        <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">문의 및 상담</h1>
                        <p className="text-slate-500 dark:text-slate-500 font-bold text-xs sm:text-sm tracking-tight">사용자들의 문의사항을 확인하고 정성껏 답변해 주세요.</p>
                    </div>
                </div>
            </header>

            <div className="grid grid-cols-1 xl:grid-cols-12 gap-8 px-2">
                {/* Inquiry List Area */}
                <div className={cn(
                    "xl:col-span-5 space-y-6",
                    selectedInquiry && "hidden xl:block"
                )}>
                    <div className="bg-white dark:bg-[#111827]/60 backdrop-blur-xl border border-slate-200 dark:border-slate-800/60 rounded-[32px] overflow-hidden shadow-xl">
                        <div className="p-6 border-b border-slate-100 dark:border-slate-800 space-y-4">
                            <div className="flex items-center justify-between">
                                <h3 className="text-lg font-black text-slate-900 dark:text-white tracking-tight shrink-0 mr-4">문의 리스트</h3>
                                <div className="flex gap-1.5 overflow-x-auto no-scrollbar">
                                    {(['all', 'pending', 'in_progress', 'completed'] as const).map((s) => (
                                        <button
                                            key={s}
                                            onClick={() => setFilterStatus(s)}
                                            className={cn(
                                                "px-2.5 py-1.5 rounded-xl text-[9px] font-black uppercase tracking-widest transition-all whitespace-nowrap",
                                                filterStatus === s
                                                    ? "bg-indigo-600 text-white shadow-lg shadow-indigo-500/20"
                                                    : "bg-slate-50 dark:bg-slate-800 text-slate-400 hover:text-slate-600 dark:hover:text-slate-200"
                                            )}
                                        >
                                            {s === 'all' ? '전체' : s === 'pending' ? '대기' : s === 'in_progress' ? '진행' : '완료'}
                                        </button>
                                    ))}
                                </div>
                            </div>

                            {/* Category Filter */}
                            <div className="flex gap-2">
                                {(['all', 'question', 'bug', 'suggestion'] as const).map((c) => (
                                    <button
                                        key={c}
                                        onClick={() => setFilterCategory(c)}
                                        className={cn(
                                            "flex-1 px-2 py-1.5 rounded-lg text-[9px] font-black uppercase tracking-widest transition-all text-center",
                                            filterCategory === c
                                                ? "bg-slate-900 dark:bg-white text-white dark:text-slate-900"
                                                : "bg-slate-50 dark:bg-slate-800/50 text-slate-400 hover:bg-slate-100"
                                        )}
                                    >
                                        {c === 'all' ? '전체 카테고리' : c === 'question' ? '질문' : c === 'bug' ? '버그' : '건의'}
                                    </button>
                                ))}
                            </div>
                        </div>

                        <div className="divide-y divide-slate-100 dark:divide-slate-800 overflow-y-auto max-h-[700px] custom-scrollbar">
                            {filteredInquiries.length === 0 ? (
                                <div className="p-20 text-center space-y-3">
                                    <AlertCircle className="w-10 h-10 text-slate-200 mx-auto" />
                                    <p className="text-slate-400 font-bold text-sm">해당하는 문의가 없습니다.</p>
                                </div>
                            ) : (
                                filteredInquiries.map((inquiry) => {
                                    const hasNewMessage = inquiry.is_admin_unread && inquiry.status !== 'completed';

                                    return (
                                        <div
                                            key={inquiry.id}
                                            onClick={() => handleSelectInquiry(inquiry)}
                                            className={cn(
                                                "p-6 cursor-pointer transition-all hover:bg-slate-50/50 dark:hover:bg-slate-800/30 flex items-center justify-between group relative",
                                                selectedInquiry?.id === inquiry.id && "bg-indigo-50/50 dark:bg-indigo-500/10 border-l-4 border-l-indigo-600"
                                            )}
                                        >
                                            <div className="space-y-2 flex-1 min-w-0 pr-4">
                                                <div className="flex items-center gap-2">
                                                    <span className={cn(
                                                        "px-2 py-0.5 rounded-lg text-[9px] font-black uppercase tracking-widest",
                                                        inquiry.status === 'pending' ? "bg-amber-100 dark:bg-amber-500/20 text-amber-600 dark:text-amber-400" :
                                                            inquiry.status === 'in_progress' ? "bg-indigo-100 dark:bg-indigo-500/20 text-indigo-600 dark:text-indigo-400" :
                                                                "bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400"
                                                    )}>
                                                        {inquiry.status === 'pending' ? '답변 대기' : inquiry.status === 'in_progress' ? '상담 진행 중' : '답변 완료'}
                                                    </span>
                                                    <span className="text-[10px] font-black text-slate-400">{new Date(inquiry.created_at).toLocaleDateString()}</span>
                                                    {hasNewMessage && (
                                                        <span className="flex h-2 w-2 rounded-full bg-red-500 animate-pulse" />
                                                    )}
                                                </div>
                                                <div className="flex items-center gap-2">
                                                    <span className="bg-slate-100 dark:bg-slate-800 text-slate-500 px-1.5 py-0.5 rounded text-[9px] font-bold">
                                                        {inquiry.category === 'bug' ? '버그' : inquiry.category === 'suggestion' ? '건의' : '질문'}
                                                    </span>
                                                    <h4 className="text-sm font-bold text-slate-900 dark:text-white truncate tracking-tight">{inquiry.title}</h4>
                                                </div>
                                                <div className="flex items-center gap-1.5 text-xs text-slate-500">
                                                    <User className="w-3 h-3" />
                                                    <span>{inquiry.user?.full_name}</span>
                                                    {inquiry.images && inquiry.images.length > 0 && (
                                                        <>
                                                            <span className="w-0.5 h-0.5 bg-slate-300 rounded-full mx-1" />
                                                            <ImageIcon className="w-3 h-3" />
                                                            <span>사진 {inquiry.images.length}</span>
                                                        </>
                                                    )}
                                                </div>
                                            </div>
                                            <ChevronRight className={cn(
                                                "w-5 h-5 text-slate-300 transition-all group-hover:translate-x-1",
                                                selectedInquiry?.id === inquiry.id && "text-indigo-500"
                                            )} />
                                        </div>
                                    );
                                })
                            )}
                        </div>
                    </div>
                </div>

                {/* Response Detail Area (Right) */}
                <div className={cn(
                    "xl:col-span-7",
                    !selectedInquiry && "hidden xl:block"
                )}>
                    {!selectedInquiry ? (
                        <div className="h-full min-h-[600px] bg-slate-50 dark:bg-slate-900/40 border-2 border-dashed border-slate-200 dark:border-slate-800 rounded-[40px] flex flex-col items-center justify-center p-20 text-center gap-4">
                            <div className="w-24 h-24 bg-white dark:bg-slate-800 rounded-[32px] flex items-center justify-center shadow-xl">
                                <MessageSquare className="w-10 h-10 text-slate-200" />
                            </div>
                            <div className="space-y-1">
                                <h3 className="text-lg font-black text-slate-400 dark:text-slate-600">문의 내용을 선택하세요</h3>
                                <p className="text-slate-400 dark:text-slate-600 text-sm font-bold">리스트에서 문의를 선택하면 상세 내용과 답변 내역이 표시됩니다.</p>
                            </div>
                        </div>
                    ) : (
                        <div className="bg-white dark:bg-[#111827]/60 backdrop-blur-xl border border-slate-200 dark:border-slate-800/60 rounded-[32px] flex flex-col shadow-xl overflow-hidden animate-in slide-in-from-right-4 duration-300 min-h-[700px]">
                            {/* Chat Header */}
                            <div className="p-6 border-b border-slate-100 dark:border-slate-800 bg-slate-50/30 dark:bg-slate-800/30 flex items-center justify-between">
                                <div className="flex items-center gap-4">
                                    <button onClick={() => setSelectedInquiry(null)} className="xl:hidden p-2 hover:bg-slate-100 dark:hover:bg-slate-800 rounded-xl transition-colors">
                                        <ArrowLeft className="w-5 h-5" />
                                    </button>
                                    <div>
                                        <div className="flex items-center gap-2">
                                            <h4 className="text-lg font-black text-slate-900 dark:text-white tracking-tight">{selectedInquiry.title}</h4>
                                            <div className="flex items-center gap-1.5 px-2 py-0.5 bg-indigo-50 dark:bg-indigo-500/10 border border-indigo-100 dark:border-indigo-500/20 rounded-lg shrink-0">
                                                <Church className="w-3 h-3 text-indigo-600 dark:text-indigo-400" />
                                                <span className="text-[10px] font-black text-indigo-600 dark:text-indigo-400 uppercase tracking-tight">
                                                    {selectedInquiry.user?.church?.name || '소속 없음'} {selectedInquiry.user?.department?.name ? `· ${selectedInquiry.user.department.name}` : ''}
                                                </span>
                                            </div>
                                        </div>
                                        <p className="text-xs text-slate-500 font-bold">{selectedInquiry.user?.full_name} · {new Date(selectedInquiry.created_at).toLocaleString()}</p>
                                    </div>
                                </div>
                                <div className="flex items-center gap-3">
                                    <span className="px-3 py-1.5 bg-slate-100 dark:bg-slate-800 text-slate-500 rounded-xl text-[10px] font-black uppercase tracking-widest flex items-center gap-1.5">
                                        <Tag className="w-3 h-3" /> {selectedInquiry.category === 'bug' ? '버그/오류' : selectedInquiry.category === 'question' ? '질문' : '건의사항'}
                                    </span>
                                    {selectedInquiry.status !== 'completed' && (
                                        <button
                                            onClick={handleCompleteInquiry}
                                            className="px-3 py-1.5 bg-emerald-50 dark:bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-100 dark:border-emerald-500/20 rounded-xl text-[10px] font-black uppercase tracking-widest flex items-center gap-1.5 hover:bg-emerald-500 hover:text-white transition-all shadow-lg shadow-emerald-500/10"
                                        >
                                            <CheckCircle2 className="w-3.5 h-3.5" /> 상담 종료
                                        </button>
                                    )}
                                </div>
                            </div>

                            {/* Chat Content */}
                            <div
                                ref={chatContainerRef}
                                className="flex-1 overflow-y-auto p-8 space-y-10 custom-scrollbar bg-slate-50/10 dark:bg-slate-900/10 max-h-[600px]"
                            >
                                {/* Original Inquiry Message (Isolated Section) */}
                                <div className="space-y-4">
                                    <div className="flex items-center justify-center">
                                        <div className="h-px bg-slate-200 dark:bg-slate-800 flex-1" />
                                        <span className="px-4 text-[10px] font-black text-slate-400 uppercase tracking-widest">문의 원본 내용</span>
                                        <div className="h-px bg-slate-200 dark:bg-slate-800 flex-1" />
                                    </div>
                                    <div className="bg-white dark:bg-slate-800/80 p-6 rounded-[32px] border border-slate-100 dark:border-slate-700/50 shadow-sm mx-auto max-w-[90%]">
                                        <h5 className="text-base font-black text-slate-900 dark:text-white mb-3 tracking-tight">{selectedInquiry.title}</h5>
                                        <p className="text-slate-600 dark:text-slate-300 font-bold leading-relaxed whitespace-pre-wrap text-sm">{selectedInquiry.content}</p>

                                        {selectedInquiry.images && selectedInquiry.images.length > 0 && (
                                            <div className="mt-4 flex gap-2 overflow-x-auto pb-2 scrollbar-thin scrollbar-thumb-slate-200">
                                                {selectedInquiry.images.map((img: string, idx: number) => (
                                                    <div
                                                        key={idx}
                                                        className="relative w-24 h-24 shrink-0 rounded-xl overflow-hidden border border-slate-100 cursor-pointer group"
                                                        onClick={() => setPreviewImage(img)}
                                                    >
                                                        <img src={img} alt={`attached-${idx}`} className="w-full h-full object-cover transition-transform group-hover:scale-110" />
                                                        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/10 transition-colors" />
                                                    </div>
                                                ))}
                                            </div>
                                        )}
                                    </div>
                                </div>

                                <div className="space-y-8 pt-4">
                                    <div className="flex items-center justify-center">
                                        <div className="h-px bg-slate-200 dark:bg-slate-800 flex-1" />
                                        <span className="px-4 text-[10px] font-black text-slate-400 uppercase tracking-widest">상담 대화 내역</span>
                                        <div className="h-px bg-slate-200 dark:bg-slate-800 flex-1" />
                                    </div>

                                    {responses.length === 0 ? (
                                        <div className="text-center py-10 opacity-30">
                                            <MessageSquare className="w-10 h-10 mx-auto mb-2 text-slate-400" />
                                            <p className="text-xs font-bold text-slate-400">관리자의 답변을 기다리고 있습니다.</p>
                                        </div>
                                    ) : (
                                        responses.map((res) => {
                                            const isAdmin = !!res.admin_id;
                                            return (
                                                <div key={res.id} className={cn("flex", isAdmin ? "justify-end" : "justify-start")}>
                                                    <div className="max-w-[85%] space-y-2">
                                                        <div className={cn(
                                                            "p-5 rounded-[24px] border shadow-sm",
                                                            isAdmin
                                                                ? "bg-indigo-600 text-white border-transparent rounded-tr-none shadow-indigo-500/20"
                                                                : "bg-white dark:bg-slate-900 text-slate-900 dark:text-white border-slate-100 dark:border-slate-800 rounded-tl-none"
                                                        )}>
                                                            <p className="font-bold leading-relaxed whitespace-pre-wrap text-sm">{res.content}</p>
                                                            {res.images && res.images.length > 0 && (
                                                                <div className="mt-3 flex gap-2 flex-wrap">
                                                                    {res.images.map((img: string, idx: number) => (
                                                                        <div
                                                                            key={idx}
                                                                            className="relative w-20 h-20 shrink-0 rounded-lg overflow-hidden border border-white/20 cursor-pointer group"
                                                                            onClick={() => setPreviewImage(img)}
                                                                        >
                                                                            <img src={img} alt={`response-${idx}`} className="w-full h-full object-cover transition-transform group-hover:scale-110" />
                                                                        </div>
                                                                    ))}
                                                                </div>
                                                            )}
                                                        </div>
                                                        <div className={cn("flex items-center gap-2", isAdmin ? "flex-row-reverse pr-2" : "pl-2")}>
                                                            <p className="text-[10px] text-slate-400 font-black tracking-tight">
                                                                {isAdmin ? (res.admin?.full_name || '관리자') : '사용자'}
                                                            </p>
                                                            <span className="w-1 h-1 bg-slate-300 dark:bg-slate-700 rounded-full" />
                                                            <p className="text-[10px] text-slate-400 font-bold">
                                                                {new Date(res.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                                                            </p>
                                                        </div>
                                                    </div>
                                                </div>
                                            );
                                        })
                                    )}
                                </div>
                            </div>

                            {/* Chat Input */}
                            <div className="p-8 bg-white dark:bg-slate-900 border-t border-slate-100 dark:border-slate-800">
                                {selectedInquiry.status === 'completed' ? (
                                    <div className="p-6 bg-slate-50 dark:bg-slate-800/50 rounded-2xl border border-dashed border-slate-200 dark:border-slate-700 text-center">
                                        <div className="flex items-center justify-center gap-2 mb-1">
                                            <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                                            <p className="text-sm font-black text-slate-900 dark:text-white">종료된 상담 건입니다.</p>
                                        </div>
                                        <p className="text-xs font-bold text-slate-400">대화 내용은 보관되며 추가 답변 작성이 제한됩니다.</p>
                                    </div>
                                ) : (
                                    <form onSubmit={handleSendReply} className="relative group p-4 bg-slate-50 dark:bg-slate-800/50 rounded-2xl border-2 border-transparent focus-within:border-indigo-500/30 focus-within:bg-white dark:focus-within:bg-slate-800 transition-all">
                                        {/* Image Previews */}
                                        {replyImages.length > 0 && (
                                            <div className="flex gap-2 overflow-x-auto pb-4 mb-2">
                                                {replyImages.map((file, idx) => (
                                                    <div key={idx} className="relative w-16 h-16 shrink-0 rounded-lg overflow-hidden border border-slate-200">
                                                        <img src={URL.createObjectURL(file)} alt="preview" className="w-full h-full object-cover" />
                                                        <button
                                                            type="button"
                                                            onClick={() => removeReplyImage(idx)}
                                                            className="absolute top-0.5 right-0.5 p-0.5 bg-black/50 text-white rounded-full hover:bg-black/70"
                                                        >
                                                            <XCircle className="w-3 h-3" />
                                                        </button>
                                                    </div>
                                                ))}
                                            </div>
                                        )}

                                        <div className="flex gap-4">
                                            <button
                                                type="button"
                                                onClick={() => fileInputRef.current?.click()}
                                                className="p-2 text-slate-400 hover:text-indigo-600 transition-colors"
                                            >
                                                <ImageIcon className="w-6 h-6" />
                                            </button>
                                            <input
                                                type="file"
                                                ref={fileInputRef}
                                                className="hidden"
                                                multiple
                                                accept="image/*"
                                                onChange={handleFileSelect}
                                            />

                                            <input
                                                type="text"
                                                value={replyContent}
                                                onChange={(e) => setReplyContent(e.target.value)}
                                                placeholder="사용자에게 답변을 남겨주세요..."
                                                className="flex-1 bg-transparent outline-none font-bold text-slate-900 dark:text-white"
                                            />

                                            <button
                                                type="submit"
                                                disabled={isSubmitting || (!replyContent && replyImages.length === 0)}
                                                className="px-4 py-2 bg-indigo-600 text-white rounded-xl font-black hover:bg-indigo-700 hover:scale-105 transition-all active:scale-95 disabled:opacity-50 disabled:grayscale disabled:scale-100 flex items-center justify-center shadow-lg shadow-indigo-600/20"
                                            >
                                                {isSubmitting ? <Loader2 className="w-5 h-5 animate-spin" /> : <Send className="w-5 h-5" />}
                                            </button>
                                        </div>
                                    </form>
                                )}
                                <p className="text-[10px] text-center text-slate-400 font-black mt-4 uppercase tracking-tighter">
                                    {selectedInquiry.status === 'completed' ? 'ARCHIVED CONVERSATION' : 'REAL-TIME CONSULTATION ACTIVE'}
                                </p>
                            </div>
                        </div>
                    )}
                </div>
            </div>
            {/* Image Preview Lightbox */}
            {previewImage && (
                <div
                    className="fixed inset-0 z-[100] flex items-center justify-center p-10 animate-in fade-in duration-200"
                    onClick={() => setPreviewImage(null)}
                    style={{ marginLeft: 'var(--sidebar-width, 280px)', marginTop: '80px' }} // Approximate sidebar/header offsets
                >
                    <div className="absolute inset-0 bg-black/80 backdrop-blur-sm rounded-[32px] m-4" />

                    <button
                        className="absolute top-8 right-8 z-10 p-2 bg-white/10 hover:bg-white/20 rounded-full text-white transition-colors"
                        onClick={() => setPreviewImage(null)}
                    >
                        <XCircle className="w-8 h-8" />
                    </button>

                    <img
                        src={previewImage}
                        alt="Preview"
                        className="relative z-10 max-w-full max-h-full object-contain rounded-lg shadow-2xl animate-in zoom-in-95 duration-200"
                        onClick={(e) => e.stopPropagation()}
                    />
                </div>
            )}
        </div>
    );
}

