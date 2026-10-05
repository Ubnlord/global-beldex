import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      throw new Error("Unauthorized");
    }

    const token = authHeader.slice("Bearer ".length);
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !anonKey || !serviceKey) {
      throw new Error("Server configuration is incomplete");
    }

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: { user }, error: userError } = await authClient.auth.getUser(token);
    if (userError || !user) throw new Error("Unauthorized");

    const body = await req.json();
    const from = String(body?.from || "");
    const to = String(body?.to || "");
    const amount = Number(body?.amount);

    if (!["USD", "BDX"].includes(from) || !["USD", "BDX"].includes(to) || from === to) {
      throw new Error("Invalid swap pair");
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new Error("Amount must be greater than zero");
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    let rate = 0;

    try {
      const response = await fetch(
        "https://api.coingecko.com/api/v3/simple/price?ids=beldex&vs_currencies=usd",
        { signal: controller.signal, headers: { Accept: "application/json" } },
      );
      if (response.ok) {
        const data = await response.json();
        rate = Number(data?.beldex?.usd);
      }
    } finally {
      clearTimeout(timeout);
    }

    if (!Number.isFinite(rate) || rate <= 0) {
      throw new Error("Live BDX rate is temporarily unavailable");
    }

    const adminClient = createClient(supabaseUrl, serviceKey);
    const { data, error } = await adminClient.rpc("swap_assets", {
      p_from: from,
      p_to: to,
      p_amount: amount,
      p_rate: rate,
    });

    if (error) throw new Error(error.message);

    return new Response(JSON.stringify({ transaction: data, rate }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: error instanceof Error ? error.message : "Swap failed",
    }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
