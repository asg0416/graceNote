// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function isDevProject() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const enabled = Deno.env.get("DEV_AUTH_OTP_ENABLED") === "true";
  return enabled && (supabaseUrl.includes("eftdf") || supabaseUrl.includes("127.0.0.1"));
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!isDevProject()) {
    return json({ error: "dev 전용 이메일 OTP 기능이 비활성화되어 있습니다." }, 403);
  }

  try {
    const body = await req.json();
    const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body?.password === "string" ? body.password : "";
    const metadata = body?.metadata && typeof body.metadata === "object" ? body.metadata : {};

    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return json({ error: "유효한 이메일이 필요합니다." }, 400);
    }

    if (!password || password.length < 6) {
      return json({ error: "비밀번호는 6자 이상이어야 합니다." }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    );

    const { data, error } = await supabase.auth.admin.generateLink({
      type: "signup",
      email,
      password,
      options: {
        data: metadata,
      },
    });

    if (error) {
      const message = error.message?.includes("already")
        ? "이미 가입된 계정입니다. 로그인 후 진행해 주세요."
        : error.message;
      return json({ error: message || "인증 번호 생성에 실패했습니다." }, 400);
    }

    const emailOtp = data?.properties?.email_otp;
    if (!emailOtp) {
      return json({ error: "개발 인증 번호를 생성하지 못했습니다." }, 500);
    }

    return json({
      success: true,
      email_otp: emailOtp,
      message: "개발 환경용 이메일 인증 번호가 생성되었습니다.",
    });
  } catch (error) {
    return json({ error: error?.message || "Server Error" }, 400);
  }
});
