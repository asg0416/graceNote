'use client';

import React from 'react';
import { cn } from '@/lib/utils';
import { User, ShieldCheck } from 'lucide-react';

interface MemberBadgeProps {
    member: {
        id: string;
        full_name: string;
        role_in_group?: string;
        is_linked?: boolean;
        phone?: string;
        avatar_url?: string;
        spouse_name?: string;
    };
    isSelected?: boolean;
    onClick?: () => void;
    onDoubleClick?: () => void;
    className?: string;
    profileMode?: string;
}

export const MemberBadge: React.FC<MemberBadgeProps> = ({
    member,
    isSelected,
    onClick,
    onDoubleClick,
    className,
    profileMode
}) => {
    const isLeader = member.role_in_group === 'leader';

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
                        <span className="px-1.5 py-0.5 bg-amber-500 text-white text-[8px] font-black rounded uppercase tracking-widest shadow-lg shadow-amber-500/20 shrink-0">
                            Leader
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
                </div>
            </div>

            {/* Selection Indicator */}
            {isSelected && (
                <div className="absolute top-2 right-2 w-2 h-2 rounded-full bg-indigo-500 animate-pulse" />
            )}
        </div>
    );
};
