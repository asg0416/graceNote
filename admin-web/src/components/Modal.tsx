'use client';

import React, { useEffect } from 'react';
import { X } from 'lucide-react';
import { cn } from '@/lib/utils';

interface ModalProps {
    isOpen: boolean;
    onClose: () => void;
    title: string;
    subtitle?: string;
    children: React.ReactNode;
    maxWidth?: 'sm' | 'md' | 'lg' | 'xl' | '2xl' | '3xl' | '4xl';
    className?: string;
}

export function Modal({ isOpen, onClose, title, subtitle, children, maxWidth = 'xl', className }: ModalProps) {
    useEffect(() => {
        if (isOpen) {
            document.body.style.overflow = 'hidden';
        } else {
            document.body.style.overflow = 'unset';
        }
        return () => {
            document.body.style.overflow = 'unset';
        };
    }, [isOpen]);

    if (!isOpen) return null;

    const maxWidthClasses = {
        sm: 'max-w-sm',
        md: 'max-w-md',
        lg: 'max-w-lg',
        xl: 'max-w-xl',
        '2xl': 'max-w-2xl',
        '3xl': 'max-w-3xl',
        '4xl': 'max-w-4xl',
    };

    return (
        <div className="fixed top-16 sm:top-20 lg:left-64 left-0 right-0 bottom-0 z-[100] flex items-center justify-center p-4 sm:p-6 bg-slate-900/60 dark:bg-[#030712]/80 backdrop-blur-md">
            <div className="absolute inset-0" onClick={onClose} />
            <div className={cn(
                "relative bg-white dark:bg-[#0a0f1d] w-full rounded-[32px] sm:rounded-[40px] border border-slate-200 dark:border-slate-800/80 shadow-2xl overflow-hidden animate-in fade-in zoom-in duration-300 flex flex-col max-h-[calc(100vh-8rem)]",
                maxWidthClasses[maxWidth],
                className
            )}>
                {/* Header */}
                <div className="p-6 sm:p-8 border-b border-slate-100 dark:border-slate-800/60 flex items-center justify-between bg-white dark:bg-[#0d1221] shrink-0">
                    <div className="flex flex-col">
                        <h3 className="text-xl sm:text-2xl font-black text-slate-900 dark:text-white tracking-tighter leading-tight">{title}</h3>
                        {subtitle && <p className="text-slate-400 dark:text-slate-500 text-[10px] font-black mt-1 uppercase tracking-widest">{subtitle}</p>}
                    </div>
                    <button onClick={onClose} className="w-10 h-10 sm:w-12 sm:h-12 flex items-center justify-center bg-slate-50 dark:bg-slate-800 rounded-xl sm:rounded-2xl transition-all group hover:bg-slate-100 dark:hover:bg-slate-700 border border-slate-100 dark:border-slate-700 shrink-0">
                        <X className="w-5 sm:w-6 h-5 sm:h-6 text-slate-400 group-hover:text-slate-600 dark:group-hover:text-white" />
                    </button>
                </div>

                {/* Content */}
                <div className="flex-1 overflow-y-auto custom-scrollbar p-6 sm:p-8">
                    {children}
                </div>
            </div>
        </div>
    );
}
