'use client';

import React from 'react';
import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { MemberBadge } from '../MemberBadge';
import { cn } from '@/lib/utils';

interface DraggableCardProps {
    id: string; // unit id
    members: Array<{
        id: string;
        full_name?: string | null;
        role_in_group?: string;
        is_linked?: boolean;
        phone?: string | null;
        avatar_url?: string;
        spouse_name?: string | null;
        starts_week_date?: string | null;
        ends_week_date?: string | null;
        group_starts_week_date?: string | null;
        group_ends_week_date?: string | null;
    }>;
    isSelected?: boolean;
    onClick: (memberId: string) => void;
    onDoubleClick?: (memberId: string) => void;
    profileMode?: string;
    isDraggingElsewhere?: boolean;
    movingMembersCount?: number;
    onToggleLeader?: (id: string) => void;
    onDeleteMember?: (id: string) => void;
    onUpdateMemberPeriod?: (id: string, updates: { starts_week_date: string | null; ends_week_date: string | null }) => void;
    periodStartMaxDate?: string | null;
    isDeletableMap?: Record<string, boolean>;
    readOnly?: boolean;
}

export const DraggableCard: React.FC<DraggableCardProps> = ({ id, members, isSelected, onClick, onDoubleClick, profileMode, isDraggingElsewhere, movingMembersCount = 1, onToggleLeader, onDeleteMember, onUpdateMemberPeriod, periodStartMaxDate, isDeletableMap, readOnly = false }) => {
    const {
        attributes,
        listeners,
        setNodeRef,
        transform,
        transition,
        isDragging,
    } = useSortable({ id, disabled: readOnly });

    const isGhost = isDragging;
    const isHidden = isDraggingElsewhere;

    // Split transition: 0.5s for leaving (hidden), 0.4s for everything else
    const currentTransition = isHidden
        ? 'all 500ms cubic-bezier(0.16, 1, 0.3, 1)'
        : 'all 400ms cubic-bezier(0.16, 1, 0.3, 1)';

    const style: React.CSSProperties = {
        transform: CSS.Transform.toString(transform),
        transition: transition || currentTransition,
        opacity: isGhost ? 0.2 : (isHidden ? 0 : 1),
        maxHeight: isHidden ? 0 : '800px',
        // Increased ghost height slightly for more breathing room
        minHeight: isGhost ? `${movingMembersCount * 64 + (movingMembersCount - 1) * 8 + 16}px` : (isHidden ? 0 : undefined),
        margin: isHidden ? 0 : undefined,
        padding: isHidden ? 0 : undefined,
        overflow: 'hidden',
        pointerEvents: (isGhost || isHidden) ? 'none' : 'auto',
    };

    return (
        <div
            ref={setNodeRef}
            style={style}
            {...(readOnly ? {} : attributes)}
            {...(readOnly ? {} : listeners)}
            className={cn(
                "flex flex-col gap-2 relative",
                readOnly ? "touch-auto cursor-default" : "touch-none",
                isGhost && "border-2 border-dashed border-indigo-500/20 bg-indigo-500/5 dark:bg-indigo-400/5 rounded-2xl",
                isHidden && "invisible"
            )}
        >
            <div className={cn(
                "w-full flex flex-col gap-2 transition-opacity duration-300",
                isGhost && "opacity-0"
            )}>
                {members.map(member => (
                    <MemberBadge
                        key={member.id}
                        member={{
                            ...member,
                            full_name: member.full_name || '이름 없음',
                            phone: member.phone || undefined,
                            spouse_name: member.spouse_name || undefined,
                        }}
                        isSelected={isSelected}
                        onClick={() => onClick(member.id)}
                        onDoubleClick={() => onDoubleClick?.(member.id)}
                        onToggleLeader={readOnly ? undefined : onToggleLeader}
                        onDeleteMember={readOnly ? undefined : onDeleteMember}
                        onUpdateMemberPeriod={readOnly ? undefined : onUpdateMemberPeriod}
                        periodStartMaxDate={periodStartMaxDate}
                        isDeletable={isDeletableMap?.[member.id]}
                        profileMode={profileMode}
                    />
                ))}
            </div>

            {/* Soft Ghost Background */}
            {isGhost && (
                <div className="absolute inset-0 flex items-center justify-center animate-pulse duration-[3000ms]">
                    <div className="w-[calc(100%-16px)] h-[calc(100%-16px)] bg-indigo-500/[0.03] rounded-[24px]" />
                </div>
            )}
        </div>
    );
};
