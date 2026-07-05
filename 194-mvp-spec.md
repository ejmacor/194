# 194 — MVP Feature Spec

**Version:** 1.0 · July 2026
**Founders:** Emmitt Macor (CEO), Zane Johnson (CTO)
**Purpose of this doc:** Blueprint for the initial build. Written to be handed directly to Claude Code as project context.

---

## 1. Product overview

194 is an invite-only social network for internationals living in the US. US passport holders cannot join — identity verification at signup checks the issuing country of a government ID and gates entry. Positioning is Raya-style exclusivity: apply, wait, get approved, belong.

**One-liner:** 195 countries. One doesn't get in.

**Target user:** foreign-born people living in the US (~50M+ population) — students, H-1B/O-1 workers, dual citizens, recent arrivals — who want a social layer built around the shared experience of being international in America.

**Not in MVP:** dating features (v2, shipped as a toggle inside the existing app), Android-first polish, events, monetization.

---

## 2. Tech stack

| Layer | Choice | Notes |
|---|---|---|
| Mobile app | React Native + Expo | One codebase, iOS priority, TestFlight beta |
| Backend | Supabase | Postgres, Auth, Realtime, Storage, Edge Functions |
| ID verification | Stripe Identity (or Persona) | Returns document issuing country; we never store document images |
| Transactional email | Resend | Approval / rejection / waitlist emails |
| Waitlist site | Static HTML (already built: `194-landing.html`) | Deploy on GitHub Pages or Render |
| Admin dashboard | Web app (already prototyped: `194-border-control.html`) | Rebuild as small React app reading live Supabase data |

---

## 3. Phases

### Phase 0 — Waitlist (pre-app, ship first)

Already prototyped. Remaining work:

1. Create Supabase project, `applications` table (schema below).
2. Wire landing page form → insert into `applications`.
3. Rebuild Border Control dashboard against live data, protected by Supabase Auth (email allowlist: founders only).
4. Approve action → Edge Function sends "You're in" email via Resend; Reject → polite waitlist email.
5. Deploy landing at join194.com, dashboard at an unlisted route.

### Phase 1 — MVP app (iOS via TestFlight)

**1. Onboarding & the Gate**
- Invite code or approved-email entry from the waitlist.
- Supabase Auth (email OTP; no passwords).
- ID verification step: Stripe Identity native flow. Read `document.issuing_country` from the verification result.
  - `US` → hard stop screen ("194 is for the other 194 countries."). Account flagged, cannot proceed.
  - Anything else → proceed. Store only: issuing country code, verification status, timestamp. **Never store document images or numbers.**
- Edge case: dual citizens with a US passport + another passport — MVP rule: any non-US government ID passes. Document this in the app's FAQ.

**2. Application & approval (in-app)**
- Profile draft: name, photos (2–6), nationality (from verification, not editable), city, languages, "what brought you to the US" prompt, Instagram handle (private, admin-only).
- Submitted profiles land in Border Control queue → founder approves/rejects.
- States: `draft → submitted → approved | rejected | waitlisted`. Push notification + email on decision.

**3. Profiles**
- Photo carousel, name + age, nationality flag, city, languages, prompt answers.
- Nationality is verified — show a small "verified" mark tied to the ID check. This is the product's trust primitive.

**4. Discovery**
- Card/grid feed of approved members, filterable by city, nationality, language.
- MVP sort: same city first, then recency. No algorithm yet.

**5. Messaging**
- 1:1 DMs via Supabase Realtime. Text + photos. Read receipts optional (default off).
- MVP anti-spam rule: max 10 new conversations started per day per user.

**6. Safety & moderation (required for App Store approval)**
- Block and report on every profile and conversation (report reasons: fake, harassment, spam, other).
- Reports land in Border Control with a `reports` tab; founders can suspend accounts.
- EULA + community guidelines screen at signup (Apple requires this for UGC apps).

### Phase 2 — v2 (not in MVP, listed so schema anticipates it)
- Dating mode toggle (opt-in, separate discovery pool).
- Communities by nationality/city; events.
- Membership pricing (Raya model: ~$10–25/mo) once density exists.

---

## 4. Data model (Supabase / Postgres)

```sql
-- Phase 0
applications (
  id uuid pk default gen_random_uuid(),
  name text, email text unique, country text, city text,
  instagram text,              -- RLS: admin-only read
  status text default 'pending',  -- pending | approved | rejected
  created_at timestamptz default now(),
  decided_at timestamptz, decided_by uuid
)

-- Phase 1
users (
  id uuid pk references auth.users,
  display_name text, birthdate date, city text,
  nationality_code text,       -- ISO 3166-1 alpha-2, from ID verification
  languages text[],
  verification_status text,    -- pending | verified | failed | us_blocked
  membership_status text,      -- applied | approved | rejected | suspended
  instagram text,              -- RLS: admin-only read
  created_at timestamptz default now()
)

profiles (
  user_id uuid pk references users,
  photos text[],                -- Supabase Storage paths
  prompt_1 text, prompt_2 text,
  visible boolean default false -- true only when approved
)

conversations ( id uuid pk, user_a uuid, user_b uuid, created_at timestamptz )
messages ( id uuid pk, conversation_id uuid, sender uuid, body text, image_url text, created_at timestamptz )
blocks ( blocker uuid, blocked uuid, created_at timestamptz )
reports ( id uuid pk, reporter uuid, reported uuid, reason text, detail text, status text default 'open', created_at timestamptz )
```

**Row Level Security is non-negotiable:** users read/write only their own rows; `instagram` and verification fields readable only by an `admin` role; `profiles` visible to other users only when `membership_status = 'approved'`.

---

## 5. Design system

- **Palette:** ink navy `#0B1120`, panel `#0F172B`, gold foil `#C8A55E`, bright foil `#E3C888`, paper `#EDE8DC`, muted `#7C8699`.
- **Type:** Cinzel (display, sparingly — headers, the 194 mark), Sora (body/UI), Share Tech Mono (labels, metadata, MRZ-style accents).
- **Motifs:** passport stamps for status states ("RECEIVED", "APPROVED"), MRZ strips as decorative dividers, guilloché ring backgrounds. Dark mode only in MVP.
- **Voice:** border-control deadpan. Approvals feel like clearing customs, not winning a raffle.

---

## 6. Success metrics (day-90 targets for the ND beta)

- 500+ waitlist applications; 150+ approved members in the launch city (South Bend/Chicago or NYC).
- 40% weekly active among approved members.
- 60% of members start ≥1 conversation in week 1.
- Zero verification bypasses; <24h median application decision time.

---

## 7. Build order for Claude Code

1. Supabase project + full schema + RLS policies.
2. Wire landing page form (Phase 0).
3. Border Control as a small React web app on live data + auth + Resend emails.
4. Expo app scaffold: auth → verification gate → application flow.
5. Profiles + discovery feed.
6. DMs.
7. Block/report + guidelines screens.
8. TestFlight build.

Each step should be shippable and testable before starting the next.
