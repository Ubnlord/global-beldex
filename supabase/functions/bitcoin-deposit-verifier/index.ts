import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BTC_ADDRESS = "bc1qzlq3r8e39pwl8mv3vthdxr7nnxlrq92gvs3p0m";
const REQUIRED_CONFIRMATIONS = 3;
const SATS_PER_BTC = 100_000_000;
const MEMPOOL_API = "https://mempool.space/api";

type TxStatus = { confirmed: boolean; block_height?: number; block_hash?: string; block_time?: number };
type TxOutput = { scriptpubkey_address?: string; value?: number };
type ChainTx = { txid: string; status?: TxStatus; vout?: TxOutput[] };

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url, { headers: { accept: "application/json" } });
  if (!res.ok) throw new Error(`Bitcoin provider returned HTTP ${res.status}`);
  return await res.json() as T;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return response(405, { error: "POST required" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return response(503, { error: "Bitcoin verification is not configured" });
  }

  const authorization = req.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return response(401, { error: "Authentication required" });
  }

  let body: { intent_id?: unknown; txid?: unknown };
  try { body = await req.json(); } catch { return response(400, { error: "Invalid JSON" }); }
  if (typeof body.intent_id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(body.intent_id) ||
      typeof body.txid !== "string" || !/^[0-9a-f]{64}$/i.test(body.txid)) {
    return response(400, { error: "Valid intent_id and Bitcoin txid required" });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return response(401, { error: "Invalid session" });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: intent, error: intentError } = await admin
    .from("bitcoin_deposit_intent")
    .select("id,user_id,receiving_address,target_bdx,quoted_btc,quote_expires_at,status,created_at")
    .eq("id", body.intent_id)
    .maybeSingle();

  if (intentError) return response(503, { error: "Could not load deposit intent" });
  if (!intent || intent.user_id !== userData.user.id) return response(404, { error: "Deposit intent not found" });
  if (intent.receiving_address !== BTC_ADDRESS) return response(409, { error: "Receiving address mismatch; manual review required" });
  if (intent.status === "credited") return response(200, { status: "credited", message: "Deposit was already credited" });
  if (["expired", "underpaid", "review"].includes(intent.status)) {
    return response(409, { status: intent.status, message: "This deposit requires manual review or a new request" });
  }
  if (new Date(intent.quote_expires_at).getTime() < Date.now() && intent.status === "awaiting_payment") {
    await admin.from("bitcoin_deposit_intent").update({ status: "expired", updated_at: new Date().toISOString() }).eq("id", intent.id).eq("status", "awaiting_payment");
    return response(200, { status: "expired", message: "Quote expired before payment was detected" });
  }

  try {
    // Only verify the txid submitted by the authenticated user. Scanning a shared
    // address for any matching historical amount could attribute an old payment.
    const requestedTxid = (body.txid as string).toLowerCase();
    const tx = await fetchJson<ChainTx>(`${MEMPOOL_API}/tx/${requestedTxid}`);
    if (tx.txid?.toLowerCase() !== requestedTxid || !Array.isArray(tx.vout)) {
      return response(409, { error: "Transaction response did not match requested txid" });
    }
    const status = tx.status;
    if (status?.confirmed !== true || !Number.isSafeInteger(status.block_height) ||
        !status.block_hash || !Number.isSafeInteger(status.block_time)) {
      return response(200, { status: "detected", confirmations: 0, required_confirmations: REQUIRED_CONFIRMATIONS, message: "Transaction is not confirmed yet; no BDX has been credited" });
    }
    const tip = await fetchJson<number>(`${MEMPOOL_API}/blocks/tip/height`);
    if (!Number.isSafeInteger(tip) || tip < 0) throw new Error("Invalid chain tip response");
    const confirmations = Math.max(0, tip - status.block_height! + 1);
    const paymentTimeMs = status.block_time! * 1000;
    if (paymentTimeMs < new Date(intent.created_at).getTime()) {
      await admin.from("bitcoin_deposit_intent").update({ status: "review", updated_at: new Date().toISOString() }).eq("id", intent.id).neq("status", "credited");
      return response(409, { status: "review", message: "Transaction predates this deposit request; manual review required" });
    }
    if (paymentTimeMs > new Date(intent.quote_expires_at).getTime()) {
      await admin.from("bitcoin_deposit_intent").update({ status: "review", updated_at: new Date().toISOString() }).eq("id", intent.id).neq("status", "credited");
      return response(409, { status: "review", message: "Payment was confirmed after the quote expired; manual review required" });
    }

    const matches: Array<{ tx: ChainTx; vout: number; sats: number; confirmations: number; height: number; hash: string }> = [];
    for (let i = 0; i < tx.vout.length; i++) {
      const output = tx.vout[i];
      if (output.scriptpubkey_address !== BTC_ADDRESS || !Number.isSafeInteger(output.value) || (output.value ?? 0) <= 0) continue;
      matches.push({ tx, vout: i, sats: output.value!, confirmations, height: status.block_height!, hash: status.block_hash });
    }

    const minimumSats = Math.ceil(Number(intent.quoted_btc) * SATS_PER_BTC);
    if (!Number.isSafeInteger(minimumSats) || minimumSats <= 0) {
      return response(409, { error: "Invalid quoted BTC amount; manual review required" });
    }
    const qualifyingMatches = matches.filter((m) => m.sats >= minimumSats);
    if (qualifyingMatches.length === 0) {
      await admin.from("bitcoin_deposit_intent").update({ status: "underpaid", updated_at: new Date().toISOString() }).eq("id", intent.id).neq("status", "credited");
      return response(409, { status: "underpaid", message: "Payment is below the quoted BTC amount; manual review required" });
    }
    if (qualifyingMatches.length !== 1) {
      await admin.from("bitcoin_deposit_intent").update({ status: "review", updated_at: new Date().toISOString() }).eq("id", intent.id).neq("status", "credited");
      return response(409, { status: "review", message: "Multiple qualifying outputs found; manual review required" });
    }

    const match = qualifyingMatches[0];
    if (match.confirmations < REQUIRED_CONFIRMATIONS) {
      await admin.from("bitcoin_deposit_intent").update({ status: "confirming", updated_at: new Date().toISOString() }).eq("id", intent.id).neq("status", "credited");
      return response(200, { status: "confirming", confirmations: match.confirmations, required_confirmations: REQUIRED_CONFIRMATIONS, message: "Payment detected; waiting for confirmations" });
    }

    // SAFETY HOLD: the configured receiving address is shared across intents.
    // A submitted txid, amount and block timestamp cannot prove which customer
    // owns a payment to a shared address. Never auto-credit from this evidence.
    // Enable automated settlement only after per-intent addresses or an equally
    // strong, independently verifiable attribution mechanism is implemented.
    await admin.from("bitcoin_deposit_intent")
      .update({ status: "review", updated_at: new Date().toISOString() })
      .eq("id", intent.id)
      .neq("status", "credited");
    return response(409, {
      status: "review",
      message: "Bitcoin payment detected, but this shared-address setup cannot safely attribute it to this deposit. Manual review required; no BDX was credited.",
    });

    const payloadHash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify({
      txid: match.tx.txid, vout: match.vout, address: BTC_ADDRESS, sats: match.sats,
      confirmations: match.confirmations, height: match.height, block_hash: match.hash,
    })));
    const payloadHashHex = Array.from(new Uint8Array(payloadHash), b => b.toString(16).padStart(2, "0")).join("");

    const observation = {
      txid: match.tx.txid,
      intent_id: intent.id,
      output_index: match.vout,
      destination_address: BTC_ADDRESS,
      received_sats: match.sats,
      confirmations: match.confirmations,
      block_height: match.height || null,
      block_hash: match.hash || null,
      verification_provider: "mempool.space",
      provider_payload_hash: payloadHashHex,
      updated_at: new Date().toISOString(),
    };
    const { data: existingObservation, error: existingError } = await admin
      .from("bitcoin_chain_observation")
      .select("intent_id,output_index")
      .eq("txid", match.tx.txid)
      .maybeSingle();

    if (existingError) return response(503, { error: "Could not safely check transaction uniqueness" });
    if (existingObservation && (existingObservation.intent_id !== intent.id || existingObservation.output_index !== match.vout)) {
      await admin.from("bitcoin_deposit_intent").update({ status: "review", updated_at: new Date().toISOString() }).eq("id", intent.id).neq("status", "credited");
      return response(409, { status: "review", message: "Transaction already associated with another deposit; manual review required" });
    }

    const { error: observationError } = existingObservation
      ? await admin.from("bitcoin_chain_observation").update(observation).eq("txid", match.tx.txid).eq("intent_id", intent.id)
      : await admin.from("bitcoin_chain_observation").insert(observation);

    if (observationError) {
      await admin.from("bitcoin_deposit_intent").update({ status: "review", updated_at: new Date().toISOString() }).eq("id", intent.id).neq("status", "credited");
      return response(409, { status: "review", message: "Could not safely associate this output; manual review required" });
    }

    if (match.confirmations < REQUIRED_CONFIRMATIONS) {
      await admin.from("bitcoin_deposit_intent").update({ status: "confirming", updated_at: new Date().toISOString() }).eq("id", intent.id).neq("status", "credited");
      return response(200, { status: "confirming", confirmations: match.confirmations, required_confirmations: REQUIRED_CONFIRMATIONS, message: "Payment detected; waiting for confirmations" });
    }

    const { error: markError } = await admin.from("bitcoin_deposit_intent").update({ status: "verified", updated_at: new Date().toISOString() }).eq("id", intent.id).in("status", ["awaiting_payment", "detected", "confirming", "verified"]);
    if (markError) return response(503, { error: "Could not persist verification; no credit attempted" });

    const { data: credited, error: creditError } = await admin.rpc("credit_verified_bitcoin_deposit", { p_intent_id: intent.id });
    if (creditError) return response(409, { status: "verified", message: "Payment verified but credit did not complete; retry or review required" });
    return response(200, { status: "credited", transaction_id: credited?.id ?? null, message: "Verified Bitcoin deposit credited to BDX wallet" });
  } catch {
    return response(503, { error: "Bitcoin provider unavailable or response invalid; no credit was made" });
  }
});
