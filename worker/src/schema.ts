/**
 * Structured extraction schema for OpenAI-compatible `response_format.json_schema`.
 * Every field independently nullable (except items — use []). Never fabricate.
 */
export const extractionResponseSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    reasoning: {
      type: "string",
      description:
        "One or two short sentences: identify the header block, locate the Total anchor line, name the currency signal you used, and note any tricky items (dual currency, fragmented OCR, printed warranty / return policy, etc.). Keep under 40 words. Client discards this field.",
    },
    documentType: {
      type: "string",
      description:
        "Kind of document. Use 'receipt' for anything that proves a purchase (retail receipt, invoice, sales slip, ticket confirmation with total, restaurant bill). Use one of these when NOT a receipt: 'passport', 'id_card', 'business_card', 'handwritten_note', 'menu', 'letter', 'other'. When not 'receipt', return null for every extraction field.",
    },
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
    category: {
      type: ["string", "null"],
      description:
        "Short human-friendly bucket for the receipt (e.g. 'Groceries', 'Restaurant', 'Fashion', 'Electronics', 'Home', 'Repair', 'Fuel', 'Travel', 'Beauty', 'Books', 'Other'). Used as the receipt's subtitle in the app UI — should be recognisable at a glance.",
      enum: [
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
        null,
      ],
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
    "reasoning",
    "documentType",
    "merchant",
    "itemName",
    "category",
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
  /** Scratchpad the model uses to think before answering. Dropped in llm.ts. */
  reasoning?: string;
  documentType: string;
  merchant: string | null;
  itemName: string | null;
  category: string | null;
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
