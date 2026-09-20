/*
# Make Public Guide View Read-Only

## Purpose
Removes unnecessary write privileges from the public guide view. Tourists can
browse safe guide information, but cannot insert, update, or delete through the
view.

## Security Changes
- Revoke INSERT, UPDATE, and DELETE on `public_guide_profiles` from anon and authenticated.
- Keep SELECT access for anon and authenticated.
- Raw guide profile tables remain protected by owner-scoped RLS policies.
*/

REVOKE INSERT, UPDATE, DELETE ON public_guide_profiles FROM anon, authenticated;
GRANT SELECT ON public_guide_profiles TO anon, authenticated;
