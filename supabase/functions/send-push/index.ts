
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID")!;
const GOOGLE_SERVICE_ACCOUNT = JSON.parse(Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON")!);

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claimSet = {
    iss: GOOGLE_SERVICE_ACCOUNT.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const enc = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const unsigned = `${enc(header)}.${enc(claimSet)}`;

  const keyData = GOOGLE_SERVICE_ACCOUNT.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binaryKey = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsigned),
  );

  const encodedSig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const jwt = `${unsigned}.${encodedSig}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenJson = await tokenRes.json();
  if (!tokenRes.ok) {
    throw new Error(`Failed to get Google access token: ${JSON.stringify(tokenJson)}`);
  }
  return tokenJson.access_token as string;
}

export default {
  fetch: withSupabase({ auth: ["secret"] }, async (req, ctx) => {
    // Only accept calls authenticated with our service-role key (i.e. the webhook)
    if (ctx.authMode !== "secret") {
      return new Response("Forbidden", { status: 403 });
    }

    const payload = await req.json();
    const record = payload.record; // the newly inserted notifications row
    console.log("Received notification row:", JSON.stringify(record));

    if (!record?.recipient_id) {
      return Response.json({ skipped: "no recipient_id on record" }, { status: 200 });
    }

    const { data: profile, error } = await ctx.supabaseAdmin
      .from("profiles")
      .select("fcm_token")
      .eq("id", record.recipient_id)
      .single();

    if (error || !profile?.fcm_token) {
      console.log(`No fcm_token for user ${record.recipient_id}, skipping push.`);
      return Response.json({ skipped: "no fcm_token" }, { status: 200 });
    }

    const accessToken = await getAccessToken();

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: profile.fcm_token,
            notification: {
              title: record.title,
              body: record.body,
            },
            data: {
              loan_id: record.loan_id ?? "",
              notification_id: record.id ?? "",
            },
            android: {
              priority: "high",
              notification: { channel_id: "high_importance_channel" },
            },
          },
        }),
      },
    );

    const fcmJson = await fcmRes.json();

    if (!fcmRes.ok) {
      console.error("FCM send failed:", fcmJson);
      return Response.json({ error: fcmJson }, { status: 500 });
    }

    return Response.json({ success: true, fcm: fcmJson });
  }),
};