\# 194 — Status



\_Last updated: 2026-08-07\_



\## Live

\- Web: join194.com (Cloudflare Workers + Supabase + Resend)

&#x20; - Landing page redesigned — light/cream palette, Instrument Serif + Sora

&#x20; - Form writes to `applications`, handles duplicate-email (23505) gracefully

\- Resend: join194.com verified (DKIM/SPF pass, DMARC p=reject)

&#x20; - Decision emails send from hello@join194.com to the real applicant

&#x20; - Email design matched to the new site palette

\- Border Control admin panel — applicant vetting

\- Auth gate: member / approved / waitlist / none / suspended

\- claim\_gate\_status() RPC, users\_guard trigger escape hatch



\## In progress

\- Mobile app — milestone \[0] of 6



\## Decided

\- Tagline: "195 countries. Yours made it."

\- Two-referral invite model, US geofencing

\- Brand is LIGHT: paper #F5F3EF, ink #14140F, stamp #8A5A4A,

&#x20; secondary #6B675F, muted #A9A49B, line #DCD6CB, surface #FBFAF8.

&#x20; Instrument Serif (display) + Sora (UI). Supersedes spec §5 (navy/gold/dark).

\- Reviews stated as 2–8 weeks on the site and in the waitlist email

\- No invite codes — approved members sign in with their application email;

&#x20; claim\_gate\_status() promotes them



\## Next up

\- Border Control revamp using the tokens above

\- Update 194-mvp-spec.md §5 and the Expo theme in the build brief

&#x20; (both still say navy/gold/Cinzel/dark-mode-only)

\- hello@join194.com doesn't receive mail — set up Cloudflare Email Routing

&#x20; or Resend receiving, or replies bounce

\- Landing copy claims two independent reviewers; `admins` has one seeded email

\- Country dropdown includes United States

