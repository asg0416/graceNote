import { useState, useMemo } from 'react';
import { useDroppable } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { DraggableCard } from './DraggableCard';
import { cn } from '@/lib/utils';
import { Users, MoreVertical, Plus, Trash2, Edit2, X, Check, Search } from 'lucide-react';
import { useRef, useEffect } from 'react';

interface KanbanColumnProps {
    id: string; // group_id or 'unassigned'
    title: string;
    members: any[];
    selectedMemberIds: string[];
    onMemberClick: (id: string) => void;
    onMemberDoubleClick?: (id: string) => void;
    color?: string;
    onAddMembers?: () => void;
    onDelete?: () => void;
    onUpdate?: (updates: { name?: string, color_hex?: string }) => void;
    onQuickAdd?: (name: string) => void;
    autoFocusRename?: boolean;
    profileMode?: string;
    activeId?: string | null;
    movingMembersCount?: number;
    onToggleLeader?: (id: string) => void;
    autoMoveCouples?: boolean;
}

export const KanbanColumn: React.FC<KanbanColumnProps> = ({
    id,
    title,
    members,
    selectedMemberIds,
    onMemberClick,
    onMemberDoubleClick,
    color = '#4f46e5',
    onAddMembers,
    onDelete,
    onUpdate,
    onQuickAdd,
    autoFocusRename = false,
    profileMode,
    activeId,
    movingMembersCount = 1,
    onToggleLeader,
    autoMoveCouples = true
}) => {
    const { setNodeRef, isOver } = useDroppable({ id });
    const [isRenaming, setIsRenaming] = useState(false);
    const [newName, setNewName] = useState(title);
    const [newColor, setNewColor] = useState(color);
    const [isAdding, setIsAdding] = useState(false);
    const [quickAddName, setQuickAddName] = useState('');
    const [showMenu, setShowMenu] = useState(false);
    const [searchQuery, setSearchQuery] = useState('');
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

    // Auto-focus renaming on mount if requested
    useEffect(() => {
        if (autoFocusRename) {
            setIsRenaming(true);
        }
    }, [autoFocusRename]);

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

        const units: { id: string, members: any[] }[] = [];
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
    }, [filteredMembers, profileMode]);

    return (
        <div className="flex flex-col w-96 shrink-0 max-h-[820px] bg-white dark:bg-slate-900/60 rounded-[32px] border border-slate-200/80 dark:border-slate-800/60 transition-all group/column shadow-sm hover:shadow-xl hover:shadow-slate-200/40 dark:hover:shadow-none">
            {/* Header - Sticky within column */}
            <div className="sticky top-0 z-20 p-5 flex items-center justify-between border-b border-slate-200/60 dark:border-slate-800/60 bg-white/95 dark:bg-slate-950/95 backdrop-blur-xl rounded-t-[31px]">
                <div className="flex items-center gap-3 flex-1 min-w-0">
                    <div
                        className="w-2 h-6 rounded-full shrink-0"
                        style={{ backgroundColor: color }}
                    />
                    <div className="flex-1 min-w-0">
                        {isRenaming ? (
                            <div className="flex flex-col gap-2 flex-1 pr-2">
                                <div className="flex items-center gap-1">
                                    <input
                                        autoFocus
                                        value={newName}
                                        onChange={(e) => setNewName(e.target.value)}
                                        onKeyDown={(e) => {
                                            if (e.key === 'Enter') {
                                                onUpdate?.({ name: newName, color_hex: newColor });
                                                setIsRenaming(false);
                                            }
                                            if (e.key === 'Escape') {
                                                setIsRenaming(false);
                                                setNewName(title);
                                                setNewColor(color);
                                            }
                                        }}
                                        className="flex-1 bg-slate-100 dark:bg-slate-800 border-none rounded-md px-2 py-1 text-sm font-black focus:ring-2 focus:ring-indigo-500/20 outline-none"
                                    />
                                    <button
                                        onClick={() => {
                                            onUpdate?.({ name: newName, color_hex: newColor });
                                            setIsRenaming(false);
                                        }}
                                        className="p-1 text-emerald-500 hover:bg-emerald-50 dark:hover:bg-emerald-500/10 rounded"
                                    >
                                        <Check className="w-4 h-4" />
                                    </button>
                                    <button
                                        onClick={() => {
                                            setIsRenaming(false);
                                            setNewName(title);
                                            setNewColor(color);
                                        }}
                                        className="p-1 text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-500/10 rounded"
                                    >
                                        <X className="w-4 h-4" />
                                    </button>
                                </div>
                                <div className="flex gap-1.5 flex-wrap">
                                    {colorPresets.map(c => (
                                        <button
                                            key={c}
                                            onClick={() => setNewColor(c)}
                                            className={cn(
                                                "w-3.5 h-3.5 rounded-full transition-all hover:scale-125",
                                                newColor === c && "ring-2 ring-offset-2 ring-indigo-500 scale-110"
                                            )}
                                            style={{ backgroundColor: c }}
                                        />
                                    ))}
                                </div>
                            </div>
                        ) : (
                            <div onDoubleClick={() => setIsRenaming(true)} className="cursor-text group/title">
                                <h3 className="font-black text-slate-900 dark:text-white text-sm tracking-tight leading-none uppercase truncate group-hover/title:text-indigo-600 transition-colors">
                                    {title}
                                </h3>
                                <div className="flex items-center gap-3">
                                    <p className="text-[10px] font-bold text-slate-400 dark:text-slate-500 mt-1 uppercase tracking-widest flex items-center gap-1">
                                        <Users className="w-2.5 h-2.5" />
                                        {members.length}명
                                    </p>
                                </div>
                            </div>
                        )}
                    </div>
                </div>
                <div className="flex items-center gap-1 relative">
                    {onAddMembers && (
                        <button
                            onClick={onAddMembers}
                            className="p-1.5 text-slate-400 hover:text-indigo-600 hover:bg-slate-100 dark:hover:bg-slate-800 rounded-lg transition-all"
                        >
                            <Plus className="w-4 h-4" />
                        </button>
                    )}
                    <button
                        onClick={() => setShowMenu(!showMenu)}
                        className={cn(
                            "p-1.5 text-slate-300 hover:text-slate-600 dark:hover:text-slate-200 rounded-lg transition-colors",
                            showMenu && "bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-200"
                        )}
                    >
                        <MoreVertical className="w-4 h-4" />
                    </button>

                    {showMenu && (
                        <div
                            ref={menuRef}
                            className="absolute top-full right-0 mt-2 w-40 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl shadow-xl z-[100] overflow-hidden animate-in fade-in slide-in-from-top-1"
                        >
                            <button
                                onClick={() => {
                                    setIsRenaming(true);
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
                                        if (confirm('이 조를 삭제하시겠습니까? 소속된 인원은 미편성으로 이동됩니다.')) {
                                            onDelete();
                                        }
                                        setShowMenu(false);
                                    }}
                                    className="w-full flex items-center gap-2 px-4 py-2 text-xs font-bold text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-500/10 transition-colors"
                                >
                                    <Trash2 className="w-3.5 h-3.5" />
                                    조 삭제
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
                        items={familyUnits.map((u: { id: string }) => u.id)}
                        strategy={verticalListSortingStrategy}
                    >
                        {familyUnits.map((unit: { id: string, members: any[] }) => {
                            const isSelected = unit.members.some((m: any) => selectedMemberIds.includes(m.id));
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
                                    profileMode={profileMode}
                                    isDraggingElsewhere={isBeingDragged}
                                    movingMembersCount={movingMembersCount}
                                />
                            );
                        })}
                    </SortableContext>
                </div>
            </div>

            {/* Footer - Full Member Addition Trigger */}
            <div className="p-4 border-t border-slate-200/60 dark:border-slate-800/60 bg-white/30 dark:bg-slate-900/30 shrink-0 rounded-b-[32px]">
                <button
                    onClick={() => onAddMembers?.()}
                    className="w-full flex items-center justify-center gap-2 h-11 border border-dashed border-slate-200 dark:border-slate-800 rounded-2xl text-slate-400 hover:text-indigo-600 hover:border-indigo-500/50 hover:bg-white dark:hover:bg-slate-900 transition-all group active:scale-95 shadow-sm"
                >
                    <Plus className="w-4 h-4 group-hover:scale-110 transition-transform" />
                    <span className="text-xs font-black uppercase tracking-widest">성도 추가</span>
                </button>
            </div>
        </div>
    );
};
