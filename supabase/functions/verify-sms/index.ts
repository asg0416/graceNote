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
        // [ENHANCEMENT] Match by both phone AND name if provided
        let query = supabase
            .from('member_directory')
            .select('id, full_name, church_id, department_id, group_name, role_in_group')
            .eq('phone', cleanPhone);

        if (fullName && fullName.trim().length > 0) {
            query = query.eq('full_name', fullName.trim());
        }

        const { data: memberMatch } = await query.maybeSingle();

        // 4. Return Success + Match Data
        return new Response(
            JSON.stringify({
                success: true,
                matched_member: memberMatch // null if no match found (Newcomer)
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
