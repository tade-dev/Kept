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
  modelOverride?: string,
): Promise<ExtractionResponse> {
  const accountId = env.CF_ACCOUNT_ID;
  const gatewayId = env.AI_GATEWAY_ID;
  const model = modelOverride || env.LLM_MODEL || "openai/gpt-4o-mini";
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
    env.GEMINI_API_KEY ||
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

  // Normalise documentType: lowercase, trim, default to "receipt" when
  // missing (fail-open — better to attempt extraction than reject a real
  // receipt because the model forgot to fill the field).
  const documentTypeRaw = nullableString(obj.documentType)?.toLowerCase() ?? "receipt";
  const documentType = documentTypeRaw.length > 0 ? documentTypeRaw : "receipt";
  const isReceipt = documentType === "receipt";

  // When not a receipt, force null every extraction field. Prevents pollution
  // from a model that classified "passport" but still filled in a bogus total.
  const returnWindowDays = isReceipt ? nullablePositiveInt(obj.returnWindowDays) : null;
  const warrantyDurationMonths = isReceipt ? nullablePositiveInt(obj.warrantyDurationMonths) : null;
  const items = isReceipt ? normaliseItems(obj.items) : [];
  let itemName = isReceipt ? nullableString(obj.itemName) : null;
  itemName = isReceipt ? refineItemName(itemName, items) : null;
  const category = isReceipt ? normaliseCategory(obj.category) : null;
  const total = isReceipt ? reconcileTotal(nullableNumber(obj.total), items) : null;

  return {
    documentType,
    merchant: isReceipt ? nullableString(obj.merchant) : null,
    itemName,
    category,
    items,
    total,
    currencyCode: isReceipt
      ? (nullableString(obj.currencyCode)?.toUpperCase() ?? null)
      : null,
    purchaseDate: isReceipt ? nullableString(obj.purchaseDate) : null,
    // Cloud path only accepts printed coverage — never mark inferred.
    returnWindowDays,
    returnWindowIsInferred: false,
    warrantyDurationMonths,
    warrantyIsInferred: false,
    confidence: {
      merchant: clamp01(confidenceRaw.merchant),
      total: clamp01(confidenceRaw.total),
      purchaseDate: clamp01(confidenceRaw.purchaseDate),
    },
  };
}

const NON_PRODUCT_ITEM =
  /^(total|grand\s*total|subtotal|postage|shipping|delivery|tax|vat|gst|qty|quantity|balance|amount\s*due|change|cash|card|paid)$/i;

function normaliseItems(
  value: unknown,
): Array<{ name: string; price: number }> {
  if (!Array.isArray(value)) return [];
  const out: Array<{ name: string; price: number }> = [];
  const seen = new Set<string>();
  for (const entry of value) {
    if (!entry || typeof entry !== "object") continue;
    const row = entry as Record<string, unknown>;
    const name = nullableString(row.name);
    const price = nullableNumber(row.price);
    if (!name || price == null || price <= 0) continue;
    if (NON_PRODUCT_ITEM.test(name)) continue;
    // Packing slips often repeat Price Paid + line Total as two identical rows.
    const key = `${name.toLowerCase().replace(/\s+/g, " ")}|${price.toFixed(2)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ name, price });
    if (out.length >= 40) break;
  }
  return out;
}

/** Prefer item sum when a labeled total is smaller than a line item (common OCR 7→1). */
function reconcileTotal(
  total: number | null,
  items: Array<{ name: string; price: number }>,
): number | null {
  if (items.length === 0) return total;
  const sum = round2(items.reduce((acc, item) => acc + item.price, 0));
  const maxItem = Math.max(...items.map((item) => item.price));
  if (total == null || total <= 0) return sum > 0 ? sum : null;
  if (total + 0.009 < maxItem) return sum;
  return round2(total);
}

/**
 * Deterministic itemName. Rather than trust the LLM to format the label,
 * we build it here from `items[]`:
 *
 *   0 items:  fall through to whatever the LLM guessed (last-resort merchant/
 *             category hint like "Grocery shop" — usually right when items[]
 *             genuinely couldn't be parsed).
 *   1 item:   the item's name verbatim.
 *   2+ items: "{highest-priced item}, +N more"
 *             UNLESS the LLM classified this as a grocery / restaurant / fuel
 *             receipt (kept as a summary since those baskets have no single
 *             "primary" the user would identify with).
 *
 * This means the LLM can never again randomly pick "Sale" / "Repair" /
 * "Promotion" as itemName when there are real product rows to work with.
 */
function refineItemName(
  itemName: string | null,
  items: Array<{ name: string; price: number }>,
): string | null {
  if (items.length === 0) return itemName;
  if (items.length === 1) return cleanItemName(items[0].name);

  const basketSummaries = new Set([
    "grocery shop",
    "groceries",
    "restaurant meal",
    "meal",
    "lunch",
    "dinner",
    "breakfast",
    "fuel",
    "petrol",
    "gas",
  ]);
  if (itemName && basketSummaries.has(itemName.toLowerCase())) {
    return itemName;
  }

  const primary = items.reduce((a, b) => (a.price >= b.price ? a : b));
  const remaining = items.length - 1;
  return `${cleanItemName(primary.name)}, +${remaining} more`;
}

function cleanItemName(name: string): string {
  // Trim trailing punctuation the LLM sometimes leaves on OCR fragments.
  return name.replace(/[\s.,;:—-]+$/, "").trim();
}

const CATEGORY_VALUES = new Set([
  "Groceries",
  "Restaurant",
  "Fashion",
  "Electronics",
  "Home",
  "Repair",
  "Fuel",
  "Travel",
  "Beauty",
  "Books",
  "Other",
]);

/**
 * Snap the model's category output to the fixed enum. Returns null when the
 * model returned nothing usable — the iOS side falls back to the primary
 * item name as the list subtitle in that case.
 */
function normaliseCategory(raw: unknown): string | null {
  const s = nullableString(raw);
  if (!s) return null;
  // Title-case the first letter so "electronics" → "Electronics".
  const canonical = s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
  return CATEGORY_VALUES.has(canonical) ? canonical : null;
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
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

/** Whole days/months counts; rejects 0 and non-integers. */
function nullablePositiveInt(value: unknown): number | null {
  const n = nullableNumber(value);
  if (n == null || n <= 0) return null;
  const rounded = Math.round(n);
  if (Math.abs(n - rounded) > 1e-6) return null;
  return rounded;
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
