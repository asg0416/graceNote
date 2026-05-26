'use client';

import { ChevronDown } from 'lucide-react';

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
    changeType: 'moved' | 'added';
    previousGroupName: string;
    nextGroupName: string;
    starts_week_date?: string | null;
    ends_week_date?: string | null;
};

interface SeasonChangeHistoryPanelProps {
    archivedGroups: SeasonGroup[];
    newGroups: SeasonGroup[];
    movedMembers: MovedSeasonMember[];
    seasonEffectiveWeekDate: string;
    seasonEndWeekDate: string;
    readOnly: boolean;
    onArchivedGroupStartChange: (groupId: string, value: string) => void;
    onArchivedGroupEndChange: (groupId: string, value: string) => void;
    onNewGroupStartChange: (groupId: string, value: string) => void;
    onNewGroupEndChange: (groupId: string, value: string) => void;
    onMovedMemberStartChange: (memberId: string, value: string) => void;
    onMovedMemberEndChange: (memberId: string, value: string) => void;
    onRestoreArchivedGroup: (groupId: string) => void;
}

export function SeasonChangeHistoryPanel({
    archivedGroups,
    newGroups,
    movedMembers,
    seasonEffectiveWeekDate,
    seasonEndWeekDate,
    readOnly,
    onArchivedGroupStartChange,
    onArchivedGroupEndChange,
    onNewGroupStartChange,
    onNewGroupEndChange,
    onMovedMemberStartChange,
    onMovedMemberEndChange,
    onRestoreArchivedGroup,
}: SeasonChangeHistoryPanelProps) {
    return (
        <section className="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <details className="group">
                <summary className="flex cursor-pointer list-none items-center justify-between gap-4">
                    <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2">
                            <span className="text-base font-black text-slate-950 dark:text-white">기간 조정 패널</span>
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
                            현재/과거 시즌 안에서 각 조와 성도-조 소속 row가 유효한 기간을 확인하고 보정합니다. 미래 시즌은 시즌 전체 기간으로 편성합니다.
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
                                        <p className="mt-1 text-[11px] font-bold text-slate-400">
                                            시즌 안에서 이 조들이 활동한 기간을 보정합니다.
                                        </p>
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
                                                            다시 편성
                                                        </button>
                                                    )}
                                                </div>
                                            </div>
                                            <label className="space-y-1">
                                                <span className="text-[10px] font-black text-slate-400">시작 주차</span>
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
                                                <span className="text-[10px] font-black text-slate-400">마지막 활동 주차</span>
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
                                        <p className="mt-1 text-[11px] font-bold text-slate-400">
                                            시즌 안에서 새 조들이 활동할 기간을 보정합니다.
                                        </p>
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
                                                    <span className="text-[10px] font-black text-slate-400">시작 주차</span>
                                                    <input
                                                        type="date"
                                                        value={group.starts_week_date || seasonEffectiveWeekDate}
                                                        min={seasonEffectiveWeekDate}
                                                        max={group.ends_week_date || seasonEndWeekDate}
                                                        disabled={readOnly}
                                                        onChange={(event) => onNewGroupStartChange(group.id, event.target.value)}
                                                        className="h-9 w-full rounded-lg border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 outline-none focus:ring-4 focus:ring-blue-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                    />
                                                </label>
                                                <label className="space-y-1">
                                                    <span className="text-[10px] font-black text-slate-400">마지막 활동 주차</span>
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
                                    <h3 className="text-[11px] font-black uppercase tracking-[0.18em] text-amber-500">성도 소속 기간</h3>
                                    <div className="max-h-72 overflow-y-auto rounded-2xl border border-amber-100 bg-amber-50/50 dark:border-amber-500/20 dark:bg-amber-500/10">
                                        {movedMembers.map(member => (
                                            <div key={member.id} className="grid gap-3 border-b border-amber-100 px-3 py-3 last:border-b-0 dark:border-amber-500/10 lg:grid-cols-[1fr_160px_190px] lg:items-center">
                                                <div className="min-w-0">
                                                    <div className="flex flex-wrap items-center gap-2">
                                                        <span className="text-xs font-black text-slate-800 dark:text-slate-100">{member.full_name}</span>
                                                        <span className="rounded-full bg-white px-2 py-0.5 text-[10px] font-black text-amber-700 shadow-sm dark:bg-slate-950 dark:text-amber-300">
                                                            {member.changeType === 'added' ? '추가 소속' : '이동 소속'}
                                                        </span>
                                                    </div>
                                                    <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[11px] font-bold">
                                                        <span className="text-slate-400">
                                                            {member.nextGroupName === '미편성' ? '편집 대상' : '편집 대상 조'}
                                                        </span>
                                                        <span className="rounded-lg bg-amber-100 px-2 py-0.5 text-amber-800 dark:bg-amber-400/10 dark:text-amber-200">
                                                            {member.nextGroupName === '미편성' ? '미편성 기간' : member.nextGroupName}
                                                        </span>
                                                        {member.changeType === 'moved' && (
                                                            <span className="truncate text-slate-500 dark:text-slate-400">
                                                                이전 {member.previousGroupName}
                                                            </span>
                                                        )}
                                                    </div>
                                                </div>
                                                <label className="space-y-1">
                                                    <span className="text-[10px] font-black text-slate-400">소속 시작 주차</span>
                                                    <input
                                                        type="date"
                                                        value={member.starts_week_date || seasonEffectiveWeekDate}
                                                        min={seasonEffectiveWeekDate}
                                                        max={member.ends_week_date || seasonEndWeekDate}
                                                        disabled={readOnly}
                                                        onChange={(event) => onMovedMemberStartChange(member.id, event.target.value)}
                                                        className="h-9 w-full rounded-lg border border-slate-200 bg-white px-3 text-xs font-black text-slate-700 outline-none focus:ring-4 focus:ring-amber-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                    />
                                                </label>
                                                <label className="space-y-1">
                                                    <span className="text-[10px] font-black text-slate-400">소속 마지막 주차</span>
                                                    <input
                                                        type="date"
                                                        value={member.ends_week_date || seasonEndWeekDate}
                                                        min={member.starts_week_date || seasonEffectiveWeekDate}
                                                        max={seasonEndWeekDate}
                                                        disabled={readOnly}
                                                        onChange={(event) => onMovedMemberEndChange(member.id, event.target.value)}
                                                        className="h-9 w-full rounded-lg border border-amber-100 bg-white px-3 text-xs font-black text-slate-700 outline-none focus:ring-4 focus:ring-amber-500/10 disabled:bg-slate-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100"
                                                    />
                                                </label>
                                            </div>
                                        ))}
                                    </div>
                                    <p className="text-[11px] font-bold text-slate-400">
                                        이 영역은 이동 로그가 아니라 시즌 안의 성도-조 소속 row 기간을 조정하는 곳입니다. 다른 조에 복사한 다중 소속도 별도 row로 표시됩니다.
                                    </p>
                                </div>
                            )}
                        </>
                    )}
                </div>
            </details>
        </section>
    );
}
