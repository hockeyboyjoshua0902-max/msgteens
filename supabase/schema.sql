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

-- Added later (re-running upgrades older tables). email is a copy for the
-- admin panel; is_admin marks admin accounts (set it with SQL, see README).
alter table public.profiles
  add column if not exists email    text,
  add column if not exists is_admin boolean not null default false;

update public.profiles p set email = u.email
  from auth.users u where u.id = p.id and p.email is null;

alter table public.profiles enable row level security;

-- Supabase grants everything to browser roles by default; lock it down and
-- grant back only what the site needs. Users may edit their name, school and
-- role but never their points, email or admin status (admins change points
-- through the admin_set_points function below).
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
  insert into public.profiles (id, email, name, school, role)
  values (
    new.id,
    new.email,
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
-- Approve stories in the admin panel (admin.html).
-- The public never reads this table directly; the home page uses
-- get_approved_stories() below, which leaves out private details.
revoke all on public.stories from anon, authenticated;
grant select on public.stories to authenticated;
grant insert (submission_type, teen_name, teen_age, grade_level, school, city_state,
              body, why_important, photo_path, photo_description, permission)
  on public.stories to authenticated;

-- Replaced by get_approved_stories(); dropped so re-running removes it.
drop policy if exists "Anyone can read approved stories" on public.stories;

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

-- ─────────────────────────────────────────────
-- ADMIN PANEL (admin.html): admins can see every member, story and photo,
-- approve/reject stories and set points. Make someone an admin with:
--   update public.profiles set is_admin = true where email = 'you@example.com';
-- ─────────────────────────────────────────────
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select is_admin from public.profiles where id = (select auth.uid())), false);
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

drop policy if exists "Admins can view all profiles" on public.profiles;
create policy "Admins can view all profiles"
  on public.profiles for select to authenticated
  using ((select public.is_admin()));

drop policy if exists "Admins can view all stories" on public.stories;
create policy "Admins can view all stories"
  on public.stories for select to authenticated
  using ((select public.is_admin()));

drop policy if exists "Admins can view story photos" on storage.objects;
create policy "Admins can view story photos"
  on storage.objects for select to authenticated
  using (bucket_id = 'story-photos' and (select public.is_admin()));

