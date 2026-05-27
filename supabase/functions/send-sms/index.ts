/**
 * Supabase Edge Function: send SMS via Twilio.
 *
 * Secrets (Dashboard → Edge Functions → Secrets, or CLI):
 *   TWILIO_ACCOUNT_SID
 *   TWILIO_AUTH_TOKEN
 *   TWILIO_FROM_NUMBER     (E.164, e.g. +15551234567 — must be allowed in Twilio)
 *   FIREBASE_PROJECT_ID    (same as Firebase console / firebase_options projectId)
 *
 * Client must send header: x-firebase-token: <Firebase ID token>
 * Body JSON: { "to": "+639...", "body": "message", "userId"?: string, "meta"?: object }
 *
 * config.toml: verify_jwt = false (Firebase verifies the token here, not Supabase JWT).
 */

import { createRemoteJWKSet, jwtVerify } from "https://deno.land/x/jose@v5.2.4/index.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-firebase-token",
};

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);

async function verifyFirebaseIdToken(
  token: string,
  projectId: string,
): Promise<void> {
  await jwtVerify(token, FIREBASE_JWKS, {
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
    const semaphoreApiKey = (Deno.env.get("SEMAPHORE_API_KEY") ?? "").trim();
    const semaphoreSender = (Deno.env.get("SEMAPHORE_SENDER_NAME") ?? "").trim();
    const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
    const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
    const from = Deno.env.get("TWILIO_FROM_NUMBER");

    if (!projectId) {
      console.error("Missing FIREBASE_PROJECT_ID secret");
      return new Response(
        JSON.stringify({
          error: "Server misconfiguration: set FIREBASE_PROJECT_ID (Firebase console project id)",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const hasTwilio = Boolean(accountSid && authToken && from);
    if (!semaphoreApiKey && !hasTwilio) {
      console.error("Missing SMS provider secrets");
      return new Response(
        JSON.stringify({
          error:
            "SMS not configured: set SEMAPHORE_API_KEY (Philippines) or TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const firebaseToken = req.headers.get("x-firebase-token")?.trim();
    if (!firebaseToken) {
      return new Response(
        JSON.stringify({ error: "Missing x-firebase-token (Firebase ID token)" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    try {
      await verifyFirebaseIdToken(firebaseToken, projectId);
    } catch (e) {
      console.error("Firebase token invalid:", e);
      return new Response(
        JSON.stringify({ error: "Invalid or expired Firebase token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    let json: Record<string, unknown>;
    try {
      json = (await req.json()) as Record<string, unknown>;
    } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const to = String(json["to"] ?? "").trim();
    const body = String(json["body"] ?? "").trim();
    const userId = json["userId"] != null ? String(json["userId"]) : undefined;

    if (!to || !body) {
      return new Response(JSON.stringify({ error: "Missing to or body" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (body.length > 1600) {
      return new Response(JSON.stringify({ error: "Body too long (max 1600)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!to.startsWith("+")) {
      return new Response(
        JSON.stringify({ error: "Phone must be E.164 (start with +)" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (userId) {
      console.log("send-sms userId=", userId);
    }

    const meta =
      json["meta"] != null && typeof json["meta"] === "object"
        ? (json["meta"] as Record<string, unknown>)
        : {};
    const otpCode =
      meta["type"] === "otp" && meta["code"] != null
        ? String(meta["code"]).trim()
        : "";

    // Philippines: Semaphore only — do not fall back to Twilio when SEMAPHORE_API_KEY is set.
    if (semaphoreApiKey) {
      const semNumber = to.startsWith("+63")
        ? `0${to.slice(3)}`
        : to.replace("+", "");

      const postSemaphore = async (
        path: "messages" | "otp",
        includeSender: boolean,
      ): Promise<{ ok: true; provider: string }> => {
        const semParams = new URLSearchParams();
        semParams.set("apikey", semaphoreApiKey);
        semParams.set("number", semNumber);
        semParams.set("message", body);
        if (otpCode) semParams.set("code", otpCode);
        if (includeSender && semaphoreSender) {
          semParams.set("sendername", semaphoreSender.slice(0, 11));
        }

        const semRes = await fetch(
          `https://api.semaphore.co/api/v4/${path}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: semParams.toString(),
          },
        );
        const semText = await semRes.text();
        if (!semRes.ok) {
          throw new Error(
            `Semaphore HTTP ${semRes.status}: ${semText.slice(0, 300)}`,
          );
        }

        let rows: Array<{ status?: string; message?: string }> = [];
        try {
          rows = JSON.parse(semText) as Array<{ status?: string; message?: string }>;
        } catch {
          throw new Error(`Semaphore invalid JSON: ${semText.slice(0, 200)}`);
        }
        const st = String(rows[0]?.status || "").toLowerCase();
        if (st === "failed") {
          throw new Error(
            rows[0]?.message ||
              "Semaphore status Failed — check API key, credits, and sender name approval.",
          );
        }
        return {
          ok: true,
          provider: otpCode ? "semaphore_otp" : "semaphore",
        };
      };

      try {
        const path = otpCode ? "otp" : "messages";
        try {
          const r = await postSemaphore(path, true);
          return new Response(JSON.stringify(r), {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        } catch (firstErr) {
          const msg = String(firstErr);
          if (semaphoreSender && /sender/i.test(msg)) {
            const r = await postSemaphore(path, false);
            return new Response(JSON.stringify(r), {
              status: 200,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }
          throw firstErr;
        }
      } catch (e) {
        console.error("Semaphore send failed:", e);
        return new Response(
          JSON.stringify({
            error: "Semaphore rejected the message",
            detail: String(e).slice(0, 300),
          }),
          {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    if (!from?.startsWith("+")) {
      console.error("TWILIO_FROM_NUMBER must be E.164 (e.g. +15551234567)");
      return new Response(
        JSON.stringify({
          error: "Server misconfiguration: TWILIO_FROM_NUMBER must be E.164",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const basic = btoa(`${accountSid}:${authToken}`);
    const twilioUrl =
      `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`;

    const params = new URLSearchParams();
    params.set("To", to);
    params.set("From", from!);
    params.set("Body", body);

    const twilioRes = await fetch(twilioUrl, {
      method: "POST",
      headers: {
        Authorization: `Basic ${basic}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: params.toString(),
    });

    const twilioText = await twilioRes.text();

    if (!twilioRes.ok) {
      console.error("Twilio HTTP", twilioRes.status, twilioText.slice(0, 500));
      return new Response(
        JSON.stringify({
          error: "Twilio rejected the message",
          detail: twilioText.slice(0, 300),
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    let sid: string | undefined;
    try {
      const parsed = JSON.parse(twilioText) as { sid?: string };
      sid = parsed.sid;
    } catch {
      // ignore
    }

    return new Response(JSON.stringify({ ok: true, provider: "twilio", sid }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
