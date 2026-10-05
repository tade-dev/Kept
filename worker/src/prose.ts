import type { ExtractSource, OCRLine } from "./types";

/**
 * Plain-text / email shares are not receipt OCR. Mail's Select All → Share
 * path in particular includes headers, a quoted reply, a signature, and
 * legal footer. This pass drops that noise and pulls out the few facts
 * the model otherwise confuses with a photographed receipt: who sold it,
 * the order date (not the delivery date), and the amount charged (not a
 * subtotal or a price from an earlier message).
 */

export type MoneyMention = {
  amount: number;
  currency: string | null;
  label: string;
};

export type ProseReadingGuide = {
  merchantHint: string | null;
  /** YYYY-MM-DD when a labelled order date wins. Null when the only dates are deliveries. */
  orderDate: string | null;
  chargedTotal: MoneyMention | null;
  ignoredAmounts: MoneyMention[];
};

export type ProseAnalysis = {
  body: string;
  guide: ProseReadingGuide;
};

const FOOTER_MARKERS = [
  "unsubscribe",
  "privacy policy",
  "terms and conditions",
  "terms of service",
  "all rights reserved",
  "registered office",
  "do not reply",
  "this email was sent",
  "you are receiving this email",
  "you're receiving this email",
  "you’re receiving this email",
  "view this email in your browser",
  "manage your email preferences",
  "manage email preferences",
  "notification-only",
];

const MONTHS: Record<string, number> = {
  january: 1,
  jan: 1,
  february: 2,
  feb: 2,
  march: 3,
  mar: 3,
  april: 4,
  apr: 4,
  may: 5,
  june: 6,
  jun: 6,
  july: 7,
  jul: 7,
  august: 8,
  aug: 8,
  september: 9,
  sep: 9,
  sept: 9,
  october: 10,
  oct: 10,
  november: 11,
  nov: 11,
  december: 12,
  dec: 12,
};

const MONTH_PATTERN = Object.keys(MONTHS)
  .sort((a, b) => b.length - a.length)
  .join("|");

const ORDER_DATE =
  /\b(order date|ordered on|date of order|purchase date|date ordered|date placed|placed on)\b/i;
const SKIP_DATE =
  /\b(deliver|arrival|arriving|ships|shipping date|dispatch|dispatched|estimated delivery)\b/i;
const STRONG_TOTAL =
  /\b(order\s*total|grand\s*total|amount\s*charged|amount\s*paid|total\s*charged|you\s*paid|total\s*paid|payment\s*total)\b/i;
const MEDIUM_TOTAL = /\b(balance\s*due|amount\s*due)\b/i;
const IGNORE_MONEY =
  /\b(sub-?total|item\s*price|items?\s*subtotal|postage|shipping|delivery\s*charge|packing|tax|vat|gst|discount|saving|you\s*saved)\b/i;
const WEAK_TOTAL = /\btotal\b/i;

const MONEY_RE =
  /(?:(?<pre>USD|GBP|EUR|£|\$|€)\s*)(?<amt>\d{1,6}(?:[.,]\d{2})?)|(?<amt2>\d{1,6}[.,]\d{2})\s*(?<post>USD|GBP|EUR|£|\$|€)/gi;

export function normaliseSource(value: unknown): ExtractSource {
  if (value === "email" || value === "text") return value;
  return "receipt";
}

export function isProseSource(source: ExtractSource): boolean {
  return source === "email" || source === "text";
}

export function prepareProseLines(lines: OCRLine[]): OCRLine[] {
  const raw = lines.map((line) => line.text).join("\n");
  const { body } = analyseProse(raw);
  const next: OCRLine[] = body
    .split("\n")
    .map((text) => text.trim())
    .filter((text) => text.length > 0)
    .map((text) => ({ text, x: 0, y: 0, width: 0, height: 0 }));
  return next.length > 0 ? next : lines;
}

