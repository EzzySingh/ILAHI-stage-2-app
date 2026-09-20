/*
# Harden Guide Ownership and Storage Policies

## Purpose
Ensures every guide profile created through the app is automatically owned by
its signed-in Supabase user, prevents duplicate guide profiles per account, and
restricts file uploads to paths belonging to the current user.

## Database Changes
1. `guide_profiles.user_id` now defaults to `auth.uid()` when the frontend omits it.
2. A unique partial index prevents one signed-in user from creating multiple
   guide profiles while still allowing manually entered rows with a null user_id.

## Storage Security Changes
1. Guide photo uploads must use a storage path beginning with the current user's UUID.
2. Guide credential uploads must use a storage path beginning with the current user's UUID.
3. Existing public photo reads remain public because profile photos are intentionally public.
4. Credential reads remain private and owner-only.

## Important Notes
- This migration is additive and does not delete or transform existing guide data.
- The app never needs to send `user_id`; the database derives it from the authenticated session.
*/

ALTER TABLE guide_profiles
  ALTER COLUMN user_id SET DEFAULT auth.uid();

CREATE UNIQUE INDEX IF NOT EXISTS idx_guide_profiles_one_per_user
  ON guide_profiles(user_id)
  WHERE user_id IS NOT NULL;

DROP POLICY IF EXISTS "guide_photos_write_own" ON storage.objects;
CREATE POLICY "guide_photos_write_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'guide-photos'
  AND name LIKE (auth.uid()::text || '/%')
);

DROP POLICY IF EXISTS "guide_photos_update_own" ON storage.objects;
CREATE POLICY "guide_photos_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'guide-photos'
  AND auth.uid() = owner
)
WITH CHECK (
  bucket_id = 'guide-photos'
  AND name LIKE (auth.uid()::text || '/%')
);

DROP POLICY IF EXISTS "guide_creds_write_own" ON storage.objects;
CREATE POLICY "guide_creds_write_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'guide-credentials'
  AND name LIKE (auth.uid()::text || '/%')
);

DROP POLICY IF EXISTS "guide_creds_update_own" ON storage.objects;
CREATE POLICY "guide_creds_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'guide-credentials'
  AND auth.uid() = owner
)
WITH CHECK (
  bucket_id = 'guide-credentials'
  AND name LIKE (auth.uid()::text || '/%')
);
