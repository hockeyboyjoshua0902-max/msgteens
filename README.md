# msgteens
This is my report for Msg teens.

## Pages
All pages live in `public/` and share `styles.css` (look) and `app.js`
(Supabase connection, phone menu, login state, story cards):

| Page | File |
|---|---|
| Home (includes the leaderboard) | `index.html` |
| Wall of Fame (approved stories, featured article, gallery) | `stories.html` |
| Submit a Story | `submit.html` |
| Research (published research + "Add Research" form) | `research.html` |
| About (our story, founders) | `about.html` |
| Join (sign up / log in / my account) | `join.html` |
| Admin panel | `admin.html` |

The menu and footer are repeated in each page, so change them in every
public page. Old one-page links like `msgteens.com/#story` redirect to the
matching page.

## Accounts & data (Supabase)

Visitors create accounts (email + password) with Supabase Auth. Each account
gets a row in `profiles` (name, school, role, points). Signed-in users can
submit a story (their own, or a nomination of another teen) with the
"Submit a Teen Story" form; it's saved to `stories`, with an optional photo in
the private `story-photos` storage bucket. The schema is
in `supabase/schema.sql`.

The Supabase keys live in Vercel environment variables. At deploy time,
`scripts/build-config.js` writes them to `public/config.js` (not committed),
which the page loads.

### Setup
1. **Create the tables:** Supabase dashboard → **SQL Editor** → paste
   `supabase/schema.sql` → **Run**.
2. **Auth URLs:** Supabase → **Authentication → URL Configuration** → set
   **Site URL** to your live site (e.g. `https://msgteens.com`) and add it
   (plus any `*.vercel.app` URL you use) under **Redirect URLs**, so
   confirmation emails link back to the site.
3. **Environment variables:** Vercel → your project → **Settings →
   Environment Variables**. Add both for Production, Preview and Development:
   - `SUPABASE_URL`: your project URL (`https://<ref>.supabase.co`)
   - `SUPABASE_PUBLISHABLE_KEY`: the `sb_publishable_...` key
     (the legacy `SUPABASE_ANON_KEY` name also works)
4. **Redeploy** (Deployments → ⋯ → Redeploy). Env var changes only apply to
   new deployments.

Never put `SUPABASE_SECRET_KEY` (`sb_secret_...`) or the `service_role` key in Vercel for this site — it would
be published in `config.js` and bypasses all security.

### Admin panel
Go to `/admin.html` (e.g. `https://www.msgteens.com/admin.html`), or use the
"Admin panel" button on your account page (`join.html`). Admins can
review stories (with photos) and approve or reject them, see every member,
and set points.

To make an account an admin, sign up on the site first, then run this in the
Supabase SQL Editor with that account's email:

```sql
update public.profiles set is_admin = true where email = 'you@example.com';
```

(Use `is_admin = false` to remove access.) Non-admins who open the page see
"No admin access", and the database refuses their admin actions as well.

### Managing data in the Supabase dashboard
- Approved stories appear on the Wall of Fame (`stories.html`), and the
  newest three on the home page, the next time the page loads, with their photo. The public sees the
  name, grade, school, city/state, story and photo description, but never
  the teen's age or who submitted it. Moving a story back to pending or
  rejected removes it and makes its photo private again.
- New stories arrive with `status` = `pending`. Read them in Table Editor →
  `stories`, and set `status` to `approved` (or `rejected`).
- Story photos: Storage → `story-photos`. The story's `photo_path` column is
  the file's path in that bucket. Only photos of approved stories are visible
  to the public.
- After changing `supabase/schema.sql`, run the whole file again in the SQL
  Editor; it's safe to re-run and upgrades existing tables.
- Award points: Table Editor → `profiles` → edit `points`.

### Research page
`research.html` lists published research and has an "Add Research" form
(log in required), just like Submit a Story. Entries are saved to the
`research` table, with an optional chart/photo in the private
`research-photos` bucket.
- Research added by an **admin** account goes live right away.
- Everyone else's arrives as `pending`; approve or reject it in the admin
  panel's **Research** tab.
- To create the table, run the whole `supabase/schema.sql` again in the SQL
  Editor (safe to re-run).

### Likes & comments
Every story card (home page and Wall of Fame), every research entry
(`research.html`) and the Gitanjali Rao article have a ♥ like button and a 💬 comments section. Anyone can see likes and
comments; you need to be logged in to like or comment. Comments show only
the commenter's first name. People can delete their own comments, and admins
can delete anyone's (or delete rows in Table Editor → `comments`).
- **No swear words:** the database refuses any comment containing a swear
  word (including tricks like `sh1t`, `f*ck`, `f u c k`), and the site tells
  the commenter to keep it kind. To block more words, edit the lists in
  `has_swear_words` in `supabase/schema.sql` and run the file again.
- To add likes/comments to a new article page, add
  `MSG.reactions('article', '<page-name>', { open: true })` like
  `gitanjali-rao.html` does, and add the page to the `nextPage` list in
  `join.html` so logging in returns there.
- To turn it on, run the whole `supabase/schema.sql` again in the SQL Editor
  (safe to re-run).

### Local testing
```
SUPABASE_URL=... SUPABASE_PUBLISHABLE_KEY=... node scripts/build-config.js
python3 -m http.server -d public
```