export function analyseProse(raw: string): ProseAnalysis {
  const body = cleanProse(raw);
  const lines = body
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  return {
    body: lines.join("\n"),
    guide: {
      merchantHint: merchantHint(body, lines),
      orderDate: orderDate(lines),
      ...moneyGuide(lines),
    },
  };
}

export function cleanProse(raw: string): string {
  const lines = raw.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
  let cut = lines.length;
  for (let i = 1; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    if (
      isQuoteIntroducer(trimmed) ||
      isSignatureDelimiter(trimmed) ||
      isDeviceSignature(trimmed)
    ) {
      cut = i;
      break;
    }
  }
  const kept = lines.slice(0, cut).filter((line) => {
    const trimmed = line.trim();
    if (!trimmed) return true;
    if (isQuotedLine(trimmed)) return false;
    if (isLegalLine(trimmed)) return false;
    return true;
  });
  return kept
    .join("\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function isQuoteIntroducer(line: string): boolean {
  if (/^on .+ wrote:\s*$/i.test(line)) return true;
  if (/^-{5,}\s*original message\s*-{5,}$/i.test(line)) return true;
  if (/^_{5,}\s*$/.test(line)) return true;
  return false;
}

function isSignatureDelimiter(line: string): boolean {
  return /^--\s*$/.test(line);
}

function isDeviceSignature(line: string): boolean {
  return (
    /^sent from my (iphone|ipad|android|galaxy|pixel)\b/i.test(line) ||
    /^get outlook for \w+/i.test(line)
  );
}

function isQuotedLine(line: string): boolean {
  return /^>\s?/.test(line);
}

function isLegalLine(line: string): boolean {
  if (extractMoney(line).length > 0) return false;
  const lower = line.toLowerCase();
  return FOOTER_MARKERS.some((marker) => lower.includes(marker));
}

function merchantHint(body: string, lines: string[]): string | null {
  const from = fromDisplayName(body);
  if (from) return from;
  const first = lines.find((line) => line.length > 0 && line.length <= 48);
  if (!first) return null;
  if (/^(hi|hello|hey|dear|thanks|thank you|order confirmation|your order|receipt|invoice)\b/i.test(first)) {
    return null;
  }
  if (first.includes("@") || /^from:/i.test(first) || /^to:/i.test(first)) return null;
  return first;
}

function fromDisplayName(body: string): string | null {
  const line = body.split("\n").find((row) => /^from:/i.test(row.trim()));
  if (!line) return null;
  const quoted = line.match(/^from:\s*"([^"]+)"/i);
  if (quoted) {
    const name = cleanName(quoted[1]);
    if (name) return name;
  }
  const angle = line.match(/^from:\s*([^<]+)</i);
  if (angle) {
    const name = cleanName(angle[1]);
    if (name && !name.includes("@")) return name;
  }
  const domain = line.match(/@([a-z0-9.-]+\.[a-z]{2,})/i);
  if (domain) return brandFromDomain(domain[1]);
  return null;
}

function cleanName(value: string): string | null {
  const trimmed = value.replace(/\s+/g, " ").trim().replace(/^"|"$/g, "");
  return trimmed.length > 0 ? trimmed : null;
}

function brandFromDomain(domain: string): string {
  const parts = domain.toLowerCase().split(".").filter(Boolean);
  const secondLevel = new Set(["co", "com", "org", "net", "ac", "gov"]);
  let index = Math.max(parts.length - 2, 0);
  if (index > 0 && secondLevel.has(parts[index])) index -= 1;
  const brand = parts[index] ?? domain;
  return brand.charAt(0).toUpperCase() + brand.slice(1);
}

function orderDate(lines: string[]): string | null {
  let bestIso: string | null = null;
  let bestScore = 0;
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    const iso = parseLooseDate(line);
    if (!iso) continue;
    let score = 10;
    if (ORDER_DATE.test(line)) score = 100;
    else if (/^date:/i.test(line.trim())) score = 40;
    else if (/\binvoice date\b/i.test(line)) score = 30;
    else if (SKIP_DATE.test(line)) score = 0;
    if (score === 0) continue;
    if (bestIso === null || score > bestScore) {
      bestIso = iso;
      bestScore = score;
    }
  }
  return bestIso;
}

