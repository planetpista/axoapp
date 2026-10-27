/*
# Axoxia Shipping — Complete Database Schema (consolidated clean build)

This migration builds the entire Axoxia database from scratch in a single,
idempotent pass. It merges three previously-staged (but never applied)
migrations: the base schema, the security-hardening pass, and the auth-flow
fixes. The database is currently empty, so this is the only schema migration
needed.

## What this creates

### Tables (all with RLS enabled, grants scoped to authenticated + service_role)

1. **profiles** — One row per authenticated user (client / driver / admin),
   linked 1:1 to `auth.users` by id. Columns: first_name, last_name, role
   (CHECK client/driver/admin), is_active, created_at, updated_at.
   RLS: a user reads/updates only their own row; admins read all rows.

2. **driver_profiles** — Extra info for users with role='driver'. Columns:
   country, city, vehicle_type (motorbike/car/truck), account_type
   (individual or "professional:<company>"), rating, completed_deliveries,
   total_earnings, is_available, live latitude/longitude, created_at,
   updated_at. RLS: driver owns theirs; admins read all; clients read
   available drivers (for the driver map).

3. **delivery_requests** — A shipment order created by a client. Stores
   category (Mail/Parcel/Moving/Export), export_type, size, description,
   weight (>=0), dimensions, distance_km (>=0), pickup + delivery addresses
   and coordinates, sender + recipient details (with email-format CHECKs),
   price (>=0), currency, insurance, urgency, status, special_instructions,
   delivery timestamps, tracking_number (NOT NULL UNIQUE, auto-generated
   DEFAULT). RLS: client owns and manages; assigned driver updates status;
   admins see everything.

4. **delivery_history** — Append-only status log per delivery (status, notes,
   optional GPS). RLS: readable by the delivery's client, driver, or admin;
   insertable by the delivery's driver or admin.

5. **earnings** — Financial records per delivery (amount >=0, currency,
   payment_status). RLS: driver SELECTs their own; admins SELECT all;
   writes are service_role only (edge function).

6. **alerts** — System notifications (delay/incident/system/payment) with
   severity and is_read flag. RLS: admins manage all; users see alerts
   targeting them or their deliveries.

### Trigger
- **handle_new_user** (SECURITY DEFINER, search_path locked) — auto-inserts a
  blank 'client' profile row when a new auth.users row is created, with
  ON CONFLICT DO NOTHING as a safety net. The frontend then UPSERTs the
  real name/role. EXECUTE revoked from PUBLIC/anon/authenticated; only the
  auth.users trigger and service_role call it.

### Trigger
- **touch_updated_at** — sets updated_at = now() on row update for
  profiles, driver_profiles, delivery_requests. search_path locked.

### Indexes
- profiles(role); driver_profiles(is_available);
  delivery_requests(status, client_id, driver_id, created_at DESC);
  delivery_history(delivery_id, created_at DESC);
  earnings(driver_id, delivery_id);
  alerts(user_id, is_read, created_at DESC).

## Security summary
- RLS enabled on every table.
- anon role has NO grants on any table (this app requires sign-in; there is
  no public/no-auth path).
- authenticated gets the minimum verbs each table needs.
- service_role gets full CRUD on tables the edge function touches
  (paypal-verify may write payment status).
- Owner columns (client_id, driver_id, user_id) are NOT defaulted to
  auth.uid() because the frontend explicitly supplies them; the INSERT
  policies' WITH CHECK enforces ownership.
- handle_new_user locked to service_role only.

## Auth flow note (important)
The `handle_new_user` trigger inserts a blank profile on signup. The
frontend (AuthModal) uses UPSERT (onConflict: 'id') to fill in the real
name/role, so the name/role always land even if the trigger already ran.
Sign-up returns a session immediately (email confirmation is OFF by
default), so the user lands in their session directly after creating the
account.
*/

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 1. profiles
-- ============================================================
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  first_name text NOT NULL DEFAULT '',
  last_name text NOT NULL DEFAULT '',
  role text NOT NULL DEFAULT 'client'
    CHECK (role IN ('client', 'driver', 'admin')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON profiles TO service_role;

DROP POLICY IF EXISTS "select_own_profile" ON profiles;
CREATE POLICY "select_own_profile" ON profiles FOR SELECT
  TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "select_all_profiles_admin" ON profiles;
CREATE POLICY "select_all_profiles_admin" ON profiles FOR SELECT
  TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
  );

