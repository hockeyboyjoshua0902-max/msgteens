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

  // ── Smooth page changes ──
  // Fade the current page out before going to another page on this site
  // (styles.css fades the next page in). Leaves new-tab clicks, downloads,
  // other sites and same-page links alone.
  const reduceMotion = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.addEventListener('click', e => {
    const a = e.target.closest && e.target.closest('a[href]');
    if (!a || reduceMotion || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    if ((a.target && a.target !== '_self') || a.hasAttribute('download')) return;
    const url = new URL(a.href, location.href);
    if (url.origin !== location.origin) return;
    if (url.pathname === location.pathname && url.search === location.search) return;
    e.preventDefault();
    document.body.classList.add('is-leaving');
    setTimeout(() => { location.href = url.href; }, 240);
  });
  // Coming back with the browser's Back button can restore the faded-out page; undo that.
  window.addEventListener('pageshow', e => { if (e.persisted) document.body.classList.remove('is-leaving'); });

  // ── Login state, shared with the page scripts ──
  // MSG.onAuth(fn) calls fn(session) now (if known) and whenever someone logs in or out.
  const listeners = [];
  let known = false;
  let current = null;
  const cta = document.querySelector('.nav-cta');
  // Show "My Account" straight away if a saved login exists, so the menu button
  // doesn't flip from "Join Now" a moment after each page loads.
  try {
    if (cta && Object.keys(localStorage).some(k => k.startsWith('sb-') && k.endsWith('-auth-token'))) {
      cta.textContent = 'My Account';
    }
  } catch (e) { /* storage unavailable: wait for the real login check */ }

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
    // On failure, clear the loading placeholders and say so (where the page has a message).
    const fail = () => {
      grid.replaceChildren();
      grid.removeAttribute('aria-busy');
      if (empty) { empty.textContent = "Stories couldn't load right now. Please try again later."; empty.hidden = false; }
    };
    if (!db) return fail();
    const { data, error } = await db.rpc('get_approved_stories');
    if (error) { console.error('Could not load stories:', error); return fail(); }
    const stories = limit ? data.slice(0, limit) : data;

    // Approved photos are readable by everyone; signed links keep the bucket itself private.
    const paths = stories.map(s => s.photo_path).filter(Boolean);
    const urls = {};
    if (paths.length) {
      const { data: signed, error: urlError } = await db.storage.from('story-photos').createSignedUrls(paths, 60 * 60 * 24);
      if (urlError) console.error(urlError);
      (signed || []).forEach(d => { if (d.signedUrl) urls[d.path] = d.signedUrl; });
    }

    grid.replaceChildren(...stories.map((s, i) => {
      const card = make('article', 'ts-card is-new');
      card.style.animationDelay = Math.min(i, 5) * 70 + 'ms';
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
      body.append(more, reactions('story', String(s.id)));
      card.appendChild(body);
      return card;
    }));

    grid.removeAttribute('aria-busy');
    if (empty) empty.hidden = stories.length > 0;
    if (section) section.hidden = !empty && stories.length === 0;
    // Only offer "Read more" where text is actually cut off.
    grid.querySelectorAll('.ts-card').forEach(card => {
      const clipped = [...card.querySelectorAll('.ts-text')].some(t => t.scrollHeight > t.clientHeight + 1);
      card.querySelector('.ts-more').hidden = !clipped;
    });
    return stories.length;
  }

  // ── Likes & comments ──
  // reactions(kind, id) returns a like button + comments section for one story
  // ('story', its id) or article ('article', page name without .html).
  // Pass { open: true } to show the comments straight away.
  // The database refuses comments with swear words (see supabase/schema.sql).
  const bars = [];
  let refreshQueued = false;

  // The log-in page sends people back here afterwards.
  const joinUrl = () => 'join.html?next=' + encodeURIComponent(location.pathname.split('/').pop() || 'index.html');

  function reactions(kind, id, { open = false } = {}) {
    const root = make('div', 'react');
    const row = make('div', 'react-row');
    const like = make('button', 'react-btn react-like');
    const talk = make('button', 'react-btn');
    const panel = make('div', 'react-comments');
    like.type = talk.type = 'button';
    panel.hidden = true;
    row.append(like, talk);
    root.append(row, panel);

    const bar = { kind, id, root, likes: 0, comments: 0, liked: false };
    const draw = () => {
      like.textContent = (bar.liked ? '♥ ' : '♡ ') + bar.likes;
      like.setAttribute('aria-pressed', String(bar.liked));
      like.setAttribute('aria-label', 'Like (' + bar.likes + (bar.likes === 1 ? ' like)' : ' likes)'));
      talk.textContent = '💬 ' + bar.comments;
      talk.setAttribute('aria-label', (panel.hidden ? 'Show' : 'Hide') + ' comments (' + bar.comments + ')');
      talk.setAttribute('aria-expanded', String(!panel.hidden));
    };
    bar.draw = draw;

    like.addEventListener('click', async () => {
      if (!db) return;
      if (!current) { location.href = joinUrl(); return; }
      // Update straight away; undo if the database says no.
      const was = bar.liked;
      bar.liked = !was;
      bar.likes += was ? -1 : 1;
      draw();
      like.disabled = true;
      const { error } = was
        ? await db.from('likes').delete().match({ item_type: kind, item_id: id, user_id: current.user.id })
        : await db.from('likes').insert({ item_type: kind, item_id: id });
      like.disabled = false;
      if (error && error.code !== '23505') { // 23505 = already liked (e.g. in another tab)
        console.error('Could not save like:', error);
        bar.liked = was;
        bar.likes += was ? 1 : -1;
        draw();
      }
    });

    talk.addEventListener('click', () => {
      panel.hidden = !panel.hidden;
      draw();
      if (!panel.hidden) bar.renderComments();
    });

    bar.renderComments = async () => {
      const list = make('ul', 'comment-list');
      const status = make('p', 'comment-status', 'Loading comments...');
      panel.replaceChildren(status, list, commentForm());
      if (!db) { status.textContent = "Comments couldn't load right now."; return; }
      const { data, error } = await db.rpc('get_comments', { kind, item: id });
      if (error) { console.error('Could not load comments:', error); status.textContent = "Comments couldn't load right now."; return; }
      bar.comments = data.length;
      draw();
      status.textContent = data.length ? '' : 'No comments yet. Be the first!';
      status.hidden = data.length > 0;
      list.replaceChildren(...data.map(c => {
        const li = make('li', 'comment');
        const head = make('p', 'comment-head');
        head.append(make('strong', null, c.author || 'Member'),
          make('span', 'comment-date', new Date(c.created_at).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })));
        if (c.mine) {
          const del = make('button', 'comment-delete', 'Delete');
          del.type = 'button';
          del.addEventListener('click', async () => {
            if (!confirm('Delete this comment?')) return;
            del.disabled = true;
            const { error: delError } = await db.from('comments').delete().eq('id', c.id);
            if (delError) { console.error(delError); del.disabled = false; return; }
            bar.renderComments();
          });
          head.appendChild(del);
        }
        li.append(head, make('p', 'comment-body', c.body));
        return li;
      }));
    };

    function commentForm() {
      if (!current) {
        const p = make('p', 'comment-status');
        const a = make('a', null, 'Log in');
        a.href = joinUrl();
        p.append(a, ' to like and comment.');
        return p;
      }
      const form = make('form', 'comment-form');
      const box = make('textarea');
      box.maxLength = 1000;
      box.rows = 2;
      box.required = true;
      box.placeholder = 'Write something kind...';
      box.setAttribute('aria-label', 'Your comment');
      const send = make('button', null, 'Post');
      send.type = 'submit';
      const msg = make('p', 'form-msg error');
      msg.hidden = true;
      msg.setAttribute('role', 'alert');
      form.append(box, send, msg);
      form.addEventListener('submit', async e => {
        e.preventDefault();
        const body = box.value.trim();
        if (!body) return;
        send.disabled = true;
        msg.hidden = true;
        const { error } = await db.from('comments').insert({ item_type: kind, item_id: id, body });
        send.disabled = false;
        if (error) {
          console.error('Could not post comment:', error);
          msg.textContent = error.hint === 'swear_words' ? error.message : "Your comment couldn't be posted. Please try again.";
          msg.hidden = false;
          return;
        }
        bar.renderComments();
      });
      return form;
    }

    draw();
    bars.push(bar);
    if (open) { panel.hidden = false; draw(); bar.renderComments(); }
    queueRefresh();
    return root;
  }

  // Load like/comment counts for every bar on the page in one request per kind.
  function queueRefresh() {
    if (refreshQueued) return;
    refreshQueued = true;
    setTimeout(async () => {
      refreshQueued = false;
      if (!db) return;
      const live = bars.filter(b => b.root.isConnected);
      for (const kind of new Set(live.map(b => b.kind))) {
        const mine = live.filter(b => b.kind === kind);
        const { data, error } = await db.rpc('get_reactions', { kind, items: mine.map(b => b.id) });
        if (error) { console.error('Could not load likes:', error); continue; }
        data.forEach(r => mine.filter(b => b.id === r.item_id).forEach(b => {
          b.likes = r.likes; b.comments = r.comments; b.liked = r.liked;
          b.draw();
        }));
      }
    }, 0);
  }

  // Logging in or out changes "liked" and whether the comment box shows.
  listeners.push(() => {
    queueRefresh();
    bars.forEach(b => { if (!b.root.querySelector('.react-comments').hidden) b.renderComments(); });
  });

  window.MSG = {
    db,
    onAuth(fn) {
      listeners.push(fn);
      if (known) fn(current);
    },
    loadStories,
    reactions
  };
})();
