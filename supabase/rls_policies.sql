-- COIL Storage RLS Policies
-- ==========================
-- Run this in Supabase Dashboard → SQL Editor → New Query → Run
--
-- Strategy: Public READ, WRITE only via service_role (our edge function
-- verifies the Firebase ID token before signing upload URLs). The client
-- NEVER has service_role access — it only has anon key.

-- ---- AVATARS bucket ----
drop policy if exists "avatars public read"   on storage.objects;
drop policy if exists "avatars service write" on storage.objects;

create policy "avatars public read"
  on storage.objects for select
  using ( bucket_id = 'avatars' );

-- Writes (insert/update/delete) only from the service_role key used by
-- the edge function. Anon users cannot write directly.
create policy "avatars service write"
  on storage.objects for all
  to service_role
  using ( bucket_id = 'avatars' )
  with check ( bucket_id = 'avatars' );


-- ---- POSTS bucket ----
drop policy if exists "posts public read"   on storage.objects;
drop policy if exists "posts service write" on storage.objects;

create policy "posts public read"
  on storage.objects for select
  using ( bucket_id = 'posts' );

create policy "posts service write"
  on storage.objects for all
  to service_role
  using ( bucket_id = 'posts' )
  with check ( bucket_id = 'posts' );
