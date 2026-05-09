import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID");
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL");
const FIREBASE_PRIVATE_KEY = Deno.env.get("FIREBASE_PRIVATE_KEY");

const APP_BASE_URL = "https://grace-note-app-pwa-asg0416.vercel.app";

async function getLeaderProfileIdsByGroups(
  supabase: ReturnType<typeof createClient>,
  groupIds: string[],
): Promise<string[]> {
  if (groupIds.length === 0) return [];

  const { data: phase2Leaders, error: phase2Error } = await supabase
    .from("memberships")
    .select("profile_id")
    .in("group_id", groupIds)
    .eq("role", "leader")
    .eq("status", "active")
    .not("profile_id", "is", null);

  if (!phase2Error && (phase2Leaders || []).length > 0) {
    return [...new Set((phase2Leaders || []).map((leader: any) => leader.profile_id).filter(Boolean))];
  }

  const { data: legacyLeaders } = await supabase
    .from("group_members")
    .select("profile_id")
    .in("group_id", groupIds)
    .eq("role_in_group", "leader")
    .eq("is_active", true);

  return [...new Set((legacyLeaders || []).map((leader: any) => leader.profile_id).filter(Boolean))];
}

async function getActiveProfileIdsByGroups(
  supabase: ReturnType<typeof createClient>,
  groupIds: string[],
): Promise<string[]> {
  if (groupIds.length === 0) return [];

  const { data: phase2Members, error: phase2Error } = await supabase
    .from("memberships")
    .select("profile_id")
    .in("group_id", groupIds)
    .eq("status", "active")
    .not("profile_id", "is", null);

  if (!phase2Error && (phase2Members || []).length > 0) {
    return [...new Set((phase2Members || []).map((member: any) => member.profile_id).filter(Boolean))];
  }

  const { data: legacyMembers } = await supabase
    .from("group_members")
    .select("profile_id")
    .in("group_id", groupIds)
    .eq("is_active", true);

  return [...new Set((legacyMembers || []).map((member: any) => member.profile_id).filter(Boolean))];
}

