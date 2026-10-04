import { createMiddleware } from "@tanstack/react-start";

export const authMiddleware = createMiddleware({ type: "function" })
  .client(async ({ next }) => {
    const { supabase } = await import("@/lib/supabase/client");
    const { data } = await supabase.auth.getSession();
    return next({ sendContext: { bearerToken: data.session?.access_token ?? undefined } });
  })
  .server(async ({ next, context }) => {
    const { requireUserId } = await import("./verify.server");
    const userId = await requireUserId(context.bearerToken);
    return next({ context: { userId, bearerToken: context.bearerToken } });
  });
