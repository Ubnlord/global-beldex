import { getSessionUser } from '@/lib/auth/verify.server';
import { getSql } from '@/lib/db';
import type { AdminUser } from './types';

export class AdminUnauthorizedError extends Error {
  readonly status = 403;
  constructor(message = 'Unauthorized. Admin access required.') {
    super(message);
    this.name = 'AdminUnauthorizedError';
  }
}

/**
 * Get the current admin user, or throw if not an admin.
 */
export async function requireAdmin(bearerToken?: string): Promise<AdminUser> {
  const user = await getSessionUser(bearerToken);
  if (!user) {
    throw new AdminUnauthorizedError('Must be signed in');
  }

  const sql = await getSql();
  const rows = await sql`
    select id, user_id as "userId", role, permissions, created_at as "createdAt", updated_at as "updatedAt"
    from admin_user
    where user_id = ${user.id}
  `;

  if (rows.length === 0) {
    throw new AdminUnauthorizedError('User is not an admin');
  }

  return rows[0] as AdminUser;
}

/**
 * Check if the user is an admin (returns null instead of throwing).
 */
export async function getAdminUser(bearerToken?: string): Promise<AdminUser | null> {
  const user = await getSessionUser(bearerToken);
  if (!user) return null;

  const sql = await getSql();
  const rows = await sql`
    select id, user_id as "userId", role, permissions, created_at as "createdAt", updated_at as "updatedAt"
    from admin_user
    where user_id = ${user.id}
  `;

  return rows.length > 0 ? (rows[0] as AdminUser) : null;
}

/**
 * Check if admin has a specific permission.
 */
export function hasPermission(admin: AdminUser, permission: string): boolean {
  return admin.permissions.includes(permission) || admin.role === 'admin';
}

/**
 * Common admin permissions
 */
export const PERMISSIONS = {
  APPROVE_TRANSACTIONS: 'approve_transactions',
  REJECT_TRANSACTIONS: 'reject_transactions',
  VIEW_TRANSACTIONS: 'view_transactions',
  MANAGE_USERS: 'manage_users',
  MANAGE_ADMINS: 'manage_admins',
  VIEW_AUDIT_LOG: 'view_audit_log',
  MANAGE_KYC: 'manage_kyc',
} as const;
