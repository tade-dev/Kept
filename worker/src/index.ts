import { extractWithLLM, UpstreamError } from "./llm";
import type { Env, ExtractRequest, OCRLine } from "./types";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await handle(request, env);
    } catch (error) {
      // Never log request bodies or OCR text — errors may otherwise echo prompts.
      if (error instanceof UpstreamError) {
        return json({ error: error.message }, error.status);
      }
      console.error("extract_failed", { reason: "unhandled" });
      return json({ error: "Internal error." }, 500);
    }
  },
} satisfies ExportedHandler<Env>;

async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "GET" && url.pathname === "/health") {
    return json({ ok: true });
  }

  if (request.method !== "POST" || url.pathname !== "/extract") {
    return json({ error: "Not found." }, 404);
  }

  if (!checkAuth(request, env)) {
    return json({ error: "Unauthorized." }, 401);
  }

  // TODO(week 3): replace shared-secret header with App Attest attestation.
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const { success } = await env.EXTRACT_RATE_LIMIT.limit({ key: `ip:${ip}` });
  if (!success) {
    return json({ error: "Too many requests." }, 429);
  }

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

  const extraction = await extractWithLLM(env, lines);
  return json(extraction, 200);
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
    // Still compare to keep timing flatter on length mismatch.
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
