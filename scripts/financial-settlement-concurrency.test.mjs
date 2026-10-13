import assert from "node:assert/strict";
import { Client } from "pg";

const connectionString = process.env.DB_URL;
if (!connectionString) throw new Error("DB_URL is required for isolated settlement concurrency regression");

const adminId = "a3100000-0000-4000-8000-000000000061";
const userId = "a3100000-0000-4000-8000-000000000062";
const txId = "a3100000-0000-4000-8000-000000000063";
const admin = new Client({ connectionString });
await admin.connect();
const first = new Client({ connectionString });
const second = new Client({ connectionString });

try {
  await admin.query(`
    insert into auth.users (
      id,aud,role,email,encrypted_password,email_confirmed_at,
      raw_app_meta_data,raw_user_meta_data,created_at,updated_at
    ) values
      ($1,'authenticated','authenticated','settlement-race-admin@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
      ($2,'authenticated','authenticated','settlement-race-user@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now())
    on conflict (id) do nothing
  `, [adminId,userId]);
  await admin.query(`
    insert into public.user_profile(user_id,available_balance,locked_balance,bdx_balance,locked_bdx_balance,blocked,total_withdrawals)
    values ($1,100,0,0,0,false,0)
    on conflict (user_id) do update set available_balance=100,locked_balance=0,bdx_balance=0,
      locked_bdx_balance=0,blocked=false,total_withdrawals=0
  `, [userId]);
  await admin.query(`
    insert into public.admin_user(user_id,role,permissions)
    values ($1,'admin',array['approve_transactions']::text[])
    on conflict (user_id) do update set role='admin',permissions=array['approve_transactions']::text[]
  `, [adminId]);
  await admin.query(`
    insert into public.transaction(id,user_id,type,amount,currency,status,approval_status,method,note)
    values ($1,$2,'withdraw',10,'USD','pending','approved','test','isolated concurrent settlement test')
    on conflict (id) do update set status='pending',approval_status='approved',amount=10,currency='USD'
  `, [txId,userId]);

  await Promise.all([first.connect(),second.connect()]);
  await Promise.all([
    first.query("select set_config('request.jwt.claim.sub',$1,false)",[adminId]),
    second.query("select set_config('request.jwt.claim.sub',$1,false)",[adminId])
  ]);
  const outcomes = await Promise.allSettled([
    first.query("select (public.admin_settle_transaction($1::uuid,'race test')).status",[txId]),
    second.query("select (public.admin_settle_transaction($1::uuid,'race test')).status",[txId])
  ]);
  assert.equal(outcomes.filter(x=>x.status==="fulfilled").length,1,"exactly one concurrent settlement should succeed");
  assert.equal(outcomes.filter(x=>x.status==="rejected").length,1,"the duplicate settlement should be rejected");
  const profile = await admin.query("select total_withdrawals from public.user_profile where user_id=$1",[userId]);
  assert.equal(Number(profile.rows[0].total_withdrawals),10,"withdrawal total must increment exactly once");
  const audit = await admin.query("select count(*)::int n from public.transaction_audit where transaction_id=$1 and action='settled'",[txId]);
  assert.equal(audit.rows[0].n,1,"exactly one settlement audit entry must exist");
  const tx = await admin.query("select status from public.transaction where id=$1",[txId]);
  assert.equal(tx.rows[0].status,"completed","winning settlement should complete transaction");
  console.log("PASS: concurrent real RPC settlement serializes; exactly one effect and one audit entry");
} finally {
  await Promise.allSettled([first.end(),second.end()]);
  await admin.query("delete from public.transaction_audit where transaction_id=$1",[txId]).catch(()=>{});
  await admin.query("delete from public.transaction where id=$1",[txId]).catch(()=>{});
  await admin.query("delete from public.admin_user where user_id=$1",[adminId]).catch(()=>{});
  await admin.query("delete from public.user_profile where user_id=$1",[userId]).catch(()=>{});
  await admin.query("delete from auth.users where id in ($1,$2)",[adminId,userId]).catch(()=>{});
  await admin.end();
}
