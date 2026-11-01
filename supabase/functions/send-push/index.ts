// Called by a database webhook for each new row in public.notifications.
import { deliver, type PushBackend } from "./deliver.ts";
import { type NotificationRecord, secretsMatch } from "./message.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const webhookSecret = Deno.env.get("PUSH_WEBHOOK_SECRET")!;
const serviceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);

const databaseHeaders = {
  apikey: serviceRoleKey,
  Authorization: `Bearer ${serviceRoleKey}`,
};

let cachedAccessToken: { value: string; expiresAt: number } | null = null;

function base64Url(value: string | Uint8Array): string {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

async function firebaseAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt > now + 60) {
    return cachedAccessToken.value;
  }

  const unsigned = [
    base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" })),
    base64Url(JSON.stringify({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })),
  ].join(".");

  const pem = (serviceAccount.private_key as string)
    .replace(/-----[A-Z ]+-----/g, "")
    .replace(/\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (character) => character.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${base64Url(new Uint8Array(signature))}`,
    }),
  });
  if (!response.ok) {
    throw new Error(`Google token request failed: ${response.status}`);
  }
  const { access_token: value, expires_in: expiresIn } = await response.json();
  cachedAccessToken = { value, expiresAt: now + expiresIn };
  return value;
}

const backend: PushBackend = {
  async tokensFor(userId) {
    const response = await fetch(
      `${supabaseUrl}/rest/v1/push_tokens?select=token&user_id=eq.${userId}`,
      { headers: databaseHeaders },
    );
    if (!response.ok) {
      throw new Error(`Token lookup failed: ${response.status}`);
    }
    const rows: { token: string }[] = await response.json();
    return rows.map((row) => row.token);
  },
  async deleteToken(token) {
    await fetch(
      `${supabaseUrl}/rest/v1/push_tokens?token=eq.${
        encodeURIComponent(token)
      }`,
      { method: "DELETE", headers: databaseHeaders },
    );
  },
  async send(message) {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${await firebaseAccessToken()}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(message),
      },
    );
    return { status: response.status, body: await response.text() };
  },
};

Deno.serve(async (request) => {
  const provided = (request.headers.get("Authorization") ?? "")
    .replace(/^Bearer /, "");
  if (!secretsMatch(provided, webhookSecret)) {
    return new Response("Unauthorized", { status: 401 });
  }

  const payload = await request.json();
  if (payload.type !== "INSERT" || payload.table !== "notifications") {
    return new Response("Ignored", { status: 200 });
  }

  try {
    const result = await deliver(payload.record as NotificationRecord, backend);
    return Response.json(result);
  } catch (error) {
    console.error(error);
    return new Response("Delivery failed", { status: 500 });
  }
});
