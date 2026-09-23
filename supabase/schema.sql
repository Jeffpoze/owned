-- Owned: database setup. Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to run again.

-- Items: one row per item, the item itself stored as JSON (see lib/domain/models.dart).
create table if not exists public.items (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

-- Each signed-in user can see and change only their own items.
alter table public.items enable row level security;

drop policy if exists "Users read their own items" on public.items;
create policy "Users read their own items" on public.items
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users add their own items" on public.items;
create policy "Users add their own items" on public.items
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "Users update their own items" on public.items;
create policy "Users update their own items" on public.items
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete their own items" on public.items;
create policy "Users delete their own items" on public.items
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Item photos: a private bucket. Files live under <user id>/..., and only that user can reach them.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('item-photos', 'item-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;

drop policy if exists "Users read their own photos" on storage.objects;
create policy "Users read their own photos" on storage.objects
  for select to authenticated
  using (bucket_id = 'item-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "Users upload their own photos" on storage.objects;
create policy "Users upload their own photos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'item-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "Users replace their own photos" on storage.objects;
create policy "Users replace their own photos" on storage.objects
  for update to authenticated
  using (bucket_id = 'item-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "Users delete their own photos" on storage.objects;
create policy "Users delete their own photos" on storage.objects
  for delete to authenticated
  using (bucket_id = 'item-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
