(function () {
  const RES = 'spz-chat';
  const el = (id) => document.getElementById(id);
  const rootEl = el('root');
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

  let commands = [];   // [{ name, help, params:[{name, help}] }, ...]
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
    sugUsage = null;
    suggestBox.classList.add('hidden');
    suggestBox.innerHTML = '';
  }

  // Typed text in bold inside a suggestion label.
  function markMatch(label, partial) {
    if (!partial) return esc(label);
    const i = label.toLowerCase().indexOf(partial.toLowerCase());
    if (i < 0) return esc(label);
    return esc(label.slice(0, i)) + '<b>' + esc(label.slice(i, i + partial.length)) + '</b>' + esc(label.slice(i + partial.length));
  }

  let sugPartial = '';
  let sugUsage = null;   // { cmd, params, at } while typing a command's arguments

  function renderSuggest() {
    if (!sugItems.length && !sugUsage) { closeSuggest(); return; }
    let html = '';
    if (sugUsage) {
      const args = sugUsage.params.map((p, i) => {
        const cls = i === sugUsage.at ? 'sg-arg now' : 'sg-arg';
        return `<span class="${cls}">&lt;${esc(p.name)}&gt;</span>`;
      }).join(' ');
      const cur = sugUsage.params[sugUsage.at];
      html += `<div class="sg-usage"><span class="sg-main">/${esc(sugUsage.cmd)}</span> ${args}` +
        (cur && cur.help ? `<span class="sg-hint">${esc(cur.help)}</span>` : '') + '</div>';
    }
    html += sugItems
      .map((s, i) => `<div class="sg-item${i === sugIdx ? ' active' : ''}" data-i="${i}">
        ${s.icon || ''}<span class="sg-main">${markMatch(s.label, sugPartial)}</span>${s.hint ? `<span class="sg-hint">${esc(s.hint)}</span>` : ''}
      </div>`)
      .join('');
    if (sugItems.length) html += '<div class="sg-foot"><kbd>Tab</kbd> complete · <kbd>↑</kbd><kbd>↓</kbd> choose · <kbd>Enter</kbd> send</div>';
    suggestBox.innerHTML = html;
    suggestBox.classList.remove('hidden');
    suggestBox.querySelectorAll('.sg-item').forEach((n) => {
      n.addEventListener('mousedown', (e) => {
        e.preventDefault();
        applySuggestion(parseInt(n.dataset.i, 10));
      });
    });
    const act = suggestBox.querySelector('.sg-item.active');
    if (act) act.scrollIntoView({ block: 'nearest' });
  }

  // Starts-with matches first, then "contains" matches, each alphabetical.
  function rank(list, key, partial) {
    const p = partial.toLowerCase();
    const starts = [], has = [];
    for (const x of list) {
      const k = key(x).toLowerCase();
      if (k.startsWith(p)) starts.push(x);
      else if (p && k.includes(p)) has.push(x);
    }
    return starts.concat(has);
  }

  function updateSuggest() {
    const v = input.value;
    sugUsage = null;

    // DM target: "/w <partial" or "/dm <partial" or "/tell <partial"
    const dmMatch = v.match(/^\/(w|dm|tell)\s+(\S*)$/i);
    if (dmMatch) {
      sugPartial = dmMatch[2];
      sugMode = 'dm';
      sugItems = rank(players, (p) => p.username, sugPartial)
        .slice(0, 8)
        .map((p) => ({ label: p.username, hint: 'player', icon: avatarHtml(p.username, p.avatar), apply: () => `/w ${p.username} ` }));
      sugIdx = sugItems.length ? 0 : -1;
      renderSuggest();
      return;
    }

    // Slash command: "/partial" with no space yet
    const cmdMatch = v.match(/^\/(\S*)$/);
    if (cmdMatch) {
      sugPartial = cmdMatch[1];
      sugMode = 'cmd';
      sugItems = rank(commands, (c) => c.name, sugPartial)
        .slice(0, 8)
        .map((c) => ({ label: '/' + c.name, hint: c.help || 'command', apply: () => '/' + c.name + ' ' }));
      sugIdx = sugItems.length ? 0 : -1;
      renderSuggest();
      return;
    }

    // Typing a command's arguments: show its usage, current argument lit.
    const argMatch = v.match(/^\/(\S+)\s(.*)$/);
    if (argMatch) {
      const c = commands.find((x) => x.name.toLowerCase() === argMatch[1].toLowerCase());
      if (c && c.params && c.params.length) {
        const typed = argMatch[2].split(/\s+/);
        sugItems = []; sugIdx = -1; sugMode = null;
        sugUsage = { cmd: c.name, params: c.params, at: Math.min(typed.length - 1, c.params.length - 1) };
        renderSuggest();
        return;
      }
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
    // Enter always sends exactly what is typed; completing is Tab's job.
    if (e.key === 'Enter') {
      e.preventDefault();
      closeSuggest();
      send();
      return;
    }
    // Tab fills in the highlighted suggestion. When the text already IS that
    // suggestion, Tab moves on to the next one (Shift+Tab: previous) and fills
    // that instead, so repeated Tab walks the list.
    if (e.key === 'Tab') {
      e.preventDefault();
      if (!sugMode || !sugItems.length) return;
      let i = sugIdx >= 0 ? sugIdx : 0;
      if (sugItems[i].apply().trim() === input.value.trim()) {
        i = (i + (e.shiftKey ? -1 : 1) + sugItems.length) % sugItems.length;
      }
      const items = sugItems, mode = sugMode, partial = sugPartial;
      input.value = items[i].apply();
      placeCaretEnd();
      // Keep the list open on the same matches so the next Tab can cycle.
      sugItems = items; sugMode = mode; sugPartial = partial; sugIdx = i;
      renderSuggest();
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
  //
  // System lines (join / leave / server notices) follow `accent`, not `gold`.
  // `gold` would be the semantic fit, but spz-core sends all six keys on every
  // push with its own defaults filled in, so a server that rebrands with
  // `spz_theme_accent` alone would keep getting gold's stock amber here and
  // the join lines would stay orange while the rest of the chat moved.
  const THEME_VARS = {
    accent: ['--accent', '--system'],
    accent2: '--accent-2',
    danger: '--danger',
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
      if (!theme[key]) continue;
      const targets = THEME_VARS[key];
      for (const cssVar of (Array.isArray(targets) ? targets : [targets])) {
        document.documentElement.style.setProperty(cssVar, theme[key]);
      }
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

  // ── World visibility ───────────────────────────────────────────────────────
  // The client owns this: hidden through the loading screen and the spawn menu,
  // shown once the player is actually driving around. Messages that arrive while
  // hidden still land in the log, so nothing said during the wait is lost.
  function setVisible(v) {
    rootEl.classList.toggle('hud-hidden', !v);
    if (!v && isOpen) hide();
  }

  // Browser preview (no NUI): nothing will ever push visibility, so show it.
  if (typeof GetParentResourceName !== 'function') setVisible(true);

  // ── NUI messages from client Lua ──────────────────────────────────────────

  window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'visible') setVisible(d.visible !== false);
    else if (d.action === 'show') show();
    else if (d.action === 'hide') hide();
    else if (d.action === 'message') addLine(d.payload);
    else if (d.action === 'commands') commands = (d.list || []).map((c) => (typeof c === 'string' ? { name: c } : c));
    else if (d.action === 'online') players = d.list || [];
    else if (d.action === 'theme') applyTheme(d.theme);
    else if (d.action === 'minimap') applyMinimap(d.rect);
  });
})();
