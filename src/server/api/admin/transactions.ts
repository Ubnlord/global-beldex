import { createServerFn } from '@tanstack/react-start';
import { requireAdmin, PERMISSIONS, hasPermission } from '@/lib/admin/middleware.server';
import { approveTransaction, rejectTransaction, settleTransaction } from '@/lib/admin/transactions.server';

/**
 * Approve a pending transaction (requires APPROVE_TRANSACTIONS permission)
 */
export const approveTransactionFn = createServerFn(
  'POST',
  async (transactionId: string, reason?: string) => {
    const admin = await requireAdmin();
    if (!hasPermission(admin, PERMISSIONS.APPROVE_TRANSACTIONS)) {
      throw new Error('You do not have permission to approve transactions');
    }
    return approveTransaction(admin, transactionId, reason);
  },
);

/**
 * Reject a pending transaction (requires REJECT_TRANSACTIONS permission)
 */
export const rejectTransactionFn = createServerFn(
  'POST',
  async (transactionId: string, reason: string) => {
    const admin = await requireAdmin();
    if (!hasPermission(admin, PERMISSIONS.REJECT_TRANSACTIONS)) {
      throw new Error('You do not have permission to reject transactions');
    }
    return rejectTransaction(admin, transactionId, reason);
  },
);

/**
 * Settle a pending transaction (complete it)
 */
export const settleTransactionFn = createServerFn(
  'POST',
  async (transactionId: string, reason?: string) => {
    const admin = await requireAdmin();
    if (!hasPermission(admin, PERMISSIONS.APPROVE_TRANSACTIONS)) {
      throw new Error('You do not have permission to settle transactions');
    }
    return settleTransaction(admin, transactionId, reason);
  },
);
