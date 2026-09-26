// Runs on Vercel at build time (see vercel.json). Copies the Supabase
// environment variables into public/config.js so the static page can read them.
// Only put PUBLIC values here — never the service_role key.
const fs = require('fs');
const path = require('path');

const url = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  console.error('Missing SUPABASE_URL or SUPABASE_ANON_KEY environment variable.');
  process.exit(1);
}

const config = { supabaseUrl: url.trim(), supabaseAnonKey: anonKey.trim() };
fs.writeFileSync(
  path.join(__dirname, '..', 'public', 'config.js'),
  'window.MSG_CONFIG = ' + JSON.stringify(config) + ';\n'
);
console.log('Wrote public/config.js');
