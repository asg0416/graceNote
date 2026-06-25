'use client';

import { useMemo, useState } from 'react';
import type { ClipboardEvent, DragEvent, KeyboardEvent } from 'react';
import { ChevronDown } from 'lucide-react';
import { clampDateToRange, clampPeriodUpdate } from '@/lib/regroupingPeriodBulk';

type SeasonGroup = {
    id: string;
    name: string;
    color_hex?: string | null;
    starts_week_date?: string | null;
    ends_week_date?: string | null;
};

type MovedSeasonMember = {
    id: string;
    full_name: string;
    changeType: 'moved' | 'added' | 'removed' | 'period';
    previousGroupName: string | null;
    nextGroupName: string;
    starts_week_date?: string | null;
    ends_week_date?: string | null;
    recommended_starts_week_date?: string | null;
    recommended_ends_week_date?: string | null;
    selectableForBulkNormalize?: boolean;
};

const memberChangeMeta: Record<MovedSeasonMember['changeType'], {
    label: string;
    tabClassName: string;
    activeTabClassName: string;
    rowClassName: string;
    badgeClassName: string;
    groupClassName: string;
}> = {
    moved: {
        // 기존 조에서 다른 조로 이동 — 이전 조 소속 row의 group_id가 변경됨 (이전 조 소속은 사라짐)
        label: '소속 이동',
        tabClassName: 'bg-blue-50 text-blue-700 ring-1 ring-blue-100 hover:bg-blue-100 dark:bg-blue-500/10 dark:text-blue-300 dark:ring-blue-500/20',
        activeTabClassName: 'bg-blue-600 text-white shadow-sm shadow-blue-500/20',
        rowClassName: 'border-blue-100 bg-blue-50/55 dark:border-blue-500/20 dark:bg-blue-500/10',
        badgeClassName: 'bg-blue-600 text-white',
        groupClassName: 'bg-blue-100 text-blue-800 dark:bg-blue-400/10 dark:text-blue-200',
    },
    added: {
        // 복사(다중편성)로 새 소속 row 추가 — 이전 조 소속은 그대로 유지되고 새 조에도 추가됨
        label: '다중 소속 추가',
        tabClassName: 'bg-emerald-50 text-emerald-700 ring-1 ring-emerald-100 hover:bg-emerald-100 dark:bg-emerald-500/10 dark:text-emerald-300 dark:ring-emerald-500/20',
        activeTabClassName: 'bg-emerald-600 text-white shadow-sm shadow-emerald-500/20',
        rowClassName: 'border-emerald-100 bg-emerald-50/55 dark:border-emerald-500/20 dark:bg-emerald-500/10',
        badgeClassName: 'bg-emerald-600 text-white',
        groupClassName: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-400/10 dark:text-emerald-200',
    },
    removed: {
        // 조 소속 종료 — 미편성 전환, 조 종료, 다중소속 일부 제거를 모두 포함
        label: '소속 종료',
        tabClassName: 'bg-rose-50 text-rose-700 ring-1 ring-rose-100 hover:bg-rose-100 dark:bg-rose-500/10 dark:text-rose-300 dark:ring-rose-500/20',
        activeTabClassName: 'bg-rose-600 text-white shadow-sm shadow-rose-500/20',
        rowClassName: 'border-rose-100 bg-rose-50/55 dark:border-rose-500/20 dark:bg-rose-500/10',
        badgeClassName: 'bg-rose-600 text-white',
        groupClassName: 'bg-rose-100 text-rose-800 dark:bg-rose-400/10 dark:text-rose-200',
    },
    period: {
        // 조 이동 없이 소속 적용 기간만 기본 기간과 다르게 설정된 경우
        label: '기간 조정',
        tabClassName: 'bg-amber-50 text-amber-700 ring-1 ring-amber-100 hover:bg-amber-100 dark:bg-amber-500/10 dark:text-amber-300 dark:ring-amber-500/20',
        activeTabClassName: 'bg-amber-500 text-white shadow-sm shadow-amber-500/20',
        rowClassName: 'border-amber-100 bg-amber-50/55 dark:border-amber-500/20 dark:bg-amber-500/10',
        badgeClassName: 'bg-amber-500 text-white',
        groupClassName: 'bg-amber-100 text-amber-800 dark:bg-amber-400/10 dark:text-amber-200',
    },
};