DROP POLICY IF EXISTS "insert_own_profile" ON profiles;
CREATE POLICY "insert_own_profile" ON profiles FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "update_own_profile" ON profiles;
CREATE POLICY "update_own_profile" ON profiles FOR UPDATE
  TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- ============================================================
-- 2. driver_profiles
-- ============================================================
CREATE TABLE IF NOT EXISTS driver_profiles (
  user_id uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  country text NOT NULL,
  city text NOT NULL,
  vehicle_type text NOT NULL
    CHECK (vehicle_type IN ('motorbike', 'car', 'truck')),
  account_type text NOT NULL DEFAULT 'individual'
    CHECK (account_type = 'individual' OR account_type LIKE 'professional:%'),
  rating numeric(2,1) NOT NULL DEFAULT 5.0
    CHECK (rating >= 0 AND rating <= 5),
  completed_deliveries integer NOT NULL DEFAULT 0,
  total_earnings numeric(12,2) NOT NULL DEFAULT 0,
  is_available boolean NOT NULL DEFAULT true,
  latitude numeric(9,6),
  longitude numeric(9,6),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE driver_profiles ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON driver_profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON driver_profiles TO service_role;

DROP POLICY IF EXISTS "select_own_driver_profile" ON driver_profiles;
CREATE POLICY "select_own_driver_profile" ON driver_profiles FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "select_available_drivers" ON driver_profiles;
CREATE POLICY "select_available_drivers" ON driver_profiles FOR SELECT
  TO authenticated USING (is_available = true);

DROP POLICY IF EXISTS "select_all_driver_profiles_admin" ON driver_profiles;
CREATE POLICY "select_all_driver_profiles_admin" ON driver_profiles FOR SELECT
  TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
  );

DROP POLICY IF EXISTS "insert_own_driver_profile" ON driver_profiles;
CREATE POLICY "insert_own_driver_profile" ON driver_profiles FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "update_own_driver_profile" ON driver_profiles;
CREATE POLICY "update_own_driver_profile" ON driver_profiles FOR UPDATE
  TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- 3. delivery_requests
-- ============================================================
CREATE TABLE IF NOT EXISTS delivery_requests (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  client_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  driver_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  tracking_number text NOT NULL UNIQUE
    DEFAULT ('AXX' || EXTRACT(EPOCH FROM now())::bigint::text || LPAD((random() * 10000)::int::text, 4, '0')),
  category text NOT NULL
    CHECK (category IN ('Mail', 'Parcel', 'Moving', 'Export')),
  export_type text
    CHECK (export_type IS NULL OR export_type IN ('Parcel', 'Air', 'Container')),
  size text
    CHECK (size IS NULL OR size IN ('XS', 'S', 'M', 'L', 'XL')),
  description text,
  weight numeric(10,2) NOT NULL DEFAULT 0 CHECK (weight >= 0),
  length numeric(10,2),
  width numeric(10,2),
  height numeric(10,2),
  distance_km numeric(10,2) NOT NULL DEFAULT 0 CHECK (distance_km >= 0),
  pickup_address text NOT NULL,
  pickup_city text,
  pickup_country text NOT NULL,
  pickup_latitude numeric(9,6),
  pickup_longitude numeric(9,6),
  delivery_address text NOT NULL,
  delivery_city text,
  delivery_country text NOT NULL,
  delivery_latitude numeric(9,6),
  delivery_longitude numeric(9,6),
  sender_first_name text NOT NULL,
  sender_last_name text NOT NULL,
  sender_email text NOT NULL
    CHECK (sender_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
  sender_contact text NOT NULL,
  sender_country text,
  recipient_first_name text NOT NULL,
  recipient_last_name text NOT NULL,
  recipient_email text NOT NULL
    CHECK (recipient_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
  recipient_contact text NOT NULL,
  recipient_country text,
  price numeric(12,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  currency text NOT NULL DEFAULT 'EUR',
  insurance boolean NOT NULL DEFAULT false,
  urgency text NOT NULL DEFAULT 'medium'
    CHECK (urgency IN ('low', 'medium', 'high', 'urgent')),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'assigned', 'picked_up', 'in_transit', 'delivered', 'cancelled')),
  special_instructions text,
  estimated_delivery timestamptz,
  actual_delivery timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE delivery_requests ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON delivery_requests TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON delivery_requests TO service_role;

DROP POLICY IF EXISTS "select_own_deliveries_client" ON delivery_requests;
CREATE POLICY "select_own_deliveries_client" ON delivery_requests FOR SELECT
  TO authenticated USING (auth.uid() = client_id);

DROP POLICY IF EXISTS "select_assigned_deliveries_driver" ON delivery_requests;
CREATE POLICY "select_assigned_deliveries_driver" ON delivery_requests FOR SELECT
  TO authenticated USING (auth.uid() = driver_id);

DROP POLICY IF EXISTS "select_all_deliveries_admin" ON delivery_requests;
CREATE POLICY "select_all_deliveries_admin" ON delivery_requests FOR SELECT
  TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
  );

DROP POLICY IF EXISTS "insert_own_delivery" ON delivery_requests;
CREATE POLICY "insert_own_delivery" ON delivery_requests FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = client_id);

