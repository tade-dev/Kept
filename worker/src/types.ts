export type OCRLine = {
  text: string;
  x: number;
  y: number;
  width: number;
  height: number;
};

export type ExtractRequest = {
  lines: OCRLine[];
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

export type Env = {
  CF_ACCOUNT_ID: string;
  AI_GATEWAY_ID: string;
  /** e.g. openai/gpt-4o-mini or anthropic/claude-haiku-4-5 */
  LLM_MODEL: string;
  EXTRACT_SECRET: string;
  /** Generic provider key (optional if OPENAI_/ANTHROPIC_ set). */
  LLM_API_KEY?: string;
  OPENAI_API_KEY?: string;
  ANTHROPIC_API_KEY?: string;
  /** Optional — only required when the AI Gateway enforces auth. */
  CF_AIG_TOKEN?: string;
  EXTRACT_RATE_LIMIT: RateLimit;

  PASS_TYPE_IDENTIFIER: string;
  TEAM_IDENTIFIER: string;
  SIGNER_CERT_PEM?: string;
  SIGNER_KEY_PKCS8_PEM?: string;
  WWDR_PEM?: string;
};
