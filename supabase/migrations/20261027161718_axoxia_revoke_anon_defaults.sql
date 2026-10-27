/*
# Revoke default anon privileges on all app tables

Supabase grants the `anon` role broad default privileges on tables in the
`public` schema. This app requires sign-in (every RLS policy is scoped to
`TO authenticated`), so there is no public/no-auth path. Although RLS already
blocks anon from seeing any rows (no anon policies exist), revoking the
table-level grants removes the anon role's reach entirely — defense in depth,
matching the original security-hardening intent.

No data is touched. Only privilege grants on the anon role are revoked.
*/

REVOKE SELECT, INSERT, UPDATE, DELETE ON profiles FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON driver_profiles FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON delivery_requests FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON delivery_history FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON earnings FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON alerts FROM anon;
