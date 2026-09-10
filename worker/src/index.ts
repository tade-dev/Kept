import { extractWithLLM, UpstreamError } from "./llm";
import { buildSignedPass, parsePassRequest } from "./pass";
import { grantTrialBoost, parseTrialBoostRequest } from "./trialBoost";
import { isKeptPro } from "./proVerification";
import type { Env, ExtractRequest, OCRLine } from "./types";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await handle(request, env);
    } catch (error) {
      // Never log request bodies, OCR text, or cert material.
      if (error instanceof UpstreamError) {
        return json({ error: error.message }, error.status);
      }
      console.error("request_failed", { reason: "unhandled" });
      return json({ error: "Internal error." }, 500);
    }
  },
} satisfies ExportedHandler<Env>;

async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "GET" && url.pathname === "/health") {
    return json({ ok: true });
  }

  if (request.method !== "POST") {
    return json({ error: "Not found." }, 404);
  }

  if (url.pathname === "/extract") {
    return handleExtract(request, env);
  }
  if (url.pathname === "/pass") {
    return handlePass(request, env);
  }
  if (url.pathname === "/pro-boost") {
    return handleTrialBoost(request, env);
  }

  return json({ error: "Not found." }, 404);
}

async function handleTrialBoost(request: Request, env: Env): Promise<Response> {
  if (!checkAuth(request, env)) {
    return json({ error: "Unauthorized." }, 401);
  }

  const limited = await rateLimit(request, env);
  if (limited) return limited;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON body." }, 400);
  }

  const parsed = parseTrialBoostRequest(body);
  if (!parsed) {
    return json({ error: "Body must be { appUserID }." }, 400);
  }

  await grantTrialBoost(env, parsed);
  return json({ ok: true });
}

async function handleExtract(request: Request, env: Env): Promise<Response> {
  if (!checkAuth(request, env)) {
    return json({ error: "Unauthorized." }, 401);
  }

  // TODO(week 3): replace shared-secret header with App Attest attestation.
  const limited = await rateLimit(request, env);
  if (limited) return limited;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON body." }, 400);
  }

  const lines = parseLines(body);
  if (lines === null) {
    return json(
      { error: "Body must be { lines: [{ text, x, y, width, height }] }." },
      400,
    );
  }
  if (lines.length === 0) {
    return json({ error: "lines must not be empty." }, 400);
  }
  if (lines.length > 400) {
    return json({ error: "Too many lines." }, 413);
  }

  // Pro-tier model routing. The client sends its best guess (`isProClaimed`
  // + `appUserID`); we only verify against RC when Pro is claimed to save
  // the extra hop for the common free-user path. Free users trying to
  // spoof the flag get silently downgraded — RC comes back "not pro" and
  // we use the free model.
  let modelOverride: string | undefined;
  const authClaim = parseProClaim(body);
  if (authClaim.isProClaimed && authClaim.appUserID) {
    const verified = await isKeptPro(env, authClaim.appUserID);
    if (verified && env.LLM_MODEL_PRO) {
      modelOverride = env.LLM_MODEL_PRO;
    }
  }

  const extraction = await extractWithLLM(env, lines, modelOverride);
  return json(extraction, 200);
}

function parseProClaim(body: unknown): { isProClaimed: boolean; appUserID: string } {
  if (!body || typeof body !== "object") return { isProClaimed: false, appUserID: "" };
  const obj = body as Record<string, unknown>;
  return {
    isProClaimed: obj.isProClaimed === true,
    appUserID: typeof obj.appUserID === "string" ? obj.appUserID.trim() : "",
  };
}

async function handlePass(request: Request, env: Env): Promise<Response> {
  if (!checkAuth(request, env)) {
    return json({ error: "Unauthorized." }, 401);
  }

  // TODO(week 3): replace shared-secret header with App Attest attestation.
  const limited = await rateLimit(request, env);
  if (limited) return limited;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON body." }, 400);
  }

  const passRequest = parsePassRequest(body);
  if (!passRequest) {
    return json(
      {
        error:
          "Body must be { merchant, itemName, total, currencyCode, purchaseDate, coverageEndsAt, serialNumber }.",
      },
      400,
    );
  }

  const pkpass = await buildSignedPass(env, passRequest);
  return new Response(pkpass, {
    status: 200,
    headers: {
      "content-type": "application/vnd.apple.pkpass",
      "content-disposition": `attachment; filename="${passRequest.serialNumber}.pkpass"`,
      "cache-control": "no-store",
    },
  });
}

async function rateLimit(request: Request, env: Env): Promise<Response | null> {
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const { success } = await env.EXTRACT_RATE_LIMIT.limit({ key: `ip:${ip}` });
  if (!success) {
    return json({ error: "Too many requests." }, 429);
  }
  return null;
}

function checkAuth(request: Request, env: Env): boolean {
  const expected = env.EXTRACT_SECRET;
  if (!expected) return false;

  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) return false;

  return timingSafeEqual(match[1], expected);
}

function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  if (left.byteLength !== right.byteLength) {
    let dig = 0;
    for (let i = 0; i < left.byteLength; i++) dig |= left[i];
    return false;
  }
  let mismatch = 0;
  for (let i = 0; i < left.byteLength; i++) {
    mismatch |= left[i] ^ right[i];
  }
  return mismatch === 0;
}

function parseLines(body: unknown): OCRLine[] | null {
  if (!body || typeof body !== "object") return null;
  const lines = (body as ExtractRequest).lines;
  if (!Array.isArray(lines)) return null;

  const parsed: OCRLine[] = [];
  for (const item of lines) {
    if (!item || typeof item !== "object") return null;
    const row = item as Record<string, unknown>;
    if (typeof row.text !== "string") return null;
    const x = numberOrNull(row.x);
    const y = numberOrNull(row.y);
    const width = numberOrNull(row.width);
    const height = numberOrNull(row.height);
    if (x === null || y === null || width === null || height === null) return null;
    parsed.push({ text: row.text, x, y, width, height });
  }
  return parsed;
}

function numberOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}
