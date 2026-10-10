begin;

-- Align legacy non-GNS investments with their published plan rates.
-- The catalogue currently holds the correct total ROI / duration rates.
-- Only raise an investment's rate when its stored snapshot is below the
-- catalogue rate; never lower a rate that was already higher.
do $migration$
declare
  v_inv record;
  v_target_rate numeric;
  v_accrued_days integer;
  v_delta numeric;
begin
  for v_inv in
    select ui.id, ui.user_id, ui.plan_id, ui.principal, ui.daily_rate,
           ui.started_at, ui.last_accrual_at, ui.duration_days, ui.credited_profit
      from public.user_investment ui
      join public.investment_plan_catalog pc on pc.id = ui.plan_id
     where ui.plan_id in ('build', 'follow', 'apex', 'edifex', 'dixon', 'falcon')
       and ui.status in ('active', 'completed')
       and ui.daily_rate < pc.daily_rate
     for update of ui
  loop
    select daily_rate into v_target_rate
      from public.investment_plan_catalog
     where id = v_inv.plan_id;

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

    v_delta := round(
      v_inv.principal * (v_target_rate - v_inv.daily_rate) * v_accrued_days,
      18
    );

    update public.user_investment
       set daily_rate = v_target_rate,
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
        v_inv.plan_id || ' historical interest correction',
        'Server-side investment profit correction'
      );
    end if;
  end loop;
end;
$migration$;

commit;