async function getAccessToken(): Promise<string> {
  const privateKey = FIREBASE_PRIVATE_KEY!.replace(/\\n/g, "\n");
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: FIREBASE_CLIENT_EMAIL,
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };
  const toBase64Url = (data: string) =>
    btoa(data).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const headerB64 = toBase64Url(JSON.stringify(header));
  const claimB64 = toBase64Url(JSON.stringify(claim));
  const unsignedToken = `${headerB64}.${claimB64}`;
  const keyData = privateKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binaryKey = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8", binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"]
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", cryptoKey,
    new TextEncoder().encode(unsignedToken)
  );
  const signatureB64 = toBase64Url(String.fromCharCode(...new Uint8Array(signature)));
  const jwt = `${unsignedToken}.${signatureB64}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tokenData = await tokenRes.json();
  return tokenData.access_token;
}

// Internal function to send push via Google's fcm v1 api
// Data-only message: no "notification" field to prevent browser auto-display (which causes duplicates)
async function sendPush(accessToken: string, token: string, title: string, body: string, payload: any = {}): Promise<{ success: boolean; unregistered?: boolean }> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          data: {
            title,
            body,
            tag: payload.tag || "grace-note-default",
            link: payload.link || "/",
          },
        },
      }),
    }
  );
  const data = await res.json();
  if (!res.ok) {
    const errStr = JSON.stringify(data);
    console.error("[notify-event] Send failed:", errStr);
    const isUnregistered = errStr.includes("UNREGISTERED") || errStr.includes("registration-token-not-registered");
    return { success: false, unregistered: isUnregistered };
  }
  return { success: true };
}

Deno.serve(async (req: Request) => {
  const payload = await req.json();
  const { table, record, old_record, type } = payload;
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  console.log(`[notify-event] Triggered for ${table} on ${type}`);

  if (type !== 'INSERT' && type !== 'UPDATE') return new Response(JSON.stringify({ skipped: true }));

  const accessToken = await getAccessToken();
  let title = "";
  let body = "";
  let link = "/";
  let targetUserIds: string[] = [];
  let preferenceField: string = "";

  if (table === 'prayer_entries') {
    // Only send notifications for published prayers (not drafts)
    if (record.status !== 'published') {
      console.log(`[notify-event] Skipping prayer notification: status is '${record.status}', not 'published'`);
      return new Response(JSON.stringify({ skipped: true, reason: "not_published" }));
    }

    // 1. Atomic dedup: INSERT with UNIQUE constraint (group_id, week_id, event_type).
    // Only the first concurrent request succeeds; others get a conflict error and skip.
    const { data: inserted, error: dedupError } = await supabase
      .from("notification_dedup")
      .insert({
        group_id: record.group_id,
        week_id: record.week_id,
        event_type: type,
      })
      .select("id")
      .single();

    if (dedupError || !inserted) {
      console.log(`[notify-event] Skipping duplicate ${type} notification (dedup conflict)`);
      return new Response(JSON.stringify({ skipped: true, reason: "dedup" }));
    }

    // 2. Data fetching
    const { data: group } = await supabase.from("groups").select("name, church_id, department_id").eq("id", record.group_id).single();
    const { data: member } = await supabase.from("member_directory").select("full_name").eq("id", record.member_id).single();

    // Determine first publish vs re-publish using first_published_at column.
    // - first_published_at is set by DB trigger on first publish (draft→published or direct INSERT with published).
    // - If old_record already had first_published_at set, this is an edit (re-publish), not a first registration.
    // - For INSERT type, it's always a first publish.
    const isTrueUpdate = type === 'UPDATE' && old_record?.first_published_at != null;

    title = isTrueUpdate
      ? `✏️ [${group?.name || '조'}] 기도제목 수정`
      : `🙏 [${group?.name || '조'}] 기도제목 업데이트`;
    body = isTrueUpdate
      ? `${member?.full_name || '성도'}님의 기도제목이 수정되었습니다.`
      : `${member?.full_name || '성도'}님의 기도제목이 등록되었습니다. 함께 기도해주세요!`;
    link = `/attendance/share?groupId=${record.group_id}`;
    preferenceField = "push_prayer_enabled";

    // 2. Target users: department leaders + department admins (excluding author)
    const departmentId = group?.department_id;
    if (!departmentId) {
      console.log("[notify-event] No department_id found for group, skipping");
      return new Response(JSON.stringify({ skipped: true, reason: "no_department" }));
    }

    // Get all groups in the same department
    const { data: deptGroups } = await supabase.from("groups").select("id").eq("department_id", departmentId);
    const deptGroupIds = (deptGroups || []).map(g => g.id);

    // Get leaders from all groups in the department.
    // Phase 2 memberships is the canonical membership read; legacy group_members
    // remains a fallback until write-switch removes legacy dependencies.
    const leaderIds = await getLeaderProfileIdsByGroups(supabase, deptGroupIds);

    // Get department admins
    const { data: admins } = await supabase
      .from("profiles")
      .select("id")
      .eq("department_id", departmentId)
      .in("role", ["admin", "system_admin"]);

    // Exclude the author (prayer_entries uses author_id, not created_by)
    const authorId = record.author_id || record.created_by || record.user_id;
    targetUserIds = [...new Set([
      ...leaderIds,
      ...(admins || []).map(a => a.id).filter(Boolean)
    ])].filter(id => id !== authorId);

  } else if (table === 'notices') {
    title = `\ud83d\udce2 \uc0c8 \uacf5\uc9c0\uc0ac\ud56d: ${record.title}`;
    const plainContent = (record.content || "").replace(/<[^>]*>/g, "").trim();
    body = plainContent.substring(0, 50) + (plainContent.length > 50 ? "..." : "");
    link = "/home/notices";
    preferenceField = "push_notice_enabled";

    // Determine target users based on notice scope
    const tChurchIds: string[] = record.target_church_ids?.length ? record.target_church_ids : [];
    const tDeptIds: string[] = record.target_department_ids?.length ? record.target_department_ids : [];

    if (record.is_global) {
      // Global notice
      if (!record.church_id && tChurchIds.length === 0) {
        // No church specified: master global → ALL users
        const { data: author } = await supabase.from("profiles").select("role, is_master").eq("id", record.created_by).single();
        if (author?.is_master === true || author?.role === 'system_admin') {
          const { data: allUsers } = await supabase.from("profiles").select("id");
          targetUserIds = (allUsers || []).map(u => u.id);
        } else {
          console.log("[notify-event] Global notice without church_id from non-master, skipping");
        }
      } else {
        // Church-scoped global
        const churchId = record.church_id;
        const { data: allUsers } = await supabase.from("profiles").select("id").eq("church_id", churchId);
        targetUserIds = (allUsers || []).map(u => u.id);
      }
    } else if (tDeptIds.length > 0) {
      // Multi-department target (new array column)
      const { data: deptGroups } = await supabase.from("groups").select("id").in("department_id", tDeptIds);
      const groupIds = (deptGroups || []).map(g => g.id);
      if (groupIds.length > 0) {
        targetUserIds = await getActiveProfileIdsByGroups(supabase, groupIds);
      }
    } else if (tChurchIds.length > 0) {
      // Multi-church target (no departments selected → all users in those churches)
      const { data: churchUsers } = await supabase.from("profiles").select("id").in("church_id", tChurchIds);
      targetUserIds = (churchUsers || []).map(u => u.id);
    } else if (record.department_id) {
      // Legacy single department target
      const { data: deptGroups } = await supabase.from("groups").select("id").eq("department_id", record.department_id);
      const groupIds = (deptGroups || []).map(g => g.id);
      targetUserIds = await getActiveProfileIdsByGroups(supabase, groupIds);
    } else if (record.church_id) {
      // Legacy single church target (no department)
      const { data: churchUsers } = await supabase.from("profiles").select("id").eq("church_id", record.church_id);
      targetUserIds = (churchUsers || []).map(u => u.id);
    }
  }

  if (targetUserIds.length === 0) return new Response(JSON.stringify({ skipped: true }));

  // 3. Filter targets by preference (NEW)
  const { data: preferredProfiles } = await supabase
    .from("profiles")
    .select("id")
    .in("id", targetUserIds)
    .eq(preferenceField, true);

  const finalRecipientIds = (preferredProfiles || []).map(p => p.id);
  if (finalRecipientIds.length === 0) return new Response(JSON.stringify({ filtered: true }));

  // 4. Token identification: Send only to the MOST RECENT device for each user
  const { data: tokens } = await supabase
    .from("fcm_tokens")
    .select("token, user_id")
    .in("user_id", finalRecipientIds)
    .order("updated_at", { ascending: false });

  if (!tokens?.length) return new Response(JSON.stringify({ skipped: true }));

  // Token deduplication (One per user)
  const userToToken = new Map();
  tokens.forEach(t => {
    if (!userToToken.has(t.user_id)) {
      userToToken.set(t.user_id, t.token);
    }
  });

  const uniqueTokens = Array.from(userToToken.entries()); // [token, userId] pairs for cleanup
  // Use distinct tags per notification type to prevent overwriting:
  // - prayer: per-group tag so different groups don't overwrite each other
  // - notices: unique per notice id
  const tag = table === 'prayer_entries'
    ? `prayer-${record.group_id}`
    : `notice-${record.id}`;
  const results = await Promise.allSettled(
    uniqueTokens.map(([userId, token]) => sendPush(accessToken, token, title, body, { link, tag }))
  );

  // Cleanup: remove expired/unregistered tokens
  const expiredTokens: string[] = [];
  results.forEach((result, index) => {
    if (result.status === 'fulfilled' && result.value.unregistered) {
      expiredTokens.push(uniqueTokens[index][1]);
    }
  });
  if (expiredTokens.length > 0) {
    await supabase.from("fcm_tokens").delete().in("token", expiredTokens);
    console.log(`[notify-event] Cleaned up ${expiredTokens.length} expired token(s)`);
  }

  // Cleanup: delete dedup records older than 5 minutes (fire and forget)
  supabase.from("notification_dedup")
    .delete()
    .lt("created_at", new Date(Date.now() - 5 * 60 * 1000).toISOString())
    .then(() => console.log("[notify-event] Dedup cleanup done"))
    .catch(() => { });

  const sent = results.filter(r => r.status === 'fulfilled' && r.value.success).length;
  console.log(`[notify-event] Sent: ${sent}/${uniqueTokens.length}, expired cleaned: ${expiredTokens.length}`);
  return new Response(JSON.stringify({
    sent,
    total: uniqueTokens.length,
    cleaned: expiredTokens.length,
  }));
});
