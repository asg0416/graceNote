import { cn } from '@/lib/utils';

type SeasonBadgeProps = {
    title?: string | null;
    periodLabel?: string | null;
    label?: string;
    disabled?: boolean;
    className?: string;
    onClick?: () => void;
};

export function SeasonBadge({
    title,
    periodLabel,
    label = '조편성 시즌',
    disabled = false,
    className,
    onClick,
}: SeasonBadgeProps) {
    const hasSeason = Boolean(title);
    const isInteractive = Boolean(onClick) && !disabled && hasSeason;
    const Component = isInteractive ? 'button' : 'span';

    return (
        <Component
            type={isInteractive ? 'button' : undefined}
            onClick={isInteractive ? onClick : undefined}
            className={cn(
                "inline-flex min-h-7 max-w-full items-center gap-1.5 rounded-full border border-slate-200 bg-white/90 px-2.5 py-1 text-left text-xs shadow-[0_1px_2px_rgba(15,23,42,0.04)] transition-[transform,box-shadow,background-color,border-color] dark:border-slate-800 dark:bg-slate-950/90",
                isInteractive && "cursor-pointer hover:-translate-y-px hover:border-indigo-200 hover:bg-indigo-50/40 hover:shadow-[0_6px_18px_rgba(79,70,229,0.10)] active:scale-[0.96] dark:hover:border-indigo-500/30 dark:hover:bg-indigo-500/10",
                !hasSeason && "border-slate-200 bg-slate-50 text-slate-400 shadow-none dark:border-slate-800 dark:bg-slate-900",
                className
            )}
            aria-label={hasSeason ? `${label}: ${title}` : `${label}: 등록된 시즌 없음`}
        >
            <span
                className={cn(
                    "h-1.5 w-1.5 shrink-0 rounded-full bg-indigo-500",
                    !hasSeason && "bg-slate-300 dark:bg-slate-600"
                )}
            />
            <span className="flex min-w-0 items-baseline gap-1.5 leading-none">
                <span className="shrink-0 text-[11px] font-extrabold tracking-tight text-slate-400">
                    {label}
                </span>
                <span className="min-w-0 truncate text-xs font-black tracking-tight text-slate-900 dark:text-white">
                    {title || '등록된 시즌 없음'}
                </span>
                {periodLabel && (
                    <>
                        <span className="shrink-0 text-[10px] font-bold text-slate-300">·</span>
                        <span className="shrink-0 text-[11px] font-extrabold tabular-nums text-slate-500 dark:text-slate-400">
                            {periodLabel}
                        </span>
                    </>
                )}
            </span>
        </Component>
    );
}
