// Runs on Vercel at build time (see vercel.json). Copies the Supabase
// environment variables into public/config.js so the static page can read them.
// Only put PUBLIC values here — never the secret / service_role key.
const fs = require('fs');
const path = require('path');

const env = process.env;
// Accept the names shown in the Supabase dashboard, the legacy "anon" name,
// and the NEXT_PUBLIC_* names set by Vercel's Supabase integration.
const url = env.SUPABASE_URL || env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = env.SUPABASE_PUBLISHABLE_KEY || env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
  env.SUPABASE_ANON_KEY || env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const outFile = path.join(__dirname, '..', 'public', 'config.js');

if (!url || !anonKey) {
  const found = Object.keys(env).filter(k => k.includes('SUPABASE'));
  const where = env.VERCEL_ENV || 'local';
  console.warn('Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY for the "' + where + '" environment.');
  console.warn('Supabase variables this build can see: ' + (found.join(', ') || 'none'));
  console.warn('Add them in Vercel -> Settings -> Environment Variables (tick this environment), then redeploy.');
  // Never ship the live site without working accounts; previews may deploy
  // without them (sign-up then shows "not configured yet").
  if (where === 'production') process.exit(1);
  fs.writeFileSync(outFile, '// Supabase not configured for this deployment.\n');
  process.exit(0);
}

const config = { supabaseUrl: url.trim(), supabaseAnonKey: anonKey.trim() };
fs.writeFileSync(outFile, 'window.MSG_CONFIG = ' + JSON.stringify(config) + ';\n');
console.log('Wrote public/config.js');
