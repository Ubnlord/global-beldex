import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL?.trim();
const key =
  process.env.SUPABASE_PUBLISHABLE_KEY?.trim() ||
  process.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();

function requireSupabaseConfig() {
  if (!url || !key) {
    throw new Error(
      "Supabase server configuration is missing. Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.",
    );
  }

  return { url, key };
}

export function createSupabaseServerClient(accessToken: string): SupabaseClient {
  const config = requireSupabaseConfig();

  return createClient(config.url, config.key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
}
