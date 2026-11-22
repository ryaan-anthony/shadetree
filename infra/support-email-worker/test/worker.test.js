// Run with: node --test   (Node 20+; no dependencies)
import { test } from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { handleEmail, signedHeaders, MAX_BYTES } from "../src/worker.js";

const SECRET = "test-inbound-secret-0123456789abcdef";
const CLOUDFLARE = "mx.cloudflare.net; dkim=pass header.d=example.com header.s=s1; dmarc=pass header.from=example.com; spf=pass smtp.mailfrom=bounce@example.com";
const RAW = "From: member@example.com\r\nTo: support+abc@getshadetree.com\r\nSubject: Re: Logo\r\n\r\nStill blurry.\r\n";
const ENV = { HUMAN_INBOX: "inbox@example.org", APP_INBOUND_URL: "https://app.example.test/inbound/support_email", INBOUND_EMAIL_SECRET: SECRET };
const NOW = 1_795_000_000_000;

function mockMessage({ raw = RAW, rawSize, authResults = [CLOUDFLARE], forwardError } = {}) {
  const bytes = new TextEncoder().encode(raw);
  const headers = new Headers();
  for (const value of authResults) headers.append("Authentication-Results", value);
  return {
    from: "bounce@example.com",
    to: "support+abc@getshadetree.com",
    headers,
    raw: new Blob([bytes]).stream(),
    rawSize: rawSize ?? bytes.length,
    rejected: null,
    forwardedTo: [],
    setReject(reason) { this.rejected = reason; },
    async forward(to) { if (forwardError) throw new Error(forwardError); this.forwardedTo.push(to); },
  };
}

function recorder(status = 204, error) {
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url, init });
    if (error) throw new Error(error);
    return new Response(null, { status });
  };
  const lines = [];
  const log = { warn: (line) => lines.push(line), error: (line) => lines.push(line) };
  return { calls, fetch, lines, log };
}

test("forwards a copy to the human inbox and posts the raw message, signed, to the app", async () => {
  const message = mockMessage();
  const { calls, fetch, log } = recorder();
  const result = await handleEmail(message, ENV, { fetch, log, now: () => NOW });
  assert.deepEqual(result, { forwarded: true, app: "accepted" });
  assert.deepEqual(message.forwardedTo, [ENV.HUMAN_INBOX]);
  assert.equal(calls.length, 1);
  const { url, init } = calls[0];
  assert.equal(url, ENV.APP_INBOUND_URL);
  assert.equal(init.method, "POST");
  assert.equal(new TextDecoder().decode(init.body), RAW);

  const h = init.headers;
  assert.equal(h["X-Shadetree-Timestamp"], String(NOW / 1000));
  const envelope = JSON.parse(Buffer.from(h["X-Shadetree-Envelope"], "base64url").toString());
  assert.deepEqual(envelope, { from: "bounce@example.com", to: "support+abc@getshadetree.com" });
  // Checked with Node's own HMAC, independently of the Worker's Web Crypto code.
  const expected = createHmac("sha256", SECRET).update(`${h["X-Shadetree-Timestamp"]}.${h["X-Shadetree-Envelope"]}.`).update(RAW).digest("hex");
  assert.equal(h["X-Shadetree-Signature"], `v1=${expected}`);
});

test("rejects mail over 25 MiB without forwarding or posting it", async () => {
  const message = mockMessage({ rawSize: MAX_BYTES + 1 });
  const { calls, fetch, log } = recorder();
  await handleEmail(message, ENV, { fetch, log, now: () => NOW });
  assert.equal(message.rejected, "Message too large");
  assert.deepEqual(message.forwardedTo, []);
  assert.equal(calls.length, 0);
});

test("never interprets Authentication-Results: a joined sender header (x y;) is left to the app's raw-message check", async () => {
  const spoof = "x y; dkim=pass header.d=victim.example";
  const raw = `Authentication-Results: mx.cloudflare.net; dkim=none; dmarc=none\r\nAuthentication-Results: ${spoof}\r\n${RAW}`;
  const message = mockMessage({ raw, authResults: ["mx.cloudflare.net; dkim=none; dmarc=none", spoof] });
  const { calls, fetch, log } = recorder();
  await handleEmail(message, ENV, { fetch, log, now: () => NOW });
  const { init } = calls[0];
  const envelope = JSON.parse(Buffer.from(init.headers["X-Shadetree-Envelope"], "base64url").toString());
  assert.deepEqual(Object.keys(envelope).sort(), ["from", "to"]);
  assert.equal(new TextDecoder().decode(init.body), raw, "the raw message, byte for byte, is what the app checks");
});

test("an app failure or refusal doesn't reject the mail (the human copy exists) and is logged without addresses", async () => {
  for (const rec of [recorder(500), recorder(204, "connect failed for member@example.com")]) {
    const message = mockMessage();
    const result = await handleEmail(message, ENV, { fetch: rec.fetch, log: rec.log, now: () => NOW });
    assert.equal(result.forwarded, true);
    assert.notEqual(result.app, "accepted");
    assert.equal(message.rejected, null);
    assert.equal(rec.lines.length, 1);
    assert.doesNotMatch(rec.lines.join("\n"), /@example\.com|Logo|blurry/);
  }
});

test("still posts to the app when forwarding fails, and fails loudly only if both fail", async () => {
  const ok = recorder();
  const result = await handleEmail(mockMessage({ forwardError: "destination not verified" }), ENV, { fetch: ok.fetch, log: ok.log, now: () => NOW });
  assert.deepEqual(result, { forwarded: false, app: "accepted" });

  const down = recorder(503);
  await assert.rejects(handleEmail(mockMessage({ forwardError: "nope" }), ENV, { fetch: down.fetch, log: down.log, now: () => NOW }));
});

test("without app settings it still forwards, and never hardcodes a destination", async () => {
  const message = mockMessage();
  const rec = recorder();
  const result = await handleEmail(message, { HUMAN_INBOX: ENV.HUMAN_INBOX }, { fetch: rec.fetch, log: rec.log, now: () => NOW });
  assert.deepEqual(result, { forwarded: true, app: "skipped" });
  assert.equal(rec.calls.length, 0);

  const noInbox = mockMessage();
  const rec2 = recorder();
  const result2 = await handleEmail(noInbox, { ...ENV, HUMAN_INBOX: "" }, { fetch: rec2.fetch, log: rec2.log, now: () => NOW });
  assert.deepEqual(result2, { forwarded: false, app: "accepted" });
});

test("signedHeaders signs the exact bytes, including non-ASCII", async () => {
  const raw = new TextEncoder().encode("Subject: Café\r\n\r\nNaïve ✓\r\n");
  const h = await signedHeaders(raw, { from: "", to: "support@getshadetree.com" }, SECRET, NOW);
  const expected = createHmac("sha256", SECRET).update(`${h["X-Shadetree-Timestamp"]}.${h["X-Shadetree-Envelope"]}.`).update(raw).digest("hex");
  assert.equal(h["X-Shadetree-Signature"], `v1=${expected}`);
});
