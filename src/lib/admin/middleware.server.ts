import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getSessionUser } from "@/lib/auth/verify.server";
import type { AdminUser } from "./types";

export class AdminUnauthorizedError extends Error {
  readonly status = 403;
  constructor(message = "Unauthorized. Admin access required.") { super(message); this.name = "AdminUnauthorizedError"; }
}
export async function requireAdmin(bearerToken?: string): Promise<AdminUser> {
  const user = await getSessionUser(bearerToken);
  if (!user || !bearerToken) throw new AdminUnauthorizedError("Must be signed in");
  const { data, error } = await createSupabaseServerClient(bearerToken)
    .from("admin_user").select("id,user_id,role,permissions,created_at,updated_at")
    .eq("user_id", user.id).maybeSingle();
  if (error || !data) throw new AdminUnauthorizedError("User is not an admin");
  return { id:data.id,userId:data.user_id,role:data.role,permissions:data.permissions??[],createdAt:data.created_at as any,updatedAt:data.updated_at as any };
}
export async function getAdminUser(token?: string) { try { return await requireAdmin(token); } catch { return null; } }
export function hasPermission(admin: AdminUser, permission: string) { return admin.role === "admin" || admin.permissions.includes(permission); }
export const PERMISSIONS = {
  APPROVE_TRANSACTIONS:"approve_transactions", REJECT_TRANSACTIONS:"reject_transactions",
  VIEW_TRANSACTIONS:"view_transactions", MANAGE_USERS:"manage_users", MANAGE_ADMINS:"manage_admins",
  VIEW_AUDIT_LOG:"view_audit_log", MANAGE_KYC:"manage_kyc",
} as const;
