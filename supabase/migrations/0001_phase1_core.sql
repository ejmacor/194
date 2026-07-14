-- 194 — Phase 1 core schema: members, profiles, messaging, safety
-- Run in the Supabase SQL Editor. Safe to re-run (idempotent-ish: drops policies
-- before recreating; uses "if not exists" for tables).
--
-- RLS rules enforced (per spec §4):
--   1. Users read/write only their own rows.
--   2. `instagram` + verification/membership internals readable only by admins.
--   3. Profiles visible to other members only when membership_status = 'approved'.
--
-- Relies on public.is_admin() from 0000_phase0_applications.sql.

-- ===========================================================================
-- Tables
-- ===========================================================================
create table if not exists public.users (
  id                  uuid primary key references auth.users (id) on delete cascade,
  display_name        text,
  birthdate           date,
  city                text,
  nationality_code    text,                                   -- ISO 3166-1 alpha-2, set by ID verification
  languages           text[] not null default '{}',
  verification_status text not null default 'pending'
                        check (verification_status in ('pending','verified','failed','us_blocked')),
  membership_status   text not null default 'applied'
                        check (membership_status in ('applied','approved','rejected','suspended')),
  instagram           text,                                   -- admin-only
  created_at          timestamptz not null default now()
);

create table if not exists public.profiles (
  user_id  uuid primary key references public.users (id) on delete cascade,
  photos   text[] not null default '{}',                     -- Supabase Storage paths
  prompt_1 text,
  prompt_2 text,
  visible  boolean not null default false                    -- driven by membership approval (trigger below)
);

create table if not exists public.conversations (
  id         uuid primary key default gen_random_uuid(),
  user_a     uuid not null references public.users (id) on delete cascade,
  user_b     uuid not null references public.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint conversations_distinct_participants check (user_a <> user_b)
);
-- One conversation per unordered pair.
create unique index if not exists conversations_pair_uniq
  on public.conversations (least(user_a, user_b), greatest(user_a, user_b));

create table if not exists public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender          uuid not null references public.users (id) on delete cascade,
  body            text,
  image_url       text,
  created_at      timestamptz not null default now(),
  constraint messages_have_content check (body is not null or image_url is not null)
);
create index if not exists messages_conversation_idx on public.messages (conversation_id, created_at);

create table if not exists public.blocks (
  blocker    uuid not null references public.users (id) on delete cascade,
  blocked    uuid not null references public.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  constraint blocks_distinct check (blocker <> blocked)
);

create table if not exists public.reports (
  id         uuid primary key default gen_random_uuid(),
  reporter   uuid not null references public.users (id) on delete cascade,
  reported   uuid not null references public.users (id) on delete cascade,
  reason     text not null check (reason in ('fake','harassment','spam','other')),
  detail     text,
  status     text not null default 'open' check (status in ('open','reviewing','closed')),
  created_at timestamptz not null default now()
);
create index if not exists reports_status_idx on public.reports (status);

