# msgteens
This is my report for Msg teens.

## Storing signups in Supabase

The "Join the Community" form saves each signup to a `signups` table in Supabase.

1. In the Supabase dashboard, open **SQL Editor**, paste the contents of
   `supabase/schema.sql`, and click **Run**. This creates the table and a
   security policy that lets the website add signups but not read them.
2. Open **Project Settings → API** and copy the **Project URL** and the
   **anon public** key.
3. In `public/index.html`, replace `SUPABASE_URL` and `SUPABASE_ANON_KEY`
   near the bottom of the file with those values, then commit and push.
4. View signups any time in **Table Editor → signups**.

Never put the `service_role` key in the website — it bypasses all security.