-- Changes go through these functions, which check for an admin first. (Granting
-- UPDATE on these columns instead would let users change their own points.)
create or replace function public.admin_set_story_status(story_id bigint, new_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can do this' using errcode = '42501';
  end if;
  update public.stories set status = new_status where id = story_id;
  if not found then
    raise exception 'Story % not found', story_id;
  end if;
end;
$$;

create or replace function public.admin_set_points(member_id uuid, new_points integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can do this' using errcode = '42501';
  end if;
  if new_points < 0 then
    raise exception 'Points cannot be negative';
  end if;
  update public.profiles set points = new_points where id = member_id;
  if not found then
    raise exception 'Member % not found', member_id;
  end if;
end;
$$;

revoke all on function public.admin_set_story_status(bigint, text) from public, anon;
revoke all on function public.admin_set_points(uuid, integer) from public, anon;
grant execute on function public.admin_set_story_status(bigint, text) to authenticated;
grant execute on function public.admin_set_points(uuid, integer) to authenticated;

-- ─────────────────────────────────────────────
-- PUBLIC STORIES (home page "Teen Stories" section)
-- Only approved stories, and only what's safe to show publicly: no age,
-- submitter, or account details.
-- ─────────────────────────────────────────────
create or replace function public.get_approved_stories()
returns table (
  id bigint, created_at timestamptz, submission_type text, teen_name text,
  grade_level text, school text, city_state text, body text,
  why_important text, photo_path text, photo_description text
)
language sql
stable
security definer
set search_path = ''
as $$
  select id, created_at, submission_type, teen_name, grade_level, school, city_state,
         body, why_important, photo_path, photo_description
  from public.stories
  where status = 'approved'
  order by created_at desc;
$$;

revoke all on function public.get_approved_stories() from public;
grant execute on function public.get_approved_stories() to anon, authenticated;

-- A photo becomes viewable by everyone once its story is approved (and private
-- again if the story is moved back to pending or rejected).
create or replace function public.is_approved_story_photo(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.stories where photo_path = path and status = 'approved');
$$;

revoke all on function public.is_approved_story_photo(text) from public;
grant execute on function public.is_approved_story_photo(text) to anon, authenticated;

drop policy if exists "Anyone can view approved story photos" on storage.objects;
create policy "Anyone can view approved story photos"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'story-photos' and public.is_approved_story_photo(name));

-- ─────────────────────────────────────────────
-- RESEARCH: research write-ups submitted by signed-in users (research.html),
-- shown publicly once approved. Works like STORIES above. Research added by
-- an admin is published straight away; everyone else's waits for review.
-- ─────────────────────────────────────────────
create table if not exists public.research (
  id                bigint generated always as identity primary key,
  created_at        timestamptz not null default now(),
  user_id           uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  status            text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  researcher_name   text not null check (char_length(researcher_name) between 1 and 200),
  grade_level       text check (grade_level in ('6th', '7th', '8th', '9th', '10th', '11th', '12th', 'Other')),
  school            text not null check (char_length(school) between 1 and 200),
  title             text not null check (char_length(title) between 1 and 200),
  topic             text not null check (topic in ('Mental Health', 'Social Media & Technology', 'School & Education',
                                                   'Stereotypes & Perception', 'Community & Volunteering', 'Other')),
  question          text not null check (char_length(question) between 1 and 5000),
  method            text not null check (char_length(method) between 1 and 10000),
  findings          text not null check (char_length(findings) between 1 and 10000),
  why_important     text not null check (char_length(why_important) between 1 and 10000),
  sources           text not null check (char_length(sources) between 1 and 10000),
  photo_path        text check (char_length(photo_path) <= 500),
  photo_description text check (char_length(photo_description) <= 1000),
  permission        boolean not null default false check (permission)
);

create index if not exists research_user_id_idx on public.research (user_id);

alter table public.research enable row level security;

revoke all on public.research from anon, authenticated;
grant select on public.research to authenticated;
grant insert (researcher_name, grade_level, school, title, topic, question, method,
              findings, why_important, sources, photo_path, photo_description, permission)
  on public.research to authenticated;

drop policy if exists "Users can read their own research" on public.research;
create policy "Users can read their own research"
  on public.research for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can submit research" on public.research;
create policy "Users can submit research"
  on public.research for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Admins can view all research" on public.research;
create policy "Admins can view all research"
  on public.research for select to authenticated
  using ((select public.is_admin()));

-- Admins' own research goes live right away.
create or replace function public.research_auto_approve_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.is_admin() then
    new.status := 'approved';
  end if;
  return new;
end;
$$;

drop trigger if exists research_auto_approve on public.research;
create trigger research_auto_approve
  before insert on public.research
  for each row execute function public.research_auto_approve_admin();

create or replace function public.admin_set_research_status(research_id bigint, new_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can do this' using errcode = '42501';
  end if;
  update public.research set status = new_status where id = research_id;
  if not found then
    raise exception 'Research % not found', research_id;
  end if;
end;
$$;

revoke all on function public.admin_set_research_status(bigint, text) from public, anon;
grant execute on function public.admin_set_research_status(bigint, text) to authenticated;

-- Public list for research.html: approved research only, no submitter details.
create or replace function public.get_approved_research()
returns table (
  id bigint, created_at timestamptz, researcher_name text, grade_level text, school text,
  title text, topic text, question text, method text, findings text,
  why_important text, sources text, photo_path text, photo_description text
)
language sql
stable
security definer
set search_path = ''
as $$
  select id, created_at, researcher_name, grade_level, school, title, topic, question,
         method, findings, why_important, sources, photo_path, photo_description
  from public.research
  where status = 'approved'
  order by created_at desc;
$$;

revoke all on function public.get_approved_research() from public;
grant execute on function public.get_approved_research() to anon, authenticated;

-- RESEARCH PHOTOS: private bucket, same rules as story photos.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('research-photos', 'research-photos', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users can upload research photos" on storage.objects;
create policy "Users can upload research photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'research-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Admins can view research photos" on storage.objects;
create policy "Admins can view research photos"
  on storage.objects for select to authenticated
  using (bucket_id = 'research-photos' and (select public.is_admin()));

create or replace function public.is_approved_research_photo(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.research where photo_path = path and status = 'approved');
$$;

revoke all on function public.is_approved_research_photo(text) from public;
grant execute on function public.is_approved_research_photo(text) to anon, authenticated;

drop policy if exists "Anyone can view approved research photos" on storage.objects;
create policy "Anyone can view approved research photos"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'research-photos' and public.is_approved_research_photo(name));

-- ─────────────────────────────────────────────
-- LIKES & COMMENTS on stories and articles.
-- item_type says what kind of thing it is; item_id says which one:
--   'story'   -> the story's id (e.g. '12')
--   'article' -> the article page's name without .html (e.g. 'gitanjali-rao')
-- Anyone can see like counts and comments; you must be logged in to like
-- or comment. Comments with swear words are refused by the database.
-- ─────────────────────────────────────────────

-- Swear-word check used by comments. Catches common tricks too: capitals,
-- l33t spelling (sh1t, a$$), stretched letters (fuuuck), symbols (f*ck)
-- and spaced-out letters (f u c k). Whole-word entries (like "hell" or "ass")
-- only match the whole word, so "hello" and "class" are fine.
-- To block another word, add it to `whole_words` (exact word) or `anywhere`
-- (blocked even inside longer words), then re-run this file.
create or replace function public.has_swear_words(input text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  anywhere text := 'f+[u\*]*[c\*]+k|\mfu+k|\mfu+q|ph+u+c?k|sh[i\*]t|b+[i\*]+t+c+h|c+[u\*]+n+t'
    || '|n+[i\*]+gg+(e+r|a+h?)|wh+o+r+e|sl+u+t|bastard|motherf|bollock|twat|dickhead|asshole'
    || '|dumbass|jackass|smartass|badass|douche|wanker|faggot';
  whole_words text := 'a+ss+(e+s|es)?|arse|d+a+m+n+(it|ed)?|dammit|goddamn(it)?|he+ll+|cr+a+p+(py|s)?'
    || '|p+i+ss+(ed|ing)?|d+i+c+k+s?|c+o+c+k+s?|t+i+t+s?|titties|boobs?|wank(ing)?|fags?'
    || '|retard(s|ed)?|pricks?|pussy|pussies|porn|horny|cum|wtf|stfu|omfg|lmfao';
  pattern text := '(' || anywhere || ')|\m(' || whole_words || ')\M';
  plain text := lower(coalesce(input, ''));
  -- l33t spelling: 0->o 1->i 3->e 4->a 5->s 7->t 8->b @->a $->s !->i |->i
  leet  text := translate(plain, '0134578@$!|', 'oieastbasii');
  variant text;
begin
  foreach variant in array array[
    plain,
    leet,
    -- join spaced-out single letters: "f u c k" / "f.u.c.k" -> "fuck"
    regexp_replace(leet, '(?<![a-z\*])([a-z\*])[\s\.\-_,]+(?=[a-z\*](?![a-z\*]))', '\1', 'g')
  ] loop
    if variant ~ pattern then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

-- Which things can be liked/commented on (shared by both tables below).
create or replace function public.is_reactable(kind text, item text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case kind
    when 'story'   then item ~ '^\d{1,18}$'
                        and exists (select 1 from public.stories where id = item::bigint and status = 'approved')
    when 'article' then item ~ '^[a-z0-9-]{1,100}$'
    else false
  end;
$$;

revoke all on function public.is_reactable(text, text) from public, anon;
grant execute on function public.is_reactable(text, text) to authenticated;

-- LIKES: one per person per item. Click again to unlike (delete the row).
create table if not exists public.likes (
  item_type   text not null check (item_type in ('story', 'article')),
  item_id     text not null check (char_length(item_id) between 1 and 100),
  user_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (item_type, item_id, user_id)
);

create index if not exists likes_user_id_idx on public.likes (user_id);

alter table public.likes enable row level security;

revoke all on public.likes from anon, authenticated;
grant select, delete on public.likes to authenticated;
grant insert (item_type, item_id) on public.likes to authenticated;

drop policy if exists "Users can see their own likes" on public.likes;
create policy "Users can see their own likes"
  on public.likes for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can like things" on public.likes;
create policy "Users can like things"
  on public.likes for insert to authenticated
  with check ((select auth.uid()) = user_id and public.is_reactable(item_type, item_id));

drop policy if exists "Users can unlike things" on public.likes;
create policy "Users can unlike things"
  on public.likes for delete to authenticated
  using ((select auth.uid()) = user_id);

-- COMMENTS: anyone logged in can comment; you can delete your own, and
-- admins can delete anyone's (delete a row in Table Editor -> comments works too).
create table if not exists public.comments (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  user_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  item_type   text not null check (item_type in ('story', 'article')),
  item_id     text not null check (char_length(item_id) between 1 and 100),
  body        text not null check (char_length(trim(body)) between 1 and 1000)
);

create index if not exists comments_item_idx on public.comments (item_type, item_id, created_at);
create index if not exists comments_user_id_idx on public.comments (user_id);

alter table public.comments enable row level security;

revoke all on public.comments from anon, authenticated;
grant select, delete on public.comments to authenticated;
grant insert (item_type, item_id, body) on public.comments to authenticated;

drop policy if exists "Users can see their own comments" on public.comments;
create policy "Users can see their own comments"
  on public.comments for select to authenticated
  using ((select auth.uid()) = user_id or (select public.is_admin()));

drop policy if exists "Users can comment" on public.comments;
create policy "Users can comment"
  on public.comments for insert to authenticated
  with check ((select auth.uid()) = user_id and public.is_reactable(item_type, item_id));

drop policy if exists "Users can delete their own comments" on public.comments;
create policy "Users can delete their own comments"
  on public.comments for delete to authenticated
  using ((select auth.uid()) = user_id or (select public.is_admin()));

-- The swear-word filter. Runs on every new comment, so it can't be skipped
-- by going around the website. The site shows this message to the commenter.
create or replace function public.comments_block_swear_words()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.body := trim(new.body);
  if public.has_swear_words(new.body) then
    raise exception 'Please keep it kind: comments can''t include swear words.'
      using errcode = '22023', hint = 'swear_words';
  end if;
  return new;
end;
$$;

drop trigger if exists comments_block_swear_words on public.comments;
create trigger comments_block_swear_words
  before insert on public.comments
  for each row execute function public.comments_block_swear_words();

-- Like and comment counts for a list of items, plus whether you liked each.
create or replace function public.get_reactions(kind text, items text[])
returns table (item_id text, likes integer, comments integer, liked boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select i.id,
         (select count(*)::integer from public.likes l where l.item_type = kind and l.item_id = i.id),
         (select count(*)::integer from public.comments c where c.item_type = kind and c.item_id = i.id),
         exists (select 1 from public.likes l
                 where l.item_type = kind and l.item_id = i.id and l.user_id = (select auth.uid()))
  from unnest(items[1:200]) as i(id);
$$;

revoke all on function public.get_reactions(text, text[]) from public;
grant execute on function public.get_reactions(text, text[]) to anon, authenticated;

-- Comments on one item, oldest first, with the commenter's first name only
-- (never their email, school or last name).
create or replace function public.get_comments(kind text, item text)
returns table (id bigint, created_at timestamptz, author text, body text, mine boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.created_at, split_part(p.name, ' ', 1), c.body,
         coalesce(c.user_id = (select auth.uid()), false) or (select public.is_admin())
  from public.comments c
  join public.profiles p on p.id = c.user_id
  where c.item_type = kind and c.item_id = item
  order by c.created_at
  limit 500;
$$;

revoke all on function public.get_comments(text, text) from public;
grant execute on function public.get_comments(text, text) to anon, authenticated;
