-- 194 — lock claim_gate_status() away from anon.
-- Supabase's ALTER DEFAULT PRIVILEGES grants EXECUTE on new functions directly
-- to anon/authenticated/service_role, so 0002's `revoke ... from public` did
-- not strip anon's direct grant (verified: an anon call reached the function
-- body instead of getting permission-denied). No data was exposed — the
-- function's own auth check fires first — but the gate RPC should not be
-- callable by anon at all. Safe to re-run.

revoke execute on function public.claim_gate_status() from anon;
