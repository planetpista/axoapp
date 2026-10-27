/*
# Drop all application tables — clean slate

1. Drops (irreversible)
- delivery_history
- earnings
- delivery_requests
- driver_profiles
- profiles

2. Rationale
- User requested a completely clean database.
- All 5 tables in the public schema are dropped with CASCADE so any
  remaining dependencies (indexes, policies, sequences) go with them.

3. Notes
- auth.users is a Supabase-managed table and is NOT touched.
- Edge functions and storage buckets are unaffected.
- The database is now empty and ready for a fresh schema.
*/

DROP TABLE IF EXISTS delivery_history CASCADE;
DROP TABLE IF EXISTS earnings CASCADE;
DROP TABLE IF EXISTS delivery_requests CASCADE;
DROP TABLE IF EXISTS driver_profiles CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;
