'use client';

import React from 'react';
import { cn } from '@/lib/utils';

interface ExportTableViewProps {
    deptName: string;
    groups: any[];
    localMembers: any[];
    profileMode?: string;
    className?: string;
    tableRef?: React.RefObject<HTMLDivElement | null>;
}

export const ExportTableView: React.FC<ExportTableViewProps> = ({
    deptName,
    groups,
    localMembers,
    profileMode,
    className,
    tableRef
}) => {
    const date = new Date().toLocaleDateString('ko-KR', {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
    });

    const unassigned = localMembers.filter(m => !m.group_id);

    return (
        <div
            ref={tableRef}
            className={cn("bg-white p-12 text-slate-900 w-[1200px]", className)}
        >
            <div className="mb-10 text-center">
                <h1 className="text-4xl font-black tracking-tight mb-2">{deptName} 조편성 결과</h1>
                <p className="text-slate-500 font-bold uppercase tracking-widest text-sm">{date}</p>
            </div>

            <table className="w-full border-collapse border-2 border-slate-200">
                <thead>
                    <tr className="bg-slate-900 text-white">
                        <th className="border-2 border-slate-800 p-4 font-black uppercase tracking-wider w-32">조</th>
                        <th className="border-2 border-slate-800 p-4 font-black uppercase tracking-wider w-48">조장</th>
                        <th className="border-2 border-slate-800 p-4 font-black uppercase tracking-wider text-left">조원</th>
                    </tr>
                </thead>
                <tbody>
                    {groups.map((group, index) => {
                        const members = localMembers.filter(m => m.group_id === group.id);
                        const leaders = members.filter(m => m.role_in_group === 'leader');
                        const commonMembers = members.filter(m => m.role_in_group !== 'leader');

                        return (
                            <tr key={group.id} className={index % 2 === 0 ? "bg-white" : "bg-slate-50"}>
                                <td className="border-2 border-slate-200 p-6 text-center whitespace-nowrap">
                                    <span className="font-black text-xl tracking-tight leading-none">{group.name}</span>
                                </td>
                                <td className="border-2 border-slate-200 p-6 text-center whitespace-nowrap">
                                    <div className="flex flex-col items-center gap-1.5">
                                        {(() => {
                                            if (profileMode !== 'couple') {
                                                return leaders.map(l => (
                                                    <span key={l.id} className="font-black text-indigo-600 text-base">{l.full_name}</span>
                                                ));
                                            }

                                            // Unified Leader logic for couples
                                            const seenL = new Set<string>();
                                            const leaderFamilies: any[] = [];
                                            leaders.forEach(l => {
                                                if (seenL.has(l.id)) return;
                                                const spouse = leaders.find(s =>
                                                    !seenL.has(s.id) &&
                                                    s.full_name === l.spouse_name &&
                                                    s.spouse_name === l.full_name
                                                );

                                                if (spouse) {
                                                    leaderFamilies.push({ type: 'couple', m1: l, m2: spouse });
                                                    seenL.add(l.id);
                                                    seenL.add(spouse.id);
                                                } else {
                                                    leaderFamilies.push({ type: 'single', m: l });
                                                    seenL.add(l.id);
                                                }
                                            });

                                            return leaderFamilies.map((fam, i) => (
                                                <div key={i} className="flex flex-col items-center">
                                                    {fam.type === 'couple' ? (
                                                        <>
                                                            <span className="font-black text-indigo-600 text-base">
                                                                {fam.m1.full_name}, {fam.m2.full_name}
                                                            </span>
                                                            {(fam.m1.children_info || fam.m2.children_info) && (
                                                                <span className="text-[10px] text-slate-400 font-bold">({fam.m1.children_info || fam.m2.children_info})</span>
                                                            )}
                                                        </>
                                                    ) : (
                                                        <>
                                                            <span className="font-black text-indigo-600 text-base">{fam.m.full_name}</span>
                                                            {fam.m.children_info && (
                                                                <span className="text-[10px] text-slate-400 font-bold">({fam.m.children_info})</span>
                                                            )}
                                                        </>
                                                    )}
                                                </div>
                                            ));
                                        })()}
                                        {leaders.length === 0 && <span className="text-slate-300 italic">-</span>}
                                    </div>
                                </td>
                                <td className="border-2 border-slate-200 p-6 align-top">
                                    <div className="grid grid-cols-4 gap-2">
                                        {profileMode === 'couple' ? (() => {
                                            const seen = new Set<string>();
                                            const families: any[] = [];
                                            commonMembers.forEach(m => {
                                                if (seen.has(m.id)) return;
                                                const spouse = commonMembers.find(s => !seen.has(s.id) && s.full_name === m.spouse_name && s.spouse_name === m.full_name);
                                                if (spouse) {
                                                    families.push({ type: 'couple', m1: m, m2: spouse });
                                                    seen.add(m.id); seen.add(spouse.id);
                                                } else {
                                                    families.push({ type: 'single', m });
                                                    seen.add(m.id);
                                                }
                                            });
                                            return families.map((fam, i) => (
                                                <div key={i} className="flex flex-col bg-slate-100/40 p-2.5 rounded-lg border border-slate-100 min-h-[52px] justify-center">
                                                    {fam.type === 'couple' ? (
                                                        <>
                                                            <div className="flex items-center gap-1.5 mb-0.5">
                                                                <span className="font-bold text-slate-900 text-[13px]">{fam.m1.full_name}, {fam.m2.full_name}</span>
                                                            </div>
                                                            {(fam.m1.children_info || fam.m2.children_info) && (
                                                                <span className="text-[9px] text-slate-400 font-medium truncate">자녀: {fam.m1.children_info || fam.m2.children_info}</span>
                                                            )}
                                                        </>
                                                    ) : (
                                                        <>
                                                            <span className="font-bold text-slate-900 text-[13px]">{fam.m.full_name}</span>
                                                            {fam.m.children_info && (
                                                                <span className="text-[9px] text-slate-400 font-medium truncate">자녀: {fam.m.children_info}</span>
                                                            )}
                                                        </>
                                                    )}
                                                </div>
                                            ));
                                        })() : (
                                            commonMembers.map(m => (
                                                <div key={m.id} className="bg-slate-50/50 p-2 rounded-md border border-slate-100 text-center">
                                                    <span className="font-bold text-slate-700 text-[13px]">{m.full_name}</span>
                                                </div>
                                            ))
                                        )}
                                        {commonMembers.length === 0 && <span className="col-span-full text-slate-300 italic text-sm py-2">조원 없음</span>}
                                    </div>
                                </td>
                            </tr>
                        );
                    })}

                    {unassigned.length > 0 && (
                        <tr className="bg-rose-50/50">
                            <td className="border-2 border-slate-200 p-6 text-center font-black text-rose-500 whitespace-nowrap">미편성</td>
                            <td className="border-2 border-slate-200 p-6 text-center text-slate-400">-</td>
                            <td className="border-2 border-slate-200 p-6 align-top">
                                <div className="grid grid-cols-4 gap-2">
                                    {unassigned.map((m) => (
                                        <div key={m.id} className="bg-white/60 p-2.5 rounded-lg border border-rose-100/50 flex flex-col justify-center min-h-[52px]">
                                            <span className="font-bold text-slate-500 text-[13px] whitespace-nowrap">{m.full_name}</span>
                                        </div>
                                    ))}
                                </div>
                            </td>
                        </tr>
                    )}
                </tbody>
            </table>

            <div className="mt-12 text-center text-[10px] font-black text-slate-300 uppercase tracking-[0.2em]">
                Grace Note Administrative System
            </div>
        </div>
    );
};
