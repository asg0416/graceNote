import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Firebase Service Account from environment
const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID");
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL");
const FIREBASE_PRIVATE_KEY = Deno.env.get("FIREBASE_PRIVATE_KEY");

interface PushRequest {
  title: string;
  body: string;
  targetUserIds: string[];
  data?: Record<string, string>;
}

async function getAccessToken(): Promise<string> {
  const privateKey = FIREBASE_PRIVATE_KEY!.replace(/\\n/g, "\n");
  
  const header = { alg: "RS256", typ: "JWT" };
  
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: FIREBASE_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  
  const toBase64Url = (data: string) => {
    return btoa(data).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  };
  
  const headerB64 = toBase64Url(JSON.stringify(header));
  const claimB64 = toBase64Url(JSON.stringify(claim));
  const unsignedToken = `${headerB64}.${claimB64}`;
  
  const keyData = privateKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  
  const binaryKey = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));
  
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
  
  const encoder = new TextEncoder();
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    encoder.encode(unsignedToken)
  );
  
  const signatureB64 = toBase64Url(
    String.fromCharCode(...new Uint8Array(signature))
  );
  
  const jwt = `${unsignedToken}.${signatureB64}`;
  
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  
  const tokenData = await tokenRes.json();
  if (!tokenData.access_token) {
    console.error("OAuth token error:", JSON.stringify(tokenData));
    throw new Error(`Failed to get access token: ${JSON.stringify(tokenData)}`);
  }
  return tokenData.access_token;
}

async function sendFCMMessage(
  accessToken: string,
  fcmToken: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<{ success: boolean; error?: string }> {
  try {
    // Data-only message: no "notification" field to prevent duplicate display
    const message = {
      message: {
        token: fcmToken,
        data: {
          title,
          body,
          tag: "grace-note-default",
          link: data?.url || "/",
          ...(data || {}),
        },
      },
    };

    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(message),
      }
    );

    if (!res.ok) {
      const errBody = await res.text();
      console.error(`FCM send failed for token ${fcmToken.substring(0, 20)}...:`, errBody);
      return { success: false, error: errBody };
    }

    return { success: true };
  } catch (error) {
    console.error(`FCM error:`, error);
    return { success: false, error: String(error) };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    if (!FIREBASE_PROJECT_ID || !FIREBASE_CLIENT_EMAIL || !FIREBASE_PRIVATE_KEY) {
      throw new Error("Firebase service account credentials are not configured. Set FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY as Edge Function secrets.");
    }

    const { title, body, targetUserIds, data } = (await req.json()) as PushRequest;

    if (!title || !targetUserIds || targetUserIds.length === 0) {
      return new Response(
        JSON.stringify({ error: "title and targetUserIds are required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Fixed: use .in() instead of .in_() for supabase-js v2
    const { data: tokens, error: dbError } = await supabase
      .from("fcm_tokens")
      .select("token, user_id")
      .in("user_id", targetUserIds);

    if (dbError) {
      throw new Error(`DB error: ${dbError.message}`);
    }

    if (!tokens || tokens.length === 0) {
      return new Response(
        JSON.stringify({ sent: 0, message: "No FCM tokens found for target users" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    console.log(`Found ${tokens.length} token(s) for ${targetUserIds.length} user(s)`);

    const accessToken = await getAccessToken();

    const results = await Promise.allSettled(
      tokens.map((t: { token: string }) =>
        sendFCMMessage(accessToken, t.token, title, body, data)
      )
    );

    // Clean up expired/invalid tokens
    const failedTokens: string[] = [];
    results.forEach((result, index) => {
      if (
        result.status === "fulfilled" &&
        !result.value.success &&
        result.value.error?.includes("UNREGISTERED")
      ) {
        failedTokens.push(tokens[index].token);
      }
    });

    if (failedTokens.length > 0) {
      await supabase
        .from("fcm_tokens")
        .delete()
        .in("token", failedTokens);
      console.log(`Cleaned up ${failedTokens.length} expired tokens`);
    }

    const sent = results.filter(
      (r) => r.status === "fulfilled" && r.value.success
    ).length;

    return new Response(
      JSON.stringify({
        sent,
        total: tokens.length,
        cleaned: failedTokens.length,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("send-push error:", error);
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
