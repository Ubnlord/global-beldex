type QueryResult = {
  data?: unknown;
  error?: unknown;
};

/**
 * A cloud book is safe to hydrate only when all financial queries succeeded
 * and the account profile exists. A missing profile must not be converted into
 * zero-valued balances that overwrite the last known local snapshot.
 */
export function isCompleteCloudRefresh(
  profileResult: QueryResult,
  txResult: QueryResult,
  investmentsResult: QueryResult,
): boolean {
  return (
    !profileResult.error &&
    profileResult.data != null &&
    !txResult.error &&
    !investmentsResult.error
  );
}
