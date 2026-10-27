/*
# Axoxia Shipping — Complete Database Schema (clean rebuild)

This migration creates the full schema for the Axoxia shipping platform from
scratch. The previous tables were dropped in a prior migration, so the database
is currently empty.

## Tables created

1. **profiles** — One row per authenticated user (client, driver, or admin).
   Linked 1:1 to `auth.users` by id. Stores name, role, and active flag.
   RLS: each user reads/updates only their own row; admins read all.

2. **driver_profiles** — Extra info for users whose profile role is 'driver'.
   Stores country, city, vehicle type, account type (individual/professional),
   rating, completed deliveries count, total earnings, availability, and live
   GPS coordinates. RLS: drivers manage their own; admins read all; clients
   read available drivers.

3. **delivery_requests** — A shipment order created by a client. Stores
   category (Mail/Parcel/Moving/Export), sender + recipient details, addresses,
   coordinates, weight, dimensions, price, currency, urgency, status, insurance,
   special instructions, and delivery timestamps. RLS: clients manage their own
   requests; drivers update ones assigned to them; admins see all.

4. **delivery_history** — Append-only status log for each delivery (pickup,
   in_transit, delivered, etc.) with optional GPS + notes. RLS: follows the
   parent delivery's visibility.

5. **earnings** — Financial records per delivery: amount, currency, payment
   status. RLS: drivers see their own earnings; admins see all.

6. **alerts** — System notifications (delay, incident, system, payment) with
   severity and read/unread state. RLS: admins manage; users see alerts
   targeting them or their deliveries.

## Security (RLS)

- RLS enabled on every table.
- `profiles`: user owns their row; admins read all profiles.
- `driver_profiles`: driver owns theirs; admins read all; clients read
  available drivers (for the driver map).
- `delivery_requests`: client owns; assigned driver can update status;
  admins see everything.
- `delivery_history`: readable by the delivery's client or driver.
- `earnings`: driver sees their own; admins see all.
- `alerts`: admins see all; users see alerts on their deliveries.
- `service_role` granted for the edge function that verifies PayPal payments
  and may need to write payment status.

## Trigger

- `handle_new_user` — auto-inserts a `profiles` row when a new auth.users row
  is created, so Supabase sign-up flows that don't explicitly insert a profile
  still work. Default role is 'client'.

## Indexes

- profiles: role lookup.
- driver_profiles: availability filter.
- delivery_requests: status, client_id, driver_id, tracking_number (unique),
  created_at.
- delivery_history: delivery_id, created_at.
- earnings: driver_id, delivery_id.
- alerts: user_id, is_read, created_at.
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
  tracking_number text NOT NULL UNIQUE,
  category text NOT NULL
    CHECK (category IN ('Mail', 'Parcel', 'Moving', 'Export')),
  export_type text
    CHECK (export_type IS NULL OR export_type IN ('Parcel', 'Air', 'Container')),
  size text
    CHECK (size IS NULL OR size IN ('XS', 'S', 'M', 'L', 'XL')),
  description text,
  weight numeric(10,2) NOT NULL DEFAULT 0,
  length numeric(10,2),
  width numeric(10,2),
  height numeric(10,2),
  distance_km numeric(10,2) NOT NULL DEFAULT 0,
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
  sender_email text NOT NULL,
  sender_contact text NOT NULL,
  sender_country text,
  recipient_first_name text NOT NULL,
  recipient_last_name text NOT NULL,
  recipient_email text NOT NULL,
  recipient_contact text NOT NULL,
  recipient_country text,
  price numeric(12,2) NOT NULL DEFAULT 0,
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
  amount numeric(12,2) NOT NULL,
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
-- 7. Auto-create profile on signup
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

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;

-- ============================================================
-- 8. updated_at triggers
-- ============================================================
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
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
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);
