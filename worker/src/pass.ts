import { zipSync } from "fflate";
import { createOpenSslCompatiblePkcs7Signature } from "@swapnanildhol/passkit-pkcs7-signature";
import {
  icon_png,
  icon_2x_png,
  icon_3x_png,
  logo_png,
  logo_2x_png,
} from "./passAssets";
import type { Env, PassRequest } from "./types";
import { UpstreamError } from "./llm";

// Build filenames with String.fromCharCode(64) so `@` is not mangled by tooling.
const at = String.fromCharCode(64);
const ASSETS: Record<string, Uint8Array> = {
  ["icon.png"]: icon_png,
  ["icon" + at + "2x.png"]: icon_2x_png,
  ["icon" + at + "3x.png"]: icon_3x_png,
  ["logo.png"]: logo_png,
  ["logo" + at + "2x.png"]: logo_2x_png,
};

export function parsePassRequest(body: unknown): PassRequest | null {
  if (!body || typeof body !== "object") return null;
  const obj = body as Record<string, unknown>;
  const merchant = stringField(obj.merchant);
  const itemName = stringField(obj.itemName);
  const currencyCode = stringField(obj.currencyCode);
  const purchaseDate = stringField(obj.purchaseDate);
  const coverageEndsAt = stringField(obj.coverageEndsAt);
  const serialNumber = stringField(obj.serialNumber);
  const total = typeof obj.total === "number" && Number.isFinite(obj.total) ? obj.total : null;

  if (
    !merchant ||
    !itemName ||
    total === null ||
    !currencyCode ||
    !purchaseDate ||
    !coverageEndsAt ||
    !serialNumber
  ) {
    return null;
  }

  return {
    merchant,
    itemName,
    total,
    currencyCode: currencyCode.toUpperCase(),
    purchaseDate,
    coverageEndsAt,
    serialNumber,
  };
}

export async function buildSignedPass(
  env: Env,
  request: PassRequest,
): Promise<Uint8Array> {
  const passTypeIdentifier = env.PASS_TYPE_IDENTIFIER;
  const teamIdentifier = env.TEAM_IDENTIFIER;
  const signerCertPem = normalizePem(env.SIGNER_CERT_PEM);
  const privateKeyPkcs8Pem = normalizePem(env.SIGNER_KEY_PKCS8_PEM);
  const wwdrPem = normalizePem(env.WWDR_PEM);

  if (!passTypeIdentifier || !teamIdentifier) {
    throw new UpstreamError("Pass type / team identifier is not configured.", 500);
  }
  if (!signerCertPem || !privateKeyPkcs8Pem || !wwdrPem) {
    throw new UpstreamError("Pass signing certificates are not configured.", 500);
  }

  const passJson = buildPassJson(env, request);
  const files: Record<string, Uint8Array> = {
    "pass.json": new TextEncoder().encode(JSON.stringify(passJson)),
    ...ASSETS,
  };

  const manifest: Record<string, string> = {};
  for (const [name, bytes] of Object.entries(files)) {
    manifest[name] = await sha1Hex(bytes);
  }
  const manifestJson = JSON.stringify(manifest);
  const manifestBytes = new TextEncoder().encode(manifestJson);

  let signature: Uint8Array;
  try {
    signature = await createOpenSslCompatiblePkcs7Signature({
      manifest: manifestJson,
      signerCertPem,
      privateKeyPkcs8Pem,
      wwdrPem,
    });
  } catch {
    throw new UpstreamError("Pass signing failed.", 500);
  }

  const zipInput: Record<string, Uint8Array> = {
    ...files,
    "manifest.json": manifestBytes,
    signature,
  };

  return zipSync(zipInput, { level: 6 });
}

