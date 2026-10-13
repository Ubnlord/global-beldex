/**
 * Pure conversion primitives. This module never fetches quotes, reads browser
 * storage, or mutates balances. A trusted server caller must supply a fresh
 * quote from the website's live market provider.
 */
export type FreshBdxQuote = {
  usdPerBdx: number;
  source: string;
  observedAt: string;
  providerTimestamp?: string;
};
export type ConversionAmount = {
  originalUsd: string;
  bdxUnits: string;
  roundingRemainderBdxNumerator: string;
  roundingRemainderBdxDenominator: string;
};
export type QuotePolicy = {
  maxAgeMs: number;
  nowMs: number;
  allowedSources: readonly string[];
  minUsdPerBdx: number;
  maxUsdPerBdx: number;
};

export function validateFreshBdxQuote(quote: FreshBdxQuote | null | undefined, policy: QuotePolicy): FreshBdxQuote {
  if (!quote) throw new Error("Fresh BDX market quote required");
  if (!policy.allowedSources.includes(quote.source)) throw new Error("Unapproved BDX quote source");
  if (!Number.isFinite(quote.usdPerBdx) || quote.usdPerBdx < policy.minUsdPerBdx || quote.usdPerBdx > policy.maxUsdPerBdx) {
    throw new Error("BDX quote outside approved price bounds");
  }
  const observed = Date.parse(quote.observedAt);
  if (!Number.isFinite(observed) || observed > policy.nowMs || policy.nowMs - observed > policy.maxAgeMs) {
    throw new Error("BDX quote is stale or has an invalid timestamp");
  }
  if (quote.providerTimestamp !== undefined) {
    const providerTime = Date.parse(quote.providerTimestamp);
    if (!Number.isFinite(providerTime) || providerTime > policy.nowMs || policy.nowMs - providerTime > policy.maxAgeMs) {
      throw new Error("Provider BDX quote is stale or has an invalid timestamp");
    }
  }
  return quote;
}

/** Decimal-string conversion. The sub-scale remainder is retained as an exact rational. */
export function convertUsdToBdx(usdAmount: string, usdPerBdx: string, bdxScale = 18): ConversionAmount {
  if (!/^\d+(?:\.\d+)?$/.test(usdAmount) || !/^\d+(?:\.\d+)?$/.test(usdPerBdx)) {
    throw new Error("Amounts must be non-negative decimal strings");
  }
  if (!Number.isInteger(bdxScale) || bdxScale < 0 || bdxScale > 30) throw new Error("Invalid BDX decimal scale");
  const [usdWhole, usdFrac = ""] = usdAmount.split(".");
  const [rateWhole, rateFrac = ""] = usdPerBdx.split(".");
  const usdScale = usdFrac.length;
  const rateScale = rateFrac.length;
  const usdInt = BigInt(usdWhole + usdFrac);
  const rateInt = BigInt(rateWhole + rateFrac);
  if (rateInt <= 0n) throw new Error("BDX price must be positive");
  const numerator = usdInt * 10n ** BigInt(rateScale + bdxScale);
  const denominator = rateInt * 10n ** BigInt(usdScale);
  const unitsInt = numerator / denominator;
  const remainderNumerator = numerator % denominator;
  const scaleFactor = 10n ** BigInt(bdxScale);
  const unitsWhole = unitsInt / scaleFactor;
  const unitsFraction = (unitsInt % scaleFactor).toString().padStart(bdxScale, "0").replace(/0+$/, "");
  const bdxUnits = unitsFraction ? `${unitsWhole}.${unitsFraction}` : unitsWhole.toString();
  // Exact remaining BDX fraction below the configured BDX unit scale.
  return {
    originalUsd: usdAmount,
    bdxUnits,
    roundingRemainderBdxNumerator: remainderNumerator.toString(),
    roundingRemainderBdxDenominator: (denominator * scaleFactor).toString(),
  };
}

/** Display-only valuation; this function cannot change the source BDX units. */
export function bdxUsdDisplay(bdxUnits: string, liveUsdPerBdx: number): number {
  if (!/^\d+(?:\.\d+)?$/.test(bdxUnits) || !Number.isFinite(liveUsdPerBdx) || liveUsdPerBdx <= 0) {
    throw new Error("Valid BDX units and live market price required");
  }
  return Number(bdxUnits) * liveUsdPerBdx;
}
