// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface RequestBody {
    phone: string;
    code: string;
    fullName?: string;
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const supabase = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        const body: RequestBody = await req.json()
        const { phone, code, fullName } = body
        const cleanPhone = phone.replace(/-/g, '').trim()

        // 1. Verify Code
        const { data: verification } = await supabase
            .from('phone_verifications')
            .select('*')
            .eq('phone', cleanPhone)
            .maybeSingle()

        if (!verification) {
            throw new Error('Verification request not found')
        }

        if (verification.code !== code) {
            throw new Error('Invalid verification code')
        }

        if (new Date(verification.expires_at) < new Date()) {
            throw new Error('Verification code expired')
        }

        // 2. Clear verification on success
        await supabase.from('phone_verifications').delete().eq('id', verification.id)

        // 3. Find Match in Member Directory
        // Match by both phone AND name if provided, then project the result
        // through current person memberships so historical legacy rows do not
        // appear in the onboarding confirmation dialog.
        let query = supabase
            .from('member_directory')
            .select(`
                id, 
                person_id,
                full_name, 
                church_id, 
                department_id, 
                group_name, 
                role_in_group,
                family_name,
                spouse_name,
                children_info,
                wedding_anniversary,
                is_active,
                departments:department_id (name)
            `)
            .eq('phone', cleanPhone);

        if (fullName && fullName.trim().length > 0) {
            query = query.eq('full_name', fullName.trim());
        }

        const { data: rawMemberMatches, error: matchError } = await query.limit(50);

        if (matchError) throw matchError;

        const now = new Date();
        const isEffective = (startsAt?: string | null, endsAt?: string | null) => {
            const startsOk = !startsAt || new Date(startsAt) <= now;
            const endsOk = !endsAt || new Date(endsAt) >= now;
            return startsOk && endsOk;
        };

        const rawMatches = rawMemberMatches ?? [];
        const directoryById = new Map(rawMatches.map((row: any) => [row.id, row]));
        const directoryByPerson = new Map<string, any[]>();
        for (const row of rawMatches) {
            if (!row.person_id) continue;
            const rows = directoryByPerson.get(row.person_id) ?? [];
            rows.push(row);
            directoryByPerson.set(row.person_id, rows);
        }

        const personIds = [...new Set(rawMatches.map((row: any) => row.person_id).filter(Boolean))];
        let membershipMatches: any[] = [];

        if (personIds.length > 0) {
            const { data: memberships, error: membershipError } = await supabase
                .from('memberships')
                .select(`
                    id,
                    person_id,
                    role,
                    status,
                    starts_at,
                    ends_at,
                    legacy_member_directory_id,
                    groups:group_id (
                        id,
                        name,
                        church_id,
                        department_id,
                        is_active,
                        active_from,
                        ended_at,
                        departments:department_id (name)
                    )
                `)
                .in('person_id', personIds)
                .eq('status', 'active')
                .not('group_id', 'is', null);

            if (membershipError) throw membershipError;

            membershipMatches = (memberships ?? [])
                .filter((membership: any) => {
                    const group = membership.groups;
                    if (!group || group.is_active === false) return false;
                    return isEffective(membership.starts_at, membership.ends_at) &&
                        isEffective(group.active_from, group.ended_at);
                })
                .map((membership: any) => {
                    const group = membership.groups;
                    const sourceDirectory = directoryById.get(membership.legacy_member_directory_id) ??
                        (directoryByPerson.get(membership.person_id) ?? [])
                            .find((row: any) => row.church_id === group.church_id && row.department_id === group.department_id) ??
                        (directoryByPerson.get(membership.person_id) ?? [])[0];

                    return {
                        id: sourceDirectory?.id ?? membership.legacy_member_directory_id ?? membership.id,
                        person_id: membership.person_id,
                        full_name: sourceDirectory?.full_name ?? fullName,
                        church_id: group.church_id,
                        department_id: group.department_id,
                        group_id: group.id,
                        group_name: group.name,
                        role_in_group: membership.role ?? sourceDirectory?.role_in_group ?? 'member',
                        family_name: sourceDirectory?.family_name,
                        spouse_name: sourceDirectory?.spouse_name,
                        children_info: sourceDirectory?.children_info,
                        wedding_anniversary: sourceDirectory?.wedding_anniversary,
                        departments: group.departments,
                    };
                });
        }

        const fallbackMatches = rawMatches.filter((row: any) => row.is_active === true);
        const sourceMatches = membershipMatches.length > 0 ? membershipMatches : fallbackMatches;
        const hasAssignedGroup = sourceMatches.some((row: any) => !!String(row.group_name ?? '').trim());
        const visibleMatches = hasAssignedGroup
            ? sourceMatches.filter((row: any) => !!String(row.group_name ?? '').trim())
            : sourceMatches;

        const deduped = new Map<string, any>();
        for (const row of visibleMatches) {
            const key = [
                row.person_id ?? '',
                row.church_id ?? '',
                row.department_id ?? '',
                row.group_id ?? '',
                row.group_name ?? '',
                row.role_in_group ?? '',
            ].join('|');
            if (!deduped.has(key)) deduped.set(key, row);
        }

        const memberMatches = [...deduped.values()]
            .sort((a: any, b: any) => {
                if (a.role_in_group === 'leader' && b.role_in_group !== 'leader') return -1;
                if (a.role_in_group !== 'leader' && b.role_in_group === 'leader') return 1;
                return String(a.group_name ?? '').localeCompare(String(b.group_name ?? ''), 'ko');
            })
            .slice(0, 10);

        // 4. Return Success + Match Data
        return new Response(
            JSON.stringify({
                success: true,
                matched_members: memberMatches // Returns array of matches
            }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200
            }
        )

    } catch (error: any) {
        return new Response(
            JSON.stringify({ error: error.message || 'Server Error' }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400
            }
        )
    }
})
