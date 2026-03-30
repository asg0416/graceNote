import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID");
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL");
const FIREBASE_PRIVATE_KEY = Deno.env.get("FIREBASE_PRIVATE_KEY");

const APP_BASE_URL = "https://grace-note-app-pwa-asg0416.vercel.app";

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
async function sendPush(accessToken: string, token: string, title: string, body: string, payload: any = {}) {
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
  if (!res.ok) console.error("[notify-event] Send failed:", data);
  return res.ok;
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

    // 1. Dedup check: Skip if same group+week+event was notified within last 5 seconds (to prevent concurrent batch upsert spam)
    const DEDUP_WINDOW_SECONDS = 5;
    const { data: recentNotif } = await supabase
      .from("notification_dedup")
      .select("id")
      .eq("group_id", record.group_id)
      .eq("week_id", record.week_id)
      .eq("event_type", type)
      .gte("created_at", new Date(Date.now() - DEDUP_WINDOW_SECONDS * 1000).toISOString())
      .limit(1);

    if (recentNotif && recentNotif.length > 0) {
      console.log(`[notify-event] Skipping duplicate ${type} notification (within ${DEDUP_WINDOW_SECONDS}s window)`);
      return new Response(JSON.stringify({ skipped: true, reason: "dedup" }));
    }

    // Record this notification for dedup
    await supabase.from("notification_dedup").insert({
      group_id: record.group_id,
      week_id: record.week_id,
      event_type: type,
    });

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

    // Get leaders from all groups in the department
    const { data: leaders } = await supabase
      .from("group_members")
      .select("profile_id")
      .in("group_id", deptGroupIds)
      .eq("role_in_group", "leader")
      .eq("is_active", true);

    // Get department admins
    const { data: admins } = await supabase
      .from("profiles")
      .select("id")
      .eq("department_id", departmentId)
      .in("role", ["admin", "system_admin"]);

    // Exclude the author
    const authorId = record.created_by || record.user_id;
    targetUserIds = [...new Set([
      ...(leaders || []).map(l => l.profile_id).filter(Boolean),
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
        const { data: deptMembers } = await supabase.from("group_members").select("profile_id").in("group_id", groupIds).eq("is_active", true);
        targetUserIds = [...new Set((deptMembers || []).map(m => m.profile_id).filter(Boolean))];
      }
    } else if (tChurchIds.length > 0) {
      // Multi-church target (no departments selected → all users in those churches)
      const { data: churchUsers } = await supabase.from("profiles").select("id").in("church_id", tChurchIds);
      targetUserIds = (churchUsers || []).map(u => u.id);
    } else if (record.department_id) {
      // Legacy single department target
      const { data: deptGroups } = await supabase.from("groups").select("id").eq("department_id", record.department_id);
      const groupIds = (deptGroups || []).map(g => g.id);
      const { data: deptMembers } = await supabase.from("group_members").select("profile_id").in("group_id", groupIds).eq("is_active", true);
      targetUserIds = [...new Set((deptMembers || []).map(m => m.profile_id).filter(Boolean))];
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

  const uniqueTokens = Array.from(userToToken.values());
  // Use distinct tags per notification type to prevent overwriting:
  // - prayer: per-group tag so different groups don't overwrite each other
  // - notices: unique per notice id
  const tag = table === 'prayer_entries'
    ? `prayer-${record.group_id}`
    : `notice-${record.id}`;
  const results = await Promise.allSettled(uniqueTokens.map(token => sendPush(accessToken, token, title, body, { link, tag })));

  // Cleanup: delete dedup records older than 5 minutes (fire and forget)
  supabase.from("notification_dedup")
    .delete()
    .lt("created_at", new Date(Date.now() - 5 * 60 * 1000).toISOString())
    .then(() => console.log("[notify-event] Dedup cleanup done"))
    .catch(() => { });

  return new Response(JSON.stringify({
    sent: results.filter(r => r.status === 'fulfilled').length,
    total: uniqueTokens.length
  }));
});
