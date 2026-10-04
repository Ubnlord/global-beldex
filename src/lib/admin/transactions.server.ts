import { getSql } from '@/lib/db';
import { uid } from '@/lib/utils';
import type { AdminUser, Transaction, TransactionAudit } from './types';

/**
 * Get all pending transactions awaiting approval
 */
export async function getPendingTransactions(): Promise<Transaction[]> {
  const sql = await getSql();
  const rows = await sql`
    select 
      id, user_id as "userId", type, amount, status, 
      approval_status as "approvalStatus", method, note, 
      approved_by as "approvedBy", approval_reason as "approvalReason",
      approved_at as "approvedAt", settled_at as "settledAt",
      created_at as "createdAt", updated_at as "updatedAt"
    from transaction
    where approval_status = 'awaiting'
    order by created_at desc
  `;
  return rows as Transaction[];
}

/**
 * Get all transactions for a specific user
 */
export async function getUserTransactions(userId: string): Promise<Transaction[]> {
  const sql = await getSql();
  const rows = await sql`
    select 
      id, user_id as "userId", type, amount, status, 
      approval_status as "approvalStatus", method, note, 
      approved_by as "approvedBy", approval_reason as "approvalReason",
      approved_at as "approvedAt", settled_at as "settledAt",
      created_at as "createdAt", updated_at as "updatedAt"
    from transaction
    where user_id = ${userId}
    order by created_at desc
  `;
  return rows as Transaction[];
}

/**
 * Get a single transaction by ID
 */
export async function getTransaction(transactionId: string): Promise<Transaction | null> {
  const sql = await getSql();
  const rows = await sql`
    select 
      id, user_id as "userId", type, amount, status, 
      approval_status as "approvalStatus", method, note, 
      approved_by as "approvedBy", approval_reason as "approvalReason",
      approved_at as "approvedAt", settled_at as "settledAt",
      created_at as "createdAt", updated_at as "updatedAt"
    from transaction
    where id = ${transactionId}
  `;
  return rows.length > 0 ? (rows[0] as Transaction) : null;
}

/**
 * Approve a pending transaction
 */
export async function approveTransaction(
  admin: AdminUser,
  transactionId: string,
  reason?: string,
): Promise<Transaction> {
  const sql = await getSql();
  const now = new Date();

  // Get the transaction first
  const tx = await getTransaction(transactionId);
  if (!tx) throw new Error('Transaction not found');
  if (tx.approvalStatus !== 'awaiting') {
    throw new Error('Transaction is not awaiting approval');
  }

  // Determine new status
  const newStatus = tx.type === 'deposit' || tx.type === 'withdraw' ? 'pending' : 'approved';

  // Update transaction
  await sql`
    update transaction
    set 
      approval_status = 'approved',
      status = ${newStatus},
      approved_by = ${admin.id},
      approval_reason = ${reason || null},
      approved_at = ${now},
      updated_at = ${now}
    where id = ${transactionId}
  `;

  // Audit log
  await createAuditLog(admin.id, transactionId, 'approved', tx, {
    ...tx,
    approvalStatus: 'approved',
    status: newStatus,
    approvedAt: now,
  }, reason);

  const updated = await getTransaction(transactionId);
  if (!updated) throw new Error('Failed to retrieve updated transaction');
  return updated;
}

/**
 * Reject a pending transaction
 */
export async function rejectTransaction(
  admin: AdminUser,
  transactionId: string,
  reason: string,
): Promise<Transaction> {
  const sql = await getSql();
  const now = new Date();

  // Get the transaction first
  const tx = await getTransaction(transactionId);
  if (!tx) throw new Error('Transaction not found');
  if (tx.approvalStatus !== 'awaiting') {
    throw new Error('Transaction is not awaiting approval');
  }

  // For withdrawals, refund the amount back to user's available balance
  if (tx.type === 'withdraw') {
    await sql`
      update user_profile
      set 
        available_balance = available_balance + ${tx.amount},
        updated_at = ${now}
      where user_id = ${tx.userId}
    `;
  }

  // Update transaction
  await sql`
    update transaction
    set 
      approval_status = 'rejected',
      status = 'failed',
      approved_by = ${admin.id},
      approval_reason = ${reason},
      approved_at = ${now},
      updated_at = ${now}
    where id = ${transactionId}
  `;

  // Audit log
  await createAuditLog(admin.id, transactionId, 'rejected', tx, {
    ...tx,
    approvalStatus: 'rejected',
    status: 'failed',
    approvedAt: now,
  }, reason);

  const updated = await getTransaction(transactionId);
  if (!updated) throw new Error('Failed to retrieve updated transaction');
  return updated;
}

/**
 * Settle a pending deposit/withdrawal (complete it)
 */
export async function settleTransaction(
  admin: AdminUser,
  transactionId: string,
  reason?: string,
): Promise<Transaction> {
  const sql = await getSql();
  const now = new Date();

  const tx = await getTransaction(transactionId);
  if (!tx) throw new Error('Transaction not found');

  if (tx.type !== 'deposit' && tx.type !== 'withdraw') {
    throw new Error('Only deposits and withdrawals can be settled');
  }

  if (tx.status === 'completed') {
    throw new Error('Transaction is already completed');
  }

  // Update user profile balances
  if (tx.type === 'deposit') {
    await sql`
      update user_profile
      set 
        available_balance = available_balance + ${tx.amount},
        total_deposits = total_deposits + ${tx.amount},
        updated_at = ${now}
      where user_id = ${tx.userId}
    `;
  } else if (tx.type === 'withdraw') {
    await sql`
      update user_profile
      set 
        total_withdrawals = total_withdrawals + ${tx.amount},
        updated_at = ${now}
      where user_id = ${tx.userId}
    `;
  }

  // Update transaction
  await sql`
    update transaction
    set 
      status = 'completed',
      settled_at = ${now},
      updated_at = ${now}
    where id = ${transactionId}
  `;

  // Audit log
  await createAuditLog(admin.id, transactionId, 'settled', tx, {
    ...tx,
    status: 'completed',
    settledAt: now,
  }, reason);

  const updated = await getTransaction(transactionId);
  if (!updated) throw new Error('Failed to retrieve updated transaction');
  return updated;
}

/**
 * Create transaction audit log entry
 */
async function createAuditLog(
  adminId: string,
  transactionId: string,
  action: 'created' | 'approved' | 'rejected' | 'settled' | 'cancelled',
  oldValues: Transaction,
  newValues: Partial<Transaction>,
  reason?: string,
): Promise<void> {
  const sql = await getSql();
  await sql`
    insert into transaction_audit (id, transaction_id, admin_id, action, old_values, new_values, reason, created_at)
    values (${uid()}, ${transactionId}, ${adminId}, ${action}, ${JSON.stringify(oldValues)}, ${JSON.stringify(newValues)}, ${reason || null}, ${new Date()})
  `;
}

/**
 * Get audit log for a transaction
 */
export async function getTransactionAuditLog(transactionId: string): Promise<TransactionAudit[]> {
  const sql = await getSql();
  const rows = await sql`
    select 
      id, transaction_id as "transactionId", admin_id as "adminId", 
      action, old_values as "oldValues", new_values as "newValues", 
      reason, created_at as "createdAt"
    from transaction_audit
    where transaction_id = ${transactionId}
    order by created_at asc
  `;
  return rows as TransactionAudit[];
}
