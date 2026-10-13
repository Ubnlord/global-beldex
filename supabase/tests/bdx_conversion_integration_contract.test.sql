begin;
create extension if not exists pgtap with schema extensions;

-- Conversion integration contract only. The conversion RPC is intentionally not
-- installed yet; these tests protect existing currency separation and establish
-- that the database has the fields needed to reconcile each denomination.
select plan(15);

select has_column('public','user_profile','available_balance','legacy USD available balance remains present');
select has_column('public','user_profile','locked_balance','legacy USD locked balance remains present');
select has_column('public','user_profile','bdx_balance','BDX available balance is separate');
select has_column('public','user_profile','locked_bdx_balance','BDX locked balance is separate');
select has_column('public','user_profile','referral_earnings','legacy referral total remains present');
select has_column('public','user_profile','referral_earnings_bdx','BDX referral total is separate');
select has_column('public','user_investment','currency','investment currency is explicit');
select has_column('public','user_investment','principal','investment principal is reconcilable');
select has_column('public','user_investment','credited_profit','credited profit is reconcilable');
select has_column('public','transaction','currency','transaction currency is explicit');
select has_column('public','transaction','amount','historical transaction amount is preserved');

select ok(
  to_regprocedure('public.convert_legacy_usd_wallets_to_bdx(uuid,numeric,text,timestamptz)') is null,
  'no unreviewed production conversion RPC is installed'
);
select ok(
  to_regprocedure('public.convert_legacy_usd_wallets_to_bdx(uuid,numeric,text,timestamptz)') is null,
  'conversion remains unavailable until the atomic audited implementation is reviewed'
);
select ok(
  (select count(*) = 0 from public.user_profile
   where available_balance < 0 or locked_balance < 0 or bdx_balance < 0 or locked_bdx_balance < 0),
  'no negative wallet balances exist in the isolated fixture at test start'
);
select ok(
  (select count(*) = 0 from public.user_investment where currency not in ('USD','BDX')),
  'investment records use supported denominations only'
);

select * from finish();
rollback;
