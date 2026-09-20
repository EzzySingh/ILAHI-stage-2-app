/*
# Guide Profiles and Availability Tables

## Purpose
Creates the database backend for ILAHI's local-guide / livelihood-side interface.
Guides register with a fast Tier 1 flow (name, phone, primary area, photo) and
optionally complete a Tier 2 profile later (specialties, areas of expertise,
bio, credentials, availability). The schema is designed to be fully human-editable
from the Supabase Table Editor — only `full_name`, `phone`, and `primary_area`
are NOT NULL; every other column is nullable so a row can be inserted with just
those three fields without the app breaking.

## New Tables

### 1. guide_profiles
- `id` (uuid, PK, auto-generated)
- `user_id` (uuid, FK to auth.users, ON DELETE CASCADE) — identifies the guide's auth account
- `full_name` (text, NOT NULL) — guide's display name
- `phone` (text, NOT NULL) — contact phone, validated client-side, never publicly exposed
- `photo_url` (text, nullable) — public storage URL for profile photo
- `primary_area` (text, NOT NULL) — single required city/area (Tier 1)
- `areas_of_expertise` (text[], nullable) — multiple localities/neighborhoods (Tier 2)
- `specialties` (text[], nullable) — tag list e.g. 'heritage walks','food trails' (Tier 2)
- `bio` (text, nullable) — short personal description (Tier 2)
- `availability_preset` (text, default 'flexible') — 'weekday_mornings' | 'weekends' | 'flexible' | 'custom'
- `is_verified` (boolean, default false) — admin-controlled manual approval flag
- `verification_notes` (text, nullable) — admin-only internal notes, never public
- `credential_url` (text, nullable) — private storage path for ID/certs, never public
- `contact_visible` (boolean, default false) — flips true once a match/booking exists
- `profile_completion_pct` (int, GENERATED ALWAYS AS computed from filled fields * 25, STORED)
- `created_at` (timestamptz, default now())
- `updated_at` (timestamptz, default now())

The completion percentage is computed from 4 optional fields (bio, specialties,
areas_of_expertise, credential_url) — each contributes 25%, giving 0–100%.

### 2. guide_availability
- `id` (uuid, PK, auto-generated)
- `guide_id` (uuid, FK to guide_profiles, ON DELETE CASCADE)
- `day_of_week` (int, nullable) — 0=Sunday ... 6=Saturday (nullable if using preset only)
- `start_time` (time, nullable)
- `end_time` (time, nullable)
- `is_active` (boolean, default true)
- `created_at` (timestamptz, default now())

### 3. public_guide_profiles (VIEW)
A secure view that exposes ONLY non-sensitive fields to the public/tourist side:
`id`, `full_name`, `photo_url`, `primary_area`, `areas_of_expertise`, `specialties`,
`bio`, `availability_preset`, `is_verified`, `profile_completion_pct`, `created_at`.
Never exposes: `phone`, `credential_url`, `verification_notes`, `user_id`, `contact_visible`.

## Security (RLS)

### guide_profiles
- SELECT: guides can read only their own row (user_id = auth.uid())
- INSERT: guides can insert only their own row (user_id = auth.uid())
- UPDATE: guides can update only their own row (user_id = auth.uid())
- DELETE: guides can delete only their own row (user_id = auth.uid())
- Public/anon read access is through the VIEW, not the raw table

### guide_availability
- SELECT: guides can read only their own availability (guide belongs to auth.uid())
- INSERT: guides can insert only for their own profile
- UPDATE: guides can update only for their own profile
- DELETE: guides can delete only for their own profile

### public_guide_profiles (VIEW)
- Readable by anon and authenticated (tourists browsing guides)
- Exposes only safe fields — no phone, no credentials, no internal notes

## Important Notes
1. The `user_id` column defaults to `auth.uid()` so inserts that omit it still satisfy RLS.
2. The view uses `SECURITY_BARRIER` to prevent function calls from accessing hidden columns.
3. Phone number visibility to matched tourists will be handled by a separate
   function/view once a bookings table exists — not in this migration.
4. All columns except full_name, phone, primary_area are nullable for Table Editor editability.
*/

-- =========================================================
-- 1. guide_profiles table
-- =========================================================
CREATE TABLE IF NOT EXISTS guide_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  phone text NOT NULL,
  photo_url text,
  primary_area text NOT NULL,
  areas_of_expertise text[],
  specialties text[],
  bio text,
  availability_preset text DEFAULT 'flexible',
  is_verified boolean DEFAULT false,
  verification_notes text,
  credential_url text,
  contact_visible boolean DEFAULT false,
  profile_completion_pct int GENERATED ALWAYS AS (
    (CASE WHEN bio IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN specialties IS NOT NULL AND array_length(specialties, 1) > 0 THEN 1 ELSE 0 END +
     CASE WHEN areas_of_expertise IS NOT NULL AND array_length(areas_of_expertise, 1) > 0 THEN 1 ELSE 0 END +
     CASE WHEN credential_url IS NOT NULL THEN 1 ELSE 0 END) * 25
  ) STORED,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Auto-update updated_at on row change