/** Ink warranty-stub palette — keep in sync with scripts/generate-pass-assets.py */
const PASS_THEME = {
  calm: {
    backgroundColor: "rgb(24, 38, 48)",
    foregroundColor: "rgb(245, 242, 236)",
    labelColor: "rgb(214, 168, 106)",
  },
  urgent: {
    backgroundColor: "rgb(42, 28, 24)",
    foregroundColor: "rgb(245, 242, 236)",
    labelColor: "rgb(232, 140, 90)",
  },
  expired: {
    backgroundColor: "rgb(36, 36, 40)",
    foregroundColor: "rgb(220, 218, 214)",
    labelColor: "rgb(168, 160, 152)",
  },
} as const;

function buildPassJson(env: Env, request: PassRequest) {
  const ends = new Date(request.coverageEndsAt);
  const endsValid = !Number.isNaN(ends.getTime());
  const daysRemaining = endsValid
    ? Math.max(0, Math.ceil((ends.getTime() - Date.now()) / 86_400_000))
    : 0;

  const money = formatMoney(request.total, request.currencyCode);
  const expiryLabel = endsValid ? isoDateOnly(ends) : request.coverageEndsAt;
  const theme =
    daysRemaining <= 0
      ? PASS_THEME.expired
      : daysRemaining < 14
        ? PASS_THEME.urgent
        : PASS_THEME.calm;

  const daysLabel =
    daysRemaining <= 0 ? "ENDED" : daysRemaining === 1 ? "DAY LEFT" : "DAYS LEFT";

  return {
    formatVersion: 1,
    passTypeIdentifier: env.PASS_TYPE_IDENTIFIER,
    serialNumber: request.serialNumber,
    teamIdentifier: env.TEAM_IDENTIFIER,
    organizationName: "Kept",
    description: `${request.itemName} · coverage countdown`,
    foregroundColor: theme.foregroundColor,
    backgroundColor: theme.backgroundColor,
    labelColor: theme.labelColor,
    // Wordmark lives in logo.png — empty logoText avoids "Kept Kept".
    logoText: "",
    expirationDate: endsValid ? ends.toISOString() : undefined,
    relevantDate: endsValid ? ends.toISOString() : undefined,
    generic: {
      headerFields: [
        {
          key: "days",
          label: daysLabel,
          value: String(daysRemaining),
          textAlignment: "PKTextAlignmentRight",
        },
      ],
      primaryFields: [
        {
          key: "item",
          label: "ITEM",
          value: request.itemName,
        },
      ],
      secondaryFields: [
        {
          key: "merchant",
          label: "STORE",
          value: request.merchant,
        },
        {
          key: "price",
          label: "PAID",
          value: money,
          textAlignment: "PKTextAlignmentRight",
        },
      ],
      auxiliaryFields: [
        {
          key: "expires",
          label: "COVER ENDS",
          value: expiryLabel,
        },
        {
          key: "purchased",
          label: "PURCHASED",
          value: request.purchaseDate,
          textAlignment: "PKTextAlignmentRight",
        },
      ],
      backFields: [
        {
          key: "serial",
          label: "Serial",
          value: request.serialNumber,
        },
        {
          key: "about",
          label: "About Kept",
          value:
            "Kept tracks when your warranty or return window ends. This pass keeps the countdown in Wallet until cover ends.",
        },
      ],
    },
  };
}

function stringField(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function normalizePem(value: string | undefined): string | undefined {
  if (!value) return undefined;
  let trimmed = value.trim();
  // Wrangler / .dev.vars may keep surrounding quotes.
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    trimmed = trimmed.slice(1, -1);
  }
  if (!trimmed) return undefined;
  // Allow .dev.vars single-line PEMs with literal \n sequences.
  return trimmed.includes("\\n") ? trimmed.replace(/\\n/g, "\n") : trimmed;
}

async function sha1Hex(data: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-1", data);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function isoDateOnly(date: Date): string {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function formatMoney(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat("en-GB", {
      style: "currency",
      currency,
      maximumFractionDigits: 2,
    }).format(amount);
  } catch {
    return `${amount.toFixed(2)} ${currency}`;
  }
}
