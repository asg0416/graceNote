'use client';

import { useState, useRef } from 'react';
import Papa from 'papaparse';
import { supabase } from '@/lib/supabase';
import { Modal } from '@/components/Modal';
import {
    Upload,
    Loader2,
    CheckCircle2,
    AlertCircle,
    LayoutGrid,
    Sparkles,
    PencilLine,
    Trash2,
    UserPlus,
    FileSpreadsheet,
    FileText
} from 'lucide-react';
import { read, utils } from 'xlsx';

interface Department {
    id: string;
    name: string;
    color_hex?: string;
}

interface MemberData {
    full_name: string;
    phone: string;
    role_in_group: 'leader' | 'member';
    group_name: string;
    spouse_name: string | null;
    children_info: string | null;
    church_id: string;
    department_id: string;
    is_linked: boolean;
    person_id?: string | null;
    profile_id?: string | null;
    batch_link_id?: string; // Client-side ID to link rows within the same batch
}

interface DBMatch {
    id: string;
    full_name: string;
    phone: string | null;
    person_id: string;
    profile_id: string | null;
    group_name: string | null;
    department_name?: string;
}

interface SmartBatchModalProps {
    onClose: () => void;
    onSuccess: () => void;
    churchId: string;
    departments: Department[];
    initialDeptId?: string;
}

