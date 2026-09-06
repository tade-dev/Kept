import type { Env, TrialBoostRequest } from "./types";
import { UpstreamError } from "./llm";

/**
 * Grants a 7-day "Kept Pro" promotional entitlement to the given
 * RevenueCat app user via RC's REST API. Called by the iOS app after it
 * detects a "highly engaged in the first 24h" signal (see the
 * TrialBoostService in Swift).
 *
 * Behind a secret only the app can hit, so we don't need any client-side
 * eligibility gating on RC's side — the engagement check runs in the app
 * and we trust it. If we ever move engagement detection off-device this
 * function is the natural place to also enforce it here.
 */
export async function grantTrialBoost(
  env: Env,
  request: TrialBoostRequest,
): Promise<void> {
  if (!env.RC_SECRET_KEY) {
    throw new UpstreamError("Trial boost is not configured.", 500);
  }
  if (!env.RC_ENTITLEMENT_IDENTIFIER) {
    throw new UpstreamError("Trial boost entitlement is not configured.", 500);
  }

  // RC REST API path uses the entitlement identifier and app user id
  // verbatim. We URL-encode both because both allow characters that would
  // break the path otherwise (RC's default anonymous ids contain colons).
  const url =
    `https://api.revenuecat.com/v1/subscribers/` +
    `${encodeURIComponent(request.appUserID)}` +
    `/entitlements/${encodeURIComponent(env.RC_ENTITLEMENT_IDENTIFIER)}` +
    `/promotional`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      // RC accepts a static secret key here — this MUST stay server-side.
      authorization: `Bearer ${env.RC_SECRET_KEY}`,
      "x-platform": "ios",
    },
    // "weekly" = exactly 7 days per RC's fixed-duration enum. If we ever
    // want a different length swap for `{ duration: "custom",
    // custom_duration_ms: N }`.
    body: JSON.stringify({ duration: "weekly" }),
  });

  if (response.status === 201 || response.status === 200) {
    return;
  }

  // Surface RC's own error shape when possible so we can debug from the
  // Worker logs without exposing secrets.
  let detail = "unknown";
  try {
    const body = (await response.json()) as { message?: string };
    if (body?.message) detail = body.message;
  } catch {
    // ignore
  }
  console.error("trial_boost_failed", {
    status: response.status,
    detail: detail.slice(0, 200),
  });
  throw new UpstreamError("Couldn't grant the trial boost.", 502);
}

export function parseTrialBoostRequest(body: unknown): TrialBoostRequest | null {
  if (!body || typeof body !== "object") return null;
  const obj = body as Record<string, unknown>;
  const appUserID = typeof obj.appUserID === "string" ? obj.appUserID.trim() : "";
  if (!appUserID) return null;
  return { appUserID };
}
