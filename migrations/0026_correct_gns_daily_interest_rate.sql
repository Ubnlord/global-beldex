begin;

-- GNS PLAN terms are 1.90% total over 30 days (simple interest).
-- The old server rate, 0.0019 / 30, incorrectly represented 0.19% total.
do $migration$
declare
  v_old_rate numeric := round(0.0019::numeric / 30, 18);
  v_new_rate numeric := round(0.019::numeric / 30, 18);
  v_inv record;
  v_accrued_days integer;
  v_delta numeric;
begin
  update public.investment_plan_catalog
     set daily_rate = v_new_rate,
         updated_at = now()
   where id = 'gns'
     and daily_rate is distinct from v_new_rate;

  -- Correct only GNS investments that carry the known incorrect rate.
  -- last_accrual_at represents the days already processed; days after it
  -- remain for the normal accrual function and are not included in this credit.
  for v_inv in
    select id, user_id, principal, started_at, last_accrual_at,
           duration_days, status
      from public.user_investment
     where plan_id = 'gns'
       and status in ('active', 'completed')
       and daily_rate = v_old_rate
     for update
  loop
    v_accrued_days := least(
      v_inv.duration_days,
      greatest(
        0,
        floor(
          extract(epoch from (
            least(
              v_inv.last_accrual_at,
              v_inv.started_at + make_interval(days => v_inv.duration_days)
            ) - v_inv.started_at
          )) / 86400
        )::integer
      )
    );

    v_delta := round(v_inv.principal * (v_new_rate - v_old_rate) * v_accrued_days, 18);

    update public.user_investment
       set daily_rate = v_new_rate,
           credited_profit = credited_profit + v_delta,
           updated_at = now()
     where id = v_inv.id;

    if v_delta > 0 then
      update public.user_profile
         set available_balance = available_balance + v_delta,
             updated_at = now()
       where user_id = v_inv.user_id;

      insert into public.transaction(
        user_id, type, amount, status, approval_status, method, note
      )
      values (
        v_inv.user_id,
        'bonus',
        v_delta,
        'completed',
        'approved',
        'GNS historical interest correction',
        'Server-side investment profit'
      );
    end if;
  end loop;
end;
$migration$;

commit;