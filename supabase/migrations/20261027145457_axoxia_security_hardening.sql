/*
# Security hardening — post-schema fixes

1. Revoke anon role privileges on all application tables.
   The anon role should NOT reach any table in this app — every policy is
   scoped to `authenticated`, and there is no public/no-auth path. Without
   these revokes, the anon key can see the table schema via GraphQL even
   though RLS blocks the rows.

2. Lock search_path on `touch_updated_at` (mutable search_path lint).

3. Revoke EXECUTE on `handle_new_user` from `authenticated` — only the
   auth.users trigger (running as service_role / superuser) should call it.

4. Drop stale functions from the previous schema that no longer have
   backing tables: `generate_tracking_number` and `update_updated_at_column`.
*/

-- 1. Revoke anon privileges
REVOKE SELECT, INSERT, UPDATE, DELETE ON profiles FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON driver_profiles FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON delivery_requests FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON delivery_history FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON earnings FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON alerts FROM anon;

-- 2. Lock search_path on touch_updated_at
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- 3. Lock down handle_new_user — revoke from authenticated too
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM authenticated;

-- 4. Drop stale functions from the old schema
DROP FUNCTION IF EXISTS public.generate_tracking_number();
DROP FUNCTION IF EXISTS public.update_updated_at_column();
