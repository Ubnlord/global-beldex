import assert from "node:assert/strict";
import { Client } from "pg";

const connectionString = process.env.DB_URL;
if (!connectionString) throw new Error("DB_URL is required for isolated concurrency regression");

const admin = new Client({ connectionString });
await admin.connect();
const schema = "bdx_conversion_concurrency_test";

try {
  await admin.query(`drop schema if exists ${schema} cascade`);
  await admin.query(`create schema ${schema}`);
  await admin.query(`
    create table ${schema}.account_state (
      user_id text primary key,
      available_usd numeric(38,18) not null,
      available_bdx numeric(38,18) not null default 0
    );
    create table ${schema}.conversion_run (
      conversion_id uuid primary key,
      user_id text not null unique,
      quote numeric(38,18) not null,
      quote_source text not null,
      observed_at timestamptz not null
    );
    create table ${schema}.audit_map (
      conversion_id uuid not null,
      user_id text not null,
      source_usd numeric(38,18) not null,
      target_bdx numeric(38,18) not null,
      primary key (conversion_id, user_id)
    );
    insert into ${schema}.account_state(user_id, available_usd) values ('race-account', 100);
    create function ${schema}.convert_once(p_conversion_id uuid, p_user_id text, p_quote numeric)
    returns text language plpgsql as $fn$
    declare v_run ${schema}.conversion_run%rowtype; v_usd numeric;
    begin
      if p_quote is null or p_quote <= 0 then raise exception 'invalid quote'; end if;
      perform pg_advisory_xact_lock(hashtextextended(p_user_id, 741109));
      -- Intentionally widen the race window so both independent sessions overlap.
      perform pg_sleep(0.25);
      select * into v_run from ${schema}.conversion_run where user_id=p_user_id;
      if found then
        if v_run.conversion_id=p_conversion_id then return 'already_converted'; end if;
        raise exception 'account already converted by another run';
      end if;
      select available_usd into v_usd from ${schema}.account_state where user_id=p_user_id for update;
      if not found then raise exception 'account not found'; end if;
      insert into ${schema}.conversion_run values(p_conversion_id,p_user_id,p_quote,'test-provider',now());
      insert into ${schema}.audit_map values(p_conversion_id,p_user_id,v_usd,round(v_usd/p_quote,18));
      update ${schema}.account_state set available_usd=0, available_bdx=available_bdx+round(v_usd/p_quote,18)
        where user_id=p_user_id;
      return 'converted';
    end $fn$;
  `);

  const first = new Client({ connectionString });
  const second = new Client({ connectionString });
  await Promise.all([first.connect(), second.connect()]);
  const conversionId = "a0000000-0000-4000-8000-000000000001";
  try {
    const results = await Promise.all([
      first.query(`select ${schema}.convert_once($1::uuid,$2,$3::numeric) as result`, [conversionId, "race-account", "0.1"]),
      second.query(`select ${schema}.convert_once($1::uuid,$2,$3::numeric) as result`, [conversionId, "race-account", "0.1"])
    ]);
    assert.deepEqual(results.map(r => r.rows[0].result).sort(), ["already_converted", "converted"]);
    const state = await admin.query(`select available_usd, available_bdx from ${schema}.account_state where user_id='race-account'`);
    assert.equal(Number(state.rows[0].available_usd), 0, "source USD balance must be zero after conversion");
    assert.equal(Number(state.rows[0].available_bdx), 1000, "destination BDX balance must be credited exactly once");
    const runs = await admin.query(`select count(*)::int as n from ${schema}.conversion_run`);
    const maps = await admin.query(`select count(*)::int as n from ${schema}.audit_map`);
    assert.equal(runs.rows[0].n, 1, "concurrent same-ID attempts must produce one run row");
    assert.equal(maps.rows[0].n, 1, "concurrent same-ID attempts must produce one immutable source mapping");
  } finally {
    await Promise.all([first.end(), second.end()]);
  }

  // Force an exception after the audit insert and balance write. PostgreSQL must
  // roll back the whole statement, including both audit and run marker.
  await admin.query(`insert into ${schema}.account_state(user_id, available_usd) values ('rollback-account', 25)`);
  await admin.query(`create function ${schema}.fail_after_write(p_conversion_id uuid)
    returns void language plpgsql as $fn$
    begin
      insert into ${schema}.conversion_run values(p_conversion_id,'rollback-account',0.1,'test-provider',now());
      insert into ${schema}.audit_map values(p_conversion_id,'rollback-account',25,250);
      update ${schema}.account_state set available_usd=0,available_bdx=available_bdx+250 where user_id='rollback-account';
      raise exception 'forced rollback';
    end $fn$`);
  await assert.rejects(
    admin.query(`select ${schema}.fail_after_write('a0000000-0000-4000-8000-000000000002')`),
    /forced rollback/
  );
  const rolledBack = await admin.query(`
    select a.available_usd, a.available_bdx,
      (select count(*)::int from ${schema}.conversion_run where user_id='rollback-account') as runs,
      (select count(*)::int from ${schema}.audit_map where user_id='rollback-account') as maps
    from ${schema}.account_state a where a.user_id='rollback-account'
  `);
  assert.equal(Number(rolledBack.rows[0].available_usd), 25, "rollback preserves source USD balance");
  assert.equal(Number(rolledBack.rows[0].available_bdx), 0, "rollback preserves destination BDX balance");
  assert.equal(rolledBack.rows[0].runs, 0, "rollback must remove conversion marker");
  assert.equal(rolledBack.rows[0].maps, 0, "rollback must remove audit mapping");

  console.log("PASS: two independent PostgreSQL sessions serialize same-ID conversion; one effect, one mapping");
  console.log("PASS: forced exception rolls back balance changes, conversion marker, and audit mapping");
} finally {
  await admin.query(`drop schema if exists ${schema} cascade`);
  await admin.end();
}
