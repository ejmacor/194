-- 194 — Phase 1, Milestone 1: gate RPC + controlled membership promotion
-- Run in the Supabase SQL Editor. Safe to re-run (create-or-replace throughout).
--
-- What this adds:
--   1. A transaction-local system-write escape hatch in users_guard_protected().
--      The guard normally blocks non-admins from touching membership_status /
--      verification_status / nationality_code — and because is_admin() reads
--      the CALLER's JWT, even SECURITY DEFINER functions hit it. Trusted RPCs
--      opt out for a single statement via set_config('app.system_write','on',true),
--      which can never leak past the current transaction.
--   2. claim_gate_status(): the single RPC the app calls after OTP login.
--      Resolves the caller's gate state from users.membership_status and the
--      applications row matching their verified email, promoting
--      applied → approved when their application was approved.
--      Returns: 'member' | 'approved' | 'waitlist' | 'none' | 'suspended'.
--
-- Security notes:
--   - EXECUTE granted to authenticated only; anon cannot probe email statuses.
--   - Status is resolved from auth.jwt()->>'email' — the OTP-verified email of
--     the caller — never from a client-supplied parameter.
--   - No new SELECT policies on applications: the definer context reads it here,
--     and this RPC is the only path by which a member learns their status.
--   - Rejected states (application or membership) surface as 'waitlist':
--     rejections are deliberately soft and the app never renders them.

-- ===========================================================================
-- 1. Guard with scoped system-write bypass (otherwise identical to 0001)
-- ===========================================================================
create or replace function public.users_guard_protected()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Scoped bypass for trusted SECURITY DEFINER RPCs (e.g. claim_gate_status).
  -- Transaction-local by construction: set_config(..., is_local => true).
  if current_setting('app.system_write', true) = 'on' then
    return new;
  end if;
  if public.is_admin() then
    return new;                                     -- admins may set anything
  end if;
  if tg_op = 'INSERT' then
    if new.membership_status <> 'applied'
       or new.verification_status <> 'pending'
       or new.nationality_code is not null then
      raise exception 'membership/verification/nationality are system-controlled';
    end if;
  elsif tg_op = 'UPDATE' then
    if new.membership_status  is distinct from old.membership_status
       or new.verification_status is distinct from old.verification_status
       or new.nationality_code    is distinct from old.nationality_code then
      raise exception 'membership/verification/nationality are system-controlled';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists users_guard on public.users;
create trigger users_guard
  before insert or update on public.users
  for each row execute function public.users_guard_protected();

-- ===========================================================================
-- 2. The gate RPC
-- ===========================================================================
create or replace function public.claim_gate_status()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_email      text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_membership text;
  v_app_status text;
begin
  if v_uid is null or v_email = '' then
    raise exception 'authentication required';
  end if;

  -- Rows are normally provisioned by handle_new_user on signup; be defensive
  -- anyway (defaults pass the guard, and profiles_guard derives visibility).
  insert into public.users (id) values (v_uid) on conflict (id) do nothing;
  insert into public.profiles (user_id) values (v_uid) on conflict (user_id) do nothing;

  select membership_status into v_membership
  from public.users where id = v_uid;

  if v_membership = 'suspended' then return 'suspended'; end if;
  if v_membership = 'approved'  then return 'member';    end if;
  if v_membership = 'rejected'  then return 'waitlist';  end if;  -- soft rejection

  -- membership_status = 'applied' → resolve via the waitlist application
  -- belonging to the caller's OTP-verified email.
  select status into v_app_status
  from public.applications
  where lower(email) = v_email
  order by created_at desc
  limit 1;

  if v_app_status is null then
    return 'none';
  elsif v_app_status = 'approved' then
    -- Controlled promotion: applied → approved, under the scoped bypass.
    -- users_sync_visibility then flips profiles.visible via its own trigger.
    perform set_config('app.system_write', 'on', true);
    update public.users
       set membership_status = 'approved'
     where id = v_uid
       and membership_status = 'applied';
    perform set_config('app.system_write', '', true);   -- close the window early
    return 'approved';
  else
    return 'waitlist';  -- pending and rejected both read as waitlist
  end if;
end $$;

-- create function grants EXECUTE to PUBLIC by default — remove that, then
-- grant to signed-in users only. anon gets nothing: no email-status probing.
revoke all on function public.claim_gate_status() from public;
grant execute on function public.claim_gate_status() to authenticated;
