import { createFileRoute, Navigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { CheckCircle, XCircle, RefreshCw, Users, Clock } from "lucide-react";
import { supabase } from "@/lib/supabase/client";

export const Route = createFileRoute("/app/admin")({ component: AdminPage });

type Tx = { id:string; user_id:string; type:string; amount:string|number; status:string; approval_status:string; method:string|null; created_at:string };

function AdminPage() {
  const [allowed,setAllowed]=useState<boolean|null>(null);
  const [txs,setTxs]=useState<Tx[]>([]);
  const [users,setUsers]=useState<any[]>([]);
  const [loading,setLoading]=useState(true);
  const [busy,setBusy]=useState<string|null>(null);
  const [error,setError]=useState("");

  async function load() {
    setLoading(true); setError("");
    const {data:{user}}=await supabase.auth.getUser();
    if(!user){setAllowed(false);setLoading(false);return;}
    const {data:admin}=await supabase.from("admin_user").select("id,role,permissions").eq("user_id",user.id).maybeSingle();
    if(!admin){setAllowed(false);setLoading(false);return;}
    setAllowed(true);
    const [t,u]=await Promise.all([
      supabase.from("transaction").select("*").eq("approval_status","awaiting").order("created_at",{ascending:false}),
      supabase.from("user_profile").select("id,user_id,username,fullname,country,kyc_status,available_balance,total_deposits,total_withdrawals").order("created_at",{ascending:false})
    ]);
    if(t.error) setError(t.error.message); else setTxs((t.data??[]) as Tx[]);
    if(!u.error) setUsers(u.data??[]);
    setLoading(false);
  }

  useEffect(()=>{void load();},[]);

  async function act(kind:"approve"|"reject"|"settle",id:string){
    setBusy(id); setError("");
    const rpc=kind==="approve"?"admin_approve_transaction":kind==="reject"?"admin_reject_transaction":"admin_settle_transaction";
    const args:any={p_transaction_id:id,p_reason:kind==="reject"?"Rejected by administrator":null};
    const {error:e}=await supabase.rpc(rpc,args);
    if(e) setError(e.message); else await load();
    setBusy(null);
  }

  if(allowed===false) return <Navigate to="/login" />;
  return <div className="mx-auto max-w-[1400px] px-4 py-6 sm:px-6">
    <div className="mb-8 flex items-center justify-between gap-4">
      <div><h1 className="text-3xl font-bold text-fg">Admin Dashboard</h1><p className="mt-1 text-sm text-muted">Supabase-backed users and transaction approvals.</p></div>
      <button onClick={()=>void load()} className="inline-flex items-center gap-2 rounded-lg border border-line px-4 py-2 text-sm"><RefreshCw size={16}/>Refresh</button>
    </div>
    {error&&<div className="mb-5 rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-300">{error}</div>}
    {loading?<div className="py-16 text-center text-muted">Loading secure admin data…</div>:<>
      <div className="grid gap-4 sm:grid-cols-2 mb-8">
        <div className="rounded-xl border border-line bg-panel p-5"><div className="flex items-center gap-2 text-muted"><Clock size={18}/>Awaiting transactions</div><div className="mt-2 text-3xl font-bold">{txs.length}</div></div>
        <div className="rounded-xl border border-line bg-panel p-5"><div className="flex items-center gap-2 text-muted"><Users size={18}/>Registered profiles</div><div className="mt-2 text-3xl font-bold">{users.length}</div></div>
      </div>
      <section className="mb-8 rounded-xl border border-line bg-panel overflow-hidden">
        <div className="border-b border-line p-5"><h2 className="text-xl font-semibold">Pending transactions</h2></div>
        <div className="divide-y divide-line">{txs.length===0?<div className="p-6 text-sm text-muted">No transactions awaiting approval.</div>:txs.map(t=><div key={t.id} className="p-5 flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div><div className="font-semibold capitalize">{t.type} · {Number(t.amount).toLocaleString()}</div><div className="text-sm text-muted">{t.method??"No method"} · {new Date(t.created_at).toLocaleString()}</div><div className="mt-1 text-xs text-muted break-all">{t.user_id}</div></div>
          <div className="flex gap-2"><button disabled={busy===t.id} onClick={()=>void act("approve",t.id)} className="inline-flex items-center gap-2 rounded-lg bg-accent px-4 py-2 text-sm font-medium"><CheckCircle size={16}/>Approve</button><button disabled={busy===t.id} onClick={()=>void act("reject",t.id)} className="inline-flex items-center gap-2 rounded-lg border border-red-500/40 px-4 py-2 text-sm"><XCircle size={16}/>Reject</button></div>
        </div>)}</div>
      </section>
      <section className="rounded-xl border border-line bg-panel overflow-hidden">
        <div className="border-b border-line p-5"><h2 className="text-xl font-semibold">Users</h2></div>
        <div className="divide-y divide-line">{users.map(u=><div key={u.id} className="p-5 grid gap-2 sm:grid-cols-4 text-sm"><div><b>{u.fullname||u.username||"Unnamed"}</b><div className="text-muted">{u.username||"—"}</div></div><div>{u.country||"—"}</div><div>KYC: {u.kyc_status}</div><div className="sm:text-right">Balance: {Number(u.available_balance).toLocaleString()}</div></div>)}</div>
      </section>
    </>}
  </div>;
}
