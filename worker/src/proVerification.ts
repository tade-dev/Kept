import type { Env } from "./types";

/**
 * Confirms that the given RevenueCat appUserID currently holds an active
 * `Kept Pro` entitlement. Used by `/extract` to authorise the Pro-tier
 * model without trusting the client's own `isPro` claim.
 *
 * Fails closed: any RC error / network hiccup / missing config → returns
 * `false`. Worst case is a genuine Pro user getting the free model on one
 * extract, which is a graceful degradation (extractions still work).
 * Beats accidentally serving the premium model to a free user because a
 * transient error blew past our check.
 */
export async function isKeptPro(
  env: Env,
  appUserID: string,
): Promise<boolean> {
  if (!env.RC_SECRET_KEY || !env.RC_ENTITLEMENT_IDENTIFIER) return false;
  if (!appUserID) return false;

  const url =
    `https://api.revenuecat.com/v1/subscribers/` +
    `${encodeURIComponent(appUserID)}`;

  let response: Response;
  try {
    response = await fetch(url, {
      headers: {
        authorization: `Bearer ${env.RC_SECRET_KEY}`,
        "x-platform": "ios",
      },
      // Short timeout so a stuck RC request doesn't stall a Pro user's
      // extract — the Worker's overall extract path budgets ~10s for the
      // LLM, and we don't want to eat much of that on entitlement checks.
      signal: AbortSignal.timeout(3000),
    });
  } catch {
    return false;
  }

  if (!response.ok) return false;

  let body: RcSubscriberResponse;
  try {
    body = (await response.json()) as RcSubscriberResponse;
  } catch {
    return false;
  }

  const entitlement =
    body.subscriber?.entitlements?.[env.RC_ENTITLEMENT_IDENTIFIER];
  if (!entitlement) return false;

  // `expires_date` is null on lifetime purchases and non-null on subs.
  // Non-null + past = expired; non-null + future or null = active.
  if (entitlement.expires_date) {
    const expiresAt = Date.parse(entitlement.expires_date);
    if (!Number.isNaN(expiresAt) && expiresAt <= Date.now()) return false;
  }

  return true;
}

type RcSubscriberResponse = {
  subscriber?: {
    entitlements?: Record<string, RcEntitlement>;
  };
};

type RcEntitlement = {
  /** ISO 8601 timestamp; null for non-expiring (lifetime) entitlements. */
  expires_date: string | null;
  product_identifier?: string;
};
