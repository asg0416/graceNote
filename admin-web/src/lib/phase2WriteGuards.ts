/* eslint-disable @typescript-eslint/no-explicit-any */

type Phase2DirectoryRow = {
    id: string;
    full_name: string | null;
    group_name: string | null;
    is_active: boolean | null;
};

type Phase2MemberProfileRow = {
    member_directory_id: string | null;
    person_id: string | null;
};

type Phase2MembershipRow = {
    legacy_member_directory_id: string | null;
};

type SupabaseLike = {
    from: (table: string) => any;
};

const uniqueIds = (ids: string[]) => (
    Array.from(new Set(ids.filter(Boolean)))
);

const formatNames = (rows: Phase2DirectoryRow[], ids: Set<string>) => {
    const names = rows
        .filter((row) => ids.has(row.id))
        .map((row) => row.full_name || row.id);

    if (names.length <= 5) return names.join(', ');
    return `${names.slice(0, 5).join(', ')} 외 ${names.length - 5}명`;
};

export const assertPhase2MemberDirectorySync = async (
    supabase: SupabaseLike,
    memberDirectoryIds: string[],
    contextLabel = '성도 저장'
) => {
    const ids = uniqueIds(memberDirectoryIds);
    if (ids.length === 0) return;

    const { data: directoryRows, error: directoryError } = await supabase
        .from('member_directory')
        .select('id, full_name, group_name, is_active')
        .in('id', ids);

    if (directoryError) throw directoryError;

    const directories = (directoryRows || []) as Phase2DirectoryRow[];
    const existingDirectoryIds = new Set(directories.map((row) => row.id));
    const missingDirectoryIds = ids.filter((id) => !existingDirectoryIds.has(id));

    if (missingDirectoryIds.length > 0) {
        throw new Error(
            `${contextLabel} 후 legacy 명부 row를 다시 확인하지 못했습니다: ${missingDirectoryIds.join(', ')}`
        );
    }

    const { data: profileRows, error: profileError } = await supabase
        .from('member_profiles')
        .select('member_directory_id, person_id')
        .in('member_directory_id', ids);

    if (profileError) throw profileError;

    const profileByDirectoryId = new Map(
        ((profileRows || []) as Phase2MemberProfileRow[])
            .filter((row) => row.member_directory_id && row.person_id)
            .map((row) => [row.member_directory_id as string, row])
    );

    const missingProfileIds = new Set(
        directories
            .filter((row) => !profileByDirectoryId.has(row.id))
            .map((row) => row.id)
    );

    const membershipExpectedIds = directories
        .filter((row) => row.is_active !== false)
        .filter((row) => Boolean(row.group_name?.trim()))
        .map((row) => row.id);

    const { data: membershipRows, error: membershipError } = membershipExpectedIds.length > 0
        ? await supabase
            .from('memberships')
            .select('legacy_member_directory_id')
            .in('legacy_member_directory_id', membershipExpectedIds)
            .in('status', ['active', 'inactive', 'ended'])
        : { data: [], error: null };

    if (membershipError) throw membershipError;

    const membershipDirectoryIds = new Set(
        ((membershipRows || []) as Phase2MembershipRow[])
            .map((row) => row.legacy_member_directory_id)
            .filter(Boolean) as string[]
    );

    const missingMembershipIds = new Set(
        membershipExpectedIds.filter((id) => !membershipDirectoryIds.has(id))
    );

    if (missingProfileIds.size === 0 && missingMembershipIds.size === 0) {
        return;
    }

    const messages = [
        missingProfileIds.size > 0
            ? `member_profiles 누락: ${formatNames(directories, missingProfileIds)}`
            : null,
        missingMembershipIds.size > 0
            ? `memberships 누락: ${formatNames(directories, missingMembershipIds)}`
            : null,
    ].filter(Boolean);

    throw new Error(
        `${contextLabel} 후 Phase 2 person 동기화가 완료되지 않았습니다. ${messages.join(' / ')}`
    );
};
