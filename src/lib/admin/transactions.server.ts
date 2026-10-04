import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { AdminUser, Transaction, TransactionAudit } from "./types";

const map = (r:any): Transaction => ({id:r.id,userId:r.user_id,type:r.type,amount:Number(r.amount),status:r.status,approvalStatus:r.approval_status,method:r.method??undefined,note:r.note??undefined,approvedBy:r.approved_by??undefined,approvalReason:r.approval_reason??undefined,approvedAt:r.approved_at as any,settledAt:r.settled_at as any,createdAt:r.created_at as any,updatedAt:r.updated_at as any});

export async function getPendingTransactions(token:string) {
  const {data,error}=await createSupabaseServerClient(token).from("transaction").select("*").eq("approval_status","awaiting").order("created_at",{ascending:false});
  if(error) throw error; return (data??[]).map(map);
}
export async function getUserTransactions(userId:string,token:string) {
  const {data,error}=await createSupabaseServerClient(token).from("transaction").select("*").eq("user_id",userId).order("created_at",{ascending:false});
  if(error) throw error; return (data??[]).map(map);
}
export async function approveTransaction(_admin:AdminUser,id:string,reason:string|undefined,token:string) {
  const {data,error}=await createSupabaseServerClient(token).rpc("admin_approve_transaction",{p_transaction_id:id,p_reason:reason??null});
  if(error) throw error; return map(data);
}
export async function rejectTransaction(_admin:AdminUser,id:string,reason:string,token:string) {
  const {data,error}=await createSupabaseServerClient(token).rpc("admin_reject_transaction",{p_transaction_id:id,p_reason:reason});
  if(error) throw error; return map(data);
}
export async function settleTransaction(_admin:AdminUser,id:string,reason:string|undefined,token:string) {
  const {data,error}=await createSupabaseServerClient(token).rpc("admin_settle_transaction",{p_transaction_id:id,p_reason:reason??null});
  if(error) throw error; return map(data);
}
export async function getTransactionAuditLog(id:string,token:string):Promise<TransactionAudit[]> {
  const {data,error}=await createSupabaseServerClient(token).from("transaction_audit").select("*").eq("transaction_id",id).order("created_at",{ascending:true});
  if(error) throw error; return (data??[]) as TransactionAudit[];
}
