-- 194 — Milestone 1 verification: claim_gate_status() across all five gate
-- states, plus a check that the users_guard still blocks normal self-promotion.
--
-- HOW TO RUN: paste this whole file into the Supabase SQL Editor and Run.
-- It creates identifiable fake rows (*@gate-test.example.com), impersonates
-- each fake user, deletes everything it created, and ends with a PASS/FAIL
-- table. Expected: every row shows PASS.

drop table if exists public._gate_results;
create table public._gate_results (ord int, scenario text, expected text, got text);
grant insert on public._gate_results to authenticated;

-- ---------------------------------------------------------------------------
-- Fixtures (run as postgres: bypasses RLS; handle_new_user provisions
-- public.users + public.profiles for each auth user)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-194a-4000-8000-000000000001', 'none@gate-test.example.com'),
  ('00000000-194a-4000-8000-000000000002', 'pending@gate-test.example.com'),
  ('00000000-194a-4000-8000-000000000003', 'rejected@gate-test.example.com'),
  ('00000000-194a-4000-8000-000000000004', 'approved@gate-test.example.com'),
  ('00000000-194a-4000-8000-000000000005', 'suspended@gate-test.example.com');

insert into public.applications (name, email, country, city, status, decided_at) values
  ('Gate Test Pending',  'pending@gate-test.example.com',  'Testland', 'Test City', 'pending',  null),
  ('Gate Test Rejected', 'rejected@gate-test.example.com', 'Testland', 'Test City', 'rejected', now()),
  ('Gate Test Approved', 'approved@gate-test.example.com', 'Testland', 'Test City', 'approved', now());

-- Suspend user 5 (needs the system bypass; cleared immediately after)
select set_config('app.system_write', 'on', false);
update public.users set membership_status = 'suspended'
 where id = '00000000-194a-4000-8000-000000000005';
select set_config('app.system_write', '', false);

-- ---------------------------------------------------------------------------
-- [1] No application → 'none'
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"00000000-194a-4000-8000-000000000001","email":"none@gate-test.example.com","role":"authenticated"}', false);
set role authenticated;
insert into _gate_results select 1, 'no application', 'none', public.claim_gate_status();
reset role;

-- ---------------------------------------------------------------------------
-- [2] Application pending → 'waitlist'
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"00000000-194a-4000-8000-000000000002","email":"pending@gate-test.example.com","role":"authenticated"}', false);
set role authenticated;
insert into _gate_results select 2, 'application pending', 'waitlist', public.claim_gate_status();
reset role;

-- ---------------------------------------------------------------------------
-- [3] Application rejected → 'waitlist' (soft; never a rejection state)
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"00000000-194a-4000-8000-000000000003","email":"rejected@gate-test.example.com","role":"authenticated"}', false);
set role authenticated;
insert into _gate_results select 3, 'application rejected', 'waitlist', public.claim_gate_status();
reset role;

-- ---------------------------------------------------------------------------
-- [4] Application approved → first call promotes → 'approved';
--     second call → 'member'; side effects verified as postgres.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"00000000-194a-4000-8000-000000000004","email":"approved@gate-test.example.com","role":"authenticated"}', false);
set role authenticated;
insert into _gate_results select 4, 'application approved -> first claim', 'approved', public.claim_gate_status();
insert into _gate_results select 5, 'second call after promotion', 'member', public.claim_gate_status();
reset role;

insert into _gate_results
select 6, 'users.membership_status promoted', 'approved',
       (select membership_status from public.users
         where id = '00000000-194a-4000-8000-000000000004');
insert into _gate_results
select 7, 'profiles.visible flipped by trigger', 'true',
       (select visible::text from public.profiles
         where user_id = '00000000-194a-4000-8000-000000000004');

-- ---------------------------------------------------------------------------
-- [5] Membership suspended → 'suspended'
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"00000000-194a-4000-8000-000000000005","email":"suspended@gate-test.example.com","role":"authenticated"}', false);
set role authenticated;
insert into _gate_results select 8, 'membership suspended', 'suspended', public.claim_gate_status();
reset role;

-- ---------------------------------------------------------------------------
-- [6] Guard intact: a normal (non-RPC) self-promotion must still be blocked
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"00000000-194a-4000-8000-000000000002","email":"pending@gate-test.example.com","role":"authenticated"}', false);
do $$
begin
  execute 'set local role authenticated';
  update public.users set membership_status = 'approved'
   where id = '00000000-194a-4000-8000-000000000002';
  -- reaching here means the guard did NOT fire
  insert into _gate_results values (9, 'guard blocks direct self-promotion', 'blocked', 'NOT BLOCKED');
exception when others then
  if sqlerrm like '%system-controlled%' then
    insert into _gate_results values (9, 'guard blocks direct self-promotion', 'blocked', 'blocked');
  else
    raise;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Cleanup (cascades: auth.users -> public.users -> public.profiles)
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '', false);
delete from public.applications where email like '%@gate-test.example.com';
delete from auth.users where email like '%@gate-test.example.com';

-- ---------------------------------------------------------------------------
-- Results
-- ---------------------------------------------------------------------------
select ord, scenario, expected, got,
       case when expected is not distinct from got then 'PASS' else 'FAIL' end as result
from _gate_results
order by ord;

-- The results table sticks around so you can re-inspect it; re-running this
-- script recreates it. To remove it manually: drop table public._gate_results;