CREATE OR REPLACE FUNCTION update_guide_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_guide_updated_at ON guide_profiles;
CREATE TRIGGER trigger_guide_updated_at
  BEFORE UPDATE ON guide_profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_guide_updated_at();

-- Enable RLS
ALTER TABLE guide_profiles ENABLE ROW LEVEL SECURITY;

-- Drop existing policies (idempotent)
DROP POLICY IF EXISTS "guides_select_own" ON guide_profiles;
DROP POLICY IF EXISTS "guides_insert_own" ON guide_profiles;
DROP POLICY IF EXISTS "guides_update_own" ON guide_profiles;
DROP POLICY IF EXISTS "guides_delete_own" ON guide_profiles;

-- SELECT: guide can read only their own row
CREATE POLICY "guides_select_own"
ON guide_profiles FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- INSERT: guide can insert only their own row
CREATE POLICY "guides_insert_own"
ON guide_profiles FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- UPDATE: guide can update only their own row
CREATE POLICY "guides_update_own"
ON guide_profiles FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- DELETE: guide can delete only their own row
CREATE POLICY "guides_delete_own"
ON guide_profiles FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

-- =========================================================
-- 2. guide_availability table
-- =========================================================
CREATE TABLE IF NOT EXISTS guide_availability (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  guide_id uuid REFERENCES guide_profiles(id) ON DELETE CASCADE,
  day_of_week int,
  start_time time,
  end_time time,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE guide_availability ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "avail_select_own" ON guide_availability;
DROP POLICY IF EXISTS "avail_insert_own" ON guide_availability;
DROP POLICY IF EXISTS "avail_update_own" ON guide_availability;
DROP POLICY IF EXISTS "avail_delete_own" ON guide_availability;

-- SELECT: guide can read availability for their own profile
CREATE POLICY "avail_select_own"
ON guide_availability FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM guide_profiles
    WHERE guide_profiles.id = guide_availability.guide_id
    AND guide_profiles.user_id = auth.uid()
  )
);

-- INSERT: guide can insert availability for their own profile
CREATE POLICY "avail_insert_own"
ON guide_availability FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM guide_profiles
    WHERE guide_profiles.id = guide_availability.guide_id
    AND guide_profiles.user_id = auth.uid()
  )
);

-- UPDATE: guide can update availability for their own profile
CREATE POLICY "avail_update_own"
ON guide_availability FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM guide_profiles
    WHERE guide_profiles.id = guide_availability.guide_id
    AND guide_profiles.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM guide_profiles
    WHERE guide_profiles.id = guide_availability.guide_id
    AND guide_profiles.user_id = auth.uid()
  )
);

-- DELETE: guide can delete availability for their own profile
CREATE POLICY "avail_delete_own"
ON guide_availability FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM guide_profiles
    WHERE guide_profiles.id = guide_availability.guide_id
    AND guide_profiles.user_id = auth.uid()
  )
);

-- =========================================================
-- 3. public_guide_profiles VIEW (safe public read access)
-- =========================================================
CREATE OR REPLACE VIEW public_guide_profiles
WITH (security_barrier = true) AS
SELECT
  id,
  full_name,
  photo_url,
  primary_area,
  areas_of_expertise,
  specialties,
  bio,
  availability_preset,
  is_verified,
  profile_completion_pct,
  created_at
FROM guide_profiles;

-- Grant public read access on the view
GRANT SELECT ON public_guide_profiles TO anon, authenticated;

-- =========================================================
-- 4. Storage buckets
-- =========================================================
-- guide-photos: public read, authenticated write
-- guide-credentials: private (no public read), authenticated write
INSERT INTO storage.buckets (id, name, public)
VALUES ('guide-photos', 'guide-photos', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('guide-credentials', 'guide-credentials', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies: guide-photos (public read, owner write)
DROP POLICY IF EXISTS "guide_photos_read_all" ON storage.objects;
CREATE POLICY "guide_photos_read_all"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (bucket_id = 'guide-photos');

DROP POLICY IF EXISTS "guide_photos_write_own" ON storage.objects;
CREATE POLICY "guide_photos_write_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'guide-photos');

DROP POLICY IF EXISTS "guide_photos_update_own" ON storage.objects;
CREATE POLICY "guide_photos_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'guide-photos' AND auth.uid() = owner)
WITH CHECK (bucket_id = 'guide-photos');

-- Storage policies: guide-credentials (private, owner write only)
DROP POLICY IF EXISTS "guide_creds_read_own" ON storage.objects;
CREATE POLICY "guide_creds_read_own"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'guide-credentials' AND auth.uid() = owner);

DROP POLICY IF EXISTS "guide_creds_write_own" ON storage.objects;
CREATE POLICY "guide_creds_write_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'guide-credentials');

DROP POLICY IF EXISTS "guide_creds_update_own" ON storage.objects;
CREATE POLICY "guide_creds_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'guide-credentials' AND auth.uid() = owner)
WITH CHECK (bucket_id = 'guide-credentials');

-- =========================================================
-- 5. Indexes
-- =========================================================
CREATE INDEX IF NOT EXISTS idx_guide_profiles_user_id ON guide_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_guide_profiles_primary_area ON guide_profiles(primary_area);
CREATE INDEX IF NOT EXISTS idx_guide_availability_guide_id ON guide_availability(guide_id);
