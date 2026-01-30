'use client';

import React, { useState } from 'react';
import {
    DndContext,
    DragOverlay,
    rectIntersection,
    KeyboardSensor,
    PointerSensor,
    useSensor,
    useSensors,
    DragStartEvent,
    DragOverEvent,
    DragEndEvent,
    defaultDropAnimationSideEffects,
} from '@dnd-kit/core';
import { Plus } from 'lucide-react';
import {
    arrayMove,
    SortableContext,
    sortableKeyboardCoordinates,
    verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { KanbanColumn } from './KanbanColumn';
import { MemberBadge } from '../MemberBadge';
import { cn } from '@/lib/utils';

interface KanbanBoardProps {
    groups: any[];
    members: any[];
    onMoveMembers: (memberIds: string[], targetGroupId: string | null, isCopy?: boolean, targetIndex?: number) => void;
    onReorderMembers: (memberIds: string[], targetGroupId: string | null) => void;
    selectedMemberIds: string[];
    onMemberClick: (id: string) => void;
    onMemberDoubleClick?: (id: string) => void;
    onAddGroup?: (name: string, color: string) => void;
    onDeleteGroup?: (id: string) => void;
    onUpdateGroup?: (id: string, updates: { name?: string, color_hex?: string }) => void;
    onQuickAddMember?: (groupId: string | null, name: string) => void;
    onAddMembers?: (groupId: string | null) => void;
    lastAddedGroupId?: string | null;
    profileMode?: string;
    autoMoveCouples?: boolean;
    onToggleLeader?: (id: string) => void;
}

export const KanbanBoard: React.FC<KanbanBoardProps> = ({
    groups,
    members,
    onMoveMembers,
    onReorderMembers,
    onToggleLeader,
    selectedMemberIds,
    onMemberClick,
    onMemberDoubleClick,
    onAddGroup,
    onDeleteGroup,
    onUpdateGroup,
    onQuickAddMember,
    onAddMembers,
    lastAddedGroupId,
    profileMode,
    autoMoveCouples = true
}) => {
    const [activeId, setActiveId] = useState<string | null>(null);
    const [dragSessionMembers, setDragSessionMembers] = useState<any[] | null>(null);

    // Track the last move request to prevent loops while state is updating or during animations
    const lastMoveRequestRef = React.useRef<{
        ids: string[];
        targetGroupId: string | null;
        timestamp: number;
    } | null>(null);

    // Use local session members if dragging, otherwise use props
    const currentMembers = dragSessionMembers || members;
    const activeMember = currentMembers.find(m => m.id === activeId);

    const sensors = useSensors(
        useSensor(PointerSensor, {
            activationConstraint: {
                distance: 5, // Allow some movement before drag starts to allow clicks
            }
        }),
        useSensor(KeyboardSensor, {
            coordinateGetter: sortableKeyboardCoordinates,
        })
    );

    const handleDragStart = React.useCallback((event: DragStartEvent) => {
        setActiveId(event.active.id as string);
        // Start a local session with a deep copy of members
        setDragSessionMembers([...members]);
    }, [members]);

    const handleDragOver = React.useCallback((event: DragOverEvent) => {
        const { active, over } = event;
        if (!over || !dragSessionMembers) return;

        const activeId = active.id as string;
        const overId = over.id as string;

        const activeMemberInSession = dragSessionMembers.find(m => m.id === activeId);
        if (!activeMemberInSession) return;

        let overGroupId: string | null = null;
        if (groups.some(g => g.id === overId) || overId === 'unassigned') {
            overGroupId = overId === 'unassigned' ? null : overId;
        } else {
            const overMember = dragSessionMembers.find(m => m.id === overId);
            if (overMember) overGroupId = overMember.group_id || null;
        }

        if (activeMemberInSession.group_id === overGroupId) return;

        const activeUnitIds = [activeMemberInSession.id];
        if (autoMoveCouples && profileMode === 'couple' && activeMemberInSession.spouse_name) {
            const spouse = dragSessionMembers.find(s =>
                s.full_name === activeMemberInSession.spouse_name &&
                s.spouse_name === activeMemberInSession.full_name &&
                s.group_id === activeMemberInSession.group_id
            );
            if (spouse) activeUnitIds.push(spouse.id);
        }

        const now = Date.now();
        const lastMove = lastMoveRequestRef.current;

        // Strict flickering protection: 
        // If we recently moved to a group, don't move back or to another group too quickly
        if (lastMove && now - lastMove.timestamp < 300) {
            return;
        }

        lastMoveRequestRef.current = {
            ids: activeUnitIds,
            targetGroupId: overGroupId,
            timestamp: now
        };

        const isCopy = (event.activatorEvent as any)?.shiftKey;
        if (!isCopy) {
            setDragSessionMembers(prev => {
                if (!prev) return prev;
                return prev.map(m => {
                    if (activeUnitIds.includes(m.id)) {
                        return { ...m, group_id: overGroupId };
                    }
                    return m;
                });
            });
        }
    }, [dragSessionMembers, groups, profileMode]);

    const handleDragEnd = React.useCallback((event: DragEndEvent) => {
        const { active, over } = event;
        const finalSessionMembers = dragSessionMembers;

        setActiveId(null);
        setDragSessionMembers(null);
        lastMoveRequestRef.current = null;

        if (!over || !finalSessionMembers) return;

        const activeUnitId = active.id as string;
        const overId = over.id as string;

        // Find the target group from the LOCAL session state (where it might have moved)
        const finalActiveMember = finalSessionMembers.find(m => m.id === activeUnitId);
        if (!finalActiveMember) return;

        let targetGroupId: string | null = null;
        let targetIndex: number | undefined = undefined;

        if (groups.some(g => g.id === overId) || overId === 'unassigned') {
            targetGroupId = overId === 'unassigned' ? null : overId;
        } else {
            const overMember = finalSessionMembers.find(m => m.id === overId);
            if (overMember) {
                targetGroupId = overMember.group_id || null;
                const groupMembers = finalSessionMembers.filter(m => (m.group_id || null) === targetGroupId);

                let unitsInGroup: string[] = [];
                const seen = new Set<string>();
                groupMembers.forEach(m => {
                    if (seen.has(m.id)) return;
                    unitsInGroup.push(m.id);
                    seen.add(m.id);
                    if (profileMode === 'couple' && m.spouse_name) {
                        const spouse = groupMembers.find(s =>
                            s.full_name === m.spouse_name && s.spouse_name === m.full_name
                        );
                        if (spouse) seen.add(spouse.id);
                    }
                });

                const idx = unitsInGroup.indexOf(overId);
                if (idx !== -1) targetIndex = idx;
            }
        }

        // Calculate all member IDs that should move (active unit + selected)
        const idsToMoveSet = new Set<string>();
        idsToMoveSet.add(activeUnitId);

        if (autoMoveCouples && profileMode === 'couple' && finalActiveMember.spouse_name) {
            const spouse = members.find(s => // Use members prop to find original spouse
                s.full_name === finalActiveMember.spouse_name &&
                s.spouse_name === finalActiveMember.full_name &&
                s.group_id === members.find(m => m.id === activeUnitId)?.group_id // find original group
            );
            if (spouse) idsToMoveSet.add(spouse.id);
        }

        selectedMemberIds.forEach(id => idsToMoveSet.add(id));

        const isCopy = (event.activatorEvent as any)?.shiftKey;
        onMoveMembers(Array.from(idsToMoveSet), targetGroupId, isCopy, targetIndex);
    }, [dragSessionMembers, groups, members, profileMode, selectedMemberIds, onMoveMembers]);

    const getMembersByGroup = (groupId: string | null) => {
        return currentMembers.filter((m: any) => (m.group_id || null) === groupId);
    };

    const [isAddingNew, setIsAddingNew] = useState(false);
    const [newGroupName, setNewGroupName] = useState('');
    const [selectedColor, setSelectedColor] = useState('#4f46e5');

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

    const handleSubmitNewGroup = () => {
        if (newGroupName.trim()) {
            onAddGroup?.(newGroupName.trim(), selectedColor);
            setIsAddingNew(false);
            setNewGroupName('');
            setSelectedColor('#4f46e5');
        }
    };

    // Helper to get all members currently moving (dragged + selected)
    const getAllMovingMembers = () => {
        if (!activeId) return [];
        const activeMemberInSession = currentMembers.find((m: any) => m.id === activeId);
        if (!activeMemberInSession) return [];

        const movingIds = new Set<string>();
        movingIds.add(activeMemberInSession.id);

        if (autoMoveCouples && profileMode === 'couple' && activeMemberInSession.spouse_name) {
            const spouse = currentMembers.find((s: any) =>
                s.full_name === activeMemberInSession.spouse_name &&
                s.spouse_name === activeMemberInSession.full_name &&
                s.group_id === activeMemberInSession.group_id
            );
            if (spouse) movingIds.add(spouse.id);
        }

        selectedMemberIds.forEach(id => movingIds.add(id));
        return currentMembers.filter((m: any) => movingIds.has(m.id));
    };

    const movingMembers = getAllMovingMembers();
    const movingMembersCount = movingMembers.length;

    return (
        <DndContext
            sensors={sensors}
            collisionDetection={rectIntersection}
            onDragStart={handleDragStart}
            onDragOver={handleDragOver}
            onDragEnd={handleDragEnd}
        >
            <div className="flex gap-8 px-2 items-start pb-20">
                {/* Unassigned Column */}
                <KanbanColumn
                    id="unassigned"
                    title="미편성 인원"
                    members={getMembersByGroup(null)}
                    selectedMemberIds={selectedMemberIds}
                    onMemberClick={onMemberClick}
                    onMemberDoubleClick={onMemberDoubleClick}
                    onToggleLeader={onToggleLeader}
                    color="#94a3b8"
                    onQuickAdd={onQuickAddMember ? (name) => onQuickAddMember(null, name) : undefined}
                    onAddMembers={onAddMembers ? () => onAddMembers(null) : undefined}
                    profileMode={profileMode}
                    activeId={activeId}
                    movingMembersCount={movingMembersCount}
                    autoMoveCouples={autoMoveCouples}
                />

                {/* Group Columns */}
                {groups.map(group => (
                    <KanbanColumn
                        key={group.id}
                        id={group.id}
                        title={group.name}
                        color={group.color_hex || '#4f46e5'}
                        members={getMembersByGroup(group.id)}
                        selectedMemberIds={selectedMemberIds}
                        onMemberClick={onMemberClick}
                        onMemberDoubleClick={onMemberDoubleClick}
                        onToggleLeader={onToggleLeader}
                        onDelete={onDeleteGroup ? () => onDeleteGroup(group.id) : undefined}
                        onUpdate={onUpdateGroup ? (updates) => onUpdateGroup(group.id, updates) : undefined}
                        onQuickAdd={onQuickAddMember ? (name) => onQuickAddMember(group.id, name) : undefined}
                        onAddMembers={onAddMembers ? () => onAddMembers(group.id) : undefined}
                        autoFocusRename={lastAddedGroupId === group.id}
                        profileMode={profileMode}
                        activeId={activeId}
                        movingMembersCount={movingMembersCount}
                        autoMoveCouples={autoMoveCouples}
                    />
                ))}

                {/* Add Group Placeholder / Button */}
                {!isAddingNew ? (
                    <button
                        onClick={() => setIsAddingNew(true)}
                        className="w-96 shrink-0 h-24 border-2 border-dashed border-slate-300 dark:border-slate-800 rounded-[32px] flex items-center justify-center group cursor-pointer hover:border-indigo-500/50 hover:bg-white dark:hover:bg-slate-900 transition-all active:scale-[0.98] shadow-sm"
                    >
                        <div className="flex items-center gap-3 text-slate-400 group-hover:text-indigo-500 transition-colors">
                            <Plus className="w-5 h-5" />
                            <span className="font-black text-xs uppercase tracking-widest">신규 조 추가</span>
                        </div>
                    </button>
                ) : (
                    <div className="w-96 shrink-0 bg-slate-50/50 dark:bg-slate-900/40 border border-slate-200/60 dark:border-slate-800/60 p-6 rounded-[32px] animate-in zoom-in-95 duration-200">
                        <div className="space-y-4">
                            <div className="flex items-center justify-between">
                                <div className="flex items-center gap-2 text-slate-400">
                                    <Plus className="w-4 h-4" />
                                    <span className="text-[10px] font-black uppercase tracking-widest">신규 조 생성</span>
                                </div>
                                <div className="flex gap-1.5">
                                    {colorPresets.map(color => (
                                        <button
                                            key={color}
                                            onClick={() => setSelectedColor(color)}
                                            className={cn(
                                                "w-4 h-4 rounded-full transition-all hover:scale-125",
                                                selectedColor === color && "ring-2 ring-offset-2 ring-indigo-500 shadow-sm scale-110"
                                            )}
                                            style={{ backgroundColor: color }}
                                        />
                                    ))}
                                </div>
                            </div>
                            <div className="flex gap-2">
                                <input
                                    autoFocus
                                    placeholder="조 이름을 입력하세요"
                                    value={newGroupName}
                                    onChange={(e) => setNewGroupName(e.target.value)}
                                    onKeyDown={(e) => {
                                        if (e.key === 'Enter') {
                                            e.preventDefault();
                                            handleSubmitNewGroup();
                                        }
                                        if (e.key === 'Escape') {
                                            setIsAddingNew(false);
                                            setNewGroupName('');
                                        }
                                    }}
                                    className="flex-1 bg-white dark:bg-slate-950 border border-slate-200 dark:border-slate-800 rounded-2xl px-4 py-3 text-sm font-bold focus:ring-4 focus:ring-indigo-500/10 outline-none transition-all placeholder:text-slate-300"
                                />
                                <button
                                    onClick={handleSubmitNewGroup}
                                    className="px-6 h-[46px] bg-indigo-600 text-white rounded-2xl text-sm font-black flex items-center gap-2 hover:bg-indigo-700 active:scale-95 transition-all shadow-lg shadow-indigo-600/20"
                                >
                                    완료
                                </button>
                            </div>
                            <button
                                onClick={() => {
                                    setIsAddingNew(false);
                                    setNewGroupName('');
                                }}
                                className="w-full h-10 text-slate-400 hover:text-slate-600 text-[10px] font-black uppercase tracking-widest transition-colors"
                            >
                                취소
                            </button>
                        </div>
                    </div>
                )}
            </div>

            <DragOverlay dropAnimation={{
                sideEffects: defaultDropAnimationSideEffects({
                    styles: {
                        active: {
                            opacity: '0.4',
                        },
                    },
                }),
            }}>
                {movingMembers.length > 0 ? (
                    <div className="relative cursor-grabbing transition-transform duration-500 ease-out">
                        {/* Stack Effect (Up to 3 cards) */}
                        {movingMembers.slice(0, 3).reverse().map((m, idx, arr) => {
                            const isMain = idx === arr.length - 1;
                            const offsetIdx = arr.length - 1 - idx;
                            return (
                                <div
                                    key={m.id}
                                    className={cn(
                                        "w-96 transition-all duration-700 ease-out",
                                        isMain ? "relative z-30 rotate-[0.5deg] scale-[1.01] shadow-2xl" :
                                            offsetIdx === 1 ? "absolute top-1 left-1 z-20 opacity-60 scale-[0.99]" :
                                                "absolute top-2 left-2 z-10 opacity-30 scale-[0.98]"
                                    )}
                                >
                                    <MemberBadge
                                        member={m}
                                        isSelected={selectedMemberIds.includes(m.id)}
                                        className="border-indigo-500 bg-white dark:bg-slate-900 shadow-2xl"
                                    />
                                </div>
                            );
                        })}

                        {/* Multi-select Badge */}
                        {movingMembers.length > 1 && (
                            <div className="absolute -top-3 -right-3 z-[40] bg-indigo-600 text-white text-[10px] font-black px-2.5 py-1 rounded-full shadow-xl ring-4 ring-white dark:ring-slate-950 animate-in zoom-in-50 duration-300">
                                {movingMembers.length}
                            </div>
                        )}
                    </div>
                ) : null}
            </DragOverlay>
        </DndContext>
    );
};
