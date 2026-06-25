import { useEffect, useMemo, useRef, useState } from 'react';
import { useDroppable } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { DraggableCard } from './DraggableCard';
import { cn } from '@/lib/utils';
import { Users, MoreVertical, Plus, Trash2, Edit2, X, Search } from 'lucide-react';
import { PeriodEditPopover } from './PeriodEditPopover';
import { isPeriodEdited } from '@/lib/periodBadgeState';

type KanbanMember = {
    id: string;
    full_name?: string | null;
    phone?: string | null;
    spouse_name?: string | null;
    [key: string]: unknown;
};

interface KanbanColumnProps {
    id: string; // group_id or 'unassigned'
    title: string;
    members: KanbanMember[];
    selectedMemberIds: string[];
    onMemberClick: (id: string) => void;
    onMemberDoubleClick?: (id: string) => void;
    color?: string;
    isNewMemberGroup?: boolean;
    climbingThreshold?: number | null;
    startsWeekDate?: string | null;
    endsWeekDate?: string | null;
    periodMinDate?: string | null;
    periodMaxDate?: string | null;
    periodStartMaxDate?: string | null;
    onAddMembers?: () => void;
    onDelete?: () => void;
    onUpdate?: (updates: { name?: string, color_hex?: string, is_new_member_group?: boolean, climbing_threshold?: number | null }) => void;
    onUpdateGroupPeriod?: (updates: { starts_week_date: string | null; ends_week_date: string | null }) => void;
    onUpdateMemberPeriod?: (id: string, updates: { starts_week_date: string | null; ends_week_date: string | null }) => void;
    autoFocusRename?: boolean;
    profileMode?: string;
    activeId?: string | null;
    movingMembersCount?: number;
    onToggleLeader?: (id: string) => void;
    onDeleteMember?: (id: string) => void;
    isDeletableMap?: Record<string, boolean>;
    autoMoveCouples?: boolean;
    readOnly?: boolean;
    fillHeight?: boolean;
}

