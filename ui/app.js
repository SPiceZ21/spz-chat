(function () {
  const RES = 'spz-chat';
  const el = (id) => document.getElementById(id);
  const dock = el('dock');
  const launcher = el('launcher');
  const log = el('log');
  const bar = el('bar');
  const input = el('input');
  const suggestBox = el('suggest');

  const post = (cb, body) =>
    fetch(`https://${RES}/${cb}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {}),
    }).then((r) => r.json().catch(() => ({}))).catch(() => ({}));

  const esc = (s) =>
    String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // Discord avatar when spz-identity has one cached, otherwise an initials badge.
  const avatarHtml = (name, url) =>
    url
      ? `<img class="av" src="${esc(url)}" alt="">`
      : `<span class="av-fallback">${esc(String(name || '?').trim()[0] || '?').toUpperCase()}</span>`;

  const CHANNELS = {
    global: { prefix: '', placeholder: 'Message everyone...' },
    crew: { prefix: '/c ', placeholder: 'Message your crew...' },
    dm: { prefix: '/w ', placeholder: 'Whisper... /w <name> message' },
  };

  let commands = [];   // [name, ...]
  let players = [];    // [{username}, ...]
  let sentHistory = [];
  let historyIdx = -1;
  let fadeTimer = null;
  let closeTimer = null;
  let isOpen = false;
  let closeStartedAt = 0;
  let lastLineAt = 0;
  let lastSendAt = 0;
  let anims = [];      // WAAPI animations owned by the open/close sequence

  let sugItems = [];    // current suggestion entries {label, hint, apply}
  let sugIdx = -1;
  let sugMode = null;   // 'cmd' | 'dm'

  const MAX_LINES = 100;

  // ── Log rendering ──────────────────────────────────────────────────────────

  function addLine(payload) {
    const channel = payload.channel || 'global';
    const div = document.createElement('div');
    div.className = 'line ' + channel;

    // Two islands per row: the avatar on its own, and the message box
    // (name + text). System / error lines have no sender, so message-only.
    if (channel === 'system' || channel === 'error') {
      div.innerHTML = `<div class="msg"><span class="line-body"><span class="text">${esc(payload.text)}</span></span></div>`;
    } else {
      let tag = '';
      if (channel === 'crew') tag = `<span class="tag">Crew</span>`;
      if (channel === 'dm') tag = `<span class="tag">${payload.dir === 'out' ? 'To' : 'DM'}</span>`;
      const crewTag = channel !== 'dm' && payload.crewTag
        ? ` <span class="crewtag">${esc(payload.crewTag)}</span>` : '';

      div.innerHTML =
        `<div class="who">${avatarHtml(payload.from, payload.avatar)}</div>` +
        `<div class="msg"><span class="line-body">` +
        tag +
        `<span class="from">${esc(payload.from)}</span>` +
        crewTag +
        ` <span class="text">${esc(payload.text)}</span>` +
        `</span></div>`;
    }

    log.insertBefore(div, log.firstChild);
    while (log.children.length > MAX_LINES) log.removeChild(log.lastChild);
    lastLineAt = Date.now();
    updateLogMask();

    if (!isOpen) {
      // Don't flag your own echo as unread.
      if (Date.now() - lastSendAt > 1500) {
        dock.classList.add('unread');
        launcher.animate(
          [{ transform: 'scale(1)' }, { transform: 'scale(1.12)' }, { transform: 'scale(1)' }],
          { duration: 320, easing: 'cubic-bezier(.3, 1.4, .6, 1)' }
        );
      }
      if (!dock.classList.contains('closing')) wake();
    }
  }

  // Closed: recent lines peek above the icon, then fade back to icon-only.
  function wake() {
    dock.classList.remove('faded');
    clearTimeout(fadeTimer);
    fadeTimer = setTimeout(() => dock.classList.add('faded'), 6000);
  }

  function fadeNow() {
    log.style.transition = 'none';
    dock.classList.add('faded');
    void log.offsetWidth;
    log.style.transition = '';
  }

  // Feather the top edge only when there's hidden history above it.
  function updateLogMask() {
    const overflow = log.scrollHeight > log.clientHeight + 1;
    const atTop = Math.abs(log.scrollTop) + log.clientHeight >= log.scrollHeight - 2;
    log.classList.toggle('overflow', overflow && !atTop);
  }
  log.addEventListener('scroll', updateLogMask);

  function stopAnims() {
    anims.forEach((a) => a.cancel());
    anims = [];
  }

  // ── Show / hide ────────────────────────────────────────────────────────────
  // Open:  icon → small box → full bar (CSS keyframes on .launcher), then the
  //        chips and history rows rise out of the bar, staggered bottom-up.
  // Close: rows sink back into the bar, bar shrinks back down to the icon.

  const EASE_OUT = 'cubic-bezier(.2, .8, .2, 1)';

  function show() {
    if (isOpen) return;
    isOpen = true;
    stopAnims();
    clearTimeout(fadeTimer);
    clearTimeout(closeTimer);

    dock.classList.remove('closing', 'faded', 'unread');
    dock.classList.add('open');
    bar.classList.remove('hidden');
    input.value = '';
    setChannel('global');
    closeSuggest();
    historyIdx = -1;
    log.scrollTop = 0;
    updateLogMask();

    const rows = [bar, ...Array.from(log.children).slice(0, 8)];
    rows.forEach((node, i) => {
      anims.push(node.animate(
        [{ opacity: 0, transform: 'translateY(14px)' }, { opacity: 1, transform: 'none' }],
        { duration: 300, delay: 280 + i * 40, easing: EASE_OUT, fill: 'backwards' }
      ));
    });

    setTimeout(() => input.focus(), 10);
  }

  function hide() {
    if (!isOpen) return;
    isOpen = false;
    stopAnims();
    closeSuggest();
    input.blur();
    closeStartedAt = Date.now();

    dock.classList.remove('open');
    dock.classList.add('closing');

    const sink = [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(12px)' }];
    anims.push(bar.animate(sink, { duration: 140, easing: 'ease-in', fill: 'forwards' }));
    anims.push(log.animate(sink, { duration: 180, easing: 'ease-in', fill: 'forwards' }));

    closeTimer = setTimeout(() => {
      bar.classList.add('hidden');
      log.scrollTop = 0;
      // A reply/echo that landed mid-close should still peek; otherwise icon only.
      if (lastLineAt > closeStartedAt) wake();
      else fadeNow();
      stopAnims();
      dock.classList.remove('closing');
      updateLogMask();
    }, 360);
  }

  // ── Channel pills ──────────────────────────────────────────────────────────

  function setChannel(ch) {
    document.querySelectorAll('.chip').forEach((b) => b.classList.toggle('active', b.dataset.ch === ch));
    input.placeholder = CHANNELS[ch].placeholder;

    const cur = input.value;
    const stripped = cur.replace(/^\/(c|crew|w|dm|tell|g)\s+/i, '').replace(/^\/(c|crew)\s*$/i, '');
    input.value = CHANNELS[ch].prefix + stripped;
    placeCaretEnd();
  }

  document.querySelectorAll('.chip').forEach((b) => {
    b.addEventListener('click', () => setChannel(b.dataset.ch));
  });

  function placeCaretEnd() {
    const v = input.value;
    input.focus();
    input.setSelectionRange(v.length, v.length);
  }

  // ── Autocomplete ─────────────────────────────────────────────────────────

  function closeSuggest() {
    sugItems = [];
    sugIdx = -1;
    sugMode = null;
    suggestBox.classList.add('hidden');
    suggestBox.innerHTML = '';
  }

  function renderSuggest() {
    if (!sugItems.length) { closeSuggest(); return; }
    suggestBox.innerHTML = sugItems
      .map((s, i) => `<div class="sg-item${i === sugIdx ? ' active' : ''}" data-i="${i}">
        ${s.icon || ''}<span class="sg-main">${esc(s.label)}</span>${s.hint ? `<span class="sg-hint">${esc(s.hint)}</span>` : ''}
      </div>`)
      .join('');
    suggestBox.classList.remove('hidden');
    suggestBox.querySelectorAll('.sg-item').forEach((n) => {
      n.addEventListener('mousedown', (e) => {
        e.preventDefault();
        applySuggestion(parseInt(n.dataset.i, 10));
      });
    });
  }

  function updateSuggest() {
    const v = input.value;

    // DM target: "/w <partial" or "/dm <partial" or "/tell <partial" with no trailing space yet consumed
    const dmMatch = v.match(/^\/(w|dm|tell)\s+(\S*)$/i);
    if (dmMatch) {
      const partial = dmMatch[2].toLowerCase();
      sugMode = 'dm';
      sugItems = players
        .filter((p) => p.username.toLowerCase().startsWith(partial))
        .slice(0, 8)
        .map((p) => ({ label: p.username, hint: 'player', icon: avatarHtml(p.username, p.avatar), apply: () => `/w ${p.username} ` }));
      sugIdx = sugItems.length ? 0 : -1;
      renderSuggest();
      return;
    }

    // Slash command: "/partial" with no space yet
    const cmdMatch = v.match(/^\/(\S*)$/);
    if (cmdMatch) {
      const partial = cmdMatch[1].toLowerCase();
      sugMode = 'cmd';
      sugItems = commands
        .filter((c) => c.toLowerCase().startsWith(partial))
        .slice(0, 8)
        .map((c) => ({ label: '/' + c, hint: 'command', apply: () => '/' + c + ' ' }));
      sugIdx = sugItems.length ? 0 : -1;
      renderSuggest();
      return;
    }

    closeSuggest();
  }

  function applySuggestion(i) {
    if (i < 0 || i >= sugItems.length) return;
    input.value = sugItems[i].apply();
    closeSuggest();
    placeCaretEnd();
  }

  // ── Send ───────────────────────────────────────────────────────────────────

  function send() {
    const text = input.value.trim();
    if (!text) { post('close', {}); hide(); return; }
    sentHistory.push(text);
    if (sentHistory.length > 30) sentHistory.shift();
    historyIdx = -1;
    lastSendAt = Date.now();
    post('send', { text });
    hide();
  }

  // ── Input events ───────────────────────────────────────────────────────────

  input.addEventListener('input', updateSuggest);

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      if (sugMode && sugIdx >= 0) { applySuggestion(sugIdx); return; }
      send();
      return;
    }
    if (e.key === 'Tab') {
      e.preventDefault();
      if (sugMode && sugItems.length) applySuggestion(sugIdx >= 0 ? sugIdx : 0);
      return;
    }
    if (e.key === 'Escape') {
      e.preventDefault();
      if (sugMode) { closeSuggest(); return; }
      post('close', {});
      hide();
      return;
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (sugItems.length) { sugIdx = (sugIdx + 1) % sugItems.length; renderSuggest(); }
      else if (historyIdx > -1) {
        historyIdx--;
        input.value = historyIdx === -1 ? '' : sentHistory[sentHistory.length - 1 - historyIdx];
        placeCaretEnd();
      }
      return;
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (sugItems.length) { sugIdx = (sugIdx - 1 + sugItems.length) % sugItems.length; renderSuggest(); }
      else if (historyIdx + 1 < sentHistory.length) {
        historyIdx++;
        input.value = sentHistory[sentHistory.length - 1 - historyIdx];
        placeCaretEnd();
      }
      return;
    }
  });

  // ── Base theme (server.cfg spz_theme_* convars, pushed from spz-core) ─────
  // Keys map to this page's CSS variable names; unknown/missing keys are a
  // no-op since the stylesheet's own :root defaults still apply.
  const THEME_VARS = {
    accent: '--accent',
    accent2: '--accent-2',
    danger: '--danger',
    gold: '--system',
  };
  // Some rgba(...) glows/tints reference the accent as raw components rather
  // than the solid hex, so they can carry an alpha — keep those in sync too.
  const THEME_RGB_VARS = { accent: '--accent-rgb' };
  function hexToRgbTriplet(hex) {
    const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex || '');
    return m ? `${parseInt(m[1], 16)}, ${parseInt(m[2], 16)}, ${parseInt(m[3], 16)}` : null;
  }
  function applyTheme(theme) {
    if (!theme) return;
    for (const key in THEME_VARS) {
      if (theme[key]) document.documentElement.style.setProperty(THEME_VARS[key], theme[key]);
    }
    for (const key in THEME_RGB_VARS) {
      const rgb = theme[key] && hexToRgbTriplet(theme[key]);
      if (rgb) document.documentElement.style.setProperty(THEME_RGB_VARS[key], rgb);
    }
  }

  // ── Minimap anchor ─────────────────────────────────────────────────────────
  // Client pushes the real minimap rect (screen fractions) so the dock sits
  // beside the map at any resolution / safezone.
  function applyMinimap(m) {
    if (!m) return;
    const root = document.documentElement.style;
    root.setProperty('--map-left', `${m.left * 100}vw`);
    root.setProperty('--map-w', `${m.width * 100}vw`);
    root.setProperty('--map-h', `${(m.bottom - m.top) * 100}vh`);
    root.setProperty('--map-bottom', `${(1 - m.bottom) * 100}vh`);
    updateLogMask();
  }

  // ── NUI messages from client Lua ──────────────────────────────────────────

  window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'show') show();
    else if (d.action === 'hide') hide();
    else if (d.action === 'message') addLine(d.payload);
    else if (d.action === 'commands') commands = d.list || [];
    else if (d.action === 'online') players = d.list || [];
    else if (d.action === 'theme') applyTheme(d.theme);
    else if (d.action === 'minimap') applyMinimap(d.rect);
  });
})();
