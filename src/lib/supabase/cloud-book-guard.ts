type QueryResult = {
  data?: unknown;
  error?: unknown;
};

const requiredBalanceFields = [
  "available_balance",
  "locked_balance",
  "total_withdrawals",
  "bdx_balance",
  "referral_earnings",
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasValidBalances(value: unknown): boolean {
  if (!isRecord(value)) return false;
  return requiredBalanceFields.every((field) => {
    const amount = value[field];
    return amount !== null && amount !== undefined && amount !== "" &&
      Number.isFinite(typeof amount === "number" ? amount : Number(amount));
  });
}

function isArrayData(value: unknown): value is unknown[] {
  return Array.isArray(value);
}

/**
 * A cloud book is safe to hydrate only when every required query completed
 * without error, the profile exists with all required numeric balance fields,
 * and both ledgers are actual arrays. Empty arrays are valid; missing/null
 * data is not, because it must never be mistaken for an empty financial ledger.
 */
export function isCompleteCloudRefresh(
  profileResult: QueryResult,
  txResult: QueryResult,
  investmentsResult: QueryResult,
): boolean {
  return (
    !profileResult.error &&
    hasValidBalances(profileResult.data) &&
    !txResult.error &&
    isArrayData(txResult.data) &&
    !investmentsResult.error &&
    isArrayData(investmentsResult.data)
  );
}
