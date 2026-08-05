import type { OCRLine } from "./types";

export const SYSTEM_PROMPT = `You extract structured purchase data from OCR lines of a photographed retail receipt.

RULES
- Every field is independently nullable. If unsure, return null. Never fabricate.
- Merchant may be missing because it is only a logo — return null rather than guessing from a website or promo banner.
- Total is the amount actually paid: prefer lines labeled Total, Grand Total, Amount Due, or Balance. Never use subtotal, tax/GST/VAT alone, cash tendered, or change.
- items: every purchased product line with its price. Skip headers, payment rows, tax, change, and the total itself. Cap at ~40 lines; for huge grocery tickets prefer the clearest product lines. Use [] when none are readable.
- itemName: the primary item to track for warranty (highest-value durable good). For a grocery basket, "Grocery shop" is fine even when items[] is filled.
- Dates on UK / Ireland / Australia / NZ / most-of-Europe receipts are DD/MM/YY (or DD/MM/YYYY) unless the receipt clearly shows otherwise. Convert to YYYY-MM-DD.
- Currency: use an explicit ISO code if present (£→GBP, A$/AU$→AUD, bare $ with AU address→AUD, otherwise USD only when that is justified).
- Confidence is per field, 0…1. Low confidence when OCR is noisy or several candidates compete.
- OCR lines include normalised bounding boxes (origin bottom-left). Prefer text near the top for merchant and near labeled totals for price.
- Do not invent warranty or return windows. Those are out of scope for this endpoint.`;

export function buildUserPrompt(lines: OCRLine[]): string {
  const payload = lines.map((line, index) => ({
    i: index,
    text: line.text,
    x: line.x,
    y: line.y,
    w: line.width,
    h: line.height,
  }));
  return `OCR lines (top→bottom reading order already applied by the client):\n${JSON.stringify(payload)}`;
}
