import { createFileRoute, useNavigate } from '@tanstack/react-router';
import { useState } from 'react';
import { AlertCircle, CheckCircle, XCircle, Clock, Users, TrendingUp } from 'lucide-react';
import { AdminDashboard } from '@/components/admin/dashboard';
import { PendingTransactions } from '@/components/admin/pending-transactions';
import { UserManagement } from '@/components/admin/user-management';
import { Button } from '@/components/ui/button';
import { AppShell } from '@/components/layout/app-shell';
import { toast } from '@/components/layout/toast';

export const Route = createFileRoute('/app/admin')({
  component: AdminPage,
});

type AdminTab = 'dashboard' | 'transactions' | 'users';

function AdminPage() {
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<AdminTab>('dashboard');

  const tabs = [
    { id: 'dashboard', label: 'Dashboard', icon: TrendingUp },
    { id: 'transactions', label: 'Transactions', icon: Clock },
    { id: 'users', label: 'Users', icon: Users },
  ] as const;

  return (
    <AppShell>
      <div className="mx-auto max-w-[1400px] px-4 py-6 sm:px-6">
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-fg">Admin Dashboard</h1>
          <p className="mt-1 text-sm text-muted">Manage users, approve transactions, and monitor platform activity</p>
        </div>

        {/* Tabs */}
        <div className="mb-6 border-b border-line">
          <div className="flex gap-1">
            {tabs.map((tab) => {
              const Icon = tab.icon;
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id as AdminTab)}
                  className={`flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition-colors ${
                    activeTab === tab.id
                      ? 'border-accent text-accent'
                      : 'border-transparent text-muted hover:text-fg'
                  }`}
                >
                  <Icon size={16} />
                  {tab.label}
                </button>
              );
            })}
          </div>
        </div>

        {/* Tab Content */}
        <div className="space-y-6">
          {activeTab === 'dashboard' && <AdminDashboard />}
          {activeTab === 'transactions' && <PendingTransactions />}
          {activeTab === 'users' && <UserManagement />}
        </div>
      </div>
    </AppShell>
  );
}
