/**
 * Structured extraction schema for OpenAI-compatible `response_format.json_schema`.
 * Every field independently nullable (except items — use []). Never fabricate.
 */
export const extractionResponseSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    merchant: {
      type: ["string", "null"],
      description:
        "Storefront / retailer name if printed as text. Null when only a logo is present or the name is unreadable.",
    },
    itemName: {
      type: ["string", "null"],
      description:
        "Primary item for warranty tracking: highest-value durable good, or a short summary like Grocery shop when many small lines. Null if unclear.",
    },
    items: {
      type: "array",
      description:
        "Purchased line items with unit/line prices. Exclude subtotal, tax, tender, change, discounts-as-payment, and the grand total row. Empty array if none can be read.",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          name: {
            type: "string",
            description: "Short product name as printed (cleaned).",
          },
          price: {
            type: "number",
            description: "Line price as a positive decimal. No currency symbol.",
          },
        },
        required: ["name", "price"],
      },
    },
    total: {
      type: ["number", "null"],
      description:
        "Amount actually paid (Total / Amount due / Grand total). Not subtotal, tax, tendered cash, or change.",
    },
    currencyCode: {
      type: ["string", "null"],
      description: "ISO 4217 code such as GBP, AUD, USD. Null if unknown.",
    },
    purchaseDate: {
      type: ["string", "null"],
      description: "Purchase date as YYYY-MM-DD. Null if no date is present.",
    },
    returnWindowDays: {
      type: ["number", "null"],
      description:
        "Return/refund/exchange window in days ONLY when printed on the receipt (e.g. 14, 28, 30, or days until a printed deadline). Null when not stated. Never invent a default.",
    },
    returnWindowIsInferred: {
      type: "boolean",
      description:
        "Must be false when returnWindowDays is set from printed text. False when returnWindowDays is null.",
    },
    warrantyDurationMonths: {
      type: ["number", "null"],
      description:
        "Warranty/guarantee length in months ONLY when printed (convert years → months). Null when not stated. Never invent a default.",
    },
    warrantyIsInferred: {
      type: "boolean",
      description:
        "Must be false when warrantyDurationMonths is set from printed text. False when warrantyDurationMonths is null.",
    },
    confidence: {
      type: "object",
      additionalProperties: false,
      description: "Per-field confidence in [0, 1].",
      properties: {
        merchant: { type: "number" },
        total: { type: "number" },
        purchaseDate: { type: "number" },
      },
      required: ["merchant", "total", "purchaseDate"],
    },
  },
  required: [
    "merchant",
    "itemName",
    "items",
    "total",
    "currencyCode",
    "purchaseDate",
    "returnWindowDays",
    "returnWindowIsInferred",
    "warrantyDurationMonths",
    "warrantyIsInferred",
    "confidence",
  ],
} as const;

export type ExtractionResponse = {
  merchant: string | null;
  itemName: string | null;
  items: Array<{ name: string; price: number }>;
  total: number | null;
  currencyCode: string | null;
  purchaseDate: string | null;
  returnWindowDays: number | null;
  returnWindowIsInferred: boolean;
  warrantyDurationMonths: number | null;
  warrantyIsInferred: boolean;
  confidence: {
    merchant: number;
    total: number;
    purchaseDate: number;
  };
};
