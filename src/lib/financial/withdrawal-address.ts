const BASE58 = /^[1-9A-HJ-NP-Za-km-z]+$/;

export function normalizeDestination(value: string) {
  return value.trim();
}

export function validateWithdrawalDestination(method: string, value: string): string | null {
  const address = normalizeDestination(value);
  if (!address) return "Please enter a destination address";

  if (method === "Ethereum") {
    if (!/^0x[0-9a-fA-F]{40}$/.test(address)) {
      return "Invalid Ethereum destination address";
    }
    return null;
  }

  if (method === "Bitcoin") {
    const bech32 = /^bc1[ac-hj-np-z02-9]{11,71}$/.test(address.toLowerCase());
    const legacy = /^[13][1-9A-HJ-NP-Za-km-z]{25,34}$/.test(address);
    if (!bech32 && !legacy) {
      return "Invalid Bitcoin destination address";
    }
    return null;
  }

  if (method === "Beldex") {
    // Beldex addresses are Beldex-specific Base58 strings. This is a
    // syntax/network-length guard; final chain validation belongs to the
    // Beldex wallet/RPC layer before a real payout is broadcast.
    if (!BASE58.test(address) || address.length < 90 || address.length > 110) {
      return "Invalid Beldex destination address";
    }
    return null;
  }

  return "Invalid withdrawal method";
}
