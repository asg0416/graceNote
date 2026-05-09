// chore: trigger dev deployment 2026-04-11
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID");
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL");
const FIREBASE_PRIVATE_KEY = Deno.env.get("FIREBASE_PRIVATE_KEY");

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

async function sendPush(accessToken: string, token: string, title: string, body: string, tag = "grace-note-scheduler") {
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
            tag,
            link: "/",
          },
        },
      }),
    }
  );
  return res.ok;
}

async function getLeaderRowsByGroups(
  supabase: ReturnType<typeof createClient>,
  groupIds: string[],
  includePushPreference = false,
): Promise<any[]> {
  if (groupIds.length === 0) return [];

  const phase2Select = includePushPreference
    ? "profile_id, group_id, profiles(push_reminder_enabled)"
    : "profile_id, group_id";
  const { data: phase2Leaders, error: phase2Error } = await supabase
    .from("memberships")
    .select(phase2Select)
    .in("group_id", groupIds)
    .eq("role", "leader")
    .eq("status", "active")
    .not("profile_id", "is", null);

  if (!phase2Error && (phase2Leaders || []).length > 0) {
    return phase2Leaders || [];
  }

  const legacySelect = includePushPreference
    ? "profile_id, group_id, profiles(push_reminder_enabled)"
    : "profile_id, group_id";
  const { data: legacyLeaders } = await supabase
    .from("group_members")
    .select(legacySelect)
    .in("group_id", groupIds)
    .eq("role_in_group", "leader")
    .eq("is_active", true);

  return legacyLeaders || [];
}

