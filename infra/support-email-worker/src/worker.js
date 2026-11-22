// Shadetree support-email Worker (OPS-05, Shadetree ADR 0021).
//
// Cloudflare Email Routing runs this for mail to support@getshadetree.com (and, with
// subaddressing on, support+<token>@). For each message it:
//   1. rejects anything over 25 MiB;
//   2. always forwards a copy to the human support inbox (env.HUMAN_INBOX, a verified
//      Email Routing destination address);
//   3. posts the raw message to the app (env.APP_INBOUND_URL), signed with
//      env.INBOUND_EMAIL_SECRET (contract: docs/runbooks/inbound-email.md, "The signed post").
// If the app is down or refuses the post, the mail is NOT rejected: the human copy exists.
// Logs never contain addresses, subjects or bodies.
//
// What Cloudflare found (SPF/DKIM/DMARC) is NOT sent separately: the app reads Cloudflare's own
// Authentication-Results from the signed raw message (the first such field, which Cloudflare
// prepends). message.headers.get() joins repeated headers with ", ", so a sender's header could
// be mistaken for Cloudflare's; this Worker never interprets it.
//
// Single file, no dependencies: Terraform uploads it as is (infra/email.tf,
// cloudflare_workers_script with module = true), its settings as secret_text bindings.

export const MAX_BYTES = 25 * 1024 * 1024;
const APP_TIMEOUT_MS = 20_000;

export default {
  async email(message, env, ctx) {
    await handleEmail(message, env);
  },
};

// deps: { fetch, now (ms), log } so tests can replace them.
export async function handleEmail(message, env, deps = {}) {
  const doFetch = deps.fetch ?? globalThis.fetch;
  const now = deps.now ?? Date.now;
  const log = deps.log ?? console;

  if (message.rawSize > MAX_BYTES) {
    message.setReject("Message too large");
    log.warn(JSON.stringify({ event: "support_email.rejected", reason: "too_large", size: message.rawSize }));
    return { forwarded: false, app: "skipped" };
  }

  // message.raw can be read only once.
  const raw = new Uint8Array(await new Response(message.raw).arrayBuffer());

  let forwarded = false;
  try {
    if (!env.HUMAN_INBOX) throw new Error("HUMAN_INBOX is not set");
    await message.forward(env.HUMAN_INBOX);
    forwarded = true;
  } catch (error) {
    log.error(JSON.stringify({ event: "support_email.forward_failed", error: scrub(error) }));
  }

  const app = await postToApp(raw, message, env, { doFetch, now, log });
  // Lost only if both failed: let Cloudflare report a temporary failure instead of accepting it.
  if (!forwarded && app !== "accepted") throw new Error("support email could not be delivered anywhere");
  return { forwarded, app };
}

async function postToApp(raw, message, env, { doFetch, now, log }) {
  if (!env.APP_INBOUND_URL || !env.INBOUND_EMAIL_SECRET) {
    log.error(JSON.stringify({ event: "support_email.app_skipped", reason: "not_configured" }));
    return "skipped";
  }
  const headers = await signedHeaders(raw, { from: message.from ?? "", to: message.to ?? "" }, env.INBOUND_EMAIL_SECRET, now());
  try {
    const response = await doFetch(env.APP_INBOUND_URL, {
      method: "POST",
      headers,
      body: raw,
      signal: AbortSignal.timeout(APP_TIMEOUT_MS),
    });
    if (response.ok) return "accepted";
    log.error(JSON.stringify({ event: "support_email.app_refused", status: response.status }));
    return "refused";
  } catch (error) {
    log.error(JSON.stringify({ event: "support_email.app_failed", error: scrub(error) }));
    return "failed";
  }
}

// The signed post's headers (docs/runbooks/inbound-email.md, "The signed post"):
//   signature = hex(HMAC-SHA256(secret, "<timestamp>.<envelope>.<raw body>"))
export async function signedHeaders(raw, envelopeFields, secret, nowMs) {
  const timestamp = Math.floor(nowMs / 1000).toString();
  const envelope = base64url(new TextEncoder().encode(JSON.stringify(envelopeFields)));
  const signature = await hmacHex(secret, concat(new TextEncoder().encode(`${timestamp}.${envelope}.`), raw));
  return {
    "Content-Type": "message/rfc822",
    "X-Shadetree-Timestamp": timestamp,
    "X-Shadetree-Envelope": envelope,
    "X-Shadetree-Signature": `v1=${signature}`,
  };
}

export async function hmacHex(secret, bytes) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, bytes));
  return Array.from(mac, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function base64url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function concat(a, b) {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

// Error text without anything address-like.
function scrub(error) {
  return String(error?.message ?? error).replace(/[^\s<>"]+@[^\s<>"]+/g, "[EMAIL]").slice(0, 300);
}
