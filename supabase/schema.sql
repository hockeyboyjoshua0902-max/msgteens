-- MSG Teens database schema.
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run.
--
-- Accounts themselves (email + password) live in Supabase Auth (auth.users).
-- Everything below is app data linked to those accounts.

-- ─────────────────────────────────────────────
-- PROFILES: one row per account
-- ─────────────────────────────────────────────
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  name        text not null check (char_length(name) between 1 and 200),
  school      text check (char_length(school) <= 200),
  role        text check (role in ('teen', 'parent', 'teacher', 'community')),
  points      integer not null default 0
);

alter table public.profiles enable row level security;

-- Supabase grants everything to browser roles by default; lock it down and
-- grant back only what the site needs. Users may edit their name, school and
-- role but never their points (change those from the dashboard).
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (name, school, role) on public.profiles to authenticated;

drop policy if exists "Users can view their own profile" on public.profiles;
create policy "Users can view their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- Create the profile automatically when someone signs up, using the
-- name/school/role the sign-up form passes as user metadata.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.profiles (id, name, school, role)
  values (
    new.id,
    left(coalesce(nullif(trim(meta ->> 'name'), ''), split_part(new.email, '@', 1)), 200),
    left(nullif(trim(meta ->> 'school'), ''), 200),
    case when meta ->> 'role' in ('teen', 'parent', 'teacher', 'community')
         then meta ->> 'role' end
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────
-- STORIES: submitted by signed-in users (own story or a nomination),
-- shown publicly once approved
-- ─────────────────────────────────────────────
create table if not exists public.stories (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  user_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending', 'approved', 'rejected'))
);

-- Story fields (added separately so re-running upgrades an older stories table).
alter table public.stories
  add column if not exists submission_type   text check (submission_type in ('self', 'nominee')),
  add column if not exists teen_name         text check (char_length(teen_name) between 1 and 200),
  add column if not exists teen_age          integer check (teen_age between 5 and 25),
  add column if not exists grade_level       text check (grade_level in ('6th', '7th', '8th', '9th', '10th', '11th', '12th', 'Other')),
  add column if not exists school            text check (char_length(school) between 1 and 200),
  add column if not exists city_state        text check (char_length(city_state) <= 200),
  add column if not exists body              text check (char_length(body) between 1 and 10000),
  add column if not exists why_important     text check (char_length(why_important) between 1 and 10000),
  add column if not exists photo_path        text check (char_length(photo_path) <= 500),
  add column if not exists photo_description text check (char_length(photo_description) <= 1000),
  add column if not exists permission        boolean not null default false;

-- An early version of this file had a required title; the form doesn't use it.
alter table public.stories drop column if exists title;

-- Rules every submission must meet (dropped and re-added so re-runs work).
alter table public.stories drop constraint if exists stories_submission_complete;
alter table public.stories add constraint stories_submission_complete check (
  submission_type is not null and teen_name is not null and teen_age is not null
  and school is not null and body is not null and why_important is not null
  and permission
  and (submission_type <> 'self' or city_state is not null)
);

create index if not exists stories_user_id_idx on public.stories (user_id);

alter table public.stories enable row level security;

-- Users submit the story fields only; user_id and status are filled in by
-- the defaults, so nobody can post as someone else or self-approve.
-- Approve stories by changing status in the dashboard (Table Editor).
revoke all on public.stories from anon, authenticated;
grant select on public.stories to anon, authenticated;
grant insert (submission_type, teen_name, teen_age, grade_level, school, city_state,
              body, why_important, photo_path, photo_description, permission)
  on public.stories to authenticated;

drop policy if exists "Anyone can read approved stories" on public.stories;
create policy "Anyone can read approved stories"
  on public.stories for select to anon, authenticated
  using (status = 'approved');

drop policy if exists "Users can read their own stories" on public.stories;
create policy "Users can read their own stories"
  on public.stories for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can submit stories" on public.stories;
create policy "Users can submit stories"
  on public.stories for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- ─────────────────────────────────────────────
-- STORY PHOTOS: private storage bucket (view them in Dashboard -> Storage).
-- Each user can upload only into a folder named after their own user id.
-- ─────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('story-photos', 'story-photos', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users can upload story photos" on storage.objects;
create policy "Users can upload story photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'story-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
