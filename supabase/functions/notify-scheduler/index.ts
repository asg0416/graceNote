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

async function sendPush(accessToken: string, token: string, title: string, body: string) {
  const iconUrl = `${APP_BASE_URL}/icons/Icon-192.png`;
  const badgeUrl = `${APP_BASE_URL}/icons/Icon-192.png`;

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
          notification: { title, body },
          webpush: {
            notification: { 
              title, 
              body, 
              icon: iconUrl,
              badge: badgeUrl,
              tag: "grace-note-scheduler",
              renotify: true
            },
            fcm_options: { link: "/" }
          },
        },
      }),
    }
  );
  return res.ok;
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const task = url.searchParams.get("task");
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const accessToken = await getAccessToken();

  // Get current KST info
  const nowKST = new Date(new Date().getTime() + (9 * 60 * 60 * 1000));
  const dayOfWeek = nowKST.getDay(); // 0:Sun, 1:Mon, ...
  const hourKST = nowKST.getHours();
  
  console.log(`[scheduler] Task: ${task}, Day: ${dayOfWeek}, Hour(KST): ${hourKST}`);

  // Fetch all departments with their settings directly
  const { data: activeDepts } = await supabase.from("departments").select("id, church_id, leader_reminder_enabled, leader_reminder_days, leader_reminder_time, climbing_alert_enabled, climbing_alert_day, climbing_alert_time");
  if (!activeDepts?.length) return new Response("No departments found");

  if (task === "all_tasks" || task === "leader_reminder") {
    // 1. Leader Reminder
    const reminderDepts = activeDepts.filter(c => 
      c.leader_reminder_enabled && 
      c.leader_reminder_days.includes(dayOfWeek) &&
      parseInt(c.leader_reminder_time.split(':')[0]) === hourKST
    );
    
    if (reminderDepts.length > 0) {
      console.log(`[scheduler] Leader reminder active for ${reminderDepts.length} departments`);
      const lastSunday = new Date(nowKST);
      lastSunday.setDate(nowKST.getDate() - dayOfWeek);
      const dateStr = lastSunday.toISOString().split('T')[0];

      const reminderDeptIds = reminderDepts.map(c => c.id);
      const reminderChurchIds = [...new Set(reminderDepts.map(c => c.church_id))];

      const { data: weeks } = await supabase.from("weeks").select("id, church_id").in("church_id", reminderChurchIds).eq("week_date", dateStr);
      if (weeks?.length) {
        const { data: allGroups } = await supabase.from("groups").select("id, name, department_id, church_id").in("department_id", reminderDeptIds);
        const { data: attendedGroups } = await supabase.from("attendance_records").select("group_id, week_id").in("week_id", weeks.map(w => w.id));
        const { data: prayedGroups } = await supabase.from("prayer_entries").select("group_id, week_id").in("week_id", weeks.map(w => w.id));

        const completedKeys = new Set([
          ...(attendedGroups || []).map(g => `${g.group_id}:${g.week_id}`),
          ...(prayedGroups || []).map(g => `${g.group_id}:${g.week_id}`)
        ]);

        const incompleteGroups = (allGroups || []).filter(g => {
            const weekId = weeks.find(w => w.church_id === g.church_id)?.id;
            return weekId && !completedKeys.has(`${g.id}:${weekId}`);
        });

        if (incompleteGroups.length > 0) {
          const { data: leaders } = await supabase
            .from("group_members")
            .select("profile_id, groups(name, department_id), profiles(push_reminder_enabled)")
            .in("group_id", incompleteGroups.map(g => g.id))
            .eq("role_in_group", "leader")
            .eq("is_active", true);

          const targetLeaderIds = (leaders || [])
              .filter(l => (l.profiles as any).push_reminder_enabled === true)
              .map(l => l.profile_id);

          if (targetLeaderIds.length > 0) {
            const { data: tokens } = await supabase.from("fcm_tokens").select("token, user_id, device_info").in("user_id", targetLeaderIds);
            const seen = new Set();
            const uniqueTokens = (tokens || []).filter(t => {
                const key = `${t.user_id}:${t.device_info}`;
                if (seen.has(key)) return false;
                seen.add(key);
                return true;
            });
            const title = "\u23F0 미완료 리마인더";
            const body = "아직 이번 주 출석체크 및 기도제목이 등록되지 않았습니다. 은혜를 나누어주세요! 🙏";
            await Promise.allSettled(uniqueTokens.map(t => sendPush(accessToken, t.token, title, body)));
          }
        }
      }
    }
  }

  if (task === "all_tasks" || task === "climbing_reminder") {
    // 2. Climbing Alert
    const climbingDepts = activeDepts.filter(c => 
      c.climbing_alert_enabled && 
      c.climbing_alert_day === dayOfWeek &&
      parseInt(c.climbing_alert_time.split(':')[0]) === hourKST
    );
    
    if (climbingDepts.length > 0) {
      console.log(`[scheduler] Climbing alert active for ${climbingDepts.length} departments`);
      const climbingDeptIds = climbingDepts.map(c => c.id);

      const { data: groups } = await supabase
          .from("groups")
          .select("id, name, climbing_threshold, department_id")
          .in("department_id", climbingDeptIds)
          .eq("is_new_member_group", true);

      if (groups?.length) {
        for (const group of groups) {
          if (!group.climbing_threshold) continue;
          const { data: attendance } = await supabase.from("attendance").select("directory_member_id").eq("group_id", group.id).eq("status", "present");
          const counts: Record<string, number> = {};
          attendance?.forEach(a => counts[a.directory_member_id] = (counts[a.directory_member_id] || 0) + 1);
          const targetThreshold = group.climbing_threshold - 1;
          const candidates = Object.entries(counts).filter(([_, count]) => count === targetThreshold);

          if (candidates.length > 0) {
            const { data: names } = await supabase.from("member_directory").select("full_name").in("id", candidates.map(c => c[0]));
            const memberNames = names?.map(n => n.full_name).join(", ");
            const { data: leaders } = await supabase.from("group_members").select("profile_id, profiles(push_reminder_enabled)").eq("group_id", group.id).eq("role_in_group", "leader").eq("is_active", true);
            const leaderIds = (leaders || []).filter(l => (l.profiles as any).push_reminder_enabled === true).map(l => l.profile_id);

            if (leaderIds.length > 0) {
              const { data: tokens } = await supabase.from("fcm_tokens").select("token, user_id, device_info").in("user_id", leaderIds);
              const seen = new Set();
              const uniqueTokens = (tokens || []).filter(t => {
                const key = `${t.user_id}:${t.device_info}`;
                if (seen.has(key)) return false;
                seen.add(key);
                return true;
              });
              const title = "🧗 등반 예정자 알림";
              const body = `다음 번 출석 시 등반 예정자가 있습니다: ${memberNames}`;
              await Promise.allSettled(uniqueTokens.map(t => sendPush(accessToken, t.token, title, body)));
            }
          }
        }
      }
    }
  }

  return new Response("Scheduler run complete");
});
