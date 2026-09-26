# msgteens
This is my report for Msg teens.

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

### Managing data
- New stories arrive with `status` = `pending`. Read them in Table Editor →
  `stories`, and set `status` to `approved` (or `rejected`).
- Story photos: Storage → `story-photos`. The story's `photo_path` column is
  the file's path in that bucket. The bucket is private, so photos are not
  visible to the public.
- After changing `supabase/schema.sql`, run the whole file again in the SQL
  Editor; it's safe to re-run and upgrades existing tables.
- Award points: Table Editor → `profiles` → edit `points`.

### Local testing
```
SUPABASE_URL=... SUPABASE_PUBLISHABLE_KEY=... node scripts/build-config.js
python3 -m http.server -d public
```
