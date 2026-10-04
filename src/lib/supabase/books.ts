import type { Book } from "@/lib/platform/store";
import { supabase } from "./client";

function num(v: unknown) { const n=Number(v); return Number.isFinite(n)?n:0; }

export async function pullCloudBook(): Promise<Book | null> {
  const { data:{user} } = await supabase.auth.getUser();
  if (!user) return null;
  const [profileResult, txResult] = await Promise.all([
    supabase.from("user_profile").select("available_balance,locked_balance,total_withdrawals").eq("user_id",user.id).maybeSingle(),
    supabase.from("transaction").select("id,type,amount,status,method,note,created_at").eq("user_id",user.id).order("created_at",{ascending:false}),
  ]);
  if (profileResult.error) return null;
  const p=profileResult.data;
  const txs=(txResult.data??[]).map((t:any)=>({
    id:t.id,type:t.type,amount:num(t.amount),status:t.status,date:new Date(t.created_at).toISOString(),
    method:t.method??undefined,note:t.note??undefined,
  }));
  return {
    available:num(p?.available_balance),
    bdx:0,
    locked:num(p?.locked_balance),
    profit:0,
    bonus:0,
    referralBonus:0,
    withdrawn:num(p?.total_withdrawals),
    txs,
    plans:[],
    notices:[],
    tickets:[],
  };
}

// Financial state is server-authoritative. These legacy write helpers intentionally do nothing.
export async function pushCloudBook(_book: Book) { return; }
export function scheduleCloudSave(_book: Book) { return; }
