// 194 — send-decision-email
// Supabase Edge Function. Sends the "you're in" / waitlist email via Resend
// when a founder approves or rejects an application in Border Control.
//
// Security: the caller's JWT is required and must belong to an admin founder
// (verified via the is_admin() RPC). The Resend API key stays server-side.
//
// Env / secrets:
//   RESEND_API_KEY          (required) Resend API key
//   DECISION_EMAIL_FROM     (optional) From address. Defaults to Resend's test
//                           sender. Set to e.g. "194 <hello@join194.com>" once
//                           the domain is verified in Resend.
//   DECISION_EMAIL_TEST_TO  (optional) If set, ALL mail is redirected to this
//                           address instead of the applicant — used while on
//                           Resend's test sender (which only mails your own
//                           account). Unset it in production.
//   SUPABASE_URL, SUPABASE_ANON_KEY  auto-injected by Supabase.

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const FROM = Deno.env.get("DECISION_EMAIL_FROM") ?? "194 Border Control <onboarding@resend.dev>";
const TEST_TO = Deno.env.get("DECISION_EMAIL_TEST_TO") ?? "";

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

  // --- Authorize: caller must be an admin founder ---
  const adminRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/is_admin`, {
    method: "POST",
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: authHeader,
      "Content-Type": "application/json",
    },
    body: "{}",
  });
  const isAdmin = adminRes.ok && (await adminRes.json()) === true;
  if (!isAdmin) return json({ error: "Not authorized" }, 403);

  // --- Validate input ---
  let payload: { application_id?: string; decision?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const { application_id, decision } = payload ?? {};
  if (!application_id || (decision !== "approved" && decision !== "rejected")) {
    return json({ error: "application_id and decision (approved|rejected) are required" }, 400);
  }

  // --- Look up the application (admin read allowed by RLS via the caller's JWT) ---
  const appRes = await fetch(
    `${SUPABASE_URL}/rest/v1/applications?id=eq.${encodeURIComponent(application_id)}&select=name,email,country`,
    { headers: { apikey: SUPABASE_ANON_KEY, Authorization: authHeader } },
  );
  if (!appRes.ok) return json({ error: "Application lookup failed", detail: await appRes.text() }, 502);
  const rows = await appRes.json();
  const app = Array.isArray(rows) ? rows[0] : null;
  if (!app || !app.email) return json({ error: "Application not found" }, 404);

  const to = TEST_TO || app.email;
  const { subject, html, text } = buildEmail(decision, app.name || "there");

  // --- Send via Resend ---
  const sendRes = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: FROM, to, subject, html, text }),
  });
  const sendBody = await sendRes.json().catch(() => ({}));
  if (!sendRes.ok) return json({ error: "Email send failed", detail: sendBody }, 502);

  return json({ ok: true, id: (sendBody as { id?: string }).id, to });
});

// ---------- Email content (border-control deadpan, per the brand voice) ----------
function buildEmail(decision: string, name: string): { subject: string; html: string; text: string } {
  const firstName = String(name).trim().split(/\s+/)[0] || "there";
  if (decision === "approved") {
    return {
      subject: "194 — Cleared for entry",
      text:
        `APPROVED\n\n${firstName}, your application cleared.\n\n` +
        `You're one of the 194. We'll email your invite when your access opens — ` +
        `keep an eye on this inbox.\n\n— 194 Border Control`,
      html: shell(
        "APPROVED",
        "#4CAF7D",
        `<p style="margin:0 0 16px">${esc(firstName)}, your application cleared.</p>` +
          `<p style="margin:0 0 16px">You're one of the 194. Welcome inside.</p>` +
          `<p style="margin:0;color:#7C8699;font-size:14px">We'll send your invite the moment your access opens. Keep an eye on this inbox.</p>`,
      ),
    };
  }
  // rejected -> polite waitlist
  return {
    subject: "194 — Application received",
    text:
      `RECEIVED\n\n${firstName}, thank you for applying to 194.\n\n` +
      `You're on the waitlist. We admit in waves, and we'll reach out if a place ` +
      `opens for you.\n\n— 194 Border Control`,
    html: shell(
      "RECEIVED",
      "#C8A55E",
      `<p style="margin:0 0 16px">${esc(firstName)}, thank you for applying to 194.</p>` +
        `<p style="margin:0 0 16px">You're on the waitlist. We admit in waves — if a place opens for you, we'll be in touch.</p>` +
        `<p style="margin:0;color:#7C8699;font-size:14px">No further action is needed on your side.</p>`,
    ),
  };
}

function esc(s: string): string {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!),
  );
}

function shell(stamp: string, stampColor: string, bodyHtml: string): string {
  return `<!doctype html><html><body style="margin:0;background:#0B1120;padding:32px 0;font-family:Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0B1120;">
    <tr><td align="center">
      <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px;width:100%;background:#0F172B;border:1px solid rgba(200,165,94,0.22);border-radius:8px;">
        <tr><td style="padding:36px 36px 8px;text-align:center;">
          <div style="font-size:26px;letter-spacing:8px;color:#C8A55E;font-weight:600;">194</div>
          <div style="font-size:11px;letter-spacing:3px;color:#7C8699;margin-top:6px;">BORDER CONTROL</div>
        </td></tr>
        <tr><td style="padding:20px 36px 0;text-align:center;">
          <span style="display:inline-block;border:1px solid ${stampColor};color:${stampColor};font-size:14px;letter-spacing:5px;padding:10px 22px;border-radius:3px;transform:rotate(-2deg);">${stamp}</span>
        </td></tr>
        <tr><td style="padding:28px 36px 36px;color:#EDE8DC;font-size:16px;line-height:1.6;">
          ${bodyHtml}
        </td></tr>
        <tr><td style="padding:18px 36px;border-top:1px solid rgba(200,165,94,0.18);color:#5b6577;font-size:11px;letter-spacing:1px;text-align:center;">
          194 &middot; 195 countries. Yours made it.
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}
