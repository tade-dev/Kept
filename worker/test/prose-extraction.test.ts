import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { buildExtractionMessages, buildUserPrompt, SYSTEM_PROMPT } from "../src/prompt";
import { analyseProse, normaliseSource } from "../src/prose";
import { extractionSchemaFor } from "../src/schema";
import type { OCRLine } from "../src/types";

function fixture(name: string): string {
  return readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8");
}

function linesFrom(text: string): OCRLine[] {
  return text
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .map((text, index) => ({
      text,
      x: 0.1,
      y: Math.max(0, 1 - index * 0.02),
      width: 0.8,
      height: 0.02,
    }));
}

test("missing or unknown source stays on the receipt prompt", () => {
  assert.equal(normaliseSource(undefined), "receipt");
  assert.equal(normaliseSource("photo"), "receipt");
  assert.equal(normaliseSource("email"), "email");
  assert.equal(normaliseSource("text"), "text");
});

test("receipt user prompt is still the OCR payload", () => {
  const lines: OCRLine[] = [
    { text: "ASDA", x: 0.1, y: 0.9, width: 0.5, height: 0.04 },
  ];
  const user = buildUserPrompt(lines);
  assert.equal(
    user,
    `OCR lines (top→bottom reading order already applied by the client). Extract per the schema and rules above.\n${JSON.stringify([{ i: 0, text: "ASDA", x: 0.1, y: 0.9, w: 0.5, h: 0.04 }])}`,
  );
  assert.match(SYSTEM_PROMPT, /photographed retail receipt/);
});

test("Mail Select-All plain text: order total and order date, not the quoted sale price", () => {
  const raw = fixture("mail-select-all-harbor.txt");
  const messages = buildExtractionMessages("text", linesFrom(raw));

  assert.match(messages.system, /Select All/);
  assert.doesNotMatch(messages.system, /photographed retail receipt/);
  assert.match(messages.user, /Likely merchant: Harbor & Co/);
  assert.match(messages.user, /Likely order date: 2026-06-18/);
  assert.match(messages.user, /Likely amount charged: 37\.95 GBP/);
  assert.match(messages.user, /Linen apron, oat/);
  assert.match(messages.user, /Order Total: £37\.95/);
  assert.doesNotMatch(messages.user, /19\.00/);
  assert.doesNotMatch(messages.user, /Sent from my iPhone/);
  assert.doesNotMatch(messages.user, /Unsubscribe/);
  assert.doesNotMatch(messages.user, /Registered office/);
  assert.match(messages.user, /Do not use these other amounts: 34\.00 GBP/);

  const receipt = buildExtractionMessages("receipt", linesFrom(raw));
  assert.equal(receipt.system, SYSTEM_PROMPT);
  assert.match(receipt.user, /19\.00/);
  assert.match(receipt.user, /photographed|OCR lines/);
  assert.doesNotMatch(receipt.user, /Likely amount charged/);
});

test("HTML-stripped email without headers still prefers the order total over subtotal", () => {
  const analysis = analyseProse(fixture("stripped-order-harbor.txt"));
  assert.equal(analysis.guide.merchantHint, "Harbor & Co");
  assert.equal(analysis.guide.orderDate, "2026-06-18");
  assert.equal(analysis.guide.chargedTotal?.amount, 37.95);
  assert.equal(analysis.guide.chargedTotal?.currency, "GBP");
  assert.ok(analysis.guide.ignoredAmounts.some((item) => item.amount === 34));
  assert.ok(analysis.guide.ignoredAmounts.some((item) => item.amount === 3.95));
  // The arrival date stays in the body (the model can see it) but the guide
  // must not promote it over the labelled order date.
  assert.match(analysis.body, /22 June 2026/);
  assert.notEqual(analysis.guide.orderDate, "2026-06-22");
});

test("amount-charged email ignores the ship date and the quoted lower price", () => {
  const raw = fixture("amount-charged-cedar.txt");
  const messages = buildExtractionMessages("email", linesFrom(raw));
  assert.match(messages.user, /Likely merchant: Cedar Supply/);
  assert.match(messages.user, /Likely order date: 2026-03-03/);
  assert.match(messages.user, /Likely amount charged: 48\.20 USD/);
  assert.doesNotMatch(messages.user, /29\.00/);
  assert.doesNotMatch(messages.user, /2026-03-09/);
  assert.doesNotMatch(messages.user, /2026-03-02/);
  assert.match(
    extractionSchemaFor("email").properties.merchant.description ?? "",
    /From:/,
  );
  assert.match(
    extractionSchemaFor("receipt").properties.merchant.description,
    /Storefront/,
  );
});

test("a note with no purchase does not invent a charged total", () => {
  const analysis = analyseProse(`From: Harbor & Co <news@harborandco.example>
Subject: This week at Harbor

Hi Riley,

Our spring lookbook is up. Nothing was purchased in this note.

Unsubscribe | Privacy policy
`);
  assert.equal(analysis.guide.merchantHint, "Harbor & Co");
  assert.equal(analysis.guide.orderDate, null);
  assert.equal(analysis.guide.chargedTotal, null);
  assert.doesNotMatch(analysis.body, /Unsubscribe/);
});
