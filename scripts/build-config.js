// Runs on Vercel at build time (see vercel.json). Copies the Supabase
// environment variables into public/config.js so the static page can read them.
// Only put PUBLIC values here — never the secret / service_role key.
const fs = require('fs');
const path = require('path');

const url = process.env.SUPABASE_URL;
// Supabase's newer "publishable" key replaces the legacy "anon" key; accept either.
const anonKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  console.error('Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY environment variable.');
  process.exit(1);
}

const config = { supabaseUrl: url.trim(), supabaseAnonKey: anonKey.trim() };
fs.writeFileSync(
  path.join(__dirname, '..', 'public', 'config.js'),
  'window.MSG_CONFIG = ' + JSON.stringify(config) + ';\n'
);
console.log('Wrote public/config.js');