-- ===========================================================================
-- Auto-provision a users + profiles row on signup
-- ===========================================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.users (id) values (new.id) on conflict (id) do nothing;
  insert into public.profiles (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ===========================================================================
-- Guard: non-admins cannot self-escalate protected columns
-- ===========================================================================
create or replace function public.users_guard_protected()
returns trigger language plpgsql security definer set search_path = public as $$
begin
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

-- Keep profile visibility tied to membership approval.
create or replace function public.sync_profile_visibility()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.profiles
     set visible = (new.membership_status = 'approved')
   where user_id = new.id;
  return new;
end $$;

drop trigger if exists users_sync_visibility on public.users;
create trigger users_sync_visibility
  after update of membership_status on public.users
  for each row execute function public.sync_profile_visibility();

-- Non-admins cannot manually flip their own profile visibility: it is always
-- derived from their membership status.
create or replace function public.profiles_guard_visible()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.visible := coalesce(
      (select membership_status = 'approved' from public.users where id = new.user_id),
      false);
  end if;
  return new;
end $$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before insert or update on public.profiles
  for each row execute function public.profiles_guard_visible();

-- ===========================================================================
-- Row Level Security
-- ===========================================================================
alter table public.users         enable row level security;
alter table public.profiles      enable row level security;
alter table public.conversations enable row level security;
alter table public.messages      enable row level security;
alter table public.blocks        enable row level security;
alter table public.reports       enable row level security;

-- ---- users ---------------------------------------------------------------
drop policy if exists users_self_select  on public.users;
drop policy if exists users_admin_select on public.users;
drop policy if exists users_self_insert  on public.users;
drop policy if exists users_self_update  on public.users;
drop policy if exists users_admin_update on public.users;

create policy users_self_select  on public.users for select to authenticated using (id = auth.uid());
create policy users_admin_select on public.users for select to authenticated using (public.is_admin());
create policy users_self_insert  on public.users for insert to authenticated with check (id = auth.uid());
create policy users_self_update  on public.users for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy users_admin_update on public.users for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---- profiles ------------------------------------------------------------
drop policy if exists profiles_self_select on public.profiles;
drop policy if exists profiles_self_insert on public.profiles;
drop policy if exists profiles_self_update on public.profiles;
drop policy if exists profiles_admin_select on public.profiles;

create policy profiles_self_select  on public.profiles for select to authenticated using (user_id = auth.uid());
create policy profiles_self_insert  on public.profiles for insert to authenticated with check (user_id = auth.uid());
create policy profiles_self_update  on public.profiles for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy profiles_admin_select on public.profiles for select to authenticated using (public.is_admin());
-- No self-delete (profile row is 1:1 with the account). Cross-member reads go
-- through the member_cards view (below), never this table.

-- ---- conversations -------------------------------------------------------
drop policy if exists conversations_participant_select on public.conversations;
drop policy if exists conversations_participant_insert on public.conversations;
drop policy if exists conversations_admin              on public.conversations;

-- Conversations are immutable (no update/delete): a participant can create one
-- and read the ones they're in; founders can read all for moderation.
create policy conversations_participant_select on public.conversations for select to authenticated
  using (auth.uid() in (user_a, user_b));
create policy conversations_participant_insert on public.conversations for insert to authenticated
  with check (auth.uid() in (user_a, user_b));
create policy conversations_admin on public.conversations for select to authenticated using (public.is_admin());

-- ---- messages ------------------------------------------------------------
drop policy if exists messages_participant_select on public.messages;
drop policy if exists messages_participant_insert on public.messages;
drop policy if exists messages_admin_select       on public.messages;

create policy messages_participant_select on public.messages for select to authenticated
  using (exists (
    select 1 from public.conversations c
    where c.id = conversation_id and auth.uid() in (c.user_a, c.user_b)
  ));
create policy messages_participant_insert on public.messages for insert to authenticated
  with check (
    sender = auth.uid()
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id and auth.uid() in (c.user_a, c.user_b)
    )
  );
create policy messages_admin_select on public.messages for select to authenticated using (public.is_admin());

-- ---- blocks --------------------------------------------------------------
drop policy if exists blocks_self_all on public.blocks;
drop policy if exists blocks_admin_select on public.blocks;

create policy blocks_self_all     on public.blocks for all    to authenticated using (blocker = auth.uid()) with check (blocker = auth.uid());
create policy blocks_admin_select on public.blocks for select to authenticated using (public.is_admin());

-- ---- reports -------------------------------------------------------------
drop policy if exists reports_insert     on public.reports;
drop policy if exists reports_self_select on public.reports;
drop policy if exists reports_admin_all  on public.reports;

create policy reports_insert      on public.reports for insert to authenticated with check (reporter = auth.uid());
create policy reports_self_select on public.reports for select to authenticated using (reporter = auth.uid());
create policy reports_admin_all   on public.reports for all    to authenticated using (public.is_admin()) with check (public.is_admin());

-- ===========================================================================
-- Discovery view: approved members see each other's PUBLIC fields only.
-- Security-definer (reads base tables past their RLS) but exposes no sensitive
-- columns (no instagram / birthdate / verification), only to approved callers,
-- and hides blocked pairs + self.
-- ===========================================================================
create or replace view public.member_cards
with (security_invoker = off) as
select
  u.id                                            as user_id,
  u.display_name,
  extract(year from age(u.birthdate))::int        as age,
  u.city,
  u.nationality_code,
  u.languages,
  p.photos,
  p.prompt_1,
  p.prompt_2
from public.users u
join public.profiles p on p.user_id = u.id
where u.membership_status = 'approved'
  and p.visible = true
  and u.id <> auth.uid()
  and exists (
    select 1 from public.users me
    where me.id = auth.uid() and me.membership_status = 'approved'
  )
  and not exists (
    select 1 from public.blocks b
    where (b.blocker = auth.uid() and b.blocked = u.id)
       or (b.blocker = u.id      and b.blocked = auth.uid())
  );

revoke all on public.member_cards from anon;
grant select on public.member_cards to authenticated;

-- ===========================================================================
-- Realtime for messaging
-- ===========================================================================
do $$
begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.conversations;
exception when duplicate_object then null;
end $$;
