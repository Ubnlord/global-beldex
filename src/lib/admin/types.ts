export type AdminRole = 'admin' | 'moderator' | 'support';

export type TransactionType = 'deposit' | 'withdraw' | 'swap' | 'plan' | 'referral' | 'bonus';
export type TransactionStatus = 'pending' | 'approved' | 'rejected' | 'completed' | 'failed';
export type ApprovalStatus = 'awaiting' | 'approved' | 'rejected';
export type KycStatus = 'pending' | 'verified' | 'rejected';

export interface AdminUser {
  id: string;
  userId: string;
  role: AdminRole;
  permissions: string[];
  createdAt: Date;
  updatedAt: Date;
}

export interface Transaction {
  id: string;
  userId: string;
  type: TransactionType;
  amount: number;
  status: TransactionStatus;
  approvalStatus: ApprovalStatus;
  method?: string;
  note?: string;
  approvedBy?: string;
  approvalReason?: string;
  approvedAt?: Date;
  settledAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface UserProfile {
  id: string;
  userId: string;
  username?: string;
  fullname?: string;
  phone?: string;
  country?: string;
  avatarUrl?: string;
  kycStatus: KycStatus;
  kycVerifiedAt?: Date;
  twoFactorEnabled: boolean;
  totalDeposits: number;
  totalWithdrawals: number;
  availableBalance: number;
  lockedBalance: number;
  createdAt: Date;
  updatedAt: Date;
}

export interface TransactionAudit {
  id: string;
  transactionId: string;
  adminId?: string;
  action: 'created' | 'approved' | 'rejected' | 'settled' | 'cancelled';
  oldValues?: Record<string, unknown>;
  newValues?: Record<string, unknown>;
  reason?: string;
  createdAt: Date;
}

export interface AdminDashboardStats {
  totalUsers: number;
  totalTransactionValue: number;
  pendingTransactions: number;
  awaitingApprovalCount: number;
  totalApprovedToday: number;
  totalRejectedToday: number;
}
