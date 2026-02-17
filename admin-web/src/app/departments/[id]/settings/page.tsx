'use client';

import { useEffect, useState } from 'react';
import { useRouter, useParams, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Loader2,
    ChevronLeft,
    Bell,
    Clock,
    Smartphone,
    Save,
    Settings,
    Layers,
    Palette,
    Check,
    User,
    Users,
    Plus
} from 'lucide-react';
import { cn } from '@/lib/utils';

export default function DepartmentSettingsPage() {
    const { id: deptId } = useParams();
    const router = useRouter();
    const searchParams = useSearchParams();
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [dept, setDept] = useState<any>(null);

    const colorPalette = [
        { name: 'Indigo', hex: '#4f46e5' },
        { name: 'Emerald', hex: '#10b981' },
        { name: 'Rose', hex: '#f43f5e' },
        { name: 'Amber', hex: '#f59e0b' },
        { name: 'Sky', hex: '#0ea5e9' },
        { name: 'Violet', hex: '#8b5cf6' },
        { name: 'Teal', hex: '#14b8a6' },
        { name: 'Slate', hex: '#64748b' }
    ];

    useEffect(() => {
        const fetchDept = async () => {
            if (deptId === 'new') {
                setDept({
                    name: '',
                    profile_mode: 'individual',
                    color_hex: '#4f46e5',
                    leader_reminder_enabled: false,
                    leader_reminder_days: [0, 1, 3, 6],
                    leader_reminder_time: '22:00:00',
                    climbing_alert_enabled: false,
                    climbing_alert_day: 5,
                    climbing_alert_time: '20:00:00'
                });
                setLoading(false);
                return;
            }

            try {
                const { data, error } = await supabase
                    .from('departments')
                    .select('*')
                    .eq('id', deptId)
                    .single();

                if (error) throw error;
                if (!data) {
                    router.push('/departments');
                    return;
                }
                setDept(data);
            } catch (err) {
                console.error('Fetch Dept Error:', err);
                router.push('/departments');
            } finally {
                setLoading(false);
            }
        };

        if (deptId) fetchDept();
    }, [deptId, router]);

    const handleSave = async (e: React.FormEvent) => {
        e.preventDefault();
        setSaving(true);
        try {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) throw new Error('로그인이 필요합니다.');

            const payload = {
                name: dept.name,
                profile_mode: dept.profile_mode,
                color_hex: dept.color_hex,
                leader_reminder_enabled: dept.leader_reminder_enabled,
                leader_reminder_days: dept.leader_reminder_days,
                leader_reminder_time: dept.leader_reminder_time,
                climbing_alert_enabled: dept.climbing_alert_enabled,
                climbing_alert_day: dept.climbing_alert_day,
                climbing_alert_time: dept.climbing_alert_time
            };

            if (deptId === 'new') {
                // 신규 생성 시에만 church_id 필요
                const churchIdFromQuery = searchParams.get('churchId');
                let churchId = churchIdFromQuery;
                if (!churchId) {
                    const { data: profile } = await supabase
                        .from('profiles')
                        .select('church_id')
                        .eq('id', session.user.id)
                        .single();
                    churchId = profile?.church_id || null;
                }
                if (!churchId) throw new Error('교회 정보가 없습니다.');

                const { error } = await supabase
                    .from('departments')
                    .insert({
                        ...payload,
                        church_id: churchId
                    });
                if (error) throw error;
                alert('부서가 생성되었습니다.');
            } else {
                const { error } = await supabase
                    .from('departments')
                    .update(payload)
                    .eq('id', deptId);
                if (error) throw error;
                alert('설정이 저장되었습니다.');
            }
            router.push('/departments');
        } catch (err: any) {
            console.error('Save Settings Error:', err);
            alert('오류가 발생했습니다: ' + (err.message || '알 수 없는 오류'));
        } finally {
            setSaving(false);
        }
    };

    if (loading) {
        return (
            <div className="flex items-center justify-center min-h-screen">
                <Loader2 className="w-8 h-8 animate-spin text-indigo-600" />
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-slate-50 dark:bg-slate-950 p-4 sm:p-8">
            <div className="max-w-3xl mx-auto space-y-6">
                {/* Header */}
                <div className="flex items-center justify-between">
                    <div className="flex items-center gap-4">
                        <button
                            onClick={() => router.push('/departments')}
                            className="p-2 hover:bg-slate-200 dark:hover:bg-slate-800 rounded-xl transition-all"
                        >
                            <ChevronLeft className="w-6 h-6 text-slate-600 dark:text-slate-400" />
                        </button>
                        <div>
                            <h1 className="text-2xl font-black text-slate-900 dark:text-white tracking-tight">
                                {deptId === 'new' ? '신규 부서 생성' : '부서 설정'}
                            </h1>
                            <p className="text-sm text-slate-500 font-bold">
                                {deptId === 'new' ? '새로운 부서의 정보를 입력합니다.' : `${dept.name}의 상세 정보를 관리합니다.`}
                            </p>
                        </div>
                    </div>
                    <button
                        onClick={handleSave}
                        disabled={saving}
                        className="flex items-center gap-2 px-6 py-3 bg-indigo-600 dark:bg-indigo-500 text-white font-black rounded-2xl hover:bg-indigo-500 transition-all shadow-lg shadow-indigo-600/20 active:scale-95 disabled:opacity-50 disabled:active:scale-100"
                    >
                        {saving ? <Loader2 className="w-5 h-5 animate-spin" /> : (deptId === 'new' ? <Plus className="w-5 h-5" /> : <Save className="w-5 h-5" />)}
                        <span>{deptId === 'new' ? '생성하기' : '저장하기'}</span>
                    </button>
                </div>

                <form onSubmit={handleSave} className="space-y-6 pb-24">
                    {/* Section 1: Basic Information */}
                    <div className="bg-white dark:bg-slate-900 rounded-xl border border-slate-200 dark:border-slate-800 p-7 sm:p-8 shadow-sm space-y-8">
                        <div className="flex items-center gap-3.5">
                            <div className="w-10 h-10 rounded-xl bg-indigo-50 dark:bg-indigo-500/10 flex items-center justify-center">
                                <Layers className="w-5 h-5 text-indigo-600 dark:text-indigo-400" />
                            </div>
                            <h3 className="text-lg font-black text-slate-900 dark:text-white">기본 정보</h3>
                        </div>

                        <div className="space-y-8">
                            {/* Department Name */}
                            <div className="space-y-2.5">
                                <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">부서 이름</label>
                                <input
                                    type="text"
                                    required
                                    value={dept.name}
                                    onChange={(e) => setDept({ ...dept, name: e.target.value })}
                                    className="w-full px-5 py-3.5 bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800 rounded-2xl focus:outline-none focus:border-indigo-500 text-slate-900 dark:text-white font-black transition-all text-base"
                                    placeholder="예: 청년부"
                                />
                            </div>

                            {/* Theme Color Selection */}
                            <div className="space-y-3.5">
                                <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">부서 테마 색상</label>
                                <div className="flex flex-wrap gap-3 items-center">
                                    {colorPalette.map((color) => (
                                        <button
                                            key={color.hex}
                                            type="button"
                                            onClick={() => setDept({ ...dept, color_hex: color.hex })}
                                            className={cn(
                                                "w-10 h-10 rounded-full flex items-center justify-center transition-all hover:scale-110 active:scale-95 border-4",
                                                dept.color_hex === color.hex ? "border-slate-100 dark:border-slate-800 ring-4 ring-indigo-500/15 shadow-md" : "border-transparent"
                                            )}
                                            style={{ backgroundColor: color.hex }}
                                        >
                                            {dept.color_hex === color.hex && <Check className="w-5 h-5 text-white" />}
                                        </button>
                                    ))}

                                    <div className="relative">
                                        <button
                                            type="button"
                                            className={cn(
                                                "w-10 h-10 rounded-full border-2 border-dashed border-slate-300 dark:border-slate-700 flex items-center justify-center transition-all hover:border-indigo-500 active:scale-95 overflow-hidden",
                                                !colorPalette.some(c => c.hex === dept.color_hex) && "border-indigo-500 ring-4 ring-indigo-500/10"
                                            )}
                                            onClick={() => document.getElementById('custom-color-input')?.click()}
                                            style={{ backgroundColor: !colorPalette.some(c => c.hex === dept.color_hex) ? dept.color_hex : 'transparent' }}
                                        >
                                            {!colorPalette.some(c => c.hex === dept.color_hex) ? (
                                                <Check className="w-5 h-5 text-white" />
                                            ) : (
                                                <Plus className="w-5 h-5 text-slate-400" />
                                            )}
                                        </button>
                                        <input
                                            id="custom-color-input"
                                            type="color"
                                            className="absolute inset-0 opacity-0 cursor-pointer pointer-events-none"
                                            onChange={(e) => setDept({ ...dept, color_hex: e.target.value })}
                                            tabIndex={-1}
                                        />
                                    </div>
                                </div>
                            </div>

                            {/* Profile Mode Selection */}
                            <div className="space-y-4">
                                <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">성도 관리 모드</label>
                                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                    {[
                                        { id: 'individual', title: '개인형', subtitle: '1인 1프로필 관리', icon: User },
                                        { id: 'couple', title: '부부형', subtitle: '부부/가족 단위 정렬 강조', icon: Users }
                                    ].map((mode) => (
                                        <button
                                            key={mode.id}
                                            type="button"
                                            onClick={() => setDept({ ...dept, profile_mode: mode.id as any })}
                                            className={cn(
                                                "flex items-center gap-4 p-5 rounded-[1.75rem] border-2 transition-all text-left group",
                                                dept.profile_mode === mode.id
                                                    ? "bg-indigo-50/50 dark:bg-indigo-500/5 border-indigo-600 shadow-sm"
                                                    : "bg-slate-50 dark:bg-slate-950 border-transparent hover:border-slate-200 dark:hover:border-slate-800"
                                            )}
                                        >
                                            <div className={cn(
                                                "w-12 h-12 rounded-2xl flex items-center justify-center transition-all shadow-sm",
                                                dept.profile_mode === mode.id
                                                    ? "bg-indigo-600 text-white shadow-lg shadow-indigo-600/20"
                                                    : "bg-white dark:bg-slate-900 border border-slate-100 dark:border-slate-800 text-slate-400 group-hover:text-slate-600"
                                            )}>
                                                <mode.icon className="w-6 h-6" />
                                            </div>
                                            <div>
                                                <h4 className={cn(
                                                    "font-black text-base mb-0.5",
                                                    dept.profile_mode === mode.id ? "text-indigo-600 dark:text-white" : "text-slate-900 dark:text-white"
                                                )}>{mode.title}</h4>
                                                <p className="text-[10px] text-slate-500 font-bold tracking-tight">{mode.subtitle}</p>
                                            </div>
                                        </button>
                                    ))}
                                </div>
                            </div>
                        </div>
                    </div>

                    {/* Section 2: Notifications */}
                    <div className="bg-white dark:bg-slate-900 rounded-xl border border-slate-200 dark:border-slate-800 p-7 sm:p-8 shadow-sm space-y-8">
                        <div className="flex items-center gap-3.5">
                            <div className="w-10 h-10 rounded-xl bg-amber-50 dark:bg-amber-500/10 flex items-center justify-center">
                                <Bell className="w-5 h-5 text-amber-600 dark:text-amber-400" />
                            </div>
                            <h3 className="text-lg font-black text-slate-900 dark:text-white">자동 알림 스케줄</h3>
                        </div>

                        <div className="space-y-6">
                            {/* Leader Reminder */}
                            <div className="space-y-5">
                                <div className="flex items-center justify-between p-5 bg-slate-50 dark:bg-slate-950 rounded-[1.5rem] border border-slate-100 dark:border-slate-800 transition-all hover:border-slate-200 dark:hover:border-slate-700">
                                    <div className="space-y-0.5">
                                        <h4 className="text-sm font-black text-slate-900 dark:text-white">조장 리마인더 (미제출자)</h4>
                                        <p className="text-[10px] text-slate-500 font-bold">출석/기도 미등록 조의 조장에게 리마인더 발송</p>
                                    </div>
                                    <label className="relative inline-flex items-center cursor-pointer">
                                        <input
                                            type="checkbox"
                                            className="sr-only peer"
                                            checked={dept.leader_reminder_enabled}
                                            onChange={(e) => setDept({ ...dept, leader_reminder_enabled: e.target.checked })}
                                        />
                                        <div className="w-12 h-6.5 bg-slate-200 dark:bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[4px] after:left-[4px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4.5 after:w-4.5 after:transition-all peer-checked:bg-indigo-600 shadow-inner"></div>
                                    </label>
                                </div>

                                {dept.leader_reminder_enabled && (
                                    <div className="grid grid-cols-1 md:grid-cols-2 gap-6 p-1">
                                        <div className="space-y-3">
                                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest ml-1">알림 요일</label>
                                            <div className="flex flex-wrap gap-2">
                                                {['일', '월', '화', '수', '목', '금', '토'].map((day, idx) => (
                                                    <button
                                                        key={day}
                                                        type="button"
                                                        onClick={() => {
                                                            const days = [...(dept.leader_reminder_days || [])];
                                                            if (days.includes(idx)) {
                                                                setDept({ ...dept, leader_reminder_days: days.filter(d => d !== idx) });
                                                            } else {
                                                                setDept({ ...dept, leader_reminder_days: [...days, idx].sort() });
                                                            }
                                                        }}
                                                        className={cn(
                                                            "w-10 h-10 rounded-xl font-black text-[11px] transition-all border",
                                                            dept.leader_reminder_days?.includes(idx)
                                                                ? "bg-indigo-600 border-indigo-600 text-white shadow-md shadow-indigo-600/10"
                                                                : "bg-white dark:bg-slate-900 border-slate-200 dark:border-slate-800 text-slate-500 hover:border-slate-300"
                                                        )}
                                                    >
                                                        {day}
                                                    </button>
                                                ))}
                                            </div>
                                        </div>
                                        <div className="space-y-3">
                                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest ml-1">알림 발송 시간</label>
                                            <div className="flex items-center gap-3 px-5 py-3.5 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl group focus-within:border-indigo-500 transition-all">
                                                <Clock className="w-4 h-4 text-slate-400 group-focus-within:text-indigo-500" />
                                                <input
                                                    type="time"
                                                    value={dept.leader_reminder_time?.substring(0, 5) || '22:00'}
                                                    onChange={(e) => setDept({ ...dept, leader_reminder_time: e.target.value + ':00' })}
                                                    className="bg-transparent focus:outline-none text-slate-900 dark:text-white font-black text-sm w-full"
                                                />
                                            </div>
                                        </div>
                                    </div>
                                )}
                            </div>

                            <div className="h-px bg-slate-100 dark:bg-slate-800" />

                            {/* Climbing Alert */}
                            <div className="space-y-5">
                                <div className="flex items-center justify-between p-5 bg-slate-50 dark:bg-slate-950 rounded-[1.5rem] border border-slate-100 dark:border-slate-800 transition-all hover:border-slate-200 dark:hover:border-slate-700">
                                    <div className="space-y-0.5">
                                        <h4 className="text-sm font-black text-slate-900 dark:text-white">새가족 등반 알림</h4>
                                        <p className="text-[10px] text-slate-500 font-bold">등반 예정자가 있는 경우 조장에게 자동 알림</p>
                                    </div>
                                    <label className="relative inline-flex items-center cursor-pointer">
                                        <input
                                            type="checkbox"
                                            className="sr-only peer"
                                            checked={dept.climbing_alert_enabled}
                                            onChange={(e) => setDept({ ...dept, climbing_alert_enabled: e.target.checked })}
                                        />
                                        <div className="w-12 h-6.5 bg-slate-200 dark:bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[4px] after:left-[4px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4.5 after:w-4.5 after:transition-all peer-checked:bg-indigo-600 shadow-inner"></div>
                                    </label>
                                </div>

                                {dept.climbing_alert_enabled && (
                                    <div className="grid grid-cols-1 md:grid-cols-2 gap-6 p-1">
                                        <div className="space-y-3">
                                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest ml-1">알림 요일 (매주 1회)</label>
                                            <div className="flex flex-wrap gap-2">
                                                {['일', '월', '화', '수', '목', '금', '토'].map((day, idx) => (
                                                    <button
                                                        key={day}
                                                        type="button"
                                                        onClick={() => setDept({ ...dept, climbing_alert_day: idx })}
                                                        className={cn(
                                                            "w-10 h-10 rounded-xl font-black text-[11px] transition-all border",
                                                            dept.climbing_alert_day === idx
                                                                ? "bg-indigo-600 border-indigo-600 text-white shadow-md shadow-indigo-600/10"
                                                                : "bg-white dark:bg-slate-900 border-slate-200 dark:border-slate-800 text-slate-500 hover:border-slate-300"
                                                        )}
                                                    >
                                                        {day}
                                                    </button>
                                                ))}
                                            </div>
                                        </div>
                                        <div className="space-y-3">
                                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest ml-1">알림 발송 시간</label>
                                            <div className="flex items-center gap-3 px-5 py-3.5 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl group focus-within:border-indigo-500 transition-all">
                                                <Clock className="w-4 h-4 text-slate-400 group-focus-within:text-indigo-500" />
                                                <input
                                                    type="time"
                                                    value={dept.climbing_alert_time?.substring(0, 5) || '20:00'}
                                                    onChange={(e) => setDept({ ...dept, climbing_alert_time: e.target.value + ':00' })}
                                                    className="bg-transparent focus:outline-none text-slate-900 dark:text-white font-black text-sm w-full"
                                                />
                                            </div>
                                        </div>
                                    </div>
                                )}
                            </div>
                        </div>
                    </div>
                </form>
            </div >
        </div >
    );
}
