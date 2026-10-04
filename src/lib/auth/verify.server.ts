import { getRequest } from "@tanstack/react-start/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export class UnauthorizedError extends Error {
  readonly status = 401;
  constructor() { super("Unauthorized"); this.name = "UnauthorizedError"; }
}
export type VerifiedUser = { id: string; email: string | null };

function bearerFromRequest(): string | null {
  const value = getRequest()?.headers.get("authorization");
  return value?.startsWith("Bearer ") ? value.slice(7).trim() || null : null;
}

export async function getSessionUser(bearerToken?: string): Promise<VerifiedUser | null> {
  const token = bearerToken ?? bearerFromRequest();
  if (!token) return null;
  const { data, error } = await createSupabaseServerClient(token).auth.getUser(token);
  if (error || !data.user) return null;
  return { id: data.user.id, email: data.user.email ?? null };
}
export async function requireUserId(bearerToken?: string): Promise<string> {
  const user = await getSessionUser(bearerToken);
  if (!user) throw new UnauthorizedError();
  return user.id;
}
