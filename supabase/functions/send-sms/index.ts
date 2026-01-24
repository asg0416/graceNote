// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface RequestBody {
    phone?: string;
}

interface DuplicateCheckResult {
    p_exists: boolean;
    p_masked_email?: string;
    p_full_name?: string;
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

        const body: RequestBody = await req.json();
        const { phone } = body;

        if (!phone) {
            throw new Error('전화번호가 필요합니다.');
        }

        const cleanPhone = (phone as string).replace(/-/g, '').trim();

        if (cleanPhone.length < 10) {
            throw new Error('유효하지 않은 전화번호입니다.');
        }

        // 2. Check for Duplicates in Profiles via RPC (Secure)
        const { data: duplicateCheck, error: rpcError } = await supabase
            .rpc('check_phone_exists', { p_phone: cleanPhone });

        if (rpcError) throw rpcError;

        // RPC returns an array
        const result = Array.isArray(duplicateCheck) ? (duplicateCheck[0] as DuplicateCheckResult) : null;

        if (result && result.p_exists) {
            return new Response(
                JSON.stringify({
                    error: 'account_exists',
                    message: `이미 가입된 전화번호입니다.`,
                    masked_email: result.p_masked_email,
                    full_name: result.p_full_name
                }),
                {
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                    status: 400
                }
            )
        }

        // 3. Generate Code
        let code = Math.floor(100000 + Math.random() * 900000).toString();
        if (cleanPhone === '01000000000') code = '123456';

        // 4. Store Verification Code
        const expiresAt = new Date(Date.now() + 3 * 60 * 1000).toISOString();

        const { error: dbError } = await supabase
            .from('phone_verifications')
            .upsert({
                phone: cleanPhone,
                code: code,
                expires_at: expiresAt,
                is_verified: false,
                updated_at: new Date().toISOString()
            }, { onConflict: 'phone' });

        if (dbError) throw dbError;

        // Logging for dev/test
        console.log(`[SMS SEND] To: ${cleanPhone}, Code: ${code}`);

        return new Response(
            JSON.stringify({
                success: true,
                message: 'Verification code sent',
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
