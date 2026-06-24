'use client';

import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { Check, X } from 'lucide-react';
import { clampPeriodUpdate } from '@/lib/regroupingPeriodBulk';

interface PeriodEditPopoverProps {
    title: string;
    startValue?: string | null;
    endValue?: string | null;
    minValue?: string | null;
    maxValue?: string | null;
    startMaxValue?: string | null;
    endMaxValue?: string | null;
    anchorRect: DOMRect | null;
    onApply: (updates: { starts_week_date: string | null; ends_week_date: string | null }) => void;
    onClose: () => void;
}

export const PeriodEditPopover: React.FC<PeriodEditPopoverProps> = ({
    title,
    startValue,
    endValue,
    minValue,
    maxValue,
    startMaxValue,
    endMaxValue,
    anchorRect,
    onApply,
    onClose,
}) => {
    const [draftStart, setDraftStart] = useState(startValue || '');
    const [draftEnd, setDraftEnd] = useState(endValue || '');
    const popoverRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        const handlePointerDown = (event: MouseEvent) => {
            if (popoverRef.current?.contains(event.target as Node)) return;
            onClose();
        };
        const handleKeyDown = (event: KeyboardEvent) => {
            if (event.key === 'Escape') onClose();
        };
        window.addEventListener('mousedown', handlePointerDown);
        window.addEventListener('keydown', handleKeyDown);
        window.addEventListener('scroll', onClose, true);
        window.addEventListener('resize', onClose);
        window.addEventListener('touchmove', onClose, { passive: true });
        return () => {
            window.removeEventListener('mousedown', handlePointerDown);
            window.removeEventListener('keydown', handleKeyDown);
            window.removeEventListener('scroll', onClose, true);
            window.removeEventListener('resize', onClose);
            window.removeEventListener('touchmove', onClose);
        };
    }, [onClose]);

    const apply = () => {
        const { starts_week_date: nextStart = null, ends_week_date: nextEnd = null } = clampPeriodUpdate(
            {
                starts_week_date: draftStart || null,
                ends_week_date: draftEnd || null,
            },
            {
                min: minValue || null,
                startMax: startMaxValue || maxValue || null,
                endMax: endMaxValue || maxValue || null,
            }
        );

        onApply({
            starts_week_date: nextStart,
            ends_week_date: nextEnd,
        });
        onClose();
    };

    if (!anchorRect || typeof document === 'undefined') return null;

    const width = 320;
    const viewportPadding = 12;
    const gap = 10;
    const placeOnTop = anchorRect.top > window.innerHeight / 2;
    const left = Math.max(
        viewportPadding,
        Math.min(anchorRect.left + anchorRect.width / 2 - width / 2, window.innerWidth - width - viewportPadding)
    );
    const top = placeOnTop
        ? Math.max(viewportPadding, anchorRect.top - gap)
        : Math.min(window.innerHeight - viewportPadding, anchorRect.bottom + gap);

    return createPortal(
        <div
            ref={popoverRef}
            className="fixed z-[99999] w-80 rounded-3xl border border-slate-200 bg-white p-4 text-left shadow-2xl shadow-slate-900/15 dark:border-slate-800 dark:bg-slate-950"
            style={{
                left,
                top,
                transform: placeOnTop ? 'translateY(-100%)' : 'translateY(0)',
            }}
            onClick={(event) => event.stopPropagation()}
            onDoubleClick={(event) => event.stopPropagation()}
        >
            <div className="mb-3 flex items-start justify-between gap-3">
                <div>
                    <p className="text-xs font-black text-slate-900 dark:text-white">{title}</p>
                    <p className="mt-1 text-[11px] font-bold text-slate-400">입력 후 현재 시즌 저장을 눌러야 반영됩니다.</p>
                </div>
                <button
                    type="button"
                    onClick={onClose}
                    className="rounded-xl p-1.5 text-slate-400 transition hover:bg-slate-100 hover:text-slate-700 dark:hover:bg-slate-900 dark:hover:text-white"
                    aria-label="기간 편집 닫기"
                >
                    <X className="h-4 w-4" />
                </button>
            </div>

            <div className="grid grid-cols-2 gap-2">
                <label className="space-y-1">
                    <span className="text-[10px] font-black uppercase tracking-widest text-slate-400">시작일</span>
                    <input
                        type="date"
                        value={draftStart}
                        min={minValue || undefined}
                        max={startMaxValue || maxValue || draftEnd || undefined}
                        onChange={(event) => setDraftStart(event.target.value)}
                        className="h-10 w-full rounded-2xl border border-slate-200 bg-slate-50 px-3 text-xs font-black text-slate-900 outline-none transition focus:border-indigo-300 focus:bg-white focus:ring-4 focus:ring-indigo-500/10 dark:border-slate-800 dark:bg-slate-900 dark:text-white"
                    />
                </label>
                <label className="space-y-1">
                    <span className="text-[10px] font-black uppercase tracking-widest text-slate-400">종료일</span>
                    <input
                        type="date"
                        value={draftEnd}
                        min={draftStart || minValue || undefined}
                        max={endMaxValue || maxValue || undefined}
                        onChange={(event) => setDraftEnd(event.target.value)}
                        className="h-10 w-full rounded-2xl border border-slate-200 bg-slate-50 px-3 text-xs font-black text-slate-900 outline-none transition focus:border-indigo-300 focus:bg-white focus:ring-4 focus:ring-indigo-500/10 dark:border-slate-800 dark:bg-slate-900 dark:text-white"
                    />
                </label>
            </div>

            {(minValue || maxValue) && (
                <p className="mt-3 rounded-2xl bg-slate-50 px-3 py-2 text-[11px] font-bold text-slate-500 dark:bg-slate-900 dark:text-slate-400">
                    선택 가능한 범위: {minValue || '시작 제한 없음'} ~ {maxValue || '종료 제한 없음'}
                </p>
            )}

            <button
                type="button"
                onClick={apply}
                className="mt-3 inline-flex h-10 w-full items-center justify-center gap-2 rounded-2xl bg-indigo-600 text-xs font-black text-white shadow-lg shadow-indigo-600/20 transition hover:bg-indigo-500 active:scale-[0.98]"
            >
                <Check className="h-4 w-4" />
                기간 입력
            </button>
        </div>,
        document.body
    );
};