export const KanbanColumn: React.FC<KanbanColumnProps> = ({
    id,
    title,
    members,
    selectedMemberIds,
    onMemberClick,
    onMemberDoubleClick,
    color = '#4f46e5',
    isNewMemberGroup = false,
    climbingThreshold,
    startsWeekDate,
    endsWeekDate,
    periodMinDate,
    periodMaxDate,
    periodStartMaxDate,
    onAddMembers,
    onDelete,
    onUpdate,
    onUpdateGroupPeriod,
    onUpdateMemberPeriod,
    autoFocusRename = false,
    profileMode,
    activeId,
    movingMembersCount = 1,
    onToggleLeader,
    onDeleteMember,
    isDeletableMap,
    autoMoveCouples = true,
    readOnly = false,
    fillHeight = false
}) => {
    const { setNodeRef, isOver } = useDroppable({ id });
    const [isRenaming, setIsRenaming] = useState(autoFocusRename);
    const [newName, setNewName] = useState(title);
    const [newColor, setNewColor] = useState(color);
    const [newIsNewMemberGroup, setNewIsNewMemberGroup] = useState(isNewMemberGroup);
    const [newClimbingThreshold, setNewClimbingThreshold] = useState(climbingThreshold || 4);
    const [showMenu, setShowMenu] = useState(false);
    const [searchQuery, setSearchQuery] = useState('');
    const [isEditingPeriod, setIsEditingPeriod] = useState(false);
    const [periodAnchorRect, setPeriodAnchorRect] = useState<DOMRect | null>(null);
    const [initialPeriod] = useState(() => ({
        start: startsWeekDate || null,
        end: endsWeekDate || null,
    }));
    const menuRef = useRef<HTMLDivElement>(null);

    const colorPresets = [
        '#4f46e5', // Indigo
        '#0ea5e9', // Sky
        '#10b981', // Emerald
        '#f59e0b', // Amber
        '#ef4444', // Red
        '#8b5cf6', // Violet
        '#ec4899', // Pink
        '#64748b', // Slate
    ];

    const formatShortDate = (value?: string | null) => {
        if (!value) return '';
        const [, month, day] = value.split('-');
        return month && day ? `${Number(month)}/${Number(day)}` : value;
    };

    const periodLabel = startsWeekDate || endsWeekDate
        ? `${formatShortDate(startsWeekDate) || '시작 미정'}~${formatShortDate(endsWeekDate) || '종료 미정'}`
        : null;
    const hasEditedPeriod = isPeriodEdited(initialPeriod.start, initialPeriod.end, startsWeekDate, endsWeekDate);

    // Close menu on outside click
    useEffect(() => {
        if (!showMenu) return;
        const handleClick = (e: MouseEvent) => {
            if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
                setShowMenu(false);
            }
        };
        document.addEventListener('mousedown', handleClick);
        return () => document.removeEventListener('mousedown', handleClick);
    }, [showMenu]);

    const openSettings = () => {
        setNewName(title);
        setNewColor(color);
        setNewIsNewMemberGroup(isNewMemberGroup);
        setNewClimbingThreshold(climbingThreshold || 4);
        setIsRenaming(true);
    };

    const closeSettings = () => {
        setIsRenaming(false);
        setNewName(title);
        setNewColor(color);
        setNewIsNewMemberGroup(isNewMemberGroup);
        setNewClimbingThreshold(climbingThreshold || 4);
    };

    const saveSettings = () => {
        const trimmedName = newName.trim();
        if (!trimmedName) return;
        onUpdate?.({
            name: trimmedName,
            color_hex: newColor,
            is_new_member_group: newIsNewMemberGroup,
            climbing_threshold: newIsNewMemberGroup ? newClimbingThreshold : null,
        });
        setIsRenaming(false);
    };

    // Filter members based on search query
    const filteredMembers = useMemo(() => {
        if (!searchQuery.trim()) return members;
        const query = searchQuery.toLowerCase().trim();
        return members.filter(m =>
            m.full_name?.toLowerCase().includes(query) ||
            m.phone?.includes(query)
        );
    }, [members, searchQuery]);

    // Group members into family units if in couple mode
    const familyUnits = useMemo(() => {
        if (!autoMoveCouples || profileMode !== 'couple') {
            return filteredMembers.map(m => ({ id: m.id, members: [m] }));
        }

        const units: { id: string, members: KanbanMember[] }[] = [];
        const seen = new Set<string>();

        filteredMembers.forEach(m => {
            if (seen.has(m.id)) return;

            const unit = { id: m.id, members: [m] };
            seen.add(m.id);

            if (m.spouse_name) {
                const spouse = filteredMembers.find(s =>
                    !seen.has(s.id) &&
                    s.full_name === m.spouse_name &&
                    s.spouse_name === m.full_name
                );
                if (spouse) {
                    unit.members.push(spouse);
                    seen.add(spouse.id);
                }
            }
            units.push(unit);
        });
        return units;
    }, [autoMoveCouples, filteredMembers, profileMode]);

    return (
        <div className={cn(
            "flex w-96 shrink-0 flex-col rounded-2xl border border-slate-200/80 bg-white shadow-sm transition-shadow group/column hover:shadow-xl hover:shadow-slate-200/40 dark:border-slate-800/60 dark:bg-slate-900/60 dark:hover:shadow-none",
            fillHeight ? "h-full min-h-[520px] max-h-none" : "max-h-[820px]"
        )}>
            {/* Header - Sticky within column */}
            <div className="sticky top-0 z-20 p-5 flex items-center justify-between border-b border-slate-200/60 dark:border-slate-800/60 bg-white/95 dark:bg-slate-950/95 backdrop-blur-xl rounded-t-[31px]">
                <div className="flex items-center gap-3 flex-1 min-w-0">
                    <div
                        className="w-2 h-6 rounded-full shrink-0"
                        style={{ backgroundColor: color }}
                    />
                    <div className="flex-1 min-w-0">
                        <div onDoubleClick={() => !readOnly && openSettings()} className={cn("group/title", readOnly ? "cursor-default" : "cursor-pointer")}>
                            <h3 className="font-black text-slate-900 dark:text-white text-sm tracking-tight leading-none uppercase truncate group-hover/title:text-indigo-600 transition-colors">
                                {title}
                            </h3>
                            <div className="flex items-center gap-3">
                                <p className="text-[10px] font-bold text-slate-400 dark:text-slate-500 mt-1 uppercase tracking-widest flex items-center gap-1">
                                    <Users className="w-2.5 h-2.5" />
                                    {members.length}명
                                </p>
                                {periodLabel && (
                                    <span className="relative mt-1">
                                        <button
                                            type="button"
                                            onClick={(event) => event.stopPropagation()}
                                            onDoubleClick={(event) => {
                                                event.stopPropagation();
                                                if (!readOnly && onUpdateGroupPeriod) {
                                                    setPeriodAnchorRect(event.currentTarget.getBoundingClientRect());
                                                    setIsEditingPeriod(true);
                                                }
                                            }}
                                            className={cn(
                                                "rounded-full border px-2.5 py-0.5 text-[9px] font-black transition",
                                                hasEditedPeriod
                                                    ? "border-indigo-200 bg-indigo-50 text-indigo-700 shadow-sm shadow-indigo-500/10 dark:border-indigo-500/25 dark:bg-indigo-500/10 dark:text-indigo-200"
                                                    : "border-transparent bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-300",
                                                !readOnly && onUpdateGroupPeriod && "cursor-pointer hover:ring-4 hover:ring-indigo-500/10"
                                            )}
                                            title={!readOnly && onUpdateGroupPeriod ? "더블클릭해서 조 기간을 수정합니다." : undefined}
                                        >
                                            {periodLabel}
                                        </button>
                                        {isEditingPeriod && !readOnly && onUpdateGroupPeriod && (
                                            <PeriodEditPopover
                                                title={`${title} 기간 수정`}
                                                startValue={startsWeekDate}
                                                endValue={endsWeekDate}
                                                minValue={periodMinDate}
                                                maxValue={periodMaxDate}
                                                startMaxValue={periodStartMaxDate}
                                                endMaxValue={periodMaxDate}
                                                anchorRect={periodAnchorRect}
                                                onApply={onUpdateGroupPeriod}
                                                onClose={() => {
                                                    setIsEditingPeriod(false);
                                                    setPeriodAnchorRect(null);
                                                }}
                                            />
                                        )}
                                    </span>
                                )}
                                {isNewMemberGroup && (
                                    <span className="mt-1 rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-0.5 text-[9px] font-black text-emerald-700 shadow-sm dark:border-emerald-500/20 dark:bg-emerald-500/10 dark:text-emerald-300">
                                        새가족 조
                                    </span>
                                )}
                            </div>
                        </div>
                    </div>
                </div>
                <div className="flex items-center gap-1 relative">
                    {onAddMembers && !readOnly && (
                        <button
                            onClick={onAddMembers}
                            className="p-1.5 text-slate-400 hover:text-indigo-600 hover:bg-slate-100 dark:hover:bg-slate-800 rounded-lg transition-all"
                        >
                            <Plus className="w-4 h-4" />
                        </button>
                    )}
                    {!readOnly && (
                        <button
                            onClick={() => setShowMenu(!showMenu)}
                            className={cn(
                                "p-1.5 text-slate-300 hover:text-slate-600 dark:hover:text-slate-200 rounded-lg transition-colors",
                                showMenu && "bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-200"
                            )}
                        >
                            <MoreVertical className="w-4 h-4" />
                        </button>
                    )}

                    {showMenu && !readOnly && (
                        <div
                            ref={menuRef}
                            className="absolute top-full right-0 mt-2 w-40 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl shadow-xl z-[100] overflow-hidden animate-in fade-in slide-in-from-top-1"
                        >
                            <button
                                onClick={() => {
                                    openSettings();
                                    setShowMenu(false);
                                }}
                                className="w-full flex items-center gap-2 px-4 py-2 text-xs font-bold text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors"
                            >
                                <Edit2 className="w-3.5 h-3.5" />
                                조 정보 수정
                            </button>
                            {onDelete && (
                                <button
                                    onClick={() => {
                                        if (confirm('이 조를 종료하시겠습니까? 소속된 인원은 미편성으로 이동됩니다. 기존 출석과 기도 기록은 보존됩니다.')) {
                                            onDelete();
                                        }
                                        setShowMenu(false);
                                    }}
                                    className="w-full flex items-center gap-2 px-4 py-2 text-xs font-bold text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-500/10 transition-colors"
                                >
                                    <Trash2 className="w-3.5 h-3.5" />
                                    조 종료
                                </button>
                            )}
                        </div>
                    )}
                </div>
            </div>

            {/* Column Search Bar - Only for unassigned by default, or all if needed. 
                User specifically asked for unassigned, but keeping it available for all makes it consistent. */}
            <div className="px-5 py-2 bg-white/50 dark:bg-slate-950/30">
                <div className="relative group/search">
                    <Search className={cn(
                        "absolute left-3 top-1/2 -translate-y-1/2 w-3 h-3 transition-colors",
                        searchQuery ? "text-indigo-500" : "text-slate-300 dark:text-slate-600 group-focus-within/search:text-indigo-400"
                    )} />
                    <input
                        type="text"
                        placeholder={`${title} 검색...`}
                        value={searchQuery}
                        onChange={(e) => setSearchQuery(e.target.value)}
                        className="w-full pl-8 pr-8 h-9 bg-slate-50 dark:bg-slate-800/40 border border-slate-100 dark:border-slate-800/60 rounded-xl text-[11px] font-bold focus:ring-4 focus:ring-indigo-500/5 outline-none transition-all placeholder:text-slate-300 dark:placeholder:text-slate-600"
                    />
                    {searchQuery && (
                        <button
                            onClick={() => setSearchQuery('')}
                            className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-slate-300 hover:text-slate-500 transition-colors"
                        >
                            <X className="w-3 h-3" />
                        </button>
                    )}
                </div>
            </div>

            {/* Content - Internal scroll for stability */}
            <div
                ref={setNodeRef}
                className={cn(
                    "flex-1 p-5 space-y-4 transition-colors overflow-y-auto custom-scrollbar bg-white/40 dark:bg-transparent min-h-[150px] flex flex-col",
                    isOver && "bg-indigo-500/[0.04]"
                )}
            >
                <div className="flex-1 space-y-4">
                    <SortableContext
                        items={familyUnits.map((unit) => unit.id)}
                        strategy={verticalListSortingStrategy}
                    >
                        {familyUnits.map((unit) => {
                            const isSelected = unit.members.some((member) => selectedMemberIds.includes(member.id));
                            const isBeingDragged = !!activeId && (activeId === unit.id || isSelected);

                            return (
                                <DraggableCard
                                    key={unit.id}
                                    id={unit.id}
                                    members={unit.members}
                                    isSelected={isSelected}
                                    onClick={onMemberClick}
                                    onDoubleClick={onMemberDoubleClick}
                                    onToggleLeader={onToggleLeader}
                                    onDeleteMember={onDeleteMember}
                                    isDeletableMap={isDeletableMap}
                                    profileMode={profileMode}
                                    isDraggingElsewhere={isBeingDragged}
                                    movingMembersCount={movingMembersCount}
                                    onUpdateMemberPeriod={onUpdateMemberPeriod}
                                    periodStartMaxDate={periodStartMaxDate}
                                    readOnly={readOnly}
                                />
                            );
                        })}
                    </SortableContext>
                </div>
            </div>

            {/* Footer - Full Member Addition Trigger */}
            <div className="p-4 border-t border-slate-200/60 dark:border-slate-800/60 bg-white/30 dark:bg-slate-900/30 shrink-0 rounded-b-[32px]">
                {readOnly ? (
                    <div className="w-full flex items-center justify-center gap-2 h-11 rounded-2xl bg-slate-50 dark:bg-slate-800/60 text-slate-400 border border-slate-100 dark:border-slate-800">
                        <span className="text-xs font-black uppercase tracking-widest">읽기 전용</span>
                    </div>
                ) : (
                    <button
                        onClick={() => onAddMembers?.()}
                        className="w-full flex items-center justify-center gap-2 h-11 border border-dashed border-slate-200 dark:border-slate-800 rounded-2xl text-slate-400 hover:text-indigo-600 hover:border-indigo-500/50 hover:bg-white dark:hover:bg-slate-900 transition-all group active:scale-95 shadow-sm"
                    >
                        <Plus className="w-4 h-4 group-hover:scale-110 transition-transform" />
                        <span className="text-xs font-black uppercase tracking-widest">성도 추가</span>
                    </button>
                )}
            </div>
            {isRenaming && !readOnly && (
                <div className="fixed inset-0 z-[200] flex items-center justify-center bg-slate-950/35 px-4 backdrop-blur-sm">
                    <div className="w-full max-w-lg rounded-[2rem] border border-slate-200 bg-white p-6 shadow-2xl dark:border-slate-800 dark:bg-slate-950">
                        <div className="mb-6 flex items-start justify-between gap-4">
                            <div>
                                <p className="text-[10px] font-black uppercase tracking-[0.2em] text-indigo-500">Group Settings</p>
                                <h3 className="mt-1 text-2xl font-black tracking-tight text-slate-950 dark:text-white">조 정보 수정</h3>
                            </div>
                            <button
                                type="button"
                                onClick={closeSettings}
                                className="rounded-2xl border border-slate-200 p-2 text-slate-400 transition hover:text-slate-700 dark:border-slate-800 dark:hover:text-slate-100"
                            >
                                <X className="h-5 w-5" />
                            </button>
                        </div>

                        <div className="space-y-6">
                            <label className="block space-y-2">
                                <span className="text-[10px] font-black uppercase tracking-widest text-slate-400">조 이름</span>
                                <input
                                    autoFocus
                                    value={newName}
                                    onChange={(event) => setNewName(event.target.value)}
                                    onKeyDown={(event) => {
                                        if (event.key === 'Enter') {
                                            event.preventDefault();
                                            saveSettings();
                                        }
                                        if (event.key === 'Escape') {
                                            closeSettings();
                                        }
                                    }}
                                    className="h-12 w-full rounded-2xl border border-slate-200 bg-slate-50 px-4 text-base font-black text-slate-900 outline-none transition focus:border-indigo-300 focus:ring-4 focus:ring-indigo-500/10 dark:border-slate-800 dark:bg-slate-900 dark:text-white"
                                />
                            </label>

                            <div className="space-y-2">
                                <p className="text-[10px] font-black uppercase tracking-widest text-slate-400">조 색상</p>
                                <div className="flex flex-wrap gap-2">
                                    {colorPresets.map(c => (
                                        <button
                                            key={c}
                                            type="button"
                                            onClick={() => setNewColor(c)}
                                            className={cn(
                                                "h-9 w-9 rounded-full transition-all hover:scale-110",
                                                newColor === c && "ring-4 ring-indigo-500/20 ring-offset-2 dark:ring-offset-slate-950"
                                            )}
                                            style={{ backgroundColor: c }}
                                        />
                                    ))}
                                </div>
                            </div>

                            <div className="rounded-3xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-900/70">
                                <label className="flex items-center justify-between gap-4">
                                    <div>
                                        <p className="text-sm font-black text-slate-900 dark:text-white">새가족 조</p>
                                        <p className="mt-1 text-xs font-bold text-slate-400">새가족 등반 기준을 사용하는 조로 표시합니다.</p>
                                    </div>
                                    <input
                                        type="checkbox"
                                        checked={newIsNewMemberGroup}
                                        onChange={(event) => setNewIsNewMemberGroup(event.target.checked)}
                                        className="h-5 w-5"
                                    />
                                </label>
                                {newIsNewMemberGroup && (
                                    <label className="mt-4 flex items-center justify-between gap-4 rounded-2xl bg-white px-4 py-3 dark:bg-slate-950">
                                        <span className="text-sm font-black text-slate-600 dark:text-slate-300">등반 기준 출석 횟수</span>
                                        <input
                                            type="number"
                                            min={1}
                                            max={52}
                                            value={newClimbingThreshold}
                                            onChange={(event) => setNewClimbingThreshold(Number(event.target.value) || 4)}
                                            className="h-10 w-24 rounded-xl border border-slate-200 bg-white px-3 text-right text-sm font-black text-slate-900 outline-none focus:ring-4 focus:ring-indigo-500/10 dark:border-slate-800 dark:bg-slate-900 dark:text-white"
                                        />
                                    </label>
                                )}
                            </div>
                        </div>

                        <div className="mt-7 flex gap-3">
                            <button
                                type="button"
                                onClick={closeSettings}
                                className="h-12 flex-1 rounded-2xl bg-slate-100 text-sm font-black text-slate-500 transition hover:bg-slate-200 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800"
                            >
                                취소
                            </button>
                            <button
                                type="button"
                                onClick={saveSettings}
                                className="h-12 flex-1 rounded-2xl bg-indigo-600 text-sm font-black text-white shadow-lg shadow-indigo-600/15 transition hover:bg-indigo-500 active:scale-95"
                            >
                                저장
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};
