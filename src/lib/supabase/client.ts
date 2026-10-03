import { createClient } from "@supabase/supabase-js";

const url = "https://jarzpkwdstahbzvbevrq.supabase.co";
const key = "sb_publishable_oDJ_vtmWllXluCzZWBmelw_Rd4InrPv";

export const supabase = createClient(url, key, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: "pkce",
  },
});
