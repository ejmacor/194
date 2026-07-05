-- 194 — Phase 0 schema: waitlist applications
-- Run this in the Supabase SQL Editor (or via `supabase db push`).
--
-- Scope: the `applications` table that the landing page form writes to, plus
-- the admin primitive (founders-only) used to gate reads/decisions.
-- Phase 1 tables (users, profiles, conversations, messages, blocks, reports)
-- ship in a later migration.

-- ---------------------------------------------------------------------------
-- Admin primitive: founders-only allowlist
-- ---------------------------------------------------------------------------
-- Border Control (the dashboard) authenticates founders via Supabase Auth.
-- An email in this table is treated as an admin everywhere RLS calls is_admin().
create table if not exists public.admins (
  email text primary key,
  added_at timestamptz not null default now()
);

-- No one reads/writes this table through the API; managed by service role only.
alter table public.admins enable row level security;

-- SECURITY DEFINER so it can read public.admins regardless of the caller's RLS.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins
    where email = (auth.jwt() ->> 'email')
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- applications
-- ---------------------------------------------------------------------------
create table if not exists public.applications (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  email       text not null unique,
  country     text,
  city        text,
  instagram   text,                                   -- admin-only (whole table is)
  status      text not null default 'pending'
              check (status in ('pending', 'approved', 'rejected')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  decided_by  uuid references auth.users (id)
);

create index if not exists applications_status_idx     on public.applications (status);
create index if not exists applications_created_at_idx  on public.applications (created_at desc);

alter table public.applications enable row level security;

-- Belt-and-suspenders: ensure the API roles have the table privileges RLS gates.
-- (Supabase grants these by default; explicit here so a re-run is self-contained.)
grant insert on public.applications to anon, authenticated;
grant select, update on public.applications to authenticated;

-- Policies are dropped-then-created so this whole file is safe to re-run.
drop policy if exists "public can submit applications" on public.applications;
drop policy if exists "admins read applications"        on public.applications;
drop policy if exists "admins update applications"      on public.applications;

-- Anyone (anon landing form) may submit an application, but only as a fresh
-- pending row — they cannot pre-approve themselves or stamp a decision.
create policy "public can submit applications"
  on public.applications
  for insert
  to anon, authenticated
  with check (
    status = 'pending'
    and decided_at is null
    and decided_by is null
  );

-- Only founders can read the queue (covers the admin-only `instagram` field).
create policy "admins read applications"
  on public.applications
  for select
  to authenticated
  using (public.is_admin());

-- Only founders can approve/reject.
create policy "admins update applications"
  on public.applications
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- No delete policy => deletes are denied for everyone but the service role.

-- ---------------------------------------------------------------------------
-- Seed founders (edit these to your real founder emails, then re-run this block)
-- ---------------------------------------------------------------------------
insert into public.admins (email) values
  ('ejmacor@gmail.com')       -- Emmitt Macor (CEO)
  -- ('zane@...')             -- Zane Johnson (CTO)
on conflict (email) do nothing;
