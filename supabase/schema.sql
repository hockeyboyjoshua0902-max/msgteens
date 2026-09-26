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
-- STORIES: submitted by signed-in users, shown publicly once approved
-- ─────────────────────────────────────────────
create table if not exists public.stories (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  user_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 200),
  body        text not null check (char_length(body) between 1 and 10000),
  status      text not null default 'pending' check (status in ('pending', 'approved', 'rejected'))
);

create index if not exists stories_user_id_idx on public.stories (user_id);

alter table public.stories enable row level security;

-- Users submit a title and body only; user_id and status are filled in by
-- the defaults, so nobody can post as someone else or self-approve.
-- Approve stories by changing status in the dashboard (Table Editor).
revoke all on public.stories from anon, authenticated;
grant select on public.stories to anon, authenticated;
grant insert (title, body) on public.stories to authenticated;

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
