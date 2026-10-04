// MSG Teens — shared code for every page (loaded after config.js and supabase-js).
(function () {
  const cfg = window.MSG_CONFIG;
  const db = cfg && window.supabase ? window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey) : null;
  if (!db) {
    console.warn(cfg ? 'Supabase library failed to load.'
      : 'config.js missing: set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in Vercel and redeploy.');
  }

  // ── Phone menu ──
  const toggle = document.querySelector('.nav-toggle');
  const links = document.getElementById('navLinks');
  if (toggle && links) {
    toggle.addEventListener('click', () => {
      const open = links.classList.toggle('open');
      toggle.setAttribute('aria-expanded', String(open));
      toggle.textContent = open ? '✕' : '☰';
    });
  }

  // ── Login state, shared with the page scripts ──
  // MSG.onAuth(fn) calls fn(session) now (if known) and whenever someone logs in or out.
  const listeners = [];
  let known = false;
  let current = null;
  const cta = document.querySelector('.nav-cta');

  if (db) {
    db.auth.onAuthStateChange((event, session) => {
      if (event === 'TOKEN_REFRESHED') return;
      // Defer database calls out of the auth callback, per Supabase docs.
      setTimeout(() => {
        known = true;
        current = session;
        if (cta) cta.textContent = session ? 'My Account' : 'Join Now';
        listeners.forEach(fn => fn(session));
      }, 0);
    });
  }

  // Stories are visitor-written, so build everything with textContent (never innerHTML).
  function make(tag, cls, text) {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text) node.textContent = text;
    return node;
  }

  // ── Approved stories ──
  // Fills `grid` with story cards. Shows `section` once loaded; `empty` when there are none.
  async function loadStories({ grid, section, empty, limit }) {
    if (!db) return;
    const { data, error } = await db.rpc('get_approved_stories');
    if (error) { console.error('Could not load stories:', error); return; }
    const stories = limit ? data.slice(0, limit) : data;

    // Approved photos are readable by everyone; signed links keep the bucket itself private.
    const paths = stories.map(s => s.photo_path).filter(Boolean);
    const urls = {};
    if (paths.length) {
      const { data: signed, error: urlError } = await db.storage.from('story-photos').createSignedUrls(paths, 60 * 60 * 24);
      if (urlError) console.error(urlError);
      (signed || []).forEach(d => { if (d.signedUrl) urls[d.path] = d.signedUrl; });
    }

    grid.replaceChildren(...stories.map(s => {
      const card = make('article', 'ts-card');
      if (urls[s.photo_path]) {
        const img = make('img', 'ts-photo');
        img.src = urls[s.photo_path];
        img.alt = s.photo_description || 'Photo of ' + s.teen_name;
        img.loading = 'lazy';
        img.onerror = () => img.remove();
        card.appendChild(img);
      }
      const body = make('div', 'ts-body');
      body.append(
        make('p', 'ts-tag', s.submission_type === 'self' ? 'In their own words' : 'Nominated'),
        make('h3', 'ts-name', s.teen_name),
        make('p', 'ts-meta', [s.grade_level && s.grade_level !== 'Other' ? s.grade_level + ' grade' : null, s.school, s.city_state].filter(Boolean).join(' · ')),
        make('p', 'ts-label', s.submission_type === 'self' ? 'What happened' : 'What they did'),
        make('p', 'ts-text', s.body),
        make('p', 'ts-label', 'Why it matters'),
        make('p', 'ts-text', s.why_important)
      );
      if (s.photo_description && urls[s.photo_path]) body.appendChild(make('p', 'ts-caption', s.photo_description));
      const more = make('button', 'ts-more', 'Read more');
      more.type = 'button';
      more.addEventListener('click', () => {
        more.textContent = card.classList.toggle('open') ? 'Show less' : 'Read more';
      });
      body.appendChild(more);
      card.appendChild(body);
      return card;
    }));

    if (empty) empty.hidden = stories.length > 0;
    if (section) section.hidden = !empty && stories.length === 0;
    // Only offer "Read more" where text is actually cut off.
    grid.querySelectorAll('.ts-card').forEach(card => {
      const clipped = [...card.querySelectorAll('.ts-text')].some(t => t.scrollHeight > t.clientHeight + 1);
      card.querySelector('.ts-more').hidden = !clipped;
    });
    return stories.length;
  }

  window.MSG = {
    db,
    onAuth(fn) {
      listeners.push(fn);
      if (known) fn(current);
    },
    loadStories
  };
})();