interface SeasonChangeHistoryPanelProps {
    archivedGroups: SeasonGroup[];
    newGroups: SeasonGroup[];
    movedMembers: MovedSeasonMember[];
    seasonEffectiveWeekDate: string;
    seasonEndWeekDate: string;
    startMaxWeekDate?: string | null;
    readOnly: boolean;
    onArchivedGroupStartChange: (groupId: string, value: string) => void;
    onArchivedGroupEndChange: (groupId: string, value: string) => void;
    onNewGroupStartChange: (groupId: string, value: string) => void;
    onNewGroupEndChange: (groupId: string, value: string) => void;
    onMovedMemberStartChange: (memberId: string, value: string) => void;
    onMovedMemberEndChange: (memberId: string, value: string) => void;
    onBulkUpdateMovedMemberPeriods: (memberIds: string[], updates: { starts_week_date?: string | null; ends_week_date?: string | null }) => void;
    onRestoreArchivedGroup: (groupId: string) => void;
}

export function SeasonChangeHistoryPanel({
    archivedGroups,
    newGroups,
    movedMembers,
    seasonEffectiveWeekDate,
    seasonEndWeekDate,
    startMaxWeekDate,
    readOnly,
    onArchivedGroupStartChange,
    onArchivedGroupEndChange,
    onNewGroupStartChange,
    onNewGroupEndChange,
    onMovedMemberStartChange,
    onMovedMemberEndChange,
    onBulkUpdateMovedMemberPeriods,
    onRestoreArchivedGroup,
}: SeasonChangeHistoryPanelProps) {
    const [memberTab, setMemberTab] = useState<'all' | MovedSeasonMember['changeType']>('all');
    const [selectedPeriodMemberIds, setSelectedPeriodMemberIds] = useState<string[]>([]);
    const [bulkStartsWeekDate, setBulkStartsWeekDate] = useState(seasonEffectiveWeekDate);
    const [bulkEndsWeekDate, setBulkEndsWeekDate] = useState(seasonEndWeekDate);
    const [bulkDateScope, setBulkDateScope] = useState(`${seasonEffectiveWeekDate}:${seasonEndWeekDate}`);
    const memberTabOptions = useMemo(() => {
        const labelByType: Record<'all' | MovedSeasonMember['changeType'], string> = {
            all: '전체',
            moved: memberChangeMeta.moved.label,
            added: memberChangeMeta.added.label,
            removed: memberChangeMeta.removed.label,
            period: memberChangeMeta.period.label,
        };
        const types: Array<'all' | MovedSeasonMember['changeType']> = ['all', 'moved', 'added', 'removed', 'period'];
        return types.map(type => ({
            type,
            label: labelByType[type],
            count: type === 'all'
                ? movedMembers.length
            : movedMembers.filter(member => member.changeType === type).length,
        })).filter(option => option.type === 'all' || option.count > 0);
    }, [movedMembers]);
    const effectiveMemberTab = memberTabOptions.some(option => option.type === memberTab) ? memberTab : 'all';
    const visibleMovedMembers = effectiveMemberTab === 'all'
        ? movedMembers
        : movedMembers.filter(member => member.changeType === effectiveMemberTab);
    const isPeriodTab = effectiveMemberTab === 'period';
    const periodAdjustmentMemberIds = movedMembers
        .filter(member => member.changeType === 'period' && member.selectableForBulkNormalize !== false)
        .map(member => member.id);
    const selectedValidPeriodMemberIds = selectedPeriodMemberIds.filter(id => periodAdjustmentMemberIds.includes(id));
    const selectedPeriodMemberIdSet = new Set(selectedValidPeriodMemberIds);
    const allPeriodMembersSelected = periodAdjustmentMemberIds.length > 0
        && periodAdjustmentMemberIds.every(id => selectedPeriodMemberIdSet.has(id));
    const currentBulkDateScope = `${seasonEffectiveWeekDate}:${seasonEndWeekDate}:${startMaxWeekDate || ''}`;
    const isBulkDateScopeCurrent = bulkDateScope === currentBulkDateScope;
    const resolvedBulkStartsWeekDate = isBulkDateScopeCurrent ? bulkStartsWeekDate : seasonEffectiveWeekDate;
    const resolvedBulkEndsWeekDate = isBulkDateScopeCurrent ? bulkEndsWeekDate : seasonEndWeekDate;
    const hasSelectedPeriodMembers = selectedValidPeriodMemberIds.length > 0;
    const isBulkPeriodRangeValid = Boolean(resolvedBulkStartsWeekDate)
        && Boolean(resolvedBulkEndsWeekDate)
        && resolvedBulkStartsWeekDate <= resolvedBulkEndsWeekDate;

    const togglePeriodMember = (id: string) => {
        setSelectedPeriodMemberIds(prev => (
            prev.includes(id)
                ? prev.filter(item => item !== id)
                : [...prev, id]
        ));
    };

    const toggleAllPeriodMembers = () => {
        setSelectedPeriodMemberIds(allPeriodMembersSelected ? [] : periodAdjustmentMemberIds);
    };

    const applyBulkPeriodDates = () => {
        if (!hasSelectedPeriodMembers || !isBulkPeriodRangeValid) return;

        onBulkUpdateMovedMemberPeriods(
            selectedValidPeriodMemberIds,
            clampPeriodUpdate(
                {
                    starts_week_date: resolvedBulkStartsWeekDate,
                    ends_week_date: resolvedBulkEndsWeekDate,
                },
                {
                    min: seasonEffectiveWeekDate,
                    startMax: startMaxWeekDate || seasonEndWeekDate,
                    endMax: seasonEndWeekDate,
                }
            )
        );
    };

    const updateBulkStartsWeekDate = (value: string) => {
        setBulkDateScope(currentBulkDateScope);
        setBulkStartsWeekDate(value);
    };

    const updateBulkEndsWeekDate = (value: string) => {
        setBulkDateScope(currentBulkDateScope);
        setBulkEndsWeekDate(value);
    };

    const getMemberPeriodBounds = (member: MovedSeasonMember) => {
        const min = member.recommended_starts_week_date || seasonEffectiveWeekDate;
        const endMax = member.recommended_ends_week_date || seasonEndWeekDate;
        const startMax = startMaxWeekDate && startMaxWeekDate < endMax ? startMaxWeekDate : endMax;
        return { min, startMax, endMax };
    };

    const handleMemberStartChange = (member: MovedSeasonMember, value: string) => {
        const bounds = getMemberPeriodBounds(member);
        onMovedMemberStartChange(member.id, clampDateToRange(value, bounds.min, bounds.startMax));
    };

    const handleMemberEndChange = (member: MovedSeasonMember, value: string) => {
        const bounds = getMemberPeriodBounds(member);
        onMovedMemberEndChange(member.id, clampDateToRange(value, bounds.min, bounds.endMax));
    };

    const getStartInputMax = (endMax?: string | null) => {
        const resolvedEndMax = endMax || seasonEndWeekDate;
        return startMaxWeekDate && startMaxWeekDate < resolvedEndMax ? startMaxWeekDate : resolvedEndMax;
    };

    const preventManualDateEntry = (event: KeyboardEvent<HTMLInputElement>) => {
        const allowedKeys = new Set([
            'Tab',
            'Escape',
            'Enter',
            'ArrowLeft',
            'ArrowRight',
            'ArrowUp',
            'ArrowDown',
            'Home',
            'End',
        ]);

        if (!allowedKeys.has(event.key)) {
            event.preventDefault();
        }
    };

    const preventDateTextInput = (event: ClipboardEvent<HTMLInputElement> | DragEvent<HTMLInputElement>) => {
        event.preventDefault();
    };

    return (
        <section className="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <details className="group">
                <summary className="flex cursor-pointer list-none items-center justify-between gap-4">
                    <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2">
                            <span className="text-base font-black text-slate-950 dark:text-white">시즌 변경 내역</span>
                            <span className="rounded-full bg-slate-100 px-2.5 py-1 text-[10px] font-black text-slate-500 dark:bg-slate-800">
                                종료 조 {archivedGroups.length}
                            </span>
                            <span className="rounded-full bg-blue-50 px-2.5 py-1 text-[10px] font-black text-blue-600 dark:bg-blue-500/10 dark:text-blue-300">
                                신규 조 {newGroups.length}
                            </span>
                            <span className="rounded-full bg-amber-50 px-2.5 py-1 text-[10px] font-black text-amber-700 dark:bg-amber-500/10 dark:text-amber-300">
                                소속 {movedMembers.length}
                            </span>
                        </div>
                        <p className="mt-1 text-xs font-bold text-slate-400">
                            시즌 안에서 조와 성도 소속이 실제로 유효한 기간을 확인하고, 기본 기간과 다른 소속 기간만 조정합니다.
                        </p>
                    </div>
                    <ChevronDown className="h-5 w-5 shrink-0 text-slate-400 transition group-open:rotate-180" />
                </summary>

                <div className="mt-5 grid gap-4 border-t border-slate-100 pt-5 dark:border-slate-800">
                    {archivedGroups.length === 0 && newGroups.length === 0 && movedMembers.length === 0 ? (
                        <div className="rounded-2xl border border-dashed border-slate-200 bg-slate-50 px-4 py-6 text-center text-xs font-black text-slate-400 dark:border-slate-800 dark:bg-slate-950/50">
                            아직 시즌 안에서 별도로 조정할 기간 내역이 없습니다.
                        </div>
                    ) : (
                        <>
                            {archivedGroups.length > 0 && (
                                <div className="space-y-2">
                                    <div>
                                        <h3 className="text-[11px] font-black uppercase tracking-[0.18em] text-rose-500">종료된 조</h3>
                                        <p className="mt-1 text-[11px] font-bold text-slate-400">종료된 조의 실제 활동 기간입니다. 현재 시즌 안에서만 다시 편성할 수 있습니다.</p>
                                    </div>
                                    {archivedGroups.map(group => (
                                        <div key={group.id} className="grid gap-3 rounded-2xl border border-rose-100 bg-rose-50/50 p-3 dark:border-rose-500/20 dark:bg-rose-500/10 lg:grid-cols-[1fr_160px_190px] lg:items-center">
                                            <div className="min-w-0">
                                                <div className="flex flex-wrap items-center gap-2">
                                                    <span
                                                        className="h-2.5 w-2.5 rounded-full"
                                                        style={{ backgroundColor: group.color_hex || '#64748b' }}
                                                    />
                                                    <span className="truncate text-sm font-black text-slate-900 dark:text-white">{group.name}</span>
                                                    {!readOnly && (
                                                        <button
                                                            type="button"
                                                            onClick={() => onRestoreArchivedGroup(group.id)}
                                                            className="inline-flex h-7 items-center justify-center rounded-full border border-rose-100 bg-white px-3 text-[10px] font-black text-rose-600 transition hover:border-blue-200 hover:text-blue-600 dark:border-rose-500/20 dark:bg-slate-950 dark:text-rose-300"
                                                        >
                                                            현재 시즌에 다시 편성
                                                        </button>
                                                    )}
                                                </div>
                                            </div>
                                            <label className="space-y-1">
                                                <span className="text-[10px] font-black text-slate-400">시즌 내 시작 주차</span>
                                                <input
                                                    type="date"
                                                    value={group.starts_week_date || seasonEffectiveWeekDate}
                                                    min={seasonEffectiveWeekDate}
                                                    max={group.ends_week_date || seasonEndWeekDate}
                                                    disabled={readOnly}
                                                    onChange={(event) => onArchivedGroupStartChange(group.id, event.target.value)}
                                                    className="h-9 w-full rounded-lg border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 outline-none focus:ring-4 focus:ring-rose-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                />
                                            </label>
                                            <label className="space-y-1">
                                                <span className="text-[10px] font-black text-slate-400">시즌 내 마지막 주차</span>
                                                <input
                                                    type="date"
                                                    value={group.ends_week_date || seasonEndWeekDate}
                                                    min={group.starts_week_date || seasonEffectiveWeekDate}
                                                    max={seasonEndWeekDate}
                                                    disabled={readOnly}
                                                    onChange={(event) => onArchivedGroupEndChange(group.id, event.target.value)}
                                                    className="h-9 w-full rounded-lg border border-rose-100 bg-white px-3 text-xs font-black text-slate-700 outline-none focus:ring-4 focus:ring-rose-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                />
                                            </label>
                                        </div>
                                    ))}
                                </div>
                            )}

                            {newGroups.length > 0 && (
                                <div className="space-y-2">
                                    <div>
                                        <h3 className="text-[11px] font-black uppercase tracking-[0.18em] text-blue-500">새로 생긴 조</h3>
                                        <p className="mt-1 text-[11px] font-bold text-slate-400">새로 생긴 조의 실제 활동 기간입니다. 새 조에 들어간 성도 소속은 기본적으로 이 기간을 따라갑니다.</p>
                                    </div>
                                    <div className="space-y-2">
                                        {newGroups.map(group => (
                                            <div key={group.id} className="grid gap-3 rounded-2xl border border-blue-100 bg-blue-50/60 p-3 dark:border-blue-500/20 dark:bg-blue-500/10 lg:grid-cols-[1fr_160px_190px] lg:items-center">
                                                <div className="min-w-0">
                                                    <div className="flex items-center gap-2">
                                                        <span
                                                            className="h-2.5 w-2.5 rounded-full"
                                                            style={{ backgroundColor: group.color_hex || '#2563eb' }}
                                                        />
                                                        <span className="truncate text-sm font-black text-slate-900 dark:text-white">{group.name}</span>
                                                    </div>
                                                </div>
                                                <label className="space-y-1">
                                                    <span className="text-[10px] font-black text-slate-400">시즌 내 시작 주차</span>
                                                    <input
                                                        type="date"
                                                        value={clampDateToRange(
                                                            group.starts_week_date || seasonEffectiveWeekDate,
                                                            seasonEffectiveWeekDate,
                                                            getStartInputMax(group.ends_week_date)
                                                        )}
                                                        min={seasonEffectiveWeekDate}
                                                        max={getStartInputMax(group.ends_week_date)}
                                                        disabled={readOnly}
                                                        onChange={(event) => onNewGroupStartChange(group.id, event.target.value)}
                                                        className="h-9 w-full rounded-lg border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 outline-none focus:ring-4 focus:ring-blue-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                    />
                                                </label>
                                                <label className="space-y-1">
                                                    <span className="text-[10px] font-black text-slate-400">시즌 내 마지막 주차</span>
                                                    <input
                                                        type="date"
                                                        value={group.ends_week_date || seasonEndWeekDate}
                                                        min={group.starts_week_date || seasonEffectiveWeekDate}
                                                        max={seasonEndWeekDate}
                                                        disabled={readOnly}
                                                        onChange={(event) => onNewGroupEndChange(group.id, event.target.value)}
                                                        className="h-9 w-full rounded-lg border border-blue-100 bg-white px-3 text-xs font-black text-slate-700 outline-none focus:ring-4 focus:ring-blue-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                    />
                                                </label>
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            )}

                            {movedMembers.length > 0 && (
                                <div className="space-y-2">
                                    <div className="flex flex-wrap items-center justify-between gap-3">
                                        <h3 className="text-[11px] font-black uppercase tracking-[0.18em] text-amber-500">성도 소속 기간</h3>
                                        <div className="flex flex-wrap gap-1.5">
                                            {memberTabOptions.map(option => (
                                                (() => {
                                                    const meta = option.type === 'all' ? null : memberChangeMeta[option.type];
                                                    const isActive = effectiveMemberTab === option.type;

                                                    return (
                                                <button
                                                    key={option.type}
                                                    type="button"
                                                    onClick={() => setMemberTab(option.type)}
                                                    className={`rounded-full px-3 py-1 text-[10px] font-black transition ${
                                                        isActive
                                                            ? meta?.activeTabClassName || 'bg-slate-900 text-white shadow-sm dark:bg-white dark:text-slate-950'
                                                            : meta?.tabClassName || 'bg-white text-slate-500 ring-1 ring-slate-200 hover:bg-slate-50 dark:bg-slate-950 dark:text-slate-300 dark:ring-slate-800'
                                                    }`}
                                                >
                                                    {option.label} {option.count}
                                                </button>
                                                    );
                                                })()
                                            ))}
                                        </div>
                                    </div>
                                    {periodAdjustmentMemberIds.length > 0 && !readOnly && isPeriodTab && (
                                        <div className="space-y-3 rounded-2xl border border-amber-100 bg-white px-3 py-3 dark:border-amber-500/20 dark:bg-slate-950">
                                            <div className="flex flex-wrap items-center justify-between gap-3">
                                                <label className="inline-flex items-center gap-2 text-[11px] font-black text-slate-700 dark:text-slate-200">
                                                    <input
                                                        type="checkbox"
                                                        checked={allPeriodMembersSelected}
                                                        onChange={toggleAllPeriodMembers}
                                                        className="h-4 w-4 rounded border-amber-300 text-amber-500 focus:ring-amber-500"
                                                    />
                                                    전체 선택
                                                    <span className="font-bold text-slate-400">
                                                        {selectedValidPeriodMemberIds.length}/{periodAdjustmentMemberIds.length}
                                                    </span>
                                                </label>
                                                <p className="text-[11px] font-bold text-slate-500 dark:text-slate-400">
                                                    선택한 성도에 날짜를 입력한 뒤 상단 현재 시즌 저장을 눌러야 실제 반영됩니다.
                                                </p>
                                            </div>
                                            <div className="grid gap-2 lg:grid-cols-[150px_150px_auto] lg:items-end">
                                                <label className="space-y-1">
                                                    <span className="text-[10px] font-black text-slate-400">일괄 시작 주차</span>
                                                    <input
                                                        type="date"
                                                        value={resolvedBulkStartsWeekDate}
                                                        min={seasonEffectiveWeekDate}
                                                        max={getStartInputMax(resolvedBulkEndsWeekDate)}
                                                        onChange={(event) => updateBulkStartsWeekDate(event.target.value)}
                                                        className="h-9 w-full rounded-lg border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 outline-none focus:ring-4 focus:ring-amber-500/10 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                    />
                                                </label>
                                                <label className="space-y-1">
                                                    <span className="text-[10px] font-black text-slate-400">일괄 마지막 주차</span>
                                                    <input
                                                        type="date"
                                                        value={resolvedBulkEndsWeekDate}
                                                        min={resolvedBulkStartsWeekDate || seasonEffectiveWeekDate}
                                                        max={seasonEndWeekDate}
                                                        onChange={(event) => updateBulkEndsWeekDate(event.target.value)}
                                                        className="h-9 w-full rounded-lg border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 outline-none focus:ring-4 focus:ring-amber-500/10 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                    />
                                                </label>
                                                <button
                                                    type="button"
                                                    disabled={!hasSelectedPeriodMembers || !isBulkPeriodRangeValid}
                                                    onClick={applyBulkPeriodDates}
                                                    className="inline-flex h-9 items-center justify-center rounded-xl bg-amber-500 px-4 text-[11px] font-black text-white shadow-sm shadow-amber-500/20 transition hover:bg-amber-400 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:shadow-none"
                                                >
                                                    선택한 {selectedValidPeriodMemberIds.length}명에 날짜 입력
                                                </button>
                                            </div>
                                        </div>
                                    )}
                                    <div className="max-h-72 overflow-y-auto rounded-2xl border border-amber-100 bg-amber-50/50 dark:border-amber-500/20 dark:bg-amber-500/10">
                                        {visibleMovedMembers.map(member => {
                                            const meta = memberChangeMeta[member.changeType];

                                            return (
                                            <div key={member.id} className={`grid gap-3 border-b px-3 py-3 last:border-b-0 lg:grid-cols-[1fr_160px_190px] lg:items-center ${meta.rowClassName}`}>
                                                <div className="min-w-0">
                                                    <div className="flex flex-wrap items-center gap-2">
                                                        {member.changeType === 'period' && !readOnly && isPeriodTab && (
                                                            <input
                                                                type="checkbox"
                                                                checked={selectedPeriodMemberIdSet.has(member.id)}
                                                                onChange={() => togglePeriodMember(member.id)}
                                                                className="h-4 w-4 rounded border-amber-300 text-amber-500 focus:ring-amber-500"
                                                            />
                                                        )}
                                                        <span className="text-xs font-black text-slate-800 dark:text-slate-100">{member.full_name}</span>
                                                        <span className={`rounded-full px-2 py-0.5 text-[10px] font-black shadow-sm ${meta.badgeClassName}`}>
                                                            {meta.label}
                                                        </span>
                                                    </div>
                                                    <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[11px] font-bold">
                                                        <span className={`rounded-lg px-2 py-0.5 ${meta.groupClassName}`}>
                                                            {member.changeType === 'removed' ? member.previousGroupName : member.nextGroupName}
                                                        </span>
                                                        <span className="truncate text-slate-500 dark:text-slate-400">
                                                            {member.changeType === 'added'
                                                                ? '이전 조 소속 유지 + 이 조에 추가 편성 (다중 소속)'
                                                                : member.changeType === 'removed'
                                                                    ? '이 조 소속만 종료됨 — 아래 기간 설정이 앱에 반영'
                                                                    : member.changeType === 'period'
                                                                        ? '조는 그대로이고 적용 시작·마지막 주차만 기본 기간과 다름'
                                                                    : `${member.previousGroupName}에서 이동 — 이전 조 소속 사라짐`}
                                                        </span>
                                                    </div>
                                                    {member.changeType === 'period' && (
                                                        <p className="mt-1 text-[10px] font-bold text-amber-700/80 dark:text-amber-200/80">
                                                            기본 기간: {member.recommended_starts_week_date || seasonEffectiveWeekDate} ~ {member.recommended_ends_week_date || seasonEndWeekDate}
                                                        </p>
                                                    )}
                                                </div>
                                                <label className="space-y-1">
                                                    {/* removed: 이 조에서의 소속이 시작된 주차 (= 이 조에 처음 편성된 주차) */}
                                                    <span className="text-[10px] font-black text-slate-400">{member.changeType === 'removed' ? '이 조 소속 시작 주차' : '소속 시작 주차'}</span>
                                                    <input
                                                        type="date"
                                                        value={clampDateToRange(
                                                            member.starts_week_date || getMemberPeriodBounds(member).min,
                                                            getMemberPeriodBounds(member).min,
                                                            getMemberPeriodBounds(member).startMax
                                                        )}
                                                        min={getMemberPeriodBounds(member).min}
                                                        max={clampDateToRange(
                                                            member.ends_week_date || getMemberPeriodBounds(member).startMax,
                                                            getMemberPeriodBounds(member).min,
                                                            getMemberPeriodBounds(member).startMax
                                                        )}
                                                        disabled={readOnly}
                                                        inputMode="none"
                                                        onKeyDown={preventManualDateEntry}
                                                        onPaste={preventDateTextInput}
                                                        onDrop={preventDateTextInput}
                                                        onChange={(event) => handleMemberStartChange(member, event.target.value)}
                                                        className="h-9 w-full rounded-lg border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 outline-none focus:ring-4 focus:ring-amber-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                    />
                                                </label>
                                                <label className="space-y-1">
                                                    {/* removed: 이 조에서 마지막으로 활동한 주차 — 이 날짜 이후 앱에서 이 조 소속이 보이지 않음 */}
                                                    <span className="text-[10px] font-black text-slate-400">{member.changeType === 'removed' ? '이 조 마지막 활동 주차' : '소속 마지막 주차'}</span>
                                                    <input
                                                        type="date"
                                                        value={clampDateToRange(
                                                            member.ends_week_date || getMemberPeriodBounds(member).endMax,
                                                            member.starts_week_date || getMemberPeriodBounds(member).min,
                                                            getMemberPeriodBounds(member).endMax
                                                        )}
                                                        min={clampDateToRange(
                                                            member.starts_week_date || getMemberPeriodBounds(member).min,
                                                            getMemberPeriodBounds(member).min,
                                                            getMemberPeriodBounds(member).endMax
                                                        )}
                                                        max={getMemberPeriodBounds(member).endMax}
                                                        disabled={readOnly}
                                                        inputMode="none"
                                                        onKeyDown={preventManualDateEntry}
                                                        onPaste={preventDateTextInput}
                                                        onDrop={preventDateTextInput}
                                                        onChange={(event) => handleMemberEndChange(member, event.target.value)}
                                                        className="h-9 w-full rounded-lg border border-amber-100 bg-white px-3 text-xs font-black text-slate-700 outline-none focus:ring-4 focus:ring-amber-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                    />
                                                </label>
                                            </div>
                                            );
                                        })}
                                    </div>
                                    <div className="rounded-xl border border-slate-100 bg-slate-50 px-3 py-2.5 text-[11px] font-bold text-slate-500 dark:border-slate-800 dark:bg-slate-950/50 dark:text-slate-400">
                                        <p className="mb-1 font-black text-slate-600 dark:text-slate-300">카테고리 안내</p>
                                        <ul className="space-y-1 list-none">
                                            <li><span className="font-black text-blue-600">소속 이동</span>: 드래그앤드롭으로 다른 조로 옮김 → 이전 조 소속이 사라지고 새 조로 변경됨</li>
                                            <li><span className="font-black text-emerald-600">다중 소속 추가</span>: 복사(다중편성)로 추가됨 → 이전 조 소속은 유지되고 이 조에도 동시에 속함</li>
                                            <li><span className="font-black text-rose-600">소속 종료</span>: 특정 조 소속을 끝냄 → 미편성 전환, 조 종료, 다중소속 일부 제거가 여기에 포함됨</li>
                                            <li><span className="font-black text-amber-600">기간 조정</span>: 조 이동은 없고, 그 조에 포함되는 시작·마지막 주차만 시즌/조 기본 기간과 다르게 둔 항목</li>
                                        </ul>
                                        <p className="mt-1.5 text-slate-400">※ 소속 이동으로 자동 종료된 이전 조 구간은 소속 이동으로만 봅니다. 기간 조정은 오류 표시가 아니라 별도 확인·일괄 정리가 필요한 소속 기간만 모아 둔 탭입니다. 저장 후 앱과 출석 집계에 반영됩니다.</p>
                                    </div>
                                </div>
                            )}
                        </>
                    )}
                </div>
            </details>
        </section>
    );
}
