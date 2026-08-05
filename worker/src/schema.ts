/**
 * Structured extraction schema for OpenAI-compatible `response_format.json_schema`.
 * Every field independently nullable — never fabricate.
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
        "Main purchased item short name, or a summary like Grocery shop. Null if unclear.",
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
    "total",
    "currencyCode",
    "purchaseDate",
    "confidence",
  ],
} as const;

export type ExtractionResponse = {
  merchant: string | null;
  itemName: string | null;
  total: number | null;
  currencyCode: string | null;
  purchaseDate: string | null;
  confidence: {
    merchant: number;
    total: number;
    purchaseDate: number;
  };
};
