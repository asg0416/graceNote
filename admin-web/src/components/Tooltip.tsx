'use client';

import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { cn } from '@/lib/utils';

interface TooltipProps {
    content: string;
    children: React.ReactNode;
    position?: 'top' | 'bottom' | 'left' | 'right';
    className?: string;
}

export function Tooltip({ content, children, position = 'top', className }: TooltipProps) {
    const [isVisible, setIsVisible] = useState(false);
    const [coords, setCoords] = useState({ top: 0, left: 0 });
    const triggerRef = useRef<HTMLDivElement>(null);
    const tooltipRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        if (!isVisible) return;
        const close = () => setIsVisible(false);
        window.addEventListener('scroll', close, true);
        window.addEventListener('resize', close);
        window.addEventListener('touchmove', close, { passive: true });
        return () => {
            window.removeEventListener('scroll', close, true);
            window.removeEventListener('resize', close);
            window.removeEventListener('touchmove', close);
        };
    }, [isVisible]);

    useLayoutEffect(() => {
        if (!isVisible || !triggerRef.current || !tooltipRef.current) return;

        const triggerRect = triggerRef.current.getBoundingClientRect();
        const tooltipRect = tooltipRef.current.getBoundingClientRect();
        const gap = 10;
        const viewportPadding = 12;

        const centeredLeft = triggerRect.left + triggerRect.width / 2 - tooltipRect.width / 2;
        const centeredTop = triggerRect.top + triggerRect.height / 2 - tooltipRect.height / 2;

        let top = triggerRect.top - tooltipRect.height - gap;
        let left = centeredLeft;

        if (position === 'bottom') {
            top = triggerRect.bottom + gap;
        }

        if (position === 'left') {
            top = centeredTop;
            left = triggerRect.left - tooltipRect.width - gap;
        }

        if (position === 'right') {
            top = centeredTop;
            left = triggerRect.right + gap;
        }

        const maxLeft = window.innerWidth - tooltipRect.width - viewportPadding;
        const maxTop = window.innerHeight - tooltipRect.height - viewportPadding;
        setCoords({
            top: Math.max(viewportPadding, Math.min(top, maxTop)),
            left: Math.max(viewportPadding, Math.min(left, maxLeft)),
        });
    }, [isVisible, content, position]);

    return (
        <div
            ref={triggerRef}
            className={cn("relative inline-flex", className)}
            onMouseEnter={() => setIsVisible(true)}
            onMouseLeave={() => setIsVisible(false)}
            onFocus={() => setIsVisible(true)}
            onBlur={() => setIsVisible(false)}
        >
            {children}
            {isVisible && typeof document !== 'undefined' && createPortal(
                <div
                    ref={tooltipRef}
                    style={{ top: coords.top, left: coords.left }}
                    className="fixed z-[99999] max-w-[min(22rem,calc(100vw-24px))] rounded-xl bg-slate-950 px-3 py-2 text-[11px] font-bold leading-relaxed text-white shadow-2xl shadow-slate-900/25 animate-in fade-in zoom-in-95 duration-150 pointer-events-none dark:bg-slate-800"
                >
                    {content}
                </div>,
                document.body
            )}
        </div>
    );
}