DROP POLICY IF EXISTS "update_own_delivery_client" ON delivery_requests;
CREATE POLICY "update_own_delivery_client" ON delivery_requests FOR UPDATE
  TO authenticated USING (auth.uid() = client_id) WITH CHECK (auth.uid() = client_id);

DROP POLICY IF EXISTS "update_assigned_delivery_driver" ON delivery_requests;
CREATE POLICY "update_assigned_delivery_driver" ON delivery_requests FOR UPDATE
  TO authenticated USING (auth.uid() = driver_id) WITH CHECK (auth.uid() = driver_id);

DROP POLICY IF EXISTS "delete_own_delivery" ON delivery_requests;
CREATE POLICY "delete_own_delivery" ON delivery_requests FOR DELETE
  TO authenticated USING (auth.uid() = client_id);

-- ============================================================
-- 4. delivery_history
-- ============================================================
CREATE TABLE IF NOT EXISTS delivery_history (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  delivery_id uuid NOT NULL REFERENCES delivery_requests(id) ON DELETE CASCADE,
  status text NOT NULL,
  notes text,
  location_latitude numeric(9,6),
  location_longitude numeric(9,6),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE delivery_history ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON delivery_history TO authenticated;
GRANT SELECT, INSERT, DELETE ON delivery_history TO service_role;

DROP POLICY IF EXISTS "select_delivery_history" ON delivery_history;
CREATE POLICY "select_delivery_history" ON delivery_history FOR SELECT
  TO authenticated USING (
    EXISTS (
      SELECT 1 FROM delivery_requests d
      WHERE d.id = delivery_id
        AND (d.client_id = auth.uid() OR d.driver_id = auth.uid()
             OR EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'))
    )
  );

DROP POLICY IF EXISTS "insert_delivery_history" ON delivery_history;
CREATE POLICY "insert_delivery_history" ON delivery_history FOR INSERT
  TO authenticated WITH CHECK (
    EXISTS (
      SELECT 1 FROM delivery_requests d
      WHERE d.id = delivery_id
        AND (d.driver_id = auth.uid()
             OR EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'))
    )
  );

-- ============================================================
-- 5. earnings
-- ============================================================
CREATE TABLE IF NOT EXISTS earnings (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  delivery_id uuid NOT NULL REFERENCES delivery_requests(id) ON DELETE CASCADE,
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  currency text NOT NULL DEFAULT 'EUR',
  payment_status text NOT NULL DEFAULT 'pending'
    CHECK (payment_status IN ('pending', 'completed', 'failed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE earnings ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON earnings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON earnings TO service_role;

DROP POLICY IF EXISTS "select_own_earnings" ON earnings;
CREATE POLICY "select_own_earnings" ON earnings FOR SELECT
  TO authenticated USING (auth.uid() = driver_id);

DROP POLICY IF EXISTS "select_all_earnings_admin" ON earnings;
CREATE POLICY "select_all_earnings_admin" ON earnings FOR SELECT
  TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
  );

-- ============================================================
-- 6. alerts
-- ============================================================
CREATE TABLE IF NOT EXISTS alerts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  type text NOT NULL
    CHECK (type IN ('delay', 'incident', 'system', 'payment')),
  severity text NOT NULL DEFAULT 'medium'
    CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  title text NOT NULL,
  message text NOT NULL,
  delivery_id uuid REFERENCES delivery_requests(id) ON DELETE SET NULL,
  user_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE alerts ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON alerts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON alerts TO service_role;

DROP POLICY IF EXISTS "select_own_alerts" ON alerts;
CREATE POLICY "select_own_alerts" ON alerts FOR SELECT
  TO authenticated USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM delivery_requests d
      WHERE d.id = alerts.delivery_id
        AND (d.client_id = auth.uid() OR d.driver_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "select_all_alerts_admin" ON alerts;
CREATE POLICY "select_all_alerts_admin" ON alerts FOR SELECT
  TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
  );

DROP POLICY IF EXISTS "insert_alerts_admin" ON alerts;
CREATE POLICY "insert_alerts_admin" ON alerts FOR INSERT
  TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
  );

DROP POLICY IF EXISTS "update_own_alerts" ON alerts;
CREATE POLICY "update_own_alerts" ON alerts FOR UPDATE
  TO authenticated USING (
    auth.uid() = user_id
    OR EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
  ) WITH CHECK (true);

DROP POLICY IF EXISTS "delete_alerts_admin" ON alerts;
CREATE POLICY "delete_alerts_admin" ON alerts FOR DELETE
  TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
  );

-- ============================================================
-- 7. Auto-create blank profile on signup (SECURITY DEFINER, locked)
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, first_name, last_name, role)
  VALUES (NEW.id, '', '', 'client')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 8. updated_at trigger function (search_path locked)
-- ============================================================
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

DROP TRIGGER IF EXISTS touch_profiles ON profiles;
CREATE TRIGGER touch_profiles BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS touch_driver_profiles ON driver_profiles;
CREATE TRIGGER touch_driver_profiles BEFORE UPDATE ON driver_profiles
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS touch_delivery_requests ON delivery_requests;
CREATE TRIGGER touch_delivery_requests BEFORE UPDATE ON delivery_requests
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ============================================================
-- 9. Indexes
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_available ON driver_profiles(is_available);
CREATE INDEX IF NOT EXISTS idx_delivery_requests_status ON delivery_requests(status);
CREATE INDEX IF NOT EXISTS idx_delivery_requests_client ON delivery_requests(client_id);
CREATE INDEX IF NOT EXISTS idx_delivery_requests_driver ON delivery_requests(driver_id);
CREATE INDEX IF NOT EXISTS idx_delivery_requests_created ON delivery_requests(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_delivery_history_delivery ON delivery_history(delivery_id);
CREATE INDEX IF NOT EXISTS idx_delivery_history_created ON delivery_history(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_earnings_driver ON earnings(driver_id);
CREATE INDEX IF NOT EXISTS idx_earnings_delivery ON earnings(delivery_id);
CREATE INDEX IF NOT EXISTS idx_alerts_user ON alerts(user_id);
CREATE INDEX IF NOT EXISTS idx_alerts_unread ON alerts(is_read);
CREATE INDEX IF NOT EXISTS idx_alerts_created ON alerts(created_at DESC);

-- ============================================================
-- 10. Drop any stale functions from prior schemas (safe no-ops here)
-- ============================================================
DROP FUNCTION IF EXISTS public.generate_tracking_number();
DROP FUNCTION IF EXISTS public.update_updated_at_column();
