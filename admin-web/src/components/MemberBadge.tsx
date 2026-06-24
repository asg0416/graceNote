'use client';

import React, { useState } from 'react';
import { cn } from '@/lib/utils';
import { User, ShieldCheck, Crown, Trash2 } from 'lucide-react';
import { PeriodEditPopover } from './kanban/PeriodEditPopover';
import { isPeriodEdited } from '@/lib/periodBadgeState';

interface MemberBadgeProps {
    member: {
        id: string;
        full_name: string;
        role_in_group?: string;
        is_linked?: boolean;
        phone?: string;
        avatar_url?: string;
        spouse_name?: string;
        starts_week_date?: string | null;
        ends_week_date?: string | null;
        group_starts_week_date?: string | null;
        group_ends_week_date?: string | null;
    };
    isSelected?: boolean;
    onClick?: () => void;
    onDoubleClick?: () => void;
    className?: string;
    profileMode?: string;
    onToggleLeader?: (id: string) => void;
    onDeleteMember?: (id: string) => void;
    onUpdateMemberPeriod?: (id: string, updates: { starts_week_date: string | null; ends_week_date: string | null }) => void;
    periodStartMaxDate?: string | null;
    isDeletable?: boolean;
}

export const MemberBadge: React.FC<MemberBadgeProps> = ({
    member,
    isSelected,
    onClick,
    onDoubleClick,
    className,
    profileMode,
    onToggleLeader,
    onDeleteMember,
    onUpdateMemberPeriod,
    periodStartMaxDate,
    isDeletable
}) => {
    const isLeader = member.role_in_group === 'leader';
    const [isEditingPeriod, setIsEditingPeriod] = useState(false);
    const [periodAnchorRect, setPeriodAnchorRect] = useState<DOMRect | null>(null);
    const [initialPeriod] = useState(() => ({
        start: member.starts_week_date || null,
        end: member.ends_week_date || null,
    }));
    const formatShortDate = (value?: string | null) => {
        if (!value) return '';
        const [, month, day] = value.split('-');
        return month && day ? `${Number(month)}/${Number(day)}` : value;
    };
    const hasCustomPeriod = Boolean(
        (member.starts_week_date && member.group_starts_week_date && member.starts_week_date !== member.group_starts_week_date) ||
        (member.ends_week_date && member.group_ends_week_date && member.ends_week_date !== member.group_ends_week_date)
    );
    const periodLabel = hasCustomPeriod
        ? `${formatShortDate(member.starts_week_date)}~${formatShortDate(member.ends_week_date)}`
        : null;
    const hasEditedPeriod = isPeriodEdited(initialPeriod.start, initialPeriod.end, member.starts_week_date, member.ends_week_date);

    const handleToggleLeader = (e: React.MouseEvent) => {
        e.stopPropagation();
        if (onToggleLeader) {
            onToggleLeader(member.id);
        }
    };

    return (
        <div
            onClick={onClick}
            onDoubleClick={onDoubleClick}
            className={cn(
                "group relative flex items-center gap-3 p-3 rounded-2xl border transition-all duration-300 cursor-pointer select-none",
                "bg-white dark:bg-slate-900 shadow-sm",
                isSelected
                    ? "border-indigo-500 ring-2 ring-indigo-500/10 bg-indigo-50/30 dark:bg-indigo-500/5"
                    : "border-slate-200 dark:border-slate-800 hover:border-indigo-300 dark:hover:border-slate-700 hover:shadow-md",
                className
            )}
        >
            {/* Avatar / Initial */}
            <div className={cn(
                "w-10 h-10 rounded-xl flex items-center justify-center font-black text-sm shrink-0 transition-transform group-hover:scale-105",
                isLeader
                    ? "bg-amber-100 text-amber-600 dark:bg-amber-500/10 dark:text-amber-400"
                    : "bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400 bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-800 dark:to-slate-900"
            )}>
                {member.full_name?.[0] || <User className="w-5 h-5" />}
            </div>

            {/* Info */}
            <div className="flex-1 min-w-0">
                <div className="flex items-center gap-1.5">
                    <span className="font-bold text-slate-900 dark:text-white truncate">
                        {member.full_name}
                    </span>
                    {isLeader && (
                        <span className="px-1.5 py-0.5 bg-amber-500 text-white text-[8px] font-black rounded tracking-widest shadow-lg shadow-amber-500/20 shrink-0">
                            조장
                        </span>
                    )}
                </div>
                <div className="flex items-center gap-1.5 mt-0.5">
                    <p className="text-[10px] font-medium text-slate-400 dark:text-slate-500 truncate">
                        {member.phone || '연락처 없음'}
                    </p>
                    {member.is_linked && (
                        <ShieldCheck className="w-3 h-3 text-emerald-500" />
                    )}
                    {profileMode === 'couple' && member.spouse_name && (
                        <div className="flex items-center gap-1 px-1.5 py-0.5 bg-rose-50 dark:bg-rose-500/10 border border-rose-100 dark:border-rose-500/20 rounded-md shrink-0">
                            <span className="text-[9px] font-black text-rose-500 uppercase tracking-tighter">
                                {member.spouse_name} 부부
                            </span>
                        </div>
                    )}
                    {periodLabel && (
                        <span className="relative shrink-0">
                            <button
                                type="button"
                                onClick={(event) => event.stopPropagation()}
                                onDoubleClick={(event) => {
                                    event.stopPropagation();
                                    if (onUpdateMemberPeriod) {
                                        setPeriodAnchorRect(event.currentTarget.getBoundingClientRect());
                                        setIsEditingPeriod(true);
                                    }
                                }}
                                className={cn(
                                    "rounded-md border px-1.5 py-0.5 text-[9px] font-black transition",
                                    hasEditedPeriod
                                        ? "border-indigo-200 bg-indigo-50 text-indigo-700 shadow-sm shadow-indigo-500/10 dark:border-indigo-500/25 dark:bg-indigo-500/10 dark:text-indigo-200"
                                        : "border-amber-100 bg-amber-50 text-amber-700 dark:border-amber-500/20 dark:bg-amber-500/10 dark:text-amber-300",
                                    onUpdateMemberPeriod && "cursor-pointer hover:ring-4 hover:ring-indigo-500/10"
                                )}
                                title={onUpdateMemberPeriod ? "더블클릭해서 이 소속 기간을 수정합니다." : undefined}
                            >
                                {periodLabel}
                            </button>
                            {isEditingPeriod && onUpdateMemberPeriod && (
                                <PeriodEditPopover
                                    title={`${member.full_name} 소속 기간 수정`}
                                    startValue={member.starts_week_date}
                                    endValue={member.ends_week_date}
                                    minValue={member.group_starts_week_date}
                                    maxValue={member.group_ends_week_date}
                                    startMaxValue={periodStartMaxDate || member.group_ends_week_date}
                                    endMaxValue={member.group_ends_week_date}
                                    anchorRect={periodAnchorRect}
                                    onApply={(updates) => onUpdateMemberPeriod(member.id, updates)}
                                    onClose={() => {
                                        setIsEditingPeriod(false);
                                        setPeriodAnchorRect(null);
                                    }}
                                />
                            )}
                        </span>
                    )}
                </div>
            </div>

            {/* Actions: Leader Toggle & Delete */}
            <div className="flex items-center gap-1">
                {onToggleLeader && (
                    <button
                        onClick={handleToggleLeader}
                        className={cn(
                            "p-2 rounded-xl transition-all duration-300 transform",
                            isLeader
                                ? "bg-amber-100 text-amber-600 dark:bg-amber-500/20 dark:text-amber-400 opacity-100 scale-110"
                                : "text-slate-200 dark:text-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 hover:text-amber-500 opacity-0 group-hover:opacity-100"
                        )}
                        title={isLeader ? "조장 해제" : "조장으로 지정"}
                    >
                        <Crown
                            className={cn(
                                "w-4 h-4 transition-all duration-300",
                                isLeader && "fill-amber-500"
                            )}
                        />
                    </button>
                )}

                {onDeleteMember && isDeletable && (
                    <button
                        onClick={(e) => {
                            e.stopPropagation();
                            onDeleteMember(member.id);
                        }}
                        className="p-2 text-slate-200 dark:text-slate-800 hover:text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-500/10 rounded-xl opacity-0 group-hover:opacity-100 transition-all duration-300"
                        title="조에서 제외"
                    >
                        <Trash2 className="w-4 h-4" />
                    </button>
                )}
            </div>

            {/* Selection Indicator */}
            {isSelected && (
                <div className="absolute top-2 right-2 w-2 h-2 rounded-full bg-indigo-500 animate-pulse" />
            )}
        </div>
    );
};