function parseLooseDate(line: string): string | null {
  const iso = line.match(/\b(20\d{2})-(\d{2})-(\d{2})\b/);
  if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`;

  const dayMonth = line.match(
    new RegExp(String.raw`\b(\d{1,2})\s+(${MONTH_PATTERN})\.?\s+(20\d{2})\b`, "i"),
  );
  if (dayMonth) {
    return formatISO(Number(dayMonth[3]), MONTHS[dayMonth[2].toLowerCase()], Number(dayMonth[1]));
  }

  const monthDay = line.match(
    new RegExp(String.raw`\b(${MONTH_PATTERN})\.?\s+(\d{1,2}),?\s+(20\d{2})\b`, "i"),
  );
  if (monthDay) {
    return formatISO(Number(monthDay[3]), MONTHS[monthDay[1].toLowerCase()], Number(monthDay[2]));
  }
  return null;
}

function formatISO(year: number, month: number, day: number): string | null {
  if (!month || day < 1 || day > 31 || month < 1 || month > 12) return null;
  const mm = String(month).padStart(2, "0");
  const dd = String(day).padStart(2, "0");
  return `${year}-${mm}-${dd}`;
}

function moneyGuide(lines: string[]): {
  chargedTotal: MoneyMention | null;
  ignoredAmounts: MoneyMention[];
} {
  const ignoredAmounts: MoneyMention[] = [];
  let chargedTotal: MoneyMention | null = null;
  let bestScore = 0;

  for (const line of lines) {
    const amounts = extractMoney(line);
    if (amounts.length === 0) continue;
    const chosen = amounts[amounts.length - 1];
    const mention: MoneyMention = {
      amount: chosen.amount,
      currency: chosen.currency,
      label: line.trim().slice(0, 80),
    };
    const score = scoreMoneyLine(line);
    if (score < 0) {
      ignoredAmounts.push(mention);
      continue;
    }
    if (score === 0) continue;
    // Later lines win ties so the final "Order Total" beats an earlier "Total".
    if (chargedTotal === null || score >= bestScore) {
      chargedTotal = mention;
      bestScore = score;
    }
  }

  return { chargedTotal, ignoredAmounts };
}

function scoreMoneyLine(line: string): number {
  if (STRONG_TOTAL.test(line)) return 100;
  if (MEDIUM_TOTAL.test(line)) return 80;
  if (IGNORE_MONEY.test(line)) return -1;
  if (WEAK_TOTAL.test(line)) return 50;
  return 0;
}

function extractMoney(line: string): Array<{ amount: number; currency: string | null }> {
  const out: Array<{ amount: number; currency: string | null }> = [];
  const pattern = new RegExp(MONEY_RE.source, "gi");
  for (const match of line.matchAll(pattern)) {
    const raw = match.groups?.amt ?? match.groups?.amt2;
    const symbol = match.groups?.pre ?? match.groups?.post ?? null;
    if (!raw) continue;
    const amount = parseAmount(raw);
    if (amount == null) continue;
    out.push({ amount, currency: currencyFromSymbol(symbol) });
  }
  return out;
}

function parseAmount(raw: string): number | null {
  let value = raw.trim();
  if (/^\d{1,3}(,\d{3})+(\.\d{2})$/.test(value)) value = value.replace(/,/g, "");
  else if (/^\d+,\d{2}$/.test(value)) value = value.replace(",", ".");
  const amount = Number(value);
  return Number.isFinite(amount) ? amount : null;
}

function currencyFromSymbol(symbol: string | null): string | null {
  if (!symbol) return null;
  switch (symbol.toUpperCase()) {
    case "£":
    case "GBP":
      return "GBP";
    case "€":
    case "EUR":
      return "EUR";
    case "USD":
      return "USD";
    default:
      // Bare "$" is ambiguous (USD / CAD / AUD). Leave it for the model.
      return null;
  }
}