async function getLeaderDirectoryIdsByGroup(
  supabase: ReturnType<typeof createClient>,
  groupId: string,
): Promise<Set<string>> {
  const { data: phase2Leaders, error: phase2Error } = await supabase
    .from("memberships")
    .select("legacy_member_directory_id")
    .eq("group_id", groupId)
    .eq("role", "leader")
    .eq("status", "active")
    .not("legacy_member_directory_id", "is", null);

  if (!phase2Error && (phase2Leaders || []).length > 0) {
    return new Set((phase2Leaders || []).map((leader: any) => leader.legacy_member_directory_id).filter(Boolean));
  }

  const { data: legacyLeaders } = await supabase
    .from("group_members")
    .select("member_directory_id")
    .eq("group_id", groupId)
    .eq("role_in_group", "leader")
    .eq("is_active", true);

  return new Set((legacyLeaders || []).map((leader: any) => leader.member_directory_id).filter(Boolean));
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const task = url.searchParams.get("task");
  const force = url.searchParams.get("force") === "true"; // bypass time/day check for manual testing
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const accessToken = await getAccessToken();

  const nowKST = new Date(new Date().getTime() + (9 * 60 * 60 * 1000));
  const dayOfWeek = nowKST.getDay();
  const hourKST = nowKST.getHours();
  const minuteKST = nowKST.getMinutes();

  const log: string[] = [];
  log.push(`Task: ${task}, Day: ${dayOfWeek}, Hour(KST): ${hourKST}, Minute(KST): ${minuteKST}, Force: ${force}`);

  const { data: activeDepts } = await supabase.from("departments").select("id, name, church_id, leader_reminder_enabled, leader_reminder_days, leader_reminder_time, climbing_alert_enabled, climbing_alert_day, climbing_alert_time");
  if (!activeDepts?.length) return new Response(JSON.stringify({ log: ["No departments found"] }));

  if (task === "all_tasks" || task === "leader_reminder") {
    // 1. Leader Reminder
    const reminderDepts = force
      ? activeDepts.filter(c => c.leader_reminder_enabled)
      : activeDepts.filter(c => {
        if (!c.leader_reminder_enabled || !c.leader_reminder_days?.includes(dayOfWeek)) return false;
        const [h, m] = (c.leader_reminder_time || '').split(':').map(Number);
        return h === hourKST && (m || 0) === minuteKST;
      });

    log.push(`[leader_reminder] Matched depts: ${reminderDepts.map(d => d.name).join(', ') || 'none'}`);

    if (reminderDepts.length > 0) {
      const lastSunday = new Date(nowKST);
      lastSunday.setDate(nowKST.getDate() - dayOfWeek);
      const dateStr = lastSunday.toISOString().split('T')[0];
      log.push(`[leader_reminder] Week date: ${dateStr}`);

      const reminderDeptIds = reminderDepts.map(c => c.id);
      const reminderChurchIds = [...new Set(reminderDepts.map(c => c.church_id))];

      const { data: weeks } = await supabase.from("weeks").select("id, church_id").in("church_id", reminderChurchIds).eq("week_date", dateStr);
      log.push(`[leader_reminder] Weeks found: ${weeks?.length || 0}`);

      if (weeks?.length) {
        const { data: allGroups } = await supabase.from("groups").select("id, name, department_id, church_id").in("department_id", reminderDeptIds);
        // FIX: attendance table (not attendance_records)
        const { data: attendedGroups } = await supabase.from("attendance").select("group_id, week_id").in("week_id", weeks.map(w => w.id));
        const { data: prayedGroups } = await supabase.from("prayer_entries").select("group_id, week_id, status").in("week_id", weeks.map(w => w.id));

        // A group is "complete" only when it has BOTH attendance AND published prayer entries
        const attendedKeys = new Set((attendedGroups || []).map(g => `${g.group_id}:${g.week_id}`));
        const publishedPrayerKeys = new Set((prayedGroups || []).filter(g => g.status === 'published').map(g => `${g.group_id}:${g.week_id}`));
        const draftOnlyKeys = new Set((prayedGroups || []).filter(g => g.status === 'draft').map(g => `${g.group_id}:${g.week_id}`).filter(k => !publishedPrayerKeys.has(k)));

        const incompleteGroups = (allGroups || []).filter(g => {
          const weekId = weeks.find(w => w.church_id === g.church_id)?.id;
          if (!weekId) return false;
          const key = `${g.id}:${weekId}`;
          return !attendedKeys.has(key) || !publishedPrayerKeys.has(key);
        });

        log.push(`[leader_reminder] Total groups: ${allGroups?.length || 0}, Attended: ${attendedKeys.size}, Prayed: ${publishedPrayerKeys.size}, Incomplete: ${incompleteGroups.length}`);
        log.push(`[leader_reminder] Incomplete groups: ${incompleteGroups.map(g => g.name).join(', ') || 'none'}`);

        if (incompleteGroups.length > 0) {
          // Build detail per incomplete group: what's missing
          const groupMissing = new Map<string, { name: string; noAttendance: boolean; noPrayer: boolean; hasDraftOnly: boolean }>();
          for (const g of incompleteGroups) {
            const weekId = weeks.find(w => w.church_id === g.church_id)?.id;
            if (!weekId) continue;
            const key = `${g.id}:${weekId}`;
            groupMissing.set(g.id, {
              name: g.name,
              noAttendance: !attendedKeys.has(key),
              noPrayer: !publishedPrayerKeys.has(key),
              hasDraftOnly: !publishedPrayerKeys.has(key) && draftOnlyKeys.has(key),
            });
          }

          const leaders = await getLeaderRowsByGroups(
            supabase,
            incompleteGroups.map(g => g.id),
            true,
          );

          // Build map: leader profile_id → list of { groupName, missing info }
          const leaderGroupMap = new Map<string, { name: string; noAttendance: boolean; noPrayer: boolean; hasDraftOnly: boolean }[]>();
          (leaders || [])
            .filter(l => (l.profiles as any)?.push_reminder_enabled === true && l.profile_id)
            .forEach(l => {
              const info = groupMissing.get(l.group_id);
              if (!info) return;
              const existing = leaderGroupMap.get(l.profile_id) || [];
              existing.push(info);
              leaderGroupMap.set(l.profile_id, existing);
            });

          const uniqueLeaderIds = [...leaderGroupMap.keys()];
          log.push(`[leader_reminder] Target leaders: ${uniqueLeaderIds.length}`);

          if (uniqueLeaderIds.length > 0) {
            const { data: tokens } = await supabase.from("fcm_tokens").select("token, user_id, device_info").in("user_id", uniqueLeaderIds);
            // Deduplicate tokens per user+device
            const seen = new Set();
            const uniqueTokens = (tokens || []).filter(t => {
              const key = `${t.user_id}:${t.device_info}`;
              if (seen.has(key)) return false;
              seen.add(key);
              return true;
            });
            log.push(`[leader_reminder] Sending to ${uniqueTokens.length} devices`);
            const title = "📝 이번주 기도제목을 업로드해주세요!";
            const results = await Promise.allSettled(uniqueTokens.map(t => {
              const groups = leaderGroupMap.get(t.user_id) || [];
              const details = groups.map(g => {
                const missing: string[] = [];
                if (g.noAttendance) missing.push("출석 미체크");
                if (g.noPrayer && g.hasDraftOnly) missing.push("임시저장 확인 필요");
                else if (g.noPrayer) missing.push("기도제목 미등록");
                return `${g.name}(${missing.join(", ")})`;
              });
              const body = `${details.join(", ")} 🙏`;
              return sendPush(accessToken, t.token, title, body, "grace-note-leader-reminder");
            }));
            const sent = results.filter(r => r.status === 'fulfilled' && r.value === true).length;
            log.push(`[leader_reminder] Sent: ${sent}/${uniqueTokens.length}`);
          }
        }
      }
    }
  }

  if (task === "all_tasks" || task === "climbing_reminder") {
    // 2. Climbing Alert
    const climbingDepts = force
      ? activeDepts.filter(c => c.climbing_alert_enabled)
      : activeDepts.filter(c => {
        if (!c.climbing_alert_enabled || c.climbing_alert_day !== dayOfWeek) return false;
        const [h, m] = (c.climbing_alert_time || '').split(':').map(Number);
        return h === hourKST && (m || 0) === minuteKST;
      });

    log.push(`[climbing] Matched depts: ${climbingDepts.map(d => d.name).join(', ') || 'none'}`);

    if (climbingDepts.length > 0) {
      const climbingDeptIds = climbingDepts.map(c => c.id);

      const { data: groups } = await supabase
        .from("groups")
        .select("id, name, climbing_threshold, department_id")
        .in("department_id", climbingDeptIds)
        .eq("is_new_member_group", true);

      log.push(`[climbing] New member groups: ${groups?.map(g => `${g.name}(threshold:${g.climbing_threshold})`).join(', ') || 'none'}`);

      if (groups?.length) {
        for (const group of groups) {
          if (!group.climbing_threshold) continue;
          // Get leader member_directory_ids to exclude from candidates
          const leaderDirIds = await getLeaderDirectoryIdsByGroup(supabase, group.id);

          const { data: attendance } = await supabase.from("attendance").select("directory_member_id").eq("group_id", group.id).eq("status", "present");
          const counts: Record<string, number> = {};
          attendance?.forEach(a => {
            // Exclude leaders from climbing candidates
            if (!leaderDirIds.has(a.directory_member_id)) {
              counts[a.directory_member_id] = (counts[a.directory_member_id] || 0) + 1;
            }
          });
          const targetThreshold = group.climbing_threshold - 1;
          const candidates = Object.entries(counts).filter(([_, count]) => count === targetThreshold);

          log.push(`[climbing] ${group.name}: ${attendance?.length || 0} attendance records, ${candidates.length} candidates at threshold ${targetThreshold}`);

          if (candidates.length > 0) {
            const { data: names } = await supabase.from("member_directory").select("full_name").in("id", candidates.map(c => c[0]));
            const memberNames = names?.map(n => n.full_name).join(", ");
            const leaders = await getLeaderRowsByGroups(supabase, [group.id]);
            const leaderIds = (leaders || []).map(l => l.profile_id).filter(Boolean);

            // Also notify department admins
            const { data: deptAdmins } = await supabase
              .from("profiles")
              .select("id")
              .eq("department_id", group.department_id)
              .in("role", ["admin", "system_admin"]);
            const adminIds = (deptAdmins || []).map(a => a.id);

            const allRecipientIds = [...new Set([...leaderIds, ...adminIds])].filter(id => id);
            log.push(`[climbing] Recipients: ${allRecipientIds.length} (leaders: ${leaderIds.length}, admins: ${adminIds.length})`);

            if (allRecipientIds.length > 0) {
              const { data: tokens } = await supabase.from("fcm_tokens").select("token, user_id, device_info").in("user_id", allRecipientIds);
              const seen = new Set();
              const uniqueTokens = (tokens || []).filter(t => {
                const key = `${t.user_id}:${t.device_info}`;
                if (seen.has(key)) return false;
                seen.add(key);
                return true;
              });
              const title = "🧗 등반 예정자 알림";
              const body = `다음 번 출석 시 등반 예정자가 있습니다: ${memberNames}`;
              const results = await Promise.allSettled(uniqueTokens.map(t => sendPush(accessToken, t.token, title, body, "grace-note-climbing")));
              const sent = results.filter(r => r.status === 'fulfilled' && r.value === true).length;
              log.push(`[climbing] Sent: ${sent}/${uniqueTokens.length} for candidates: ${memberNames}`);
            }
          }
        }
      }
    }
  }

  console.log(log.join('\n'));
  return new Response(JSON.stringify({ log }, null, 2));
});
