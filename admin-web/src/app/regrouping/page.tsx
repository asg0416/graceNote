'use client';

import { useEffect, useState, useMemo, useRef, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import {
    Users,
    Search,
    Loader2,
    Church,
    ChevronDown,
    Layers,
    Save,
    RotateCcw,
    CheckCircle2,
    AlertCircle,
    Plus,
    UserPlus,
    Download,
    FileDown,
    Image as ImageIcon,
    Settings2
} from 'lucide-react';
import * as XLSX from 'xlsx';
import * as htmlToImage from 'html-to-image';
import { ExportTableView } from '@/components/kanban/ExportTableView';
import { cn } from '@/lib/utils';
import { KanbanBoard } from '@/components/kanban/KanbanBoard';
import { MemberModal } from '@/components/MemberModal';
import { Modal } from '@/components/Modal';
import { Tooltip } from '@/components/Tooltip';

export default function RegroupingPage() {
    return (
        <Suspense fallback={
            <div className="h-96 flex flex-col items-center justify-center gap-4">
                <Loader2 className="w-10 h-10 text-indigo-600 animate-spin" />
                <p className="text-slate-400 font-black text-xs uppercase tracking-widest">데이터 로딩 중...</p>
            </div>
        }>
            <RegroupingPageInner />
        </Suspense>
    );
}

function RegroupingPageInner() {
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [members, setMembers] = useState<any[]>([]);
    const [localMembers, setLocalMembers] = useState<any[]>([]); // Draft state
    const [groups, setGroups] = useState<any[]>([]);
    const [departments, setDepartments] = useState<any[]>([]);
    const [churches, setChurches] = useState<any[]>([]);

    const [currentChurchId, setCurrentChurchId] = useState<string | null>(null);
    const [selectedDeptId, setSelectedDeptId] = useState<string | null>(null);
    const [isMaster, setIsMaster] = useState(false);
    const [searchTerm, setSearchTerm] = useState('');
    const [selectedMemberIds, setSelectedMemberIds] = useState<string[]>([]);

    const [isMemberModalOpen, setIsMemberModalOpen] = useState(false);
    const [memberToEdit, setMemberToEdit] = useState<any>(null);
    const [targetGroupForNewMember, setTargetGroupForNewMember] = useState<{ id: string | null, name: string } | null>(null);
    const [lastAddedGroupId, setLastAddedGroupId] = useState<string | null>(null);
    const [autoMoveCouples, setAutoMoveCouples] = useState(true);
    const [isExporting, setIsExporting] = useState(false);
    const [showExportMenu, setShowExportMenu] = useState(false);

    const [hasChanges, setHasChanges] = useState(false);
    const boardRef = useRef<HTMLDivElement>(null);
    const exportTableRef = useRef<HTMLDivElement>(null);
    const router = useRouter();
    const searchParams = useSearchParams();

    useEffect(() => {
        const init = async () => {
            setLoading(true);
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                router.push('/login');
                return;
            }

            const { data: profile } = await supabase
                .from('profiles')
                .select('church_id, department_id, is_master, role, admin_status')
                .eq('id', session.user.id)
                .single();

            const isAuthorized = profile && (profile.is_master || (profile.role === 'admin' && profile.admin_status === 'approved'));

            if (!isAuthorized) {
                await supabase.auth.signOut();
                router.push('/login?error=unauthorized');
                return;
            }

            if (profile) {
                setIsMaster(profile.is_master);
                const cId = profile.church_id;
                const dId = searchParams.get('deptId') || profile.department_id;

                setCurrentChurchId(cId);
                setSelectedDeptId(dId);

                // Start single unified loading chain
                if (profile.is_master) {
                    await fetchChurches(cId, dId);
                } else if (cId) {
                    await fetchChurchInfo(cId);
                    await fetchDepartments(cId, dId);
                }
            }
            setLoading(false);
        };

        init();
    }, []);

    // Clear lastAddedGroupId when user interacts with other elements
    useEffect(() => {
        const handleMouseDown = () => {
            if (lastAddedGroupId) setLastAddedGroupId(null);
        };
        document.addEventListener('mousedown', handleMouseDown);
        return () => document.removeEventListener('mousedown', handleMouseDown);
    }, [lastAddedGroupId]);

    const fetchChurchInfo = async (churchId: string) => {
        try {
            const { data } = await supabase.from('churches').select('name').eq('id', churchId).single();
            if (data) {
                // We need to make sure the churches list also has this if we use the memo, 
                // or just set a separate state. For consistency with the memo:
                setChurches([{ id: churchId, name: data.name }]);
            }
        } catch (err) {
            console.error(err);
        }
    };

    const fetchChurches = async (targetChurchId?: string | null, targetDeptId?: string | null) => {
        const { data } = await supabase.from('churches').select('id, name').order('name');
        setChurches(data || []);

        const effectiveChurchId = targetChurchId || (data && data.length > 0 ? data[0].id : null);
        if (effectiveChurchId) {
            if (!targetChurchId) setCurrentChurchId(effectiveChurchId);
            await fetchDepartments(effectiveChurchId, targetDeptId);
        }
    };

    const fetchDepartments = async (churchId: string, targetDeptId?: string | null) => {
        const { data } = await supabase
            .from('departments')
            .select('id, name, color_hex, profile_mode')
            .eq('church_id', churchId)
            .order('name');
        setDepartments(data || []);

        if (data && data.length > 0) {
            // Use targetDeptId from argument if available, fallback to state or first dept
            const deptIdToUse = targetDeptId || selectedDeptId || data[0].id;
            const dept = data.find(d => d.id === deptIdToUse) || data[0];

            if (dept) {
                setSelectedDeptId(dept.id);
                setAutoMoveCouples(dept.profile_mode === 'couple');
                // Fetch groups and members in parallel for visual smoothness
                await Promise.all([
                    fetchGroups(dept.id),
                    fetchMembers(churchId, dept.id)
                ]);
            }
        }
    };

    const fetchData = async () => {
        if (currentChurchId && selectedDeptId) {
            await Promise.all([
                fetchGroups(selectedDeptId),
                fetchMembers(currentChurchId, selectedDeptId)
            ]);
        }
    };

    const fetchGroups = async (deptId: string) => {
        const { data } = await supabase
            .from('groups')
            .select('id, name, color_hex, department_id')
            .eq('department_id', deptId)
            .eq('is_active', true)
            .order('name');
        setGroups(data || []);
    };

    const fetchMembers = async (churchId: string, deptId: string) => {
        setLoading(true);
        const { data } = await supabase
            .from('member_directory')
            .select('*')
            .eq('church_id', churchId)
            .eq('department_id', deptId);

        // Match members with their group_id for Kanban
        const { data: groupData } = await supabase
            .from('groups')
            .select('id, name')
            .eq('department_id', deptId);

        const membersWithGroupId = (data || []).map(m => ({
            ...m,
            group_id: groupData?.find(g => g.name === m.group_name)?.id || null
        }));

        const uniqueMembers = Array.from(
            membersWithGroupId.reduce((map: Map<string, any>, item: any) => {
                const key = item.person_id || item.id;
                const existing = map.get(key);
                if (!existing || (!existing.group_id && item.group_id)) {
                    map.set(key, item);
                }
                return map;
            }, new Map()).values()
        );

        setMembers(uniqueMembers);
        setLocalMembers(JSON.parse(JSON.stringify(uniqueMembers)));
        setHasChanges(false);
        setLoading(false);
    };

    const handleReorderMembers = useMemo(() => (ids: string[], targetGroupId: string | null) => {
        setLocalMembers(prev => {
            // Check if anything actually changed to avoid unnecessary re-renders
            let changed = false;
            const next = prev.map(m => {
                if (ids.includes(m.id) && m.group_id !== targetGroupId) {
                    changed = true;
                    return { ...m, group_id: targetGroupId };
                }
                return m;
            });
            return changed ? next : prev;
        });
        setHasChanges(true);
    }, []); // Memoized to prevent frequent recreation

    const handleMoveMembers = (ids: string[], targetGroupId: string | null, isCopy: boolean = false, targetIndex?: number) => {
        let finalIdsToMove = [...ids];

        // Couple-aware logic: if autoMoveCouples is on, find spouses
        if (autoMoveCouples && !isCopy) {
            const spousesToInclude: string[] = [];
            ids.forEach(id => {
                const member = localMembers.find(m => m.id === id);
                if (member?.spouse_name) {
                    const spouse = localMembers.find(m =>
                        m.full_name === member.spouse_name &&
                        m.spouse_name === member.full_name &&
                        m.group_id === member.group_id
                    );
                    if (spouse && !finalIdsToMove.includes(spouse.id)) {
                        spousesToInclude.push(spouse.id);
                    }
                }
            });
            finalIdsToMove = [...finalIdsToMove, ...spousesToInclude];
        }

        if (isCopy) {
            const membersToCopy = localMembers.filter(m => ids.includes(m.id));
            const newCopies = membersToCopy.map(m => ({
                ...m,
                id: `temp-copy-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
                group_id: targetGroupId,
            }));

            // If targetIndex is provided, we insert them at that position in the group
            if (targetIndex !== undefined) {
                setLocalMembers(prev => {
                    const groupMembers = prev.filter(m => m.group_id === targetGroupId);
                    const otherMembers = prev.filter(m => m.group_id !== targetGroupId);

                    const updatedGroupMembers = [...groupMembers];
                    updatedGroupMembers.splice(targetIndex, 0, ...newCopies);

                    return [...otherMembers, ...updatedGroupMembers];
                });
            } else {
                setLocalMembers(prev => [...prev, ...newCopies]);
            }
        } else {
            // MOVE logic
            setLocalMembers(prev => {
                // 1. Separate members to move from others
                const movingMembers = prev.filter(m => finalIdsToMove.includes(m.id))
                    .map(m => ({ ...m, group_id: targetGroupId }));
                const remainingMembers = prev.filter(m => !finalIdsToMove.includes(m.id));

                // 2. If targetIndex is specified, insert them at the position within the target group
                if (targetIndex !== undefined) {
                    const targetGroupMembers = remainingMembers.filter(m => m.group_id === targetGroupId);
                    const otherMembers = remainingMembers.filter(m => m.group_id !== targetGroupId);

                    const updatedTargetGroup = [...targetGroupMembers];
                    updatedTargetGroup.splice(targetIndex, 0, ...movingMembers);

                    return [...otherMembers, ...updatedTargetGroup];
                } else {
                    // Default to end of group
                    return [...remainingMembers, ...movingMembers];
                }
            });
        }
        setSelectedMemberIds([]);
        setHasChanges(true);
    };

    const handleOpenAddMemberModal = (groupInfo?: any) => {
        let target = null;
        if (typeof groupInfo === 'string') {
            // It's an ID
            const found = groups.find(g => g.id === groupInfo);
            if (found) target = found;
        } else if (groupInfo) {
            // It's already an object
            target = groupInfo;
        }

        setTargetGroupForNewMember(target);
        setMemberToEdit(null);
        setIsMemberModalOpen(true);
    };

    const handleMemberClick = (id: string) => {
        const member = localMembers.find(m => m.id === id);
        let idsToToggle = [id];

        if (autoMoveCouples && member?.spouse_name) {
            const spouse = localMembers.find(s =>
                s.full_name === member.spouse_name &&
                s.spouse_name === member.full_name &&
                s.group_id === member.group_id
            );
            if (spouse) {
                idsToToggle.push(spouse.id);
            }
        }

        setSelectedMemberIds(prev => {
            const isRemoving = prev.includes(id);
            if (isRemoving) {
                return prev.filter(mid => !idsToToggle.includes(mid));
            } else {
                // Add all but avoid duplicates
                const next = [...prev];
                idsToToggle.forEach(tid => {
                    if (!next.includes(tid)) next.push(tid);
                });
                return next;
            }
        });
    };

    const handleExportExcel = () => {
        const deptName = departments.find(d => d.id === selectedDeptId)?.name || '조편성';
        const date = new Date().toISOString().split('T')[0];

        // Prepare data in a structured format: Group, Leader(s), Members
        const exportData: any[] = [];
        const currentProfileMode = departments.find(d => d.id === selectedDeptId)?.profile_mode;

        groups.forEach(group => {
            const members = localMembers.filter(m => m.group_id === group.id);

            // Unified Leader logic for Excel
            const currentLeaders = members.filter(m => m.role_in_group === 'leader');
            let leadersText = '';

            if (currentProfileMode === 'couple') {
                const seenL = new Set<string>();
                const leaderFamilies: string[] = [];
                currentLeaders.forEach(l => {
                    if (seenL.has(l.id)) return;
                    const spouse = currentLeaders.find(s =>
                        !seenL.has(s.id) &&
                        s.full_name === l.spouse_name &&
                        s.spouse_name === l.full_name
                    );

                    if (spouse) {
                        let text = `${l.full_name}, ${spouse.full_name} (부부)`;
                        if (l.children_info || spouse.children_info) {
                            text += ` [자녀: ${l.children_info || spouse.children_info}]`;
                        }
                        leaderFamilies.push(text);
                        seenL.add(l.id);
                        seenL.add(spouse.id);
                    } else {
                        let text = l.full_name;
                        if (l.children_info) text += ` [자녀: ${l.children_info}]`;
                        leaderFamilies.push(text);
                        seenL.add(l.id);
                    }
                });
                leadersText = leaderFamilies.join('\n');
            } else {
                leadersText = currentLeaders.map(l => l.full_name).join(', ');
            }

            let regularMembersText = '';
            const commonMembers = members.filter(m => m.role_in_group !== 'leader');

            if (currentProfileMode === 'couple') {
                const seen = new Set<string>();
                const families: string[] = [];
                commonMembers.forEach(m => {
                    if (seen.has(m.id)) return;
                    const spouse = commonMembers.find(s =>
                        !seen.has(s.id) &&
                        s.full_name === m.spouse_name &&
                        s.spouse_name === m.full_name
                    );

                    if (spouse) {
                        let famText = `${m.full_name}, ${spouse.full_name} (부부)`;
                        if (m.children_info || spouse.children_info) {
                            famText += ` [자녀: ${m.children_info || spouse.children_info}]`;
                        }
                        families.push(famText);
                        seen.add(m.id);
                        seen.add(spouse.id);
                    } else {
                        let famText = m.full_name;
                        if (m.children_info) famText += ` [자녀: ${m.children_info}]`;
                        families.push(famText);
                        seen.add(m.id);
                    }
                });
                regularMembersText = families.join('\n');
            } else {
                regularMembersText = commonMembers.map(m => m.full_name).join(', ');
            }

            exportData.push({
                '조': group.name,
                '조장': leadersText || '-',
                '조원': regularMembersText || '-'
            });
        });

        // Add unassigned
        const unassigned = localMembers.filter(m => !m.group_id);
        if (unassigned.length > 0) {
            exportData.push({
                '조': '미편성',
                '조장': '-',
                '조원': unassigned.map(m => m.full_name).join(', ')
            });
        }

        const ws = XLSX.utils.json_to_sheet(exportData);

        // Adjust column widths
        ws['!cols'] = [
            { wch: 15 }, // 조
            { wch: 25 }, // 조장
            { wch: 60 }, // 조원
        ];

        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, "조편성결과");
        XLSX.writeFile(wb, `${deptName}_조편성_${date}.xlsx`);
    };

    const handleExportImage = async () => {
        if (!boardRef.current) return;

        setIsExporting(true);
        try {
            const deptName = departments.find(d => d.id === selectedDeptId)?.name || '조편성';
            const date = new Date().toISOString().split('T')[0];

            // Allow some time for UI to settle if needed
            const dataUrl = await htmlToImage.toPng(exportTableRef.current!, {
                backgroundColor: '#ffffff',
                quality: 1.0,
                pixelRatio: 2 // High quality
            });

            const link = document.createElement('a');
            link.download = `${deptName}_조편성_${date}.png`;
            link.href = dataUrl;
            link.click();
        } catch (error) {
            console.error('Image export failed:', error);
            alert('이미지 추출 중 오류가 발생했습니다.');
        } finally {
            setIsExporting(false);
        }
    };

    const handleMemberEdit = (id: string) => {
        const member = localMembers.find(m => m.id === id);
        if (member) {
            setMemberToEdit(member);
            setIsMemberModalOpen(true);
        }
    };

    const handleMemberModalSuccess = (memberData: any) => {
        if (memberToEdit) {
            // Edit existing
            setLocalMembers(prev => prev.map(m => m.id === memberData.id ? { ...m, ...memberData } : m));
        } else {
            // Add new
            const newMember = {
                ...memberData,
                group_id: targetGroupForNewMember?.id || null,
                is_new: true
            };
            setLocalMembers(prev => [...prev, newMember]);
        }
        setHasChanges(true);
    };

    const handleAddGroup = async (name: string = '새로운 조', color?: string) => {
        if (!selectedDeptId || !currentChurchId) return;

        const newGroup = {
            id: `temp-${Date.now()}`,
            name: name,
            color_hex: color || '#4f46e5',
            department_id: selectedDeptId,
            church_id: currentChurchId
        };

        setLastAddedGroupId(newGroup.id);
        setGroups(prev => [...prev, newGroup]);
        setHasChanges(true);
    };

    const handleUpdateGroup = (id: string, updates: { name?: string, color_hex?: string }) => {
        setGroups(prev => prev.map(g => g.id === id ? { ...g, ...updates } : g));
        setHasChanges(true);
    };

    const handleDeleteGroup = (id: string) => {
        // Find members in this group and move to unassigned
        setLocalMembers(prev => prev.map(m => m.group_id === id ? { ...m, group_id: null } : m));
        setGroups(prev => prev.filter(g => g.id !== id));
        setHasChanges(true);
    };

    const handleSave = async () => {
        if (!selectedDeptId || !currentChurchId) return;
        setSaving(true);

        try {
            // 1. Sync Groups (Add / Rename / Delete)
            // For simplicity, we'll fetch existing groups and compare
            const { data: remoteGroups, error: groupsError } = await supabase
                .from('groups')
                .select('*')
                .eq('department_id', selectedDeptId);

            if (groupsError) throw groupsError;

            // Delete groups that are not in local state
            const groupsToDelete = remoteGroups.filter(rg => !groups.find(lg => lg.id === rg.id));
            if (groupsToDelete.length > 0) {
                const { error: delError } = await supabase
                    .from('groups')
                    .delete()
                    .in('id', groupsToDelete.map(g => g.id));
                if (delError) throw delError;
            }

            // Upsert remaining groups (Add new / Rename existing)
            const groupsToUpsert = groups.map(g => ({
                ...(g.id.startsWith('temp-') ? {} : { id: g.id }),
                name: g.name,
                color_hex: g.color_hex,
                department_id: selectedDeptId,
                church_id: currentChurchId,
                is_active: true
            }));

            const { data: upsertedGroups, error: upsertError } = await supabase
                .from('groups')
                .upsert(groupsToUpsert, { onConflict: 'church_id,department_id,name' })
                .select();

            if (upsertError) throw upsertError;

            // Map temp group IDs to real ones for member updates
            const groupIdMap: Record<string, string> = {};
            groups.forEach((lg, idx) => {
                if (lg.id.startsWith('temp-')) {
                    // Try to match by name or order if necessary, but upsert should return in same order or we can match
                    const matched = upsertedGroups.find(ug => ug.name === lg.name);
                    if (matched) groupIdMap[lg.id] = matched.id;
                } else {
                    groupIdMap[lg.id] = lg.id;
                }
            });

            // 2. Process Member Changes
            // Identify new members, moved members, and renamed groups
            const existingMemberUpdates = localMembers.filter(m => !m.id.startsWith('temp-'));
            const groupedChanges = existingMemberUpdates.reduce((acc, m) => {
                const original = members.find(orig => orig.id === m.id);
                const mappedGroupId = m.group_id ? (groupIdMap[m.group_id] || m.group_id) : null;

                const originalGroup = remoteGroups.find(rg => rg.id === original?.group_id);
                const currentGroup = groups.find(lg => lg.id === m.group_id);

                // Trigger update if:
                // 1. Group assignment changed (moved)
                // 2. Current group was renamed (group_name in member_directory needs update)
                const isMoved = original?.group_id !== mappedGroupId;
                const isGroupRenamed = currentGroup && originalGroup && currentGroup.name !== originalGroup.name;

                if (isMoved || isGroupRenamed) {
                    const key = mappedGroupId || 'unassigned';
                    if (!acc[key]) acc[key] = [];
                    acc[key].push(m.id);
                }
                return acc;
            }, {} as Record<string, string[]>);

            for (const [groupId, memberIds] of Object.entries(groupedChanges)) {
                const targetId = groupId === 'unassigned' ? null : groupId;
                const { error } = await supabase.rpc('regroup_members', {
                    p_member_ids: memberIds,
                    p_target_group_id: targetId
                });
                if (error) throw error;
            }

            // For new/copied members (temp IDs)
            const tempMembers = localMembers.filter(m => m.id.startsWith('temp-'));
            for (const m of tempMembers) {
                const mappedGroupId = m.group_id ? (groupIdMap[m.group_id] || m.group_id) : null;
                const targetGroup = upsertedGroups.find(ug => ug.id === mappedGroupId);

                const { error: insError } = await supabase.from('member_directory').insert({
                    church_id: currentChurchId!,
                    department_id: selectedDeptId,
                    group_name: targetGroup?.name || null,
                    full_name: m.full_name,
                    phone: m.phone || '',
                    spouse_name: m.spouse_name,
                    children_info: m.children_info,
                    role_in_group: m.role_in_group || 'member',
                    birth_date: m.birth_date,
                    wedding_anniversary: m.wedding_anniversary,
                    notes: m.notes,
                    person_id: m.person_id || null
                });
                if (insError) throw insError;
            }

            // 3. Refresh State
            await fetchData();
            setHasChanges(false);
            alert('변경 사항이 성공적으로 저장되었습니다.');
        } catch (err: any) {
            console.error('Save failed:', err);
            alert(`저장 중 오류가 발생했습니다: ${err.message || '알 수 없는 오류'}`);
        } finally {
            setSaving(false);
        }
    };

    const handleReset = () => {
        if (confirm('모든 변경 사항을 취소하고 초기화하시겠습니까?')) {
            setLocalMembers(JSON.parse(JSON.stringify(members)));
            setHasChanges(false);
        }
    };

    const filteredLocalMembers = useMemo(() => {
        if (!searchTerm) return localMembers;
        return localMembers.filter(m =>
            m.full_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
            m.phone?.includes(searchTerm)
        );
    }, [localMembers, searchTerm]);

    const sortedMembers = useMemo(() => {
        const dept = departments.find(d => d.id === selectedDeptId);
        if (dept?.profile_mode !== 'couple') return filteredLocalMembers;

        // Group couples together
        const seen = new Set<string>();
        const result: any[] = [];

        filteredLocalMembers.forEach(m => {
            if (seen.has(m.id)) return;

            result.push(m);
            seen.add(m.id);

            if (m.spouse_name) {
                const spouse = filteredLocalMembers.find(s =>
                    !seen.has(s.id) &&
                    s.full_name === m.spouse_name &&
                    s.spouse_name === m.full_name &&
                    s.group_id === m.group_id
                );
                if (spouse) {
                    result.push(spouse);
                    seen.add(spouse.id);
                }
            }
        });

        return result;
    }, [filteredLocalMembers, departments, selectedDeptId]);

    const currentChurchName = useMemo(() => {
        if (!currentChurchId) return null;
        return churches.find(c => c.id === currentChurchId)?.name || null;
    }, [currentChurchId, churches]);

    const stats = useMemo(() => {
        const total = localMembers.length;
        const assigned = localMembers.filter(m => m.group_id).length;
        const unassigned = total - assigned;
        return { total, assigned, unassigned };
    }, [localMembers]);

    if (loading) {
        return (
            <div className="h-96 flex flex-col items-center justify-center gap-4">
                <Loader2 className="w-10 h-10 text-indigo-600 animate-spin" />
                <p className="text-slate-400 font-black text-xs uppercase tracking-widest">데이터 로딩 중...</p>
            </div>
        );
    }

    return (
        <div className="space-y-8 sm:space-y-10 max-w-7xl mx-auto">
            {/* Page Header */}
            <header className="space-y-8 px-2">
                <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
                    <div className="space-y-1.5">
                        <h1 className="text-3xl sm:text-4xl font-black text-slate-900 dark:text-white tracking-tighter">조편성 대시보드</h1>
                        <p className="text-slate-500 dark:text-slate-500 font-bold text-xs sm:text-sm tracking-tight">
                            {isMaster
                                ? <><span className="text-indigo-600 dark:text-indigo-400 font-extrabold underline decoration-indigo-200/50 dark:decoration-indigo-500/30 underline-offset-4">{currentChurchName || '교회 선택'}</span> · 시각적인 드래그 앤 드롭 방식으로 성도들의 소속 조를 관리합니다.</>
                                : <><span className="text-indigo-600 dark:text-indigo-400 font-extrabold underline decoration-indigo-200/50 dark:decoration-indigo-500/30 underline-offset-4">{currentChurchName} · {departments.find(d => d.id === selectedDeptId)?.name || '부서'}</span> 조편성 대시보드입니다. 성도들의 조 분배를 관리합니다.</>
                            }
                        </p>
                    </div>

                    {/* Stats Summary Integrated into Header */}
                    <div className="flex items-center gap-4 sm:gap-6 px-5 h-[44px] bg-white dark:bg-slate-900/60 backdrop-blur-md border border-slate-200 dark:border-slate-800 rounded-xl shadow-sm">
                        <div className="flex items-center gap-2">
                            <span className="text-[9px] sm:text-[10px] font-black text-slate-400 uppercase tracking-widest">전체 성도</span>
                            <span className="text-xs sm:text-sm font-black text-slate-900 dark:text-white leading-none">{stats.total}</span>
                        </div>
                        <div className="w-[1px] h-3 bg-slate-200 dark:bg-slate-800" />
                        <div className="flex items-center gap-2">
                            <span className="text-[9px] sm:text-[10px] font-black text-indigo-500 uppercase tracking-widest leading-none">편성 완료</span>
                            <span className="text-xs sm:text-sm font-black text-indigo-600 dark:text-indigo-400 leading-none">{stats.assigned}</span>
                        </div>
                        <div className="w-[1px] h-3 bg-slate-200 dark:bg-slate-800" />
                        <div className="flex items-center gap-2">
                            <span className="text-[9px] sm:text-[10px] font-black text-rose-500 uppercase tracking-widest leading-none">미편성</span>
                            <span className="text-xs sm:text-sm font-black text-rose-600 dark:text-rose-400 leading-none">{stats.unassigned}</span>
                        </div>
                    </div>
                </div>
            </header>

            {isMaster && (
                <div className="flex items-center gap-3 px-2">
                    <div className="relative group">
                        <div className="absolute left-4 top-1/2 -translate-y-1/2">
                            <Church className="w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                        </div>
                        <select
                            value={currentChurchId || ''}
                            onChange={async (e) => {
                                const newChurchId = e.target.value;
                                setCurrentChurchId(newChurchId);
                                setSelectedDeptId(null);
                                await fetchDepartments(newChurchId);
                            }}
                            className="appearance-none h-11 pl-10 pr-10 bg-white dark:bg-slate-900 border border-slate-200/60 dark:border-slate-800/60 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 cursor-pointer focus:outline-none focus:ring-4 focus:ring-indigo-500/5 transition-all shadow-sm"
                        >
                            <option value="" disabled>교회 선택</option>
                            {churches.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                        </select>
                        <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-400 pointer-events-none" />
                    </div>

                    <div className="relative group">
                        <select
                            value={selectedDeptId || ''}
                            onChange={(e) => {
                                const newDeptId = e.target.value;
                                setSelectedDeptId(newDeptId);
                                if (currentChurchId) {
                                    fetchGroups(newDeptId);
                                    fetchMembers(currentChurchId, newDeptId);
                                }
                            }}
                            className="appearance-none h-11 pl-5 pr-10 bg-white dark:bg-slate-900 border border-slate-200/60 dark:border-slate-800/60 rounded-2xl font-bold text-xs text-slate-700 dark:text-slate-200 cursor-pointer focus:outline-none focus:ring-4 focus:ring-indigo-500/5 transition-all shadow-sm"
                        >
                            <option value="" disabled>부서 선택</option>
                            {departments.map(d => <option key={d.id} value={d.id}>{d.name}</option>)}
                        </select>
                        <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-400 pointer-events-none" />
                    </div>
                </div>
            )}

            {/* Sticky Interaction Toolbar */}
            <div className="sticky top-16 sm:top-20 z-30 bg-white/80 dark:bg-slate-950/80 backdrop-blur-xl border border-slate-200 dark:border-slate-800 rounded-[32px] px-6 py-4 mb-12 shadow-sm transition-all">
                <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                    <div className="flex-1 max-w-md relative group">
                        <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                        <input
                            type="text"
                            placeholder="성도 이름으로 검색..."
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                            className="w-full pl-11 pr-4 h-11 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl text-sm font-bold focus:ring-4 focus:ring-indigo-500/10 outline-none transition-all shadow-sm"
                        />
                    </div>

                    <div className="flex items-center gap-3">
                        {departments.find(d => d.id === selectedDeptId)?.profile_mode === 'couple' && (
                            <div className="flex items-center gap-2 h-11 px-4 bg-slate-50 dark:bg-slate-900 rounded-2xl border border-slate-200/60 dark:border-slate-800/60 mr-2">
                                <label className="flex items-center gap-2 cursor-pointer group">
                                    <div className="relative">
                                        <input
                                            type="checkbox"
                                            className="sr-only"
                                            checked={autoMoveCouples}
                                            onChange={(e) => setAutoMoveCouples(e.target.checked)}
                                        />
                                        <div className={cn(
                                            "w-9 h-5 rounded-full transition-colors",
                                            autoMoveCouples ? "bg-indigo-600" : "bg-slate-300 dark:bg-slate-700"
                                        )} />
                                        <div className={cn(
                                            "absolute left-1 top-1 w-3 h-3 bg-white rounded-full transition-transform",
                                            autoMoveCouples && "translate-x-4"
                                        )} />
                                    </div>
                                    <span className="text-[10px] font-black text-slate-500 uppercase tracking-widest group-hover:text-slate-900 dark:group-hover:text-slate-200 transition-colors">부부 동시 이동</span>
                                </label>
                            </div>
                        )}

                        <div className="relative group/export">
                            <Tooltip content="현재 조편성 화면을 이미지(.png)나 엑셀(.xlsx) 파일로 저장합니다.">
                                <button
                                    onClick={() => setShowExportMenu(!showExportMenu)}
                                    className="flex items-center gap-2 px-5 h-11 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 text-slate-700 dark:text-slate-300 rounded-2xl font-black text-xs uppercase tracking-widest hover:border-indigo-500/30 transition-all shadow-sm"
                                >
                                    <Download className="w-4 h-4 text-slate-500" />
                                    내보내기
                                </button>
                            </Tooltip>

                            {showExportMenu && (
                                <div className="absolute top-full right-0 mt-2 w-48 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl shadow-xl z-50 overflow-hidden animate-in fade-in slide-in-from-top-2">
                                    <button
                                        onClick={() => {
                                            handleExportExcel();
                                            setShowExportMenu(false);
                                        }}
                                        className="w-full flex items-center gap-3 px-5 py-3 text-xs font-bold text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors border-b border-slate-100 dark:border-slate-800 text-left"
                                    >
                                        <FileDown className="w-4 h-4 text-green-500" />
                                        엑셀 파일로 저장 (.xlsx)
                                    </button>
                                    <button
                                        onClick={() => {
                                            handleExportImage();
                                            setShowExportMenu(false);
                                        }}
                                        disabled={isExporting}
                                        className="w-full flex items-center gap-3 px-5 py-3 text-xs font-bold text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors disabled:opacity-50 text-left"
                                    >
                                        <ImageIcon className="w-4 h-4 text-indigo-500" />
                                        {isExporting ? '추출 중...' : '이미지 파일로 저장 (.png)'}
                                    </button>
                                </div>
                            )}
                        </div>

                        <button
                            onClick={handleReset}
                            className="flex items-center gap-2 px-5 h-11 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 text-slate-700 dark:text-slate-300 rounded-2xl font-black text-xs uppercase tracking-widest hover:border-rose-500/30 transition-all shadow-sm"
                        >
                            <RotateCcw className="w-4 h-4 text-slate-500" />
                            초기화
                        </button>

                        <button
                            onClick={handleSave}
                            disabled={saving || !hasChanges}
                            className={cn(
                                "flex items-center gap-2 px-6 h-11 rounded-2xl font-black text-xs uppercase tracking-widest transition-all shadow-lg active:scale-95 disabled:opacity-50 disabled:scale-100 border",
                                hasChanges
                                    ? "bg-indigo-600 text-white border-indigo-600 shadow-indigo-600/20 hover:bg-indigo-500"
                                    : "bg-white dark:bg-slate-900 text-slate-600 dark:text-slate-400 border-slate-200 dark:border-slate-800 shadow-none"
                            )}
                        >
                            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
                            {saving ? '저장 중...' : '변경사항 확정'}
                        </button>
                    </div>
                </div>
            </div>

            {/* Kanban Board Container - Brightened background for a premium white theme (Photo ref) */}
            <div className="bg-white/50 dark:bg-slate-900/10 rounded-[40px] border border-slate-200/50 dark:border-slate-800/50 p-1 sm:p-2 shadow-inner overflow-hidden">
                <div ref={boardRef} className="relative w-full overflow-x-auto custom-scrollbar p-5 sm:p-8 bg-white/30">
                    <KanbanBoard
                        groups={groups}
                        members={sortedMembers}
                        onMoveMembers={handleMoveMembers}
                        onReorderMembers={handleReorderMembers}
                        selectedMemberIds={selectedMemberIds}
                        onMemberClick={handleMemberClick}
                        onMemberDoubleClick={handleMemberEdit}
                        onAddGroup={handleAddGroup}
                        onDeleteGroup={handleDeleteGroup}
                        onUpdateGroup={handleUpdateGroup}
                        onQuickAddMember={handleOpenAddMemberModal}
                        onAddMembers={handleOpenAddMemberModal}
                        profileMode={departments.find(d => d.id === selectedDeptId)?.profile_mode}
                    />
                </div>

                {/* Keyboard Shortcuts Legend */}
                <div className="px-8 py-4 bg-slate-50/50 dark:bg-slate-900/40 border-t border-slate-200/50 dark:border-slate-800/50 flex items-center gap-8">
                    <div className="flex items-center gap-3">
                        <div className="flex items-center gap-2">
                            <kbd className="min-w-[40px] h-7 px-2 flex items-center justify-center bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-sm text-[10px] font-black text-slate-700 dark:text-slate-300">Drag</kbd>
                            <span className="text-[10px] font-black text-slate-400 uppercase tracking-widest">이동</span>
                        </div>
                    </div>
                    <div className="w-[1px] h-3 bg-slate-200 dark:bg-slate-800" />
                    <div className="flex items-center gap-3">
                        <div className="flex items-center gap-2.5">
                            <div className="flex items-center gap-1.5">
                                <kbd className="min-w-[40px] h-7 px-2 flex items-center justify-center bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-sm text-[10px] font-black text-slate-700 dark:text-slate-300 uppercase tracking-tighter">Shift</kbd>
                                <span className="text-slate-300 font-bold">+</span>
                                <kbd className="min-w-[40px] h-7 px-2 flex items-center justify-center bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-sm text-[10px] font-black text-slate-700 dark:text-slate-300">Drag</kbd>
                            </div>
                            <div className="flex flex-col">
                                <span className="text-[10px] font-black text-indigo-500 uppercase tracking-widest">다른 조로 복사</span>
                                <span className="text-[9px] font-bold text-slate-400 bg-indigo-50 dark:bg-indigo-500/5 px-1.5 py-0.5 rounded-md mt-0.5">* Shift를 먼저 누른 채 드래그하세요</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            {isMemberModalOpen && currentChurchId && (
                <MemberModal
                    isOpen={isMemberModalOpen}
                    onClose={() => setIsMemberModalOpen(false)}
                    onSuccess={handleMemberModalSuccess}
                    member={memberToEdit}
                    churchId={currentChurchId}
                    departmentId={selectedDeptId || undefined}
                    groupId={targetGroupForNewMember?.id || undefined}
                    groupName={targetGroupForNewMember?.name || undefined}
                    departments={departments}
                    groups={groups}
                />
            )}

            {hasChanges && (
                <div className="fixed bottom-6 right-6 flex items-center gap-2 px-4 py-3 bg-amber-50 dark:bg-amber-500/10 border border-amber-200 dark:border-amber-500/30 rounded-2xl shadow-xl z-50 animate-in fade-in slide-in-from-bottom-4">
                    <AlertCircle className="w-5 h-5 text-amber-500" />
                    <div>
                        <p className="text-[10px] font-black text-amber-600 dark:text-amber-500 uppercase tracking-widest leading-tight">알림</p>
                        <p className="text-xs font-bold text-amber-700 dark:text-amber-400">저장되지 않은 변경 사항이 있습니다</p>
                    </div>
                </div>
            )}

            {/* Hidden export template */}
            <div className="fixed -left-[10000px] top-0 pointer-events-none overflow-hidden">
                <ExportTableView
                    tableRef={exportTableRef}
                    deptName={departments.find(d => d.id === selectedDeptId)?.name || '조편성'}
                    groups={groups}
                    localMembers={localMembers}
                    profileMode={departments.find(d => d.id === selectedDeptId)?.profile_mode}
                />
            </div>
        </div>
    );
}
