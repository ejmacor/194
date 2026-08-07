# 194 — Mobile App Build Brief (Claude Code)

You are building the 194 iOS app (React Native + Expo) inside this repo. The backend already exists and is live in production — your job is to build the app against it, not to redesign it.

## Read these first, in order — before writing any code

1. `194-mvp-spec.md` — product spec, design system, build order
2. `supabase/migrations/0000_phase0_applications.sql` — the live `applications` (waitlist) table + `is_admin()` primitive
3. `supabase/migrations/0001_phase1_core.sql` — the live Phase 1 schema: `users`, `profiles`, `conversations`, `messages`, `blocks`, `reports`, RLS policies, triggers, and the `member_cards` discovery view
4. `public/index.html` — the live landing page; this is the brand reference (palette, fonts, passport/border-control motifs, voice)
5. `supabase/functions/send-decision-email/index.ts` — how approval/rejection decisions flow today

Both migrations are ALREADY APPLIED in production. Never edit them. All schema changes go in new migrations (`0002_...` onward).

## The Gate (core requirement)

The app's entry experience is a state machine driven by the user's email against the live `applications` table (`status` ∈ `pending | approved | rejected`) and, once they have an account, `users.membership_status` (`applied | approved | rejected | suspended`).

**Flow:**

1. Open app → single email field (brand: passport-control feel, not a generic login).
2. Supabase Auth **email OTP** (6-digit code, `signInWithOtp` with `shouldCreateUser: true`, then `verifyOtp`). No passwords. Verifying the OTP proves email ownership — status is only ever revealed to the verified owner of that email, never to an unauthenticated prober.
3. After OTP verification, call a single RPC (you will create it — see Milestone 1) that resolves and returns the gate state:
   - **`member`** — `users.membership_status = 'approved'` → straight into the main app (or onboarding if profile incomplete).
   - **`approved`** — application approved but membership not yet claimed → the RPC promotes them (see promotion path below) → onboarding.
   - **`waitlist`** — application exists with status `pending` **or `rejected`** → waitlist screen. Rejections are deliberately soft: the Phase 0 reject email is already a polite waitlist email, so the app must match. Never render a rejection state.
   - **`none`** — no application row for this email → Apply screen: an in-app application form (same fields the landing form inserts: name, email prefilled + locked to the authenticated email, country, city, instagram) inserting a `pending` row into `applications`, plus a secondary link out to https://join194.com. After submitting, land on the waitlist screen.
   - **`suspended`** — `users.membership_status = 'suspended'` → locked screen, support contact hello@join194.com, sign-out only.
4. The waitlist screen re-checks status on app foreground and on pull-to-refresh, so an approval flips the experience without reinstalling.

**Screens use the passport-stamp motif for states** (RECEIVED / ON THE WAITLIST / APPROVED), per the design system in the spec. Voice is border-control deadpan.

## Milestone 1 — Migration `0002`: gate RPC + controlled membership promotion

This is the only backend work, and there is a trap you must design around:

- `0001` installs a `users_guard` trigger: non-admins cannot INSERT or UPDATE `membership_status`, `verification_status`, or `nationality_code`. `is_admin()` reads the **caller's JWT**, so even a `SECURITY DEFINER` function does not bypass the trigger — the guard will still see the end user's JWT and raise.
- Therefore: build one `SECURITY DEFINER` RPC, e.g. `claim_gate_status()`, that (a) looks up `applications` by `auth.jwt()->>'email'`, (b) if the application is `approved` and the caller's `users.membership_status` is still `'applied'`, promotes it to `'approved'` — using a scoped bypass the guard respects, e.g. `perform set_config('app.system_write', 'on', true)` (transaction-local) and a corresponding `current_setting('app.system_write', true) = 'on'` escape hatch added to the guard function — then (c) returns the final gate state as text: `member | approved | waitlist | none | suspended`.
- The bypass must be transaction-local (`set_config(..., true)`) so it can never leak into other statements, and the guard change must keep every existing protection intact for normal writes.
- `GRANT EXECUTE` to `authenticated` only. No new SELECT policies on `applications` for regular users — status flows only through this RPC.
- Client code never sees or uses the service-role key. RLS is the security model; do not weaken any existing policy.
- Write the migration idempotently (drop/recreate function + guard, matching the style of `0000`/`0001`), and test it in the Supabase SQL editor against all five states before moving on.

