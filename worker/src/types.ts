export type OCRLine = {
  text: string;
  x: number;
  y: number;
  width: number;
  height: number;
};

/**
 * What the client captured.
 * - `receipt` — photographed / imported receipt OCR (default).
 * - `email` — HTML order email, already stripped to text lines.
 * - `text` — plain-text share, including Mail → Select All → Share.
 * Unknown or missing values are treated as `receipt`.
 */
export type ExtractSource = "receipt" | "email" | "text";

export type ExtractRequest = {
  lines: OCRLine[];
  /** Optional. Absent on builds that predate email import. */
  source?: ExtractSource;
  /**
   * Optional RC customer identifier. When present + `isProClaimed` is true,
   * the worker verifies with RC before routing to the Pro-tier model.
   */
  appUserID?: string;
  /**
   * Client's local assertion that this customer is Pro. Never trusted on
   * its own — always verified against RC. Absent = free tier, no RC call
   * made (saves latency for the common free-user path).
   */
  isProClaimed?: boolean;
};

export type PassRequest = {
  merchant: string;
  itemName: string;
  total: number;
  currencyCode: string;
  purchaseDate: string;
  coverageEndsAt: string;
  serialNumber: string;
};

export type TrialBoostRequest = {
  /** The customer's RevenueCat appUserID (CloudKit-scoped in Kept). */
  appUserID: string;
};

export type Env = {
  CF_ACCOUNT_ID: string;
  AI_GATEWAY_ID: string;
  /** Free-tier model. e.g. openai/gpt-4o-mini or anthropic/claude-haiku-4-5 */
  LLM_MODEL: string;
  /** Pro-tier model — used when the customer's Pro entitlement is verified
   *  via RC. Falls back to `LLM_MODEL` when unset. e.g. openai/gpt-4o */
  LLM_MODEL_PRO?: string;
  EXTRACT_SECRET: string;
  /** Generic provider key (optional if OPENAI_/ANTHROPIC_ set). */
  LLM_API_KEY?: string;
  OPENAI_API_KEY?: string;
  ANTHROPIC_API_KEY?: string;
  GEMINI_API_KEY?: string;
  /** Optional — only required when the AI Gateway enforces auth. */
  CF_AIG_TOKEN?: string;
  EXTRACT_RATE_LIMIT: RateLimit;

  PASS_TYPE_IDENTIFIER: string;
  TEAM_IDENTIFIER: string;
  SIGNER_CERT_PEM?: string;
  SIGNER_KEY_PKCS8_PEM?: string;
  WWDR_PEM?: string;

  /** RevenueCat REST API secret key — server-only, never exposed to clients. */
  RC_SECRET_KEY?: string;
  /** Entitlement identifier configured in the RC dashboard (e.g. "Kept Pro"). */
  RC_ENTITLEMENT_IDENTIFIER?: string;
};
