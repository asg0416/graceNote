'use client';

import React, { useState } from 'react';
import { cn } from '@/lib/utils';

interface TooltipProps {
    content: string;
    children: React.ReactNode;
    position?: 'top' | 'bottom' | 'left' | 'right';
    className?: string;
}

export function Tooltip({ content, children, position = 'top', className }: TooltipProps) {
    const [isVisible, setIsVisible] = useState(false);

    const positionClasses = {
        top: 'bottom-full left-1/2 -translate-x-1/2 mb-2',
        bottom: 'top-full left-1/2 -translate-x-1/2 mt-2',
        left: 'right-full top-1/2 -translate-y-1/2 mr-2',
        right: 'left-full top-1/2 -translate-y-1/2 ml-2'
    };

    const arrowClasses = {
        top: 'top-full left-1/2 -translate-x-1/2 -mt-1 border-t-slate-900 dark:border-t-slate-800',
        bottom: 'bottom-full left-1/2 -translate-x-1/2 -mb-1 border-b-slate-900 dark:border-b-slate-800',
        left: 'left-full top-1/2 -translate-y-1/2 -ml-1 border-l-slate-900 dark:border-l-slate-800',
        right: 'right-full top-1/2 -translate-y-1/2 -mr-1 border-r-slate-900 dark:border-r-slate-800'
    };

    return (
        <div
            className={cn("relative inline-flex", className)}
            onMouseEnter={() => setIsVisible(true)}
            onMouseLeave={() => setIsVisible(false)}
        >
            {children}
            {isVisible && (
                <div className={cn(
                    "absolute z-[110] px-3 py-1.5 text-[10px] font-bold text-white bg-slate-900 dark:bg-slate-800 rounded-lg whitespace-nowrap shadow-xl animate-in fade-in zoom-in duration-200 pointer-events-none",
                    positionClasses[position],
                    className
                )}>
                    {content}
                    <div className={cn(
                        "absolute border-4 border-transparent",
                        arrowClasses[position]
                    )} />
                </div>
            )}
        </div>
    );
}