## Milestone 2 — Expo scaffold

- Expo managed workflow, TypeScript, `expo-router`, in a new `app/` directory at repo root (keep the existing `public/` and `supabase/` untouched).
- `@supabase/supabase-js` with session persistence via `expo-secure-store` (+ `react-native-url-polyfill`).
- Env: `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_ANON_KEY` in `app/.env` (gitignored) + `app/.env.example` committed. Anon key only — never the service role.
- Theme module encoding the spec's design system: ink `#0B1120`, panel `#0F172B`, gold foil `#C8A55E`, bright foil `#E3C888`, paper `#EDE8DC`, muted `#7C8699`; fonts Cinzel (display, sparingly), Sora (body/UI), Share Tech Mono (labels/metadata/MRZ accents) via `@expo-google-fonts`. Dark mode only.
- Reusable components: gold-foil button, passport-stamp badge, MRZ-strip divider.

## Milestone 3 — Auth + Gate

- Email entry → OTP code entry → `claim_gate_status()` → route to the correct screen per the state machine above.
- Handle: resend-code cooldown, wrong code, expired session, sign out (available from every gate screen).
- Setup note to surface to the founder (dashboard steps you can't do): Supabase → Authentication → Email provider must have OTP enabled; default Supabase email sender is fine for dev, Resend SMTP later.

## Milestone 4 — Onboarding (approved members only)

Profile draft per spec §Phase 1.2, writing to the existing `users` + `profiles` rows (auto-created by the `handle_new_user` trigger): display_name, birthdate, city, languages, instagram (admin-only field), photos (2–6) uploaded to a Supabase Storage bucket `photos` (create it with owner-write / authenticated-read policies in migration or documented dashboard steps), prompt_1 + prompt_2. Do NOT write `nationality_code` or `verification_status` — those are system-controlled and belong to the deferred ID-verification milestone. Completion → main app.

## Milestone 5 — Main app

Three tabs:
1. **Discovery** — reads the existing `member_cards` view only (never base tables). Card feed, filter by city / nationality / language, sort same-city-first then recency. Empty state on-brand.
2. **Messages** — 1:1 DMs on the existing `conversations` + `messages` tables via Supabase Realtime. Text + image messages. Enforce the unordered-pair uniqueness the schema already has (look up existing conversation before creating). Client-side rule: max 10 new conversations started per day.
3. **Profile** — view/edit own profile.

Every profile and conversation gets Block and Report actions wired to the existing `blocks` / `reports` tables (reasons: fake, harassment, spam, other). Blocking hides both directions immediately (the `member_cards` view already excludes blocked pairs — just refetch).

## Milestone 6 — Safety & polish

- Community guidelines + EULA acceptance screen on first entry to the main app (Apple requires this for UGC). Placeholder copy is fine, on-brand.
- Loading/error/empty states everywhere; no raw spinners on gate screens — use the stamp motif.

## Explicitly deferred (do NOT build now, leave clean seams)

- Stripe Identity passport verification (the `verification_status` / `nationality_code` flow and the US hard-stop screen) — later milestone, needs Stripe account setup first.
- Push notifications, TestFlight/EAS build config, dating mode, events, payments.

## Working rules

- One milestone at a time; each must run and be manually testable in Expo Go before starting the next. Stop and report after each milestone.
- Never commit secrets (`.env` is gitignored — keep it that way). Never print keys in output.
- Never modify `public/` (live site), the `send-decision-email` function, or applied migrations.
- If the schema forces a product tradeoff not covered here, state the options and ask instead of silently deciding.
