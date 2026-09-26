# msgteens
This is my report for Msg teens.

## Accounts & data (Supabase)

Visitors create accounts (email + password) with Supabase Auth. Each account
gets a row in `profiles` (name, school, role, points), and signed-in users can
submit `stories`, which appear publicly once you approve them. The schema is
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
   - `SUPABASE_URL`: Supabase → Project Settings → API → Project URL
   - `SUPABASE_ANON_KEY`: the **anon / public** key from the same page
4. **Redeploy** (Deployments → ⋯ → Redeploy). Env var changes only apply to
   new deployments.

Never put the `service_role` / secret key in Vercel for this site — it would
be published in `config.js` and bypasses all security.

### Managing data
- Approve a story: Table Editor → `stories` → set `status` to `approved`.
- Award points: Table Editor → `profiles` → edit `points`.

### Local testing
```
SUPABASE_URL=... SUPABASE_ANON_KEY=... node scripts/build-config.js
python3 -m http.server -d public
```
