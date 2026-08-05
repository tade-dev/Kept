import { SYSTEM_PROMPT, buildUserPrompt } from "./prompt";
import { extractionResponseSchema, type ExtractionResponse } from "./schema";
import type { Env, OCRLine } from "./types";

type CompatChatResponse = {
  choices?: Array<{
    message?: { content?: string | null };
  }>;
  error?: { message?: string; type?: string; code?: string | number };
};

/**
 * Extract via Cloudflare AI Gateway OpenAI-compatible endpoint.
 * Works with OpenAI and Anthropic (and others) by changing LLM_MODEL + API key.
 *
 * Examples:
 *   LLM_MODEL=openai/gpt-4o-mini          + OPENAI_API_KEY
 *   LLM_MODEL=anthropic/claude-haiku-4-5  + ANTHROPIC_API_KEY
 */
export async function extractWithLLM(
  env: Env,
  lines: OCRLine[],
): Promise<ExtractionResponse> {
  const accountId = env.CF_ACCOUNT_ID;
  const gatewayId = env.AI_GATEWAY_ID;
  const model = env.LLM_MODEL || "openai/gpt-4o-mini";
  const apiKey = resolveProviderKey(env);

  if (!accountId || accountId === "REPLACE_ME") {
    throw new UpstreamError("AI Gateway account is not configured.", 500);
  }
  if (!apiKey) {
    throw new UpstreamError(
      "No LLM API key configured. Set OPENAI_API_KEY or ANTHROPIC_API_KEY (or LLM_API_KEY).",
      500,
    );
  }

  // Same URL shape you already have for the gateway:
  // https://gateway.ai.cloudflare.com/v1/{account}/kept/compat/chat/completions
  const url =
    `https://gateway.ai.cloudflare.com/v1/${accountId}/${gatewayId}` +
    `/compat/chat/completions`;

  const headers: Record<string, string> = {
    "content-type": "application/json",
    // Provider key goes in Authorization for the compat endpoint.
    authorization: `Bearer ${apiKey}`,
    "cf-aig-cache-ttl": "0",
  };
  if (env.CF_AIG_TOKEN) {
    headers["cf-aig-authorization"] = `Bearer ${env.CF_AIG_TOKEN}`;
  }

  const body = {
    model,
    temperature: 0.1,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: buildUserPrompt(lines) },
    ],
    response_format: {
      type: "json_schema",
      json_schema: {
        name: "receipt_extraction",
        strict: true,
        schema: extractionResponseSchema,
      },
    },
  };

  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });
  } catch {
    throw new UpstreamError("Upstream model request failed.", 502);
  }

  let payload: CompatChatResponse;
  try {
    payload = (await response.json()) as CompatChatResponse;
  } catch {
    throw new UpstreamError(
      `Upstream model returned an error (HTTP ${response.status}).`,
      response.status === 429 ? 429 : 502,
    );
  }

  if (response.status === 429) {
    throw new UpstreamError(
      "Upstream rate limited or out of quota. Check your OpenAI/Anthropic billing.",
      429,
    );
  }

  if (!response.ok) {
    const code =
      payload.error?.code != null ? String(payload.error.code) : "";
    const type =
      typeof payload.error?.type === "string" ? payload.error.type : "";
    const detail = [code, type].filter(Boolean).join(" ");
    console.error("upstream_http_error", {
      http: response.status,
      code: code || null,
      type: type || null,
      model,
      hasGatewayToken: Boolean(env.CF_AIG_TOKEN),
    });

    if (response.status === 401 || response.status === 403) {
      throw new UpstreamError(
        "Upstream unauthorized. Check OPENAI_API_KEY / ANTHROPIC_API_KEY and CF_AIG_TOKEN (if gateway auth is on).",
        502,
      );
    }

    throw new UpstreamError(
      detail
        ? `Upstream model returned an error (HTTP ${response.status} ${detail}).`
        : `Upstream model returned an error (HTTP ${response.status}).`,
      502,
    );
  }

  const text = payload.choices?.[0]?.message?.content?.trim();
  if (!text) {
    throw new UpstreamError("Upstream model returned an empty response.", 502);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new UpstreamError("Upstream model returned non-JSON content.", 502);
  }

  return normaliseExtraction(parsed);
}

function resolveProviderKey(env: Env): string | undefined {
  return (
    env.LLM_API_KEY ||
    env.OPENAI_API_KEY ||
    env.ANTHROPIC_API_KEY ||
    undefined
  );
}

function normaliseExtraction(raw: unknown): ExtractionResponse {
  if (!raw || typeof raw !== "object") {
    throw new UpstreamError("Upstream model returned an unexpected shape.", 502);
  }
  const obj = raw as Record<string, unknown>;
  const confidenceRaw =
    obj.confidence && typeof obj.confidence === "object"
      ? (obj.confidence as Record<string, unknown>)
      : {};

  return {
    merchant: nullableString(obj.merchant),
    itemName: nullableString(obj.itemName),
    total: nullableNumber(obj.total),
    currencyCode: nullableString(obj.currencyCode)?.toUpperCase() ?? null,
    purchaseDate: nullableString(obj.purchaseDate),
    confidence: {
      merchant: clamp01(confidenceRaw.merchant),
      total: clamp01(confidenceRaw.total),
      purchaseDate: clamp01(confidenceRaw.purchaseDate),
    },
  };
}

function nullableString(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function nullableNumber(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value;
}

function clamp01(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return Math.min(1, Math.max(0, value));
}

export class UpstreamError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}
