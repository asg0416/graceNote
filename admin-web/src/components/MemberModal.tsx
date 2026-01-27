'use client';

import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { Modal } from '@/components/Modal';
import RichTextEditor from '@/components/RichTextEditor';

interface MemberModalProps {
    isOpen: boolean;
    onClose: () => void;
    onSuccess: (member: any) => void;
    member?: any; // If provided, it's Edit mode
    churchId: string;
    departmentId?: string;
    groupId?: string;
    groupName?: string;
    departments: any[];
    groups?: any[]; // For local state support (Regrouping Dashboard)
}

export const MemberModal: React.FC<MemberModalProps> = ({
    isOpen,
    onClose,
    onSuccess,
    member,
    churchId,
    departmentId,
    groupId,
    groupName,
    departments,
    groups
}) => {
    const [loading, setLoading] = useState(false);
    const [formData, setFormData] = useState<any>({
        full_name: '',
        phone: '',
        spouse_name: '',
        children_info: '',
        group_name: groupName || '',
        department_id: departmentId || '',
        role_in_group: 'member',
        birth_date: '',
        wedding_anniversary: '',
        notes: '',
        is_linked: false,
        person_id: null
    });

    const [availableGroups, setAvailableGroups] = useState<any[]>([]);
    const [nameSuggestions, setNameSuggestions] = useState<any[]>([]);

    useEffect(() => {
        if (member) {
            setFormData({
                ...member,
                department_id: member.department_id || departmentId
            });
        } else {
            setFormData({
                full_name: '',
                phone: '',
                spouse_name: '',
                children_info: '',
                group_name: groupName || '',
                department_id: departmentId || '',
                role_in_group: 'member',
                birth_date: '',
                wedding_anniversary: '',
                notes: '',
                is_linked: false,
                person_id: null
            });
        }
    }, [member, departmentId, groupName, isOpen]);

    useEffect(() => {
        const fetchGroups = async () => {
            if (formData.department_id) {
                // If local groups are provided (Regrouping Dashboard), use them
                if (groups && groups.length > 0) {
                    const localGroups = groups
                        .filter(g => g.department_id === formData.department_id)
                        .map(g => ({ name: g.name }));
                    setAvailableGroups(localGroups);
                } else {
                    // Otherwise fetch from DB
                    const { data } = await supabase
                        .from('groups')
                        .select('name')
                        .eq('department_id', formData.department_id)
                        .order('name');
                    setAvailableGroups(data || []);
                }
            } else {
                setAvailableGroups([]);
            }
        };
        fetchGroups();
    }, [formData.department_id, groups]);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!formData.phone?.trim()) {
            alert('전화번호는 필수 입력 사항입니다.');
            return;
        }
        setLoading(true);
        try {
            const {
                departments: _dept,
                profiles: _prof,
                _availableGroups,
                _profileMode,
                _affiliations,
                ...dataToSave
            } = {
                ...formData,
                church_id: churchId,
            };

            let result;
            if (member?.id && !member.id.startsWith('temp-')) {
                // Real update
                const { data, error } = await supabase
                    .from('member_directory')
                    .update(dataToSave)
                    .eq('id', member.id)
                    .select()
                    .single();
                if (error) throw error;
                result = data;
            } else {
                // Insert or local success for RegroupingPage
                // In RegroupingPage, we might want to just return the data for local state update
                result = {
                    ...dataToSave,
                    id: member?.id || `temp-new-${Date.now()}`
                };
            }

            onSuccess(result);
            onClose();
        } catch (err: any) {
            console.error(err);
            alert('오류가 발생했습니다: ' + (err.message || '알 수 없는 오류'));
        } finally {
            setLoading(false);
        }
    };

    return (
        <Modal
            isOpen={isOpen}
            onClose={onClose}
            title={member ? "성도 정보 수정" : "성도 추가"}
            subtitle={member ? "Edit Member Information" : "New Member"}
            maxWidth="2xl"
        >
            <form onSubmit={handleSubmit} className="space-y-6">
                <div className="grid grid-cols-2 gap-6">
                    <div className="space-y-2">
                        <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">이름</label>
                        <div className="relative">
                            <input
                                type="text"
                                required
                                value={formData.full_name}
                                onChange={async (e) => {
                                    const val = e.target.value;
                                    setFormData({ ...formData, full_name: val });
                                    if (!member && val.length >= 2) {
                                        const { data } = await supabase
                                            .from('member_directory')
                                            .select('*')
                                            .ilike('full_name', `%${val}%`)
                                            .limit(5);
                                        setNameSuggestions(data || []);
                                    } else {
                                        setNameSuggestions([]);
                                    }
                                }}
                                className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 font-bold"
                            />
                            {nameSuggestions.length > 0 && (
                                <div className="absolute top-full left-0 right-0 mt-2 bg-white dark:bg-slate-950 border border-slate-200 dark:border-slate-800 rounded-2xl shadow-2xl z-[100] overflow-hidden animate-in fade-in slide-in-from-top-1">
                                    <div className="p-2 border-b border-slate-100 dark:border-slate-800">
                                        <p className="text-[10px] font-black text-slate-400 uppercase tracking-widest pl-2">기존 성도 정보 불러오기</p>
                                    </div>
                                    {nameSuggestions.map((m, idx) => (
                                        <button
                                            key={idx}
                                            type="button"
                                            onClick={() => {
                                                setFormData({
                                                    ...formData,
                                                    full_name: m.full_name,
                                                    phone: m.phone || '',
                                                    spouse_name: m.spouse_name || '',
                                                    children_info: m.children_info || '',
                                                    birth_date: m.birth_date || '',
                                                    wedding_anniversary: m.wedding_anniversary || '',
                                                    notes: m.notes || '',
                                                    person_id: m.person_id,
                                                    is_linked: m.is_linked
                                                });
                                                setNameSuggestions([]);
                                            }}
                                            className="w-full flex items-center justify-between px-4 py-3 hover:bg-indigo-50 dark:hover:bg-indigo-500/10 text-left transition-colors group"
                                        >
                                            <div className="flex flex-col">
                                                <span className="text-xs font-black text-slate-900 dark:text-white">{m.full_name}</span>
                                                <span className="text-[10px] text-slate-400 font-bold">{m.phone || '연락처 없음'}</span>
                                            </div>
                                            <div className="px-2 py-1 bg-slate-100 dark:bg-slate-800 group-hover:bg-indigo-600 group-hover:text-white rounded-lg text-[9px] font-black uppercase tracking-tight transition-colors">
                                                선택
                                            </div>
                                        </button>
                                    ))}
                                </div>
                            )}
                        </div>
                    </div>
                    <div className="space-y-2">
                        <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">연락처</label>
                        <input
                            type="text"
                            required
                            value={formData.phone || ''}
                            onChange={e => setFormData({ ...formData, phone: e.target.value })}
                            className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 font-bold"
                        />
                    </div>
                </div>

                <div className="grid grid-cols-2 gap-6">
                    <div className="space-y-2">
                        <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">부서</label>
                        <select
                            required
                            value={formData.department_id || ''}
                            onChange={e => setFormData({ ...formData, department_id: e.target.value, group_name: '' })}
                            className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 font-bold"
                        >
                            <option value="">부서 선택</option>
                            {departments.map(d => <option key={d.id} value={d.id}>{d.name}</option>)}
                        </select>
                    </div>
                    <div className="space-y-2">
                        <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">조 선택</label>
                        <select
                            value={formData.group_name || ''}
                            onChange={e => setFormData({ ...formData, group_name: e.target.value })}
                            className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 font-bold"
                        >
                            <option value="">조 선택 (없음)</option>
                            {availableGroups.map(g => (
                                <option key={g.name} value={g.name}>{g.name}</option>
                            ))}
                        </select>
                    </div>
                </div>

                <div className="grid grid-cols-2 gap-6">
                    <div className="space-y-2">
                        <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">배우자</label>
                        <input
                            type="text"
                            value={formData.spouse_name || ''}
                            onChange={e => setFormData({ ...formData, spouse_name: e.target.value })}
                            className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 font-bold"
                        />
                    </div>
                    <div className="space-y-2">
                        <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">자녀 정보</label>
                        <input
                            type="text"
                            value={formData.children_info || ''}
                            onChange={e => setFormData({ ...formData, children_info: e.target.value })}
                            className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 font-bold"
                        />
                    </div>
                </div>

                <div className="grid grid-cols-2 gap-6">
                    <div className="space-y-2">
                        <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">생년월일</label>
                        <input
                            type="date"
                            value={formData.birth_date || ''}
                            onChange={e => setFormData({ ...formData, birth_date: e.target.value })}
                            className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 font-bold"
                        />
                    </div>
                    <div className="space-y-2">
                        <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">결혼기념일</label>
                        <input
                            type="date"
                            value={formData.wedding_anniversary || ''}
                            onChange={e => setFormData({ ...formData, wedding_anniversary: e.target.value })}
                            className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 font-bold"
                        />
                    </div>
                </div>

                <div className="space-y-2">
                    <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">직분/역할</label>
                    <select
                        value={formData.role_in_group}
                        onChange={e => setFormData({ ...formData, role_in_group: e.target.value })}
                        className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 font-bold"
                    >
                        <option value="member">조원</option>
                        <option value="leader">조장</option>
                    </select>
                </div>

                <div className="space-y-2">
                    <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1">기타 사항 (메모)</label>
                    <RichTextEditor
                        content={formData.notes || ''}
                        onChange={val => setFormData({ ...formData, notes: val })}
                        placeholder="특이사항이나 메모를 입력하세요..."
                    />
                </div>

                <div className="flex gap-4 pt-4 shrink-0">
                    <button type="button" onClick={onClose} className="flex-1 py-4 bg-slate-100 dark:bg-slate-900 text-slate-500 font-black rounded-3xl hover:bg-slate-200 transition-all">취소</button>
                    <button type="submit" disabled={loading} className="flex-1 py-4 bg-indigo-600 text-white font-black rounded-3xl hover:bg-indigo-500 transition-all shadow-xl shadow-indigo-600/20 disabled:opacity-50">
                        {loading ? '처리 중...' : (member ? '수정하기' : '추가하기')}
                    </button>
                </div>
            </form>
        </Modal>
    );
};
