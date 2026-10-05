import { createServerFn } from "@tanstack/react-start";
import { authMiddleware } from "@/lib/auth/middleware";
import { requireAdmin, PERMISSIONS, hasPermission } from "@/lib/admin/middleware.server";
import { approveTransaction, rejectTransaction, settleTransaction } from "@/lib/admin/transactions.server";

type TransactionInput = {
  transactionId: string;
  reason?: string;
};

type RejectInput = {
  transactionId: string;
  reason: string;
};

export const approveTransactionFn = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: TransactionInput) => data)
  .handler(async ({ context, data }) => {
    const admin = await requireAdmin(context.bearerToken);
    if (!hasPermission(admin, PERMISSIONS.APPROVE_TRANSACTIONS)) {
      throw new Error("Permission denied");
    }
    return approveTransaction(
      admin,
      data.transactionId,
      data.reason,
      context.bearerToken!,
    );
  });

export const rejectTransactionFn = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: RejectInput) => data)
  .handler(async ({ context, data }) => {
    const admin = await requireAdmin(context.bearerToken);
    if (!hasPermission(admin, PERMISSIONS.REJECT_TRANSACTIONS)) {
      throw new Error("Permission denied");
    }
    return rejectTransaction(
      admin,
      data.transactionId,
      data.reason,
      context.bearerToken!,
    );
  });

export const settleTransactionFn = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: TransactionInput) => data)
  .handler(async ({ context, data }) => {
    const admin = await requireAdmin(context.bearerToken);
    if (!hasPermission(admin, PERMISSIONS.APPROVE_TRANSACTIONS)) {
      throw new Error("Permission denied");
    }
    return settleTransaction(
      admin,
      data.transactionId,
      data.reason,
      context.bearerToken!,
    );
  });
