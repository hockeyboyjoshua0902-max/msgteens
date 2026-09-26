-- Run this once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.

create table if not exists public.signups (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  name        text not null check (char_length(name) between 1 and 200),
  email       text not null unique check (char_length(email) between 3 and 320),
  school      text check (char_length(school) <= 200),
  role        text check (role in ('teen', 'parent', 'teacher', 'community'))
);

-- Row Level Security: the website's public (anon) key may only INSERT.
-- Nobody can read, change, or delete signups from the browser; view them
-- in the dashboard (Table Editor) instead.
alter table public.signups enable row level security;

drop policy if exists "Anyone can sign up" on public.signups;
create policy "Anyone can sign up"
  on public.signups
  for insert
  to anon
  with check (true);

grant insert on public.signups to anon;
