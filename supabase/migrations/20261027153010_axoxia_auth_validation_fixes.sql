/*
# Auth flow fixes: duplicates, validation, grants, tracking numbers

## Issues fixed

1. **Duplicate profile creation** — The `handle_new_user` trigger auto-inserts
   a blank profile row on signup. The frontend then tries to INSERT a second
   profile with the user's name/role, which either fails (PK conflict) or is
   silently swallowed by ON CONFLICT, losing the name and role. Fix: the
   trigger keeps its ON CONFLICT DO NOTHING (acts as a safety net), and the
   frontend switches from INSERT to UPSERT so the name/role always land.

2. **Earnings over-broad grants** — `authenticated` had accumulated
   INSERT/UPDATE/DELETE on `earnings` from the initial broad grant. Drivers
   should only SELECT their earnings; inserts/updates are server-side
   (service_role / edge function). Revoke the excess.

3. **Profiles DELETE grant** — `authenticated` had DELETE on profiles.
   Users should not delete their profile row directly (auth.users owns the
   lifecycle via CASCADE). Revoke DELETE from authenticated; keep it on
   service_role only.

4. **Field validation** — Add CHECK constraints:
   - `delivery_requests`: weight >= 0, price >= 0, distance_km >= 0
   - `earnings`: amount >= 0
   - `delivery_requests`: sender_email and recipient_email must look like
     emails (basic format check via regex).

5. **Tracking number auto-generation** — `delivery_requests.tracking_number`
   is NOT NULL UNIQUE but has no default. Without a default, every client
   insert must supply one or fail. Add a DEFAULT that generates a unique
   tracking number (AXX + timestamp + random suffix).
*/

-- 1. Earnings: revoke excess grants from authenticated
REVOKE INSERT, UPDATE, DELETE ON earnings FROM authenticated;
GRANT SELECT ON earnings TO authenticated;

-- 2. Profiles: revoke DELETE from authenticated
REVOKE DELETE ON profiles FROM authenticated;

-- 3. Field validation: non-negative numbers
ALTER TABLE delivery_requests ADD CONSTRAINT chk_weight_nonneg
  CHECK (weight >= 0);
ALTER TABLE delivery_requests ADD CONSTRAINT chk_price_nonneg
  CHECK (price >= 0);
ALTER TABLE delivery_requests ADD CONSTRAINT chk_distance_nonneg
  CHECK (distance_km >= 0);
ALTER TABLE earnings ADD CONSTRAINT chk_amount_nonneg
  CHECK (amount >= 0);

-- 4. Email format validation on delivery_requests
ALTER TABLE delivery_requests ADD CONSTRAINT chk_sender_email_format
  CHECK (sender_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
ALTER TABLE delivery_requests ADD CONSTRAINT chk_recipient_email_format
  CHECK (recipient_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- 5. Tracking number auto-generation default
-- Uses AXX prefix + unix epoch + random int for uniqueness
ALTER TABLE delivery_requests ALTER COLUMN tracking_number
  SET DEFAULT ('AXX' || EXTRACT(EPOCH FROM now())::bigint::text || LPAD((random() * 10000)::int::text, 4, '0'));
