/** Run a refresh without allowing rejected network/RPC promises to escape. */
export async function runWithFailureFallback<T>(
  operation: () => Promise<T>,
  onFailure: () => void,
): Promise<T | null> {
  try {
    return await operation();
  } catch {
    onFailure();
    return null;
  }
}
