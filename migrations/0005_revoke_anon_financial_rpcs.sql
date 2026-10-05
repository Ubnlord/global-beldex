-- Public Data API hardening: financial RPCs require an authenticated session.
revoke execute on function public.accrue_user_investments(uuid) from public, anon;
revoke execute on function public.buy_investment_plan(text,numeric) from public, anon;
revoke execute on function public.create_financial_transaction(text,numeric,text,text) from public, anon;
revoke execute on function public.swap_assets(text,text,numeric,numeric) from public, anon;
revoke execute on function public.ensure_user_profile(text,text,text,text,text) from public, anon;
revoke execute on function public.update_user_profile(text,text,text,text,text) from public, anon;