export default function SmartBatchModal({ onClose, onSuccess, churchId, departments, initialDeptId }: SmartBatchModalProps) {
    const [step, setStep] = useState<'upload' | 'preview' | 'syncing'>('upload');
    const [tab, setTab] = useState<'ai'>('ai'); // Unified AI tab
    const [rawText, setRawText] = useState('');
    const [parsedData, setParsedData] = useState<Partial<MemberData>[]>([]);
    const [selectedDeptId, setSelectedDeptId] = useState(initialDeptId || '');
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [dbMatches, setDbMatches] = useState<Record<string, DBMatch[]>>({});
    const [matchingLoading, setMatchingLoading] = useState(false);
    const fileInputRef = useRef<HTMLInputElement>(null);
    const csvInputRef = useRef<HTMLInputElement>(null);

    const handleUpdateRow = (index: number, updates: Partial<MemberData>) => {
        const newData = [...parsedData];
        const item = newData[index];

        // If updating name, and it was linked to others in batch, update them too or unlink
        newData[index] = { ...item, ...updates };

        // If person_id is updated, sync it to all rows with the same batch_link_id
        if (updates.person_id !== undefined && item.batch_link_id) {
            newData.forEach((row, i) => {
                if (row.batch_link_id === item.batch_link_id) {
                    newData[i] = { ...newData[i], person_id: updates.person_id, profile_id: updates.profile_id, is_linked: !!updates.profile_id };
                }
            });
        }

        setParsedData(newData);
    };

    const handleDeleteRow = (index: number) => {
        const newData = parsedData.filter((_, i) => i !== index);
        setParsedData(newData);
    };

    const handleAddRow = () => {
        setParsedData([...parsedData, {
            full_name: '',
            role_in_group: 'member',
            group_name: '',
            spouse_name: '',
            children_info: '',
            church_id: churchId,
            department_id: selectedDeptId,
            is_linked: false
        }]);
    };

    // Smart Parser Logic (Legacy / Text direct paste)
    const parseText = (text: string): Partial<MemberData>[] => {
        const lines = text.split('\n');
        const results: Partial<MemberData>[] = [];
        let currentGroup = '';

        lines.forEach(line => {
            let trimmed = line.trim();
            if (!trimmed) return;

            // 1. Group Name Detection (e.g., "[1조]", "1조:", "1조 조원들", "1조 조장 : ...")
            // Enhanced regex to extract group even if role/name follows on the same line
            const groupRegex = /^([\[\]\s]*\d+조[\[\]\s]*|[\w가-힣]+조)/;
            const groupMatch = trimmed.match(groupRegex);

            if (groupMatch) {
                currentGroup = groupMatch[1].replace(/[\[\]]/g, '').trim();
                // If line contains colon after group name, it might be "1조 : 홍길동"
                if (trimmed.includes(':')) {
                    const parts = trimmed.split(':');
                    // Check if the part before colon is just the group (e.g., "1조 :")
                    const beforeColon = parts[0].trim();
                    if (beforeColon.match(groupRegex) && beforeColon.length <= currentGroup.length + 2) {
                        trimmed = parts.slice(1).join(':').trim();
                    }
                } else if (trimmed === groupMatch[0].trim()) {
                    return; // Line only contained the group name
                }
            }

            if (!trimmed) return;

            // 2. Handle comma-separated list in a single line
            const members = trimmed.split(/,|\//).map(m => m.trim()).filter(m => m);
            members.forEach(memberText => {
                // Role Detection & Name Cleaning
                let role: 'leader' | 'member' = 'member';

                // Identify role from the segment (e.g., "조장:김신영", "김신영(조장)", "리더 김신영")
                if (memberText.includes('조장') || memberText.includes('리더') || memberText.includes('인도자')) {
                    role = 'leader';
                }

                // Clean name: Remove titles and roles
                let cleanName = memberText;

                // If format is "Role : Name", extract Name
                if (cleanName.includes(':')) {
                    const colonParts = cleanName.split(':');
                    const firstPart = colonParts[0].trim();
                    if (firstPart.includes('조장') || firstPart.includes('조원') || firstPart.includes('리더')) {
                        cleanName = colonParts.slice(1).join(':').trim();
                    }
                }

                // Remove keywords
                cleanName = cleanName.replace(/조장|조원|리더|인도자|성도|집사|권사|장로|목사|[:\s-]*/g, '').trim();

                // Family Match (Name Spouse (Kids))
                const familyMatch = cleanName.match(/^([가-힣a-zA-Z0-9]+)\s*([가-힣a-zA-Z0-9]*)?\s*(\(([^)]+)\))?/);
                if (familyMatch) {
                    const fullName = familyMatch[1];
                    const spouseName = familyMatch[2] || null;
                    const childrenInfo = familyMatch[4] || null;

                    if (fullName.length >= 1) { // Skip empty or invalid names
                        results.push({
                            full_name: fullName,
                            spouse_name: spouseName,
                            children_info: childrenInfo,
                            group_name: currentGroup || '미정',
                            role_in_group: role,
                            church_id: churchId,
                            department_id: selectedDeptId,
                            is_linked: false
                        });
                    }
                }
            });
        });

        return results;
    };

    const fetchMatchesFromDB = async (data: Partial<MemberData>[]) => {
        const names = Array.from(new Set(data.map(d => d.full_name).filter(Boolean))) as string[];
        if (names.length === 0) return;

        setMatchingLoading(true);
        try {
            const { data: matches, error: matchError } = await supabase
                .from('member_directory')
                .select(`
                    id, 
                    full_name, 
                    phone, 
                    person_id, 
                    profile_id, 
                    group_name,
                    department:departments!department_id(name)
                `)
                .in('full_name', names)
                .eq('church_id', churchId);

            if (matchError) throw matchError;

            const matchMap: Record<string, DBMatch[]> = {};
            matches?.forEach((m: any) => {
                if (!matchMap[m.full_name]) matchMap[m.full_name] = [];
                matchMap[m.full_name].push({
                    id: m.id,
                    full_name: m.full_name,
                    phone: m.phone,
                    person_id: m.person_id,
                    profile_id: m.profile_id,
                    group_name: m.group_name,
                    department_name: m.departments?.name
                });
            });
            setDbMatches(matchMap);
        } catch (err) {
            console.error('Error fetching matches:', err);
        } finally {
            setMatchingLoading(false);
        }
    };

    const getRowConflictStatus = (item: Partial<MemberData>, index: number) => {
        const name = item.full_name?.trim();
        if (!name) return { type: 'none', label: '' };

        const sameNameRows = parsedData.filter(d => d.full_name?.trim() === name);
        const sameNameSameGroupRows = sameNameRows.filter(d => (d.group_name?.trim() || '미정') === (item.group_name?.trim() || '미정'));

        const hasDBMatch = dbMatches[name] && dbMatches[name].length > 0;
        const isLinkedToDB = !!item.person_id;
        const isLinked = !!item.person_id || !!item.batch_link_id;

        // 1. Red: Intra-group duplicate (Same name, Same group in batch)
        if (sameNameSameGroupRows.length > 1) {
            return { type: 'red', label: '같은 조 중복' };
        }

        // 2. Indigo: DB Name Conflict (Even if case of internal batch link, if not linked to DB person, it's a conflict)
        if (hasDBMatch && !isLinkedToDB) {
            return { type: 'indigo', label: 'DB 이름 중복 (확인 필수)' };
        }

        // 3. Green: Successfully Linked to DB or Verified internally (now only if no DB match)
        if (isLinked) {
            return { type: 'green', label: isLinkedToDB ? 'DB 성도 연동됨' : '동일인 확인됨' };
        }

        // 4. Yellow: Inter-group duplicate (Same name, Different group in batch) - NOT LINKED
        if (sameNameRows.length > 1 && sameNameSameGroupRows.length === 1 && !isLinked) {
            return { type: 'yellow', label: '타 조 중복 (연동 필요)' };
        }

        return { type: 'none', label: '' };
    };

    const handleLinkSameNames = (name: string, personId?: string, profileId?: string | null) => {
        const batchLinkId = personId ? undefined : Math.random().toString(36).substring(7);
        const newData = parsedData.map(row => {
            if (row.full_name?.trim() === name) {
                return {
                    ...row,
                    person_id: personId || row.person_id,
                    profile_id: personId ? (profileId ?? null) : row.profile_id,
                    is_linked: personId ? !!profileId : row.is_linked,
                    batch_link_id: personId ? undefined : batchLinkId
                };
            }
            return row;
        });
        setParsedData(newData);
    };

    const handleUnlinkSameNames = (name: string) => {
        const newData = parsedData.map(row => {
            if (row.full_name?.trim() === name) {
                const { person_id, profile_id, batch_link_id, ...rest } = row;
                return { ...rest, is_linked: false };
            }
            return row;
        });
        setParsedData(newData);
    };

    const handleVisionUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;

        if (!selectedDeptId) {
            alert('먼저 부서를 선택해 주세요.');
            return;
        }

        setLoading(true);
        setError(null);

        try {
            const reader = new FileReader();
            const base64Promise = new Promise<string>((resolve) => {
                reader.onload = () => resolve(reader.result as string);
                reader.readAsDataURL(file);
            });
            const base64Data = await base64Promise;

            const response = await fetch('/api/vision', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    image: base64Data,
                    mimeType: file.type || (file.name.endsWith('.pdf') ? 'application/pdf' : 'image/png')
                }),
            });

            if (!response.ok) {
                const errorData = await response.json();
                throw new Error(errorData.error || 'AI 분석에 실패했습니다.');
            }

            const { data } = await response.json();

            const mappedData: Partial<MemberData>[] = data.map((item: any) => ({
                ...item,
                role_in_group: item.role_in_group as 'leader' | 'member',
                church_id: churchId,
                department_id: selectedDeptId,
                is_linked: false
            }));

            setParsedData(mappedData);
            setStep('preview');
            fetchMatchesFromDB(mappedData);
        } catch (err: any) {
            console.error(err);
            setError('이미지 분석 중 오류가 발생했습니다: ' + err.message);
        } finally {
            setLoading(false);
        }
    };

    const handleCSVUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;

        if (!selectedDeptId) {
            alert('먼저 부서를 선택해 주세요.');
            return;
        }

        setLoading(true);
        Papa.parse(file, {
            header: true,
            skipEmptyLines: true,
            complete: (result) => {
                setLoading(false);
                const mapped: Partial<MemberData>[] = result.data.map((row: any) => ({
                    full_name: row['이름'] || row['성함'] || row['name'] || row['Name'],
                    group_name: row['조'] || row['group'] || row['Group'],
                    role_in_group: ((row['역할'] || row['role'] || row['Role'] || '').includes('장') || (row['역할'] || row['role'] || row['Role'] || '').includes('리더') ? 'leader' : 'member') as 'leader' | 'member',
                    spouse_name: row['배우자'] || row['spouse'] || row['Spouse'] || null,
                    children_info: row['자녀'] || row['children'] || row['Children'] || null,
                    phone: row['전화번호'] || row['연락처'] || row['phone'] || row['Phone'] || '',
                    church_id: churchId,
                    department_id: selectedDeptId,
                    is_linked: false
                })).filter(item => item.full_name);

                setParsedData(mapped);
                setStep('preview');
                fetchMatchesFromDB(mapped);
            },
            error: (error) => {
                setLoading(false);
                setError('CSV 파일 파싱 중 오류가 발생했습니다: ' + error.message);
            }
        });
    };

    const handleXLSXUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;

        if (!selectedDeptId) {
            alert('먼저 부서를 선택해 주세요.');
            return;
        }

        setLoading(true);
        setError(null);

        try {
            const buffer = await file.arrayBuffer();
            const workbook = read(buffer);
            const worksheet = workbook.Sheets[workbook.SheetNames[0]];

            // 1. Try with headers first
            let jsonData = utils.sheet_to_json(worksheet);

            let mapped: Partial<MemberData>[] = jsonData.map((row: any) => ({
                full_name: String(row['이름'] || row['성함'] || row['name'] || row['Name'] || '').trim(),
                group_name: String(row['조'] || row['group'] || row['Group'] || '미정').trim(),
                role_in_group: ((row['역할'] || row['role'] || row['Role'] || '').includes('장') || (row['역할'] || row['role'] || row['Role'] || '').includes('리더') ? 'leader' : 'member') as 'leader' | 'member',
                spouse_name: row['배우자'] || row['spouse'] || row['Spouse'] || null,
                children_info: row['자녀'] || row['children'] || row['Children'] || null,
                phone: String(row['전화번호'] || row['연락처'] || row['phone'] || row['Phone'] || '').trim(),
                church_id: churchId,
                department_id: selectedDeptId,
                is_linked: false
            })).filter(item => item.full_name);

            // 2. Fallback: If no results with headers, try raw array (useful if headers are missing or mismatched)
            if (mapped.length === 0) {
                const rawData = utils.sheet_to_json(worksheet, { header: 1 }) as any[][];
                if (rawData.length > 0) {
                    // Start from row 0 if it looks like data, or row 1 if it looks like headers
                    mapped = rawData.map((row) => {
                        if (!row[0]) return null;
                        const fullName = String(row[0]).trim();
                        if (fullName === '이름' || fullName === 'Name' || fullName === '성함') return null; // Skip header row

                        return {
                            full_name: fullName,
                            group_name: String(row[1] || '미정').trim(),
                            role_in_group: (String(row[2] || '').includes('장') || String(row[2] || '').includes('리더') ? 'leader' : 'member') as 'leader' | 'member',
                            spouse_name: row[3] || null,
                            children_info: row[4] || null,
                            phone: String(row[5] || '').trim(),
                            church_id: churchId,
                            department_id: selectedDeptId,
                            is_linked: false
                        };
                    }).filter(item => item && item.full_name) as Partial<MemberData>[];
                }
            }

            if (mapped.length === 0) {
                throw new Error('데이터를 찾을 수 없습니다. 파일의 첫 번째 열에 성함이 있는지 확인해 주세요.');
            }

            setParsedData(mapped);
            setStep('preview');
            fetchMatchesFromDB(mapped);
        } catch (err: any) {
            console.error(err);
            setError('엑셀 파일 파싱 중 오류가 발생했습니다: ' + err.message);
        } finally {
            setLoading(false);
        }
    };

    const downloadTemplate = () => {
        const headers = ['이름', '조', '역할', '배우자', '자녀'];
        const rows = [
            ['홍길동', '열매조', '조장', '심청이', '홍길순'],
            ['심청이', '열매조', '조원', '홍길동', '홍길순'],
            ['임꺽정', '희망조', '조장', '', ''],
        ];
        const csvContent = [headers, ...rows].map(e => e.join(",")).join("\n");
        const encodedUri = encodeURI("data:text/csv;charset=utf-8,\uFEFF" + csvContent);
        const link = document.createElement("a");
        link.setAttribute("href", encodedUri);
        link.setAttribute("download", "Gracenote_Member_Template.csv");
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    };

    const handleProcessText = () => {
        if (!selectedDeptId) {
            alert('먼저 부서를 선택해 주세요.');
            return;
        }
        if (!rawText.trim()) return;

        const data = parseText(rawText);
        setParsedData(data);
        setStep('preview');
        fetchMatchesFromDB(data);
    };

    const handleUploadToDB = async () => {
        console.log('Initiating upload to DB...');

        if (!churchId || !selectedDeptId) {
            setError('교회 또는 부서 정보가 누락되었습니다.');
            return;
        }

        // 0. Preliminary Duplicate Check (Advanced)
        const unaddressedConflicts: string[] = [];

        parsedData.forEach((item, idx) => {
            const status = getRowConflictStatus(item, idx);
            if (status.type === 'red') {
                unaddressedConflicts.push(`${item.full_name} (${item.group_name || '미정'}): 같은 조 내 중복`);
            } else if (status.type === 'yellow' && !item.batch_link_id && !item.person_id) {
                unaddressedConflicts.push(`${item.full_name}: 타 조 소속 동일인 여부를 확인해 주세요 (연동 또는 이름 수정)`);
            } else if (status.type === 'indigo' && !item.person_id) {
                // If its indigo but has person_id, it means its resolved via DB link. 
                // But getRowConflictStatus already returns 'green' if it has person_id.
                // So if we are here in indigo, it DEFINITELY needs name change or DB link.
                unaddressedConflicts.push(`${item.full_name}: DB에 이미 있는 이름입니다. 동일인이라면 '연결'하시고, 아니라면 '구분자(A, B 등)'를 붙여주세요.`);
            }
        });

        if (unaddressedConflicts.length > 0) {
            setError(`해결되지 않은 중복 이슈가 있습니다:\n${unaddressedConflicts.join('\n')}\n\n동일인이라면 '연결하기'를 클릭하고, 동명이인이라면 이름 뒤에 (A), (B) 등 구분자를 넣어주세요.`);
            return;
        }

        setStep('syncing');
        setLoading(true);
        setError(null);

        try {
            // 0. Clean and Validate Data
            const cleanParsedData: MemberData[] = parsedData.map(item => ({
                church_id: churchId,
                department_id: selectedDeptId,
                full_name: item.full_name?.trim() || '',
                phone: item.phone?.trim() || '',
                group_name: item.group_name?.trim() || '미정',
                role_in_group: item.role_in_group || 'member',
                spouse_name: item.spouse_name?.trim() || null,
                children_info: item.children_info?.trim() || null,
                person_id: item.person_id || null,
                profile_id: item.profile_id || null,
                is_linked: !!item.profile_id
            })).filter(item => item.full_name);

            console.log('Cleaned Data:', cleanParsedData);

            if (cleanParsedData.length === 0) {
                throw new Error('등록할 데이터가 없습니다.');
            }

            const missingPhone = cleanParsedData.find(item => !item.phone);
            if (missingPhone) {
                throw new Error(`${missingPhone.full_name} 성도의 전화번호가 없습니다. 동일인 식별을 위해 모든 성도의 전화번호가 필요합니다.`);
            }

            // 1. Sync groups (Upsert)
            const uniqueGroupNames = Array.from(new Set(
                cleanParsedData
                    .map(item => item.group_name)
                    .filter(name => name && name !== '미정')
            ));

            console.log('Syncing groups...', uniqueGroupNames);
            if (uniqueGroupNames.length > 0) {
                const groupRecords = uniqueGroupNames.map(name => ({
                    church_id: churchId,
                    department_id: selectedDeptId,
                    name: name
                }));

                const { error: groupError } = await supabase
                    .from('groups')
                    .upsert(groupRecords, { onConflict: 'church_id,department_id,name' });

                if (groupError) {
                    console.error('Group Sync Error:', groupError);
                    throw groupError;
                }
            }

            // 2. Bulk insert into member_directory
            console.log('Sending bulk upsert to member_directory...');
            const { error: insertError } = await supabase
                .from('member_directory')
                .upsert(cleanParsedData, { onConflict: 'church_id,department_id,group_name,full_name' });

            if (insertError) {
                console.error('Member Insert Error:', insertError);
                throw insertError;
            }

            console.log('Upload successful!');
            onSuccess();
            onClose();
        } catch (err: any) {
            console.error('Final Catch Error:', err);
            setError('데이터 저장 중 오류가 발생했습니다: ' + (err.message || '알 수 없는 오류'));
            setStep('preview');
        } finally {
            setLoading(false);
        }
    };

    return (
        <Modal
            isOpen={true} // Controlled by parent
            onClose={onClose}
            title="AI 비전 및 일괄 등록"
            subtitle="Unified Member Management"
            maxWidth="4xl"
        >
            <div className="space-y-6 sm:space-y-8">
                {/* Error Display (Common) */}
                {error && (
                    <div className="p-4 bg-amber-50 dark:bg-amber-500/10 border border-amber-100 dark:border-amber-500/20 rounded-2xl flex gap-3 items-start animate-in fade-in slide-in-from-top-2">
                        <AlertCircle className="w-5 h-5 text-amber-500 shrink-0 mt-0.5" />
                        <p className="text-xs font-bold text-amber-700 dark:text-amber-400 leading-relaxed break-words whitespace-pre-wrap">{error}</p>
                    </div>
                )}

                {step === 'upload' && (
                    <div className="space-y-8">
                        {/* 1. Dept Selection */}
                        <div className="space-y-3">
                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">1. 부서 선택</label>
                            <div className="relative">
                                <select
                                    value={selectedDeptId}
                                    onChange={(e) => setSelectedDeptId(e.target.value)}
                                    className="w-full px-6 py-4 bg-slate-50 dark:bg-slate-900 border-2 border-slate-100 dark:border-slate-800/40 rounded-3xl font-black text-slate-900 dark:text-white focus:outline-none focus:border-indigo-500 transition-all appearance-none cursor-pointer"
                                >
                                    <option value="" disabled>등록할 부서를 선택해 주세요</option>
                                    {departments.map(dept => (
                                        <option key={dept.id} value={dept.id}>
                                            {dept.name}
                                        </option>
                                    ))}
                                </select>
                                <div className="absolute right-6 top-1/2 -translate-y-1/2 pointer-events-none text-slate-400">
                                    <LayoutGrid className="w-5 h-5" />
                                </div>
                                {selectedDeptId && (
                                    <div
                                        className="absolute left-4 top-1/2 -translate-y-1/2 w-2 h-2 rounded-full shadow-sm"
                                        style={{ backgroundColor: departments.find(d => d.id === selectedDeptId)?.color_hex || '#6366f1' }}
                                    />
                                )}
                            </div>
                        </div>

                        {/* Homonym & Upsert Guidance */}
                        <div className="p-5 bg-indigo-50/50 dark:bg-indigo-500/5 border border-indigo-100 dark:border-indigo-500/10 rounded-[24px] flex gap-4">
                            <div className="w-10 h-10 bg-white dark:bg-slate-800 rounded-xl flex items-center justify-center text-indigo-600 dark:text-indigo-400 shrink-0 shadow-sm">
                                <AlertCircle className="w-5 h-5" />
                            </div>
                            <div className="space-y-1">
                                <p className="text-sm font-black text-slate-900 dark:text-white tracking-tight">중복 데이터 및 동명이인 안내</p>
                                <p className="text-[11px] text-slate-500 dark:text-slate-400 leading-relaxed font-medium">
                                    • <span className="text-indigo-600 dark:text-indigo-400 font-bold">복수 조 활동</span>이 가능합니다. 동일인이 두 개 이상의 조에 소속될 경우 각 조에 이름을 등록해 주세요.<br />
                                    • 동명이인을 구분해야 할 때만 <span className="text-indigo-600 dark:text-indigo-400 font-bold">"홍길동(A)", "홍길동(82)"</span> 처럼 구분하여 입력해 주세요.
                                </p>
                            </div>
                        </div>

                        {/* Unified AI Magic Box */}
                        <div className="space-y-4">
                            <label className="text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-[0.2em] ml-1">2. 데이터 업로드 (이미지, 파일 또는 텍스트)</label>

                            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                                {/* Upload Area */}
                                <div
                                    onClick={() => fileInputRef.current?.click()}
                                    className="h-72 border-2 border-dashed border-slate-200 dark:border-slate-800 rounded-[32px] flex flex-col items-center justify-center gap-4 hover:border-indigo-500/50 hover:bg-slate-50 dark:hover:bg-slate-900/40 transition-all cursor-pointer group relative overflow-hidden bg-white dark:bg-[#0a0f1d]"
                                >
                                    <div className="w-20 h-20 bg-indigo-50 dark:bg-indigo-500/10 rounded-[28px] flex items-center justify-center text-indigo-600 dark:text-indigo-400 group-hover:scale-110 transition-transform duration-500">
                                        {loading ? <Loader2 className="w-10 h-10 animate-spin" /> : <Upload className="w-10 h-10" />}
                                    </div>
                                    <div className="text-center px-10">
                                        <p className="font-black text-slate-900 dark:text-white text-lg tracking-tight">이미지, PDF 또는 엑셀(CSV/XLSX) 업로드</p>
                                        <p className="text-[10px] text-slate-400 mt-2 uppercase font-bold tracking-widest leading-relaxed">
                                            조편성 사진이나 명단 파일을 올려주세요.<br />AI와 시스템이 데이터를 자동으로 추출합니다.
                                        </p>
                                        <div className="flex gap-2 mt-4">
                                            <div className="flex items-center gap-1.5 px-2 py-1 bg-slate-100 dark:bg-slate-800 rounded-lg">
                                                <Upload className="w-3 h-3 text-slate-400" />
                                                <span className="text-[9px] font-black text-slate-500 uppercase">IMG</span>
                                            </div>
                                            <div className="flex items-center gap-1.5 px-2 py-1 bg-slate-100 dark:bg-slate-800 rounded-lg">
                                                <FileText className="w-3 h-3 text-red-500" />
                                                <span className="text-[9px] font-black text-slate-500 uppercase">PDF</span>
                                            </div>
                                            <div className="flex items-center gap-1.5 px-2 py-1 bg-slate-100 dark:bg-slate-800 rounded-lg">
                                                <FileSpreadsheet className="w-3 h-3 text-emerald-500" />
                                                <span className="text-[9px] font-black text-slate-500 uppercase">XLSX/CSV</span>
                                            </div>
                                        </div>
                                    </div>
                                    <input
                                        type="file"
                                        ref={fileInputRef}
                                        className="hidden"
                                        accept="image/*,.csv,.xlsx,.xls,.pdf"
                                        onChange={(e) => {
                                            const file = e.target.files?.[0];
                                            if (!file) return;

                                            const type = file.type;
                                            const fileName = file.name.toLowerCase();

                                            if (type.includes('image') || type === 'application/pdf' || fileName.endsWith('.pdf')) {
                                                handleVisionUpload(e);
                                            } else if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
                                                handleXLSXUpload(e);
                                            } else {
                                                handleCSVUpload(e);
                                            }
                                        }}
                                    />
                                </div>

                                {/* Text Area */}
                                <div className="flex flex-col gap-3">
                                    <div className="flex-1 min-h-[200px] bg-slate-50/50 dark:bg-slate-900/50 border border-slate-100 dark:border-slate-800 rounded-[32px] p-6 relative group focus-within:border-indigo-500/50 transition-all">
                                        <div className="absolute top-5 right-6 pointer-events-none opacity-20 group-focus-within:opacity-40 transition-opacity">
                                            <PencilLine className="w-6 h-6 text-slate-400" />
                                        </div>
                                        <textarea
                                            value={rawText}
                                            onChange={(e) => setRawText(e.target.value)}
                                            placeholder="텍스트를 복사해서 붙여넣으세요.&#10;예: 1조 홍길동(조장), 김철수, 이영희..."
                                            className="w-full h-full bg-transparent border-0 focus:ring-0 text-slate-900 dark:text-white font-bold text-sm leading-relaxed resize-none p-0"
                                        />
                                    </div>
                                    <button
                                        onClick={handleProcessText}
                                        disabled={!selectedDeptId || !rawText.trim()}
                                        className="w-full py-5 bg-indigo-600 dark:bg-indigo-500 text-white font-black rounded-[28px] hover:bg-indigo-500 dark:hover:bg-indigo-400 transition-all shadow-xl shadow-indigo-600/20 active:scale-95 disabled:opacity-50 disabled:shadow-none flex items-center justify-center gap-3"
                                    >
                                        <Sparkles className="w-5 h-5" />
                                        텍스트 데이터 분석하기
                                    </button>
                                </div>
                            </div>

                            {/* Rules / Notice Grid */}
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-8 pt-8 border-t border-slate-100 dark:border-slate-800/60">
                                <div className="flex gap-4 p-5 bg-slate-50 dark:bg-slate-900/40 rounded-3xl border border-slate-100 dark:border-slate-800">
                                    <div className="w-10 h-10 bg-white dark:bg-slate-800 rounded-xl flex items-center justify-center text-indigo-500 shrink-0">
                                        <AlertCircle className="w-5 h-5" />
                                    </div>
                                    <div className="space-y-1">
                                        <p className="text-xs font-black text-slate-900 dark:text-white uppercase tracking-tight">동명이인 식별 규칙</p>
                                        <p className="text-[11px] text-slate-500 dark:text-slate-400 font-medium leading-relaxed">
                                            이름 뒤에 <span className="text-indigo-600 dark:text-indigo-400 font-bold">"(A)", "(1)"</span> 처럼 고유한 값을 붙여주시면 안전하게 구분됩니다.
                                        </p>
                                    </div>
                                </div>
                                <div className="flex gap-4 p-5 bg-slate-50 dark:bg-slate-900/40 rounded-3xl border border-slate-100 dark:border-slate-800">
                                    <div className="w-10 h-10 bg-white dark:bg-slate-800 rounded-xl flex items-center justify-center text-emerald-500 shrink-0">
                                        <LayoutGrid className="w-5 h-5" />
                                    </div>
                                    <div className="space-y-1">
                                        <p className="text-xs font-black text-slate-900 dark:text-white uppercase tracking-tight">자동 업데이트 지원</p>
                                        <p className="text-[11px] text-slate-500 dark:text-slate-400 font-medium leading-relaxed">
                                            이미 등록된 성도는 <span className="text-emerald-600 dark:text-emerald-400 font-bold">새 정보로 덮어씌워지며</span>, 소속 조 정보가 즉시 갱신됩니다.
                                        </p>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                )}

                {step === 'preview' && (
                    <div className="space-y-8">
                        <div className="flex items-center justify-between">
                            <div className="space-y-1">
                                <h4 className="text-lg font-black text-slate-900 dark:text-white tracking-tight">분석 결과 미리보기 ({parsedData.length}명)</h4>
                                <p className="text-[10px] text-slate-400 font-bold uppercase tracking-widest">실제 명부 등록 전 내용을 확인하고 즉시 수정하세요.</p>
                            </div>
                            <div className="flex items-center gap-4">
                                <button
                                    onClick={handleAddRow}
                                    className="flex items-center gap-2 px-4 py-2 bg-indigo-50 dark:bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 rounded-xl text-[11px] font-black uppercase tracking-widest hover:bg-indigo-100 transition-all"
                                >
                                    <UserPlus className="w-3.5 h-3.5" />
                                    직접 추가
                                </button>
                                <button onClick={() => setStep('upload')} className="text-xs font-black text-slate-400 uppercase tracking-widest hover:text-slate-600 transition-colors">다시 시작하기</button>
                            </div>
                        </div>

                        {/* Duplication Legend */}
                        <div className="flex flex-wrap gap-4 px-2">
                            <div className="flex items-center gap-2">
                                <div className="w-3 h-3 rounded-full bg-rose-500 shadow-sm" />
                                <span className="text-[10px] font-black text-slate-500 uppercase tracking-tighter">빨간색: 같은 조 중복 (수정 필수)</span>
                            </div>
                            <div className="flex items-center gap-2">
                                <div className="w-3 h-3 rounded-full bg-amber-500 shadow-sm" />
                                <span className="text-[10px] font-black text-slate-500 uppercase tracking-tighter">노란색: 타 조 중복 (연동 필요)</span>
                            </div>
                            <div className="flex items-center gap-2">
                                <div className="w-3 h-3 rounded-full bg-indigo-500 shadow-sm" />
                                <span className="text-[10px] font-black text-slate-500 uppercase tracking-tighter">보라색: DB 이름 중복 (확인 및 이름 수정 필수)</span>
                            </div>
                            <div className="flex items-center gap-2">
                                <div className="w-3 h-3 rounded-full bg-emerald-500 shadow-sm" />
                                <span className="text-[10px] font-black text-slate-500 uppercase tracking-tighter">초록색: 연동 완료 (안전)</span>
                            </div>
                        </div>

                        <div className="bg-slate-50 dark:bg-slate-900/60 rounded-[32px] border border-slate-200 dark:border-slate-800 overflow-hidden">
                            <div className="max-h-[600px] overflow-y-auto">
                                <table className="w-full text-left">
                                    <thead className="sticky top-0 bg-white dark:bg-slate-900 border-b border-slate-200 dark:border-slate-800 z-50">
                                        <tr>
                                            <th className="px-6 py-4 text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest">Name & Family Info</th>
                                            <th className="px-6 py-4 text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest">Role</th>
                                            <th className="px-6 py-4 text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest w-40">Group</th>
                                            <th className="px-6 py-4 text-[10px] font-black text-slate-400 dark:text-slate-500 uppercase tracking-widest w-20 text-center">Action</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-slate-100 dark:divide-slate-800/40">
                                        {parsedData.map((item, idx) => {
                                            const status = getRowConflictStatus(item, idx);
                                            const rowBgColor =
                                                status.type === 'red' ? 'bg-rose-50/50 dark:bg-rose-500/5' :
                                                    status.type === 'yellow' ? 'bg-amber-50/50 dark:bg-amber-500/5' :
                                                        status.type === 'indigo' ? 'bg-indigo-50/50 dark:bg-indigo-500/5' :
                                                            status.type === 'green' ? 'bg-emerald-50/50 dark:bg-emerald-500/5' : '';

                                            const nameTextColor =
                                                status.type === 'red' ? 'text-rose-600 dark:text-rose-400' :
                                                    status.type === 'yellow' ? 'text-amber-600 dark:text-amber-400' :
                                                        status.type === 'indigo' ? 'text-indigo-600 dark:text-indigo-400' :
                                                            status.type === 'green' ? 'text-emerald-600 dark:text-emerald-400' : 'text-slate-900 dark:text-white';

                                            return (
                                                <tr key={idx} className={`hover:bg-white dark:hover:bg-slate-800/40 transition-colors ${rowBgColor}`}>
                                                    <td className="px-6 py-4">
                                                        <div className="flex flex-col gap-2">
                                                            <div className="flex flex-col gap-1">
                                                                <div className="flex items-center gap-2">
                                                                    <input
                                                                        type="text"
                                                                        value={item.full_name}
                                                                        onChange={(e) => handleUpdateRow(idx, { full_name: e.target.value })}
                                                                        className={`bg-transparent border-b border-transparent focus:border-indigo-500 transition-all font-bold focus:outline-none w-full ${nameTextColor}`}
                                                                        placeholder="이름 입력"
                                                                    />
                                                                    <input
                                                                        type="text"
                                                                        value={item.phone || ''}
                                                                        onChange={(e) => handleUpdateRow(idx, { phone: e.target.value })}
                                                                        className="bg-indigo-50/50 dark:bg-indigo-500/5 border border-indigo-100/50 dark:border-indigo-500/20 px-2 py-0.5 rounded text-[10px] font-bold text-indigo-600 dark:text-indigo-400 focus:outline-none focus:border-indigo-500 w-32"
                                                                        placeholder="010-0000-0000"
                                                                    />
                                                                    {status.type !== 'none' && (
                                                                        <span className={`px-1.5 py-0.5 text-[8px] font-black rounded uppercase tracking-tighter shrink-0 ${status.type === 'red' ? 'bg-rose-100 dark:bg-rose-500/20 text-rose-600 dark:text-rose-400' :
                                                                            status.type === 'yellow' ? 'bg-amber-100 dark:bg-amber-500/20 text-amber-600 dark:text-amber-400' :
                                                                                status.type === 'indigo' ? 'bg-indigo-100 dark:bg-indigo-500/20 text-indigo-600 dark:text-indigo-400' :
                                                                                    'bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400'
                                                                            }`}>
                                                                            {status.label}
                                                                        </span>
                                                                    )}
                                                                </div>
                                                                {/* Inter-group Link Actions */}
                                                                {status.type === 'yellow' && !item.batch_link_id && (
                                                                    <div className="mt-1">
                                                                        <button
                                                                            onClick={() => handleLinkSameNames(item.full_name || '')}
                                                                            className="text-[9px] font-black text-indigo-600 dark:text-indigo-400 hover:underline"
                                                                        >
                                                                            [목록 내 모든 {item.full_name}을 동일인으로 연결하기]
                                                                        </button>
                                                                    </div>
                                                                )}
                                                                {status.type === 'green' && (
                                                                    <div className="mt-1">
                                                                        <button
                                                                            onClick={() => handleUnlinkSameNames(item.full_name || '')}
                                                                            className="text-[9px] font-black text-rose-500 hover:underline"
                                                                        >
                                                                            [전체 연결 해제]
                                                                        </button>
                                                                    </div>
                                                                )}
                                                                {/* DB Match UI */}
                                                                {dbMatches[item.full_name || ''] && (
                                                                    <div className="flex flex-wrap gap-1.5 mt-1">
                                                                        {dbMatches[item.full_name || ''].map((match, mIdx) => (
                                                                            <button
                                                                                key={mIdx}
                                                                                onClick={() => {
                                                                                    // Link all instances of this name to this person_id
                                                                                    handleLinkSameNames(match.full_name, match.person_id, match.profile_id);
                                                                                }}
                                                                                className={`flex flex-col text-[9px] px-2 py-1 rounded-lg border transition-all text-left ${item.person_id === match.person_id
                                                                                    ? 'bg-emerald-50 border-emerald-200 text-emerald-700 dark:bg-emerald-500/10 dark:border-emerald-500/30 dark:text-emerald-400'
                                                                                    : 'bg-white border-slate-200 text-slate-500 hover:border-indigo-300 hover:text-indigo-600 dark:bg-slate-800 dark:border-slate-700'
                                                                                    }`}
                                                                            >
                                                                                <div className="flex items-center gap-1 font-black">
                                                                                    {item.person_id === match.person_id && <CheckCircle2 className="w-2.5 h-2.5" />}
                                                                                    {match.department_name} {match.group_name}
                                                                                </div>
                                                                                <div className="opacity-70">{match.phone || '번호없음'}</div>
                                                                            </button>
                                                                        ))}
                                                                        {item.person_id && (
                                                                            <button
                                                                                onClick={() => handleUnlinkSameNames(item.full_name || '')}
                                                                                className="text-[9px] px-2 py-1 rounded-lg border border-slate-200 text-slate-400 hover:text-rose-500 hover:border-rose-200 transition-all font-bold"
                                                                            >
                                                                                일괄 연동 해제
                                                                            </button>
                                                                        )}
                                                                    </div>
                                                                )}
                                                            </div>
                                                            <div className="flex gap-3">
                                                                <div className="flex-1">
                                                                    <p className="text-[8px] font-black text-slate-400 uppercase tracking-widest mb-1 ml-0.5">Spouse</p>
                                                                    <input
                                                                        type="text"
                                                                        value={item.spouse_name || ''}
                                                                        onChange={(e) => handleUpdateRow(idx, { spouse_name: e.target.value })}
                                                                        className="w-full bg-slate-100/50 dark:bg-slate-800/50 border-0 rounded-lg px-2 py-1 text-[11px] font-medium focus:ring-1 focus:ring-indigo-500/30 focus:outline-none"
                                                                        placeholder="배우자 없음"
                                                                    />
                                                                </div>
                                                                <div className="flex-2">
                                                                    <p className="text-[8px] font-black text-slate-400 uppercase tracking-widest mb-1 ml-0.5">Children</p>
                                                                    <input
                                                                        type="text"
                                                                        value={item.children_info || ''}
                                                                        onChange={(e) => handleUpdateRow(idx, { children_info: e.target.value })}
                                                                        className="w-full bg-slate-100/50 dark:bg-slate-800/50 border-0 rounded-lg px-2 py-1 text-[11px] font-medium focus:ring-1 focus:ring-indigo-500/30 focus:outline-none"
                                                                        placeholder="자녀 정보 없음"
                                                                    />
                                                                </div>
                                                            </div>
                                                        </div>
                                                    </td>
                                                    <td className="px-6 py-4 align-top">
                                                        <select
                                                            value={item.role_in_group}
                                                            onChange={(e) => handleUpdateRow(idx, { role_in_group: e.target.value as 'leader' | 'member' })}
                                                            className={`px-2 py-1.5 rounded-lg text-[10px] font-black uppercase tracking-tighter border-0 cursor-pointer focus:ring-1 focus:ring-indigo-500/30 ${item.role_in_group === 'leader'
                                                                ? 'bg-amber-100 text-amber-700 dark:bg-amber-500/20 dark:text-amber-400'
                                                                : 'bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400'}`}
                                                        >
                                                            <option value="member">조원</option>
                                                            <option value="leader">조장</option>
                                                        </select>
                                                    </td>
                                                    <td className="px-6 py-4 align-top">
                                                        <input
                                                            type="text"
                                                            value={item.group_name || ''}
                                                            onChange={(e) => handleUpdateRow(idx, { group_name: e.target.value })}
                                                            className="w-full bg-indigo-50 dark:bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 rounded-lg text-[11px] font-black uppercase tracking-widest border border-indigo-100 dark:border-indigo-500/20 px-3 py-1.5 focus:outline-none focus:ring-1 focus:ring-indigo-500/30"
                                                            placeholder="조 이름 (미정)"
                                                        />
                                                    </td>
                                                    <td className="px-6 py-4 align-top text-center">
                                                        <button
                                                            onClick={() => handleDeleteRow(idx)}
                                                            className="p-2 text-slate-400 hover:text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-500/10 rounded-lg transition-all"
                                                        >
                                                            <Trash2 className="w-4 h-4" />
                                                        </button>
                                                    </td>
                                                </tr>
                                            );
                                        })}
                                    </tbody>
                                </table>
                            </div>
                        </div>

                        <div className="flex flex-col sm:flex-row gap-4 mt-6 pb-6">
                            <button
                                onClick={onClose}
                                className="flex-1 py-4 bg-slate-100 dark:bg-slate-950 text-slate-500 font-black rounded-[28px] hover:bg-slate-200 dark:hover:bg-slate-900 transition-all border border-slate-200 dark:border-slate-800"
                            >
                                취소
                            </button>
                            <button
                                onClick={handleUploadToDB}
                                className="flex-2 py-4 bg-indigo-600 text-white font-black rounded-[28px] hover:bg-indigo-500 transition-all shadow-xl shadow-indigo-600/20 active:scale-95 flex items-center justify-center gap-2"
                            >
                                <CheckCircle2 className="w-5 h-5" />
                                최종 등록 및 저장
                            </button>
                        </div>
                    </div>
                )}

                {step === 'syncing' && (
                    <div className="py-20 flex flex-col items-center justify-center gap-6 text-center">
                        <div className="w-20 h-20 bg-indigo-50 dark:bg-indigo-500/10 rounded-full flex items-center justify-center">
                            <Loader2 className="w-10 h-10 text-indigo-600 dark:text-indigo-500 animate-spin" />
                        </div>
                        <div>
                            <h3 className="text-xl font-black text-slate-900 dark:text-white tracking-tight">명부 동기화 중...</h3>
                            <p className="text-slate-500 text-sm font-bold uppercase tracking-widest mt-1">Populating Member Directory</p>
                        </div>
                    </div>
                )}
            </div>
        </Modal>
    );
}
