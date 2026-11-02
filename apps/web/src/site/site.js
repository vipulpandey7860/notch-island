// What makes the page move: the island and its states, the robot, and every demo on the page. It works on the
// markup in page.html, the page the mockup was approved as.
let mounted = false

export function mountSite() {
  if (mounted) return  // once per page load; the page never unmounts
  mounted = true
  const $ = s => document.querySelector(s), $$ = s => [...document.querySelectorAll(s)];
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const esc = s => s.replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

  // ===================== the robot: the app's own sprites =====================
  const PAL = {K:'#1C1F26', W:'#EDF2F7', G:'#B5BDCC', D:'#242933', E:'#6BE3FF', C:'#3B8FA6', R:'#E6474D', O:'#F59924'};
  const TOPS = {antenna:['............','.....AA.....','.....KK.....'], pumpkin:['.....KA.....','...OOOOOO...','..OOOOOOOO..'], santa:['......RRRA..','...RRRRRR...','.WWWWWWWWWW.']};
  const HEAD = ['.KKKKKKKKKK.','.KWWWWWWWWK.','.KWDDDDDDWK.'];
  const EY = {ahead:['.KWDEDDEDWK.','.KWDEDDEDWK.'], right:['.KWDDEDDEWK.','.KWDDEDDEWK.'], left:['.KWEDDEDDWK.','.KWEDDEDDWK.'],
              down:['.KWDDDDDDWK.','.KWDEDDEDWK.'], shut:['.KWDDDDDDWK.','.KWDCDDCDWK.']};
  const TORSO = ['.KWWWWWWWWK.','.KKKKKKKKKK.','...KGWWGK...','..KKGWWGKK..','...KKKKKK...'];
  const ARML = ['.KWWWWWWWWK.','.KKKKKKKKKK.','..KKGWWGK...','...KGWWGKK..','...KKKKKK...'];
  const ARMR = ['.KWWWWWWWWK.','.KKKKKKKKKK.','...KGWWGKK..','..KKGWWGK...','...KKKKKK...'];
  const WAVE = ['.KWWWWWWWWKK','.KKKKKKKKKKK','...KGWWGK.K.','..KKGWWGK...','...KKKKKK...'];
  const desk = h => ['.KWWWWWWWWK.','.KKKKKKKKKK.',h,'KKKKKKKKKKKK','KGGGGGGGGGGK','.K........K.','.K........K.'];
  const LEGS = ['....K..K....','............'], DANGLE = ['...K....K...','...K....K...'];
  const FR = {
    stand:[...HEAD,...EY.ahead,...TORSO,...LEGS], look:[...HEAD,...EY.right,...TORSO,...LEGS],
    walk1:[...HEAD,...EY.right,...TORSO,'...K...K....','............'], walk2:[...HEAD,...EY.right,...TORSO,'....K...K...','............'],
    blink:[...HEAD,...EY.shut,...TORSO,...LEGS], sit:[...HEAD,...EY.ahead,...TORSO,...DANGLE], sleep:[...HEAD,...EY.shut,...TORSO,...DANGLE],
    danceA:[...HEAD,...EY.left,...ARML,'...K...K....','............'], danceB:[...HEAD,...EY.right,...ARMR,'....K...K...','............'],
    wave1:[...HEAD,'.KWDEDDEDWKK','.KWDEDDEDWKK',...WAVE,...LEGS], wave2:[...HEAD,...EY.ahead,...WAVE,...LEGS],
    work1:[...HEAD,...EY.down,...desk('..KK....KK..')], work2:[...HEAD,...EY.down,...desk('...KK..KK...')],
    stretch:['K.KKKKKKKK.K','KKWWWWWWWWKK','.KWDDDDDDWK.',...EY.shut,'.KWWWWWWWWK.','.KKKKKKKKKK.','...KGWWGK...','...KGWWGK...','...KKKKKK...',...LEGS],
  };
  const month = new Date().getMonth();
  const HAT = month === 9 ? 'pumpkin' : month === 11 ? 'santa' : 'antenna';
  // Rows under the surface it stands on: legs dangle when sitting; the desk stands on it (as in Mascot.swift)
  const below = f => ['sit','sleep'].includes(f) ? 2 : f.startsWith('work') ? 0 : 1;

  function sprite(cv, frame, px, antenna = '#FF6B80', hat = HAT, rows) {
    rows = rows || [...TOPS[hat], ...FR[frame]];
    const dpr = Math.max(2, devicePixelRatio || 1), s = px * dpr, w = rows[0].length;
    cv.width = Math.round(w * s); cv.height = Math.round(rows.length * s);
    cv.style.width = w * px + 'px'; cv.style.height = rows.length * px + 'px';
    const g = cv.getContext('2d');
    rows.forEach((r, y) => [...r].forEach((c, x) => {
      if (c === '.') return;
      g.fillStyle = c === 'A' ? antenna : PAL[c];
      const x0 = Math.round(x * s), y0 = Math.round(y * s);
      g.fillRect(x0, y0, Math.round((x + 1) * s) - x0, Math.round((y + 1) * s) - y0);
    }));
  }
  // The menu bar's app icon and the footer: just its head
  const headRows = [...TOPS.antenna.slice(1), ...HEAD, ...EY.ahead];
  sprite($('#menuBot'), null, 2, '#FF6B80', null, headRows);
  sprite($('#footBot'), null, 2, '#FF6B80', null, headRows);

  // ---- the robot beside the island ----
  const bot = $('#bot'), BPX = 2;
  const B = {off: 26, face: 1, frame: 'stand', antenna: '#FF6B80', run: 0, mode: 'idle'};
  function bdraw(f) {
    B.frame = f;
    sprite(bot, f, BPX, B.antenna);
    bot.style.top = (32 - (15 - below(f)) * BPX) + 'px';
    bplace();
  }
  function bplace() { bot.style.transform = `translateX(${B.off}px) scaleX(${B.face})`; }
  async function walkTo(target, id) {
    B.face = target > B.off ? 1 : -1;  // further from the island is to the right on screen
    let n = 0;
    while (Math.abs(B.off - target) > 1 && id === B.run) {
      B.off += Math.sign(target - B.off);
      if (n++ % 9 === 0) bdraw(B.frame === 'walk1' ? 'walk2' : 'walk1'); else bplace();
      await sleep(38);
    }
    B.face = 1;
  }
  async function behave(mode) {
    const id = ++B.run, alive = () => id === B.run;
    B.mode = mode;
    B.antenna = mode === 'music' ? '#ff8a65' : '#FF6B80';
    if (reduce) { bdraw(mode === 'music' ? 'danceA' : mode === 'work' ? 'work1' : 'stand'); return; }
    if (mode === 'music') { while (alive()) { bdraw('danceA'); await sleep(270); if (!alive()) return; bdraw('danceB'); await sleep(270); } }
    else if (mode === 'work') { while (alive()) { bdraw('work1'); await sleep(170); if (!alive()) return; bdraw('work2'); await sleep(170); } }
    else if (mode === 'watch') { B.face = -1; bdraw('look'); }  // eyes on the island, to its left
    else {
      bdraw('stand');
      while (alive()) {
        await sleep(1600 + Math.random() * 2400); if (!alive()) return;
        const r = Math.random();
        if (r < .4) { await walkTo(14 + Math.random() * 120, id); if (alive()) bdraw('stand'); }
        else if (r < .6) { bdraw('blink'); await sleep(150); if (alive()) bdraw('stand'); }
        else if (r < .75) { bdraw('look'); await sleep(1500); if (alive()) bdraw('stand'); }
        else { bdraw('sit'); await sleep(3500); if (!alive()) return; bdraw('sleep'); await sleep(2500); if (alive()) bdraw('stand'); }
      }
    }
  }
  async function react(kind) {
    if (reduce) return;
    const id = ++B.run, mode = B.mode;
    if (kind === 'hop') { bdraw('stand'); bot.classList.remove('hop'); void bot.offsetWidth; bot.classList.add('hop'); await sleep(420); }
    if (kind === 'wave') { for (let i = 0; i < 4 && id === B.run; i++) { bdraw(i % 2 ? 'wave2' : 'wave1'); await sleep(260); } }
    if (kind === 'yawn') { bdraw('stretch'); await sleep(1300); }
    if (id === B.run) behave(mode);
  }
  function say(text, ms = 1800) {
    const s = $('#say'); s.textContent = text; s.classList.add('on');
    clearTimeout(say.t); say.t = setTimeout(() => s.classList.remove('on'), ms);
  }
  let lastWave = 0;
  addEventListener('mousemove', e => {
    const r = bot.getBoundingClientRect();
    if (!r.width || ['expanded', 'alert', 'ask'].includes(island.dataset.s) || B.mode === 'watch') return;
    if (Math.hypot(e.clientX - (r.left + r.width / 2), e.clientY - (r.top + r.height / 2)) < 70 && Date.now() - lastWave > 6000) {
      lastWave = Date.now(); react('wave'); say('hi!');
    }
  }, {passive: true});

  // ===================== the island's states =====================
  const island = $('#island');
  const SIZES = {idle:[190,32,10], music:[270,32,10], shelf:[270,32,10], download:[302,32,10], timer:[370,32,10], agent:[382,32,10],
                 charging:[398,32,10], meeting:[410,32,10], peek:[390,84,22], note:[390,84,22], drop:[460,104,24], alert:[420,112,26],
                 ask:[420,112,26], expanded:[900,304,30]};
  let k = 1;
  function scale() {
    k = Math.min(1, (innerWidth - 20) / 900);
    document.documentElement.style.setProperty('--k', k);
    setIsland(island.dataset.s, true);
  }
  addEventListener('resize', scale);
  function setIsland(s, quiet) {
    const was = island.dataset.s, [w0, h0] = SIZES[was], [w, h, r] = SIZES[s], m = Math.min(1, (innerWidth - 16) / w);
    island.style.setProperty('--m', m);
    island.classList.toggle('shrink', w * h < w0 * h0);
    island.classList.toggle('big', ['expanded','alert','ask','peek','note','drop'].includes(s));
    island.style.width = w * m + 'px'; island.style.height = h * m + 'px';
    island.style.borderRadius = `0 0 ${r * m}px ${r * m}px`;
    island.dataset.s = s;
    island.querySelectorAll('.layer').forEach(l => l.classList.toggle('on', l.dataset.l === s));  // not the strips' copies
    if (quiet || s === was) return;
    if (s === 'charging') { $('#chargeFill').setAttribute('width', 0); requestAnimationFrame(() => $('#chargeFill').setAttribute('width', 17.6)); react('hop'); }
    if (s === 'meeting') react('yawn');
    if (s === 'alert') showAlert();
    if (s === 'ask') showAsk();
  }

  // The section in the middle of the screen decides what the island shows
  let shelfFiles = 0, flashing = false, sectionState = 'idle', alertDone = false, askDone = false, dragging = false, hoverOpen = false, gen = 0;
  const want = el => {
    const d = el.dataset.island;
    return d === 'files' ? (shelfFiles ? 'shelf' : 'idle') : d === 'alert' && alertDone ? 'idle' : d === 'ask' && askDone ? 'agent' : d;
  };
  /** Moving from one feature to the next, the island tucks back into the notch before it grows into the next one,
   *  the way every heads-up in the app comes out of the resting notch. */
  async function go(s) {
    const g = ++gen, cur = island.dataset.s;
    if (cur === s) return;
    if (!reduce && cur !== 'idle' && s !== 'idle') {
      setIsland('idle');
      await sleep(380);
      if (g !== gen || flashing || dragging || hoverOpen) return;
    }
    behave(botMode(s));
    setIsland(s);
  }
  const io = new IntersectionObserver(es => es.forEach(e => {
    if (!e.isIntersecting) return;
    sectionState = want(e.target);
    if (!flashing && !dragging && !hoverOpen) go(sectionState);
  }), {rootMargin: '-45% 0px -50% 0px'});

  // As in the app: hover over the notch to open it (tap on a touch screen). It closes when you move away, unless
  // you're typing in it; then Esc or a click elsewhere closes it.
  let enterT, leaveT;
  const canOpen = () => !['expanded', 'alert', 'ask', 'drop'].includes(island.dataset.s) && !dragging && !flashing;
  function openHover() { if (!canOpen()) return; hoverOpen = true; ++gen; setIsland('expanded'); }
  function closeHover(force) {
    if (!hoverOpen) return;
    const typing = island.contains(document.activeElement);
    if (typing && !force) return;
    if (typing) document.activeElement.blur();
    hoverOpen = false;
    behave(botMode(sectionState)); setIsland(sectionState);
  }
  island.addEventListener('mouseenter', () => { clearTimeout(leaveT); clearTimeout(enterT); enterT = setTimeout(openHover, 120); });
  island.addEventListener('mouseleave', () => { clearTimeout(enterT); leaveT = setTimeout(() => closeHover(false), 250); });
  island.addEventListener('focusout', () => setTimeout(() => { if (!island.matches(':hover')) closeHover(false); }));
  island.addEventListener('click', e => { if (!e.target.closest('.alert')) openHover(); });  // a heads-up's buttons answer it, they don't open the island
  island.addEventListener('keydown', e => { if (e.key === 'Escape' && e.target !== inp) closeHover(true); });
  document.addEventListener('pointerdown', e => { if (hoverOpen && !island.contains(e.target) && !e.target.closest('.stage')) closeHover(true); });
  $('.stage').addEventListener('click', openHover);
  $$('[data-island]').forEach(s => io.observe(s));
  const botMode = s => s === 'music' ? 'music' : s === 'agent' || s === 'ask' ? 'work' : 'idle';  // at its desk while Claude works
  /** Shows a state for a moment, like the app's heads-ups, then goes back to the section's. */
  async function flash(s, ms) {
    flashing = true; setIsland(s); await sleep(ms); flashing = false;
    if (!dragging) setIsland(sectionState);
  }

  // ===================== the open island: tasks, notepad, player =====================
  const now = new Date(), MIN = 60000;
  const dayStart = o => { const d = new Date(now); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() + o); return d; };
  const offOf = d => Math.round((new Date(d).setHours(0, 0, 0, 0) - dayStart(0)) / 864e5);
  const fmtTime = d => d.toLocaleTimeString([], {hour: 'numeric', minute: '2-digit'});
  const dayName = o => o === 0 ? 'Today' : o === 1 ? 'Tomorrow' : o === -1 ? 'Yesterday'
    : o > 1 && o < 7 ? dayStart(o).toLocaleDateString([], {weekday: 'long'}) : dayStart(o).toLocaleDateString([], {weekday: 'short', day: 'numeric', month: 'short'});
  const shortDate = o => dayStart(o).toLocaleDateString([], {day: 'numeric', month: 'short'});
  let nextId = 1, sel = 0, tab = 'todo';
  const T = (t, d, due = null, done = false) => ({id: nextId++, t, d, due, done});
  const prepDue = new Date(+now + 40 * MIN);
  const tasks = [
    T('Call the bank about the card', 0, new Date(+now - 50 * MIN)),
    T('Prep slides for design review', 0, prepDue),
    T('Pay electricity bill', 0, new Date(+now + 190 * MIN)),
    T('Gym', 0),
    T('Reply to Sam’s email', 0, null, true),
    T('Book dentist', 1, (() => { const d = dayStart(1); d.setHours(9, 30); return d; })()),
  ];

  // A small stand-in for the app's date reading (the app uses macOS's own date detector)
  function parse(s) {
    const marks = []; let off = null, due = null;
    const take = (re, fn) => { const m = re.exec(s); if (m) { marks.push([m.index, m.index + m[0].length]); fn(m); } };
    take(/\b(today|tonight|tomorrow|tmrw)\b/i, m => { const w = m[1].toLowerCase(); off = w === 'today' || w === 'tonight' ? 0 : 1; if (w === 'tonight') { due = dayStart(0); due.setHours(19, 0); } });
    if (off == null) take(/\b(?:on |next )?(mon|tues?|wed(?:nes)?|thu(?:rs)?|fri|sat(?:ur)?|sun)(?:day)?\b/i, m => {
      const i = ['sun','mon','tue','wed','thu','fri','sat'].indexOf(m[1].slice(0, 3).toLowerCase()); off = (i - now.getDay() + 7) % 7 || 7; });
    take(/\b(?:at )?(\d{1,2})(?::(\d{2}))? ?(am|pm)\b/i, m => { let h = +m[1] % 12; if (/pm/i.test(m[3])) h += 12; due = dayStart(off ?? 0); due.setHours(h, +m[2] || 0); });
    if (!due) take(/\bat (\d{1,2}):(\d{2})\b/i, m => { due = dayStart(off ?? 0); due.setHours(+m[1], +m[2]); });
    if (!due) take(/\bin (\d{1,3}) ?(m|mins?|minutes?|h|hrs?|hours?)\b/i, m => { due = new Date(+now + (/^h/i.test(m[2]) ? m[1] * 60 : +m[1]) * MIN); });
    if (due && off == null && due < now && offOf(due) === 0 && !/today/i.test(s)) due.setDate(due.getDate() + 1);
    if (due) off = offOf(due);
    let title = s;
    [...marks].sort((a, b) => b[0] - a[0]).forEach(([a, b]) => title = title.slice(0, a) + ' ' + title.slice(b));
    title = title.replace(/\s+/g, ' ').trim().replace(/\s+(on|at|by|due)$/i, '');
    return {title, off, due, marks: marks.sort((a, b) => a[0] - b[0])};
  }

  const check = '<svg width="10" height="10" viewBox="0 0 16 16" fill="none" stroke="#000" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M3.6 8.4l2.9 2.9 5.9-6.4"/></svg>';
  const bell = '<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><path d="M8 1.5a4.5 4.5 0 0 0-4.5 4.5v3L2 11.5h12L12.5 9V6A4.5 4.5 0 0 0 8 1.5zM6.2 13a1.9 1.9 0 0 0 3.6 0z"/></svg>';
  function renderList(freshId) {
    const day = tasks.filter(x => x.d === sel), todo = day.filter(x => !x.done).sort((a, b) => (a.due ?? 9e15) - (b.due ?? 9e15)), done = day.filter(x => x.done);
    $('#dayTitle').textContent = dayName(sel); $('#dayDate').textContent = shortDate(sel);
    $('#nTodo').textContent = todo.length; $('#nDone').textContent = done.length;
    $$('.tabs button').forEach(b => b.classList.toggle('on', b.dataset.tab === tab));
    const items = tab === 'todo' ? todo : done;
    $('#list').innerHTML = items.length ? items.map(x => {
      const late = !x.done && x.due && x.due < new Date();
      const when = x.due ? (offOf(x.due) === 0 ? fmtTime(x.due) : x.due.toLocaleDateString([], {weekday: 'short'}) + ' ' + fmtTime(x.due)) : '';
      return `<div class="task${x.done ? ' done' : ''}${x.id === freshId ? ' in' : ''}" data-id="${x.id}"><button class="tick" tabindex="-1" aria-label="Done">${x.done ? check : ''}</button>
        <div style="min-width:0"><div class="tt">${esc(x.t)}</div>${x.due ? `<div class="meta${late ? ' late' : ''}">${bell}${late ? 'Overdue · ' : ''}${when}</div>` : ''}</div></div>`;
    }).join('') : `<div class="empty"><b>${tab === 'done' ? 'Nothing finished yet' : done.length ? 'All done for ' + (sel === 0 ? 'today' : dayName(sel)) : 'Nothing planned'}</b>${tab === 'todo' && !done.length ? 'Type below to add a task' : ''}</div>`;
  }
  $('#list').addEventListener('click', e => {
    const b = e.target.closest('.tick'); if (!b) return;
    const row = b.closest('.task'), x = tasks.find(t => t.id === +row.dataset.id);
    x.done = !x.done; row.classList.toggle('done', x.done); b.innerHTML = x.done ? check : '';
    row.classList.add('out'); setTimeout(() => renderList(), 760);
  });
  $$('.tabs button').forEach(b => b.onclick = () => { tab = b.dataset.tab; renderList(); });
  $('#prevDay').onclick = () => { sel--; tab = 'todo'; renderList(); };
  $('#nextDay').onclick = () => { sel++; tab = 'todo'; renderList(); };

  const inp = $('#inp');
  function setHint(html) { const h = $('#hint'); h.hidden = !html; if (html) h.innerHTML = html; }
  function preview() {
    const s = inp.value, p = parse(s);
    let h = '', i = 0; p.marks.forEach(([a, b]) => { h += esc(s.slice(i, a)) + '<mark>' + esc(s.slice(a, b)) + '</mark>'; i = b; });
    $('#mirror').innerHTML = h + esc(s.slice(i)); $('#mirror').scrollLeft = inp.scrollLeft;
    $('#keycap').textContent = s ? '↩' : '⌥N';
    if (!s.trim()) return setHint(null);
    const off = p.off ?? sel;
    setHint(`${p.due ? bell : ''}<b>${esc(p.title || '…')}</b>&nbsp;&nbsp;·&nbsp;&nbsp;${dayName(off)}${p.due ? ', ' + fmtTime(p.due) : ''}<span class="k">↩ add&nbsp;&nbsp;·&nbsp;&nbsp;esc clear</span>`);
  }
  function addTask(text, fromNote) {
    const p = parse(text); if (!(p.title || '').trim()) return false;
    const off = fromNote ? (p.off ?? 0) : (p.off ?? sel), x = T(p.title, off, p.due);
    tasks.push(x); tab = 'todo'; renderList(x.id);
    if (off !== sel || fromNote) {
      setHint(`<span class="ok">✓</span><b>Added to ${dayName(off)}${p.due ? ', ' + fmtTime(p.due) : ''}</b>`);
      clearTimeout(addTask.t); addTask.t = setTimeout(() => { if (!inp.value) setHint(null); }, 4000);
      return 'toast';
    }
    return true;
  }
  inp.addEventListener('input', preview);
  inp.addEventListener('scroll', () => $('#mirror').scrollLeft = inp.scrollLeft);
  inp.addEventListener('keydown', e => {
    if (e.key === 'Enter' && inp.value.trim()) {
      const r = addTask(inp.value);
      if (r) { inp.value = ''; $('#mirror').innerHTML = ''; $('#keycap').textContent = '⌥N'; if (r !== 'toast') setHint(null); }
    }
    if (e.key === 'Escape') { if (inp.value) { inp.value = ''; preview(); } else closeHover(true); }  // clears, then closes
  });

  const note = $('#note');
  const countWords = () => { const n = (note.innerText.trim().match(/\S+/g) || []).length; $('#words').textContent = n === 1 ? '1 word' : n + ' words'; };
  note.addEventListener('input', countWords);
  note.addEventListener('keydown', e => {
    if (e.key !== 'Enter' || !(e.metaKey || e.ctrlKey)) return;
    e.preventDefault();
    let n = getSelection().anchorNode; while (n && n.parentNode !== note) n = n.parentNode;
    if (!n || n.nodeType !== 1) return;
    const line = n.textContent.replace(/^([-*•]|\[ ?\])\s+/, '').trim(); if (!line) return;
    n.classList.add('flash'); setTimeout(() => n.classList.remove('flash'), 800);
    addTask(line, true);
  });

  // Player, with the robot riding the progress bar
  const LEN = 223; let pos = 84, playing = true;
  const mmss = s => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  function tickPlayer() {
    $('#pbar').style.width = pos / LEN * 100 + '%';
    $('#pe').textContent = mmss(pos); $('#pr').textContent = '-' + mmss(LEN - pos);
    $('#rider').style.left = `calc(${pos / LEN * 100}% - 9px)`;
  }
  let rideStep = 0;
  setInterval(() => {
    if (playing) pos = (pos + 1) % LEN;
    tickPlayer();
    const f = playing ? (rideStep++ % 2 ? 'walk1' : 'walk2') : 'sit';
    sprite($('#rider'), f, 1.5, playing ? '#ff8a65' : '#FF6B80');
    $('#rider').style.top = (30 - (15 - below(f)) * 1.5) + 'px';  // feet on the bar, which starts 30px down
  }, 1000);
  $('#pp').onclick = () => {
    playing = !playing;
    $('#ppIcon').innerHTML = playing ? '<rect x="4" y="3" width="2.8" height="10" rx=".8"/><rect x="9.2" y="3" width="2.8" height="10" rx=".8"/>' : '<path d="M5 3v10l8-5z"/>';
    $('#pp').setAttribute('aria-label', playing ? 'Pause' : 'Play');
  };

  // ===================== due alert =====================
  const alertBot = $('#alertBot');
  let waveT;
  function showAlert() {
    $('#alertDue').textContent = 'Due ' + fmtTime(prepDue);
    clearInterval(waveT); let i = 0;
    const draw = () => sprite(alertBot, i++ % 2 ? 'wave2' : 'wave1', 2.25, '#ff9f0a');
    draw(); if (!reduce) waveT = setInterval(draw, 400);
  }
  function endAlert(msg) {
    alertDone = true; sectionState = 'idle'; setIsland('idle'); behave('idle');
    $('#alertStatus').textContent = msg; $('#again').hidden = false;
  }
  $('#snooze').onclick = () => endAlert(`Snoozed. It comes back at ${fmtTime(new Date(Date.now() + 5 * MIN))}.`);
  $('#doneBtn').onclick = () => {
    const x = tasks.find(t => t.t.startsWith('Prep')); if (x) x.done = true; renderList();
    endAlert('Ticked off. It\'s in the Done list in the island now.'); react('hop');
  };
  $('#again').onclick = () => { alertDone = false; sectionState = 'alert'; setIsland('alert'); $('#again').hidden = true; $('#alertStatus').textContent = ''; };

  // ===================== Claude Code asking =====================
  const askBot = $('#askBot');
  let askT;
  function showAsk() {
    clearInterval(askT); let i = 0;
    const draw = () => sprite(askBot, i++ % 2 ? 'wave2' : 'wave1', 2.25, '#ff9f0a');
    draw(); if (!reduce) askT = setInterval(draw, 400);
  }
  function endAsk(msg) {
    askDone = true; sectionState = 'agent'; behave('work'); setIsland('agent');
    $('#askStatus').textContent = msg; $('#askAgain').hidden = false;
  }
  $('#allow').onclick = () => endAsk('Allowed. Claude Code carries on, and the notch goes back to how long it has been working.');
  $('#deny').onclick = () => endAsk('Denied. Claude Code hears you said no, and tries another way.');
  $('#interm').onclick = () => endAsk('Handed back to the terminal, where Claude Code shows the whole request.');
  $('#askAgain').onclick = () => { askDone = false; sectionState = 'ask'; setIsland('ask'); $('#askAgain').hidden = true; $('#askStatus').textContent = ''; };

  // ===================== clips: click one to copy it =====================
  $$('.cliprow').forEach(c => c.onclick = async () => {
    const hint = $('#clipHint');
    if (c.dataset.copy) { await navigator.clipboard?.writeText(c.dataset.copy); hint.textContent = 'Copied'; }
    else hint.textContent = 'In the app, drag it straight into another app';
    clearTimeout(hint.t); hint.t = setTimeout(() => hint.textContent = 'Click to copy, or drag out', 2200);
  });

  // ===================== files: drag them up into the notch =====================
  function addToShelf(name) {
    shelfFiles++;
    const c = $('#shelfCount'); c.textContent = shelfFiles; c.classList.remove('bump'); void c.offsetWidth; c.classList.add('bump');
    $('#emptyShelf').hidden = false;
    $('#filesStatus').textContent = `${name} is on the shelf. ${shelfFiles === 1 ? 'One file' : shelfFiles + ' files'} waiting in the notch.`;
    sectionState = 'shelf'; setIsland('shelf'); react('hop');
  }
  function overIsland(x, y) {
    const r = island.getBoundingClientRect();
    if (x < r.left - 30 || x > r.right + 30 || y > r.bottom + 40) return null;
    return x > $('#zoneAir').getBoundingClientRect().left - 4 ? 'air' : 'hold';
  }
  $$('.file').forEach(f => {
    f.addEventListener('pointerdown', e => {
      if (e.button !== 0) return;
      e.preventDefault();
      const start = {x: e.clientX, y: e.clientY}; let ghost = null;
      const move = ev => {
        if (!ghost && Math.hypot(ev.clientX - start.x, ev.clientY - start.y) < 6) return;
        if (!ghost) {
          dragging = true;
          ghost = document.createElement('div'); ghost.className = 'ghost'; ghost.innerHTML = f.querySelector('.doc').outerHTML;
          document.body.append(ghost); f.classList.add('gone');
          setIsland('drop'); B.mode = 'idle'; behave('watch');
        }
        ghost.style.left = ev.clientX + 'px'; ghost.style.top = ev.clientY + 'px';
        const where = overIsland(ev.clientX, ev.clientY);
        $('#zoneHold').classList.toggle('hot', where === 'hold'); $('#zoneAir').classList.toggle('hot', where === 'air');
        $('#holdText').textContent = where === 'hold' ? 'Release to hold' : 'Drop files here';
      };
      const up = ev => {
        removeEventListener('pointermove', move); removeEventListener('pointerup', up);
        if (!ghost) return;
        f.dataset.dragged = '1';
        const where = overIsland(ev.clientX, ev.clientY);
        $$('.zone').forEach(z => z.classList.remove('hot'));
        dragging = false; behave(botMode(sectionState));
        if (where) {
          const r = island.getBoundingClientRect();
          ghost.classList.add('fly'); ghost.style.left = r.left + r.width / 2 + 'px'; ghost.style.top = '12px'; ghost.style.transform = 'translate(-50%,-50%) scale(.15)'; ghost.style.opacity = '0';
          setTimeout(() => ghost.remove(), 450);
          if (where === 'hold') addToShelf(f.dataset.name);
          else { f.classList.remove('gone'); setPeek('airdrop', f.dataset.name); $('#filesStatus').textContent = `AirDrop opens with ${f.dataset.name}, ready to send.`; }
        } else {
          const r = f.getBoundingClientRect();
          ghost.classList.add('fly'); ghost.style.left = r.left + r.width / 2 + 'px'; ghost.style.top = r.top + 40 + 'px';
          setTimeout(() => { ghost.remove(); f.classList.remove('gone'); }, 450);
          setIsland(sectionState);
        }
      };
      addEventListener('pointermove', move); addEventListener('pointerup', up);
    });
    // Keyboard (and plain clicks): straight onto the shelf
    f.addEventListener('click', () => { if (f.dataset.dragged) { delete f.dataset.dragged; return; } if (!f.classList.contains('gone')) { f.classList.add('gone'); addToShelf(f.dataset.name); } });
  });
  $('#emptyShelf').onclick = () => {
    shelfFiles = 0; $$('.file').forEach(f => f.classList.remove('gone'));
    $('#emptyShelf').hidden = true; $('#filesStatus').textContent = 'The shelf is empty again.';
    sectionState = 'idle'; setIsland('idle');
  };
  $('#dl').onclick = async () => {
    $('#dl').disabled = true; flashing = true; setIsland('download');
    for (let p = 0; p <= 100; p += 4) {
      $('#ringBar').setAttribute('stroke-dashoffset', 47.1 * (1 - p / 100)); $('#dlPct').textContent = p + '%';
      await sleep(reduce ? 10 : 70);
    }
    flashing = false; $('#dl').disabled = false;
    addToShelf('invoice-0412.pdf');
  };

  // ===================== music: a new track peeks out =====================
  const TRACKS = [['Slow Tide', 'Harbor Lights', ''], ['Glass Hours', 'Mira Vale', 'b'], ['Lowland', 'The Quiet Fields', 'c']];
  let trackN = 0;
  function setPeek(kind, name) {
    if (kind === 'airdrop') {
      $('#peekArt').className = 'art b'; $('#peekTitle').textContent = 'AirDrop'; $('#peekSub').textContent = name; $('#peekEq').hidden = true;
      flash('peek', 2600);
    } else {
      trackN = (trackN + 1) % TRACKS.length; const [t, a, c] = TRACKS[trackN];
      $('#peekArt').className = 'art ' + c; $('#peekTitle').textContent = t; $('#peekSub').textContent = a; $('#peekEq').hidden = false;
      $$('.layer[data-l=music] .art').forEach(el => el.className = 'art ' + c);
      flash('peek', 3000); react('hop');
    }
  }
  $('#skip').onclick = () => setPeek('track');

  // ===================== the timer and the agent's clock =====================
  let timerLeft = 4 * 60, agentFor = 134;
  setInterval(() => {
    if (island.dataset.s === 'timer') { timerLeft = timerLeft > 0 ? timerLeft - 1 : 4 * 60; $('#timerTime').textContent = mmss(timerLeft); }
    agentFor++; $('#agentTime').textContent = mmss(agentFor);
  }, 1000);

  // ===================== robot poses =====================
  const POSES = [
    {t: 'Walks the menu bar', d: 'Strolls along beside the notch, and stops to look around.', f: ['walk1','walk2'], scene: 'floor'},
    {t: 'Climbs the walls', d: 'Magnet boots: it walks straight up the sides of the island.', f: ['walk1','walk2'], scene: 'wall'},
    {t: 'Hangs underneath', d: 'Upside down, under the island.', f: ['walk1','walk2'], scene: 'ceiling'},
    {t: 'Sits and dozes', d: 'Swings its legs over the edge, and sleeps when nothing is going on.', f: ['sit','sleep'], scene: 'edge'},
    {t: 'Dances to music', d: 'Its antenna takes the colour of the album art.', f: ['danceA','danceB'], scene: 'floor', a: '#ff8a65'},
    {t: 'Waves at your cursor', d: 'Bring the pointer near it.', f: ['wave1','wave2'], scene: 'floor'},
    {t: 'Types during focus', d: 'At a little desk, until the timer rings.', f: ['work1','work2'], scene: 'floor'},
    {t: 'Yawns before a meeting', d: 'Five minutes to go: time to stretch.', f: ['stretch','stand'], scene: 'floor'},
    {t: 'Dresses for the season', d: 'A pumpkin in October, a Santa hat in December.', f: ['stand','stand'], scene: 'floor', hats: ['pumpkin','santa']},
  ];
  const poseBox = $('#poses');
  POSES.forEach(p => {
    const el = document.createElement('div'); el.className = 'pose'; el.tabIndex = 0;
    el.innerHTML = `<div class="scene"></div><div><b>${p.t}</b><span>${p.d}</span></div>`;
    const sc = el.querySelector('.scene');
    // The scene: the menu bar (a 64px band), the island in black, the robot on whichever surface it's using
    const band = document.createElement('i'), slab = document.createElement('i');
    band.className = 'slab'; Object.assign(band.style, {left: 0, right: 0, top: 0, height: '64px', background: 'rgba(28,31,38,.06)'});
    slab.className = 'slab';
    const S = {floor: ['calc(50% - 124px)', '96px', '64px'], edge: ['calc(50% - 124px)', '96px', '64px'],
               wall: ['calc(50% - 6px)', '110px', '100px'], ceiling: ['calc(50% - 70px)', '140px', '64px']}[p.scene];
    Object.assign(slab.style, {left: S[0], width: S[1], top: 0, height: S[2], borderRadius: '0 0 14px 14px'});
    sc.append(band, slab);
    const bots = (p.hats || [HAT]).map(() => { const c = document.createElement('canvas'); sc.append(c); return c; });
    const px = 3, H = 15 * px;
    const place = (cv, i, frame) => {
      sprite(cv, frame, px, p.a || '#FF6B80', p.hats ? p.hats[i] : HAT);
      const s = cv.style;
      if (p.scene === 'floor' || p.scene === 'edge') { s.left = `calc(50% - 10px + ${i * 60}px)`; s.top = (64 - H + below(frame) * px) + 'px'; }
      if (p.scene === 'wall') { s.left = 'calc(50% - 44px)'; s.top = '58px'; s.transform = 'rotate(-90deg)'; }  // feet on the island's side
      if (p.scene === 'ceiling') { s.left = 'calc(50% - 18px)'; s.top = '61px'; s.transform = 'scaleY(-1)'; }  // feet on its underside
    };
    bots.forEach((c, i) => place(c, i, p.f[0]));
    let timer, n = 0;
    const go = () => { if (reduce || timer) return; timer = setInterval(() => bots.forEach((c, i) => place(c, i, p.f[++n % 2])), p.f[0] === 'stretch' ? 900 : 300); };
    const stop = () => { clearInterval(timer); timer = null; n = 0; bots.forEach((c, i) => place(c, i, p.f[0])); };
    el.addEventListener('pointerenter', go); el.addEventListener('pointerleave', stop);
    el.addEventListener('focus', go); el.addEventListener('blur', stop);
    poseBox.append(el);
  });


  // ===================== the menu bar, magnified =====================
  // Each part: x from the island's left edge (negative: the robot's side), y of its bottom edge, and what it is
  const ZOOM = {
    alert:    {parts: [[42, 94, 'Rings the bell'], [184, 108, 'Snooze it, or tick it off'], [290, 60, 'Your task and its time']], bot: null},
    music:    {parts: [[-38, 31, 'The robot dances'], [22, 27, 'The album artwork'], [252, 23, 'Bars bounce while it plays']], bot: ['danceA','danceB'], a: '#ff8a65'},
    meeting:  {parts: [[-38, 31, 'Time for a stretch'], [60, 22, 'Your next meeting'], [388, 22, 'When it starts']], bot: ['stretch','stand']},
    agent:    {parts: [[-38, 31, 'Types while Claude works'], [60, 23, 'The project'], [350, 23, 'How long it has been working']], bot: ['work1','work2']},
    timer:    {parts: [[34, 23, 'What it is for'], [338, 23, 'Time left']], bot: null},
    charging: {parts: [[-38, 31, 'A hop when you plug in'], [52, 23, 'Shows as you plug in'], [372, 23, 'The battery filling up']], bot: ['stand','look']},
  };
  const zooms = $$('.zoom').map(fig => {
    const st = fig.dataset.zoom, [w, h, r] = SIZES[st], z = ZOOM[st];
    fig.innerHTML = `<div class="zwrap"><div class="zscene"><i class="zband"></i><div class="zisland" style="width:${w}px;height:${h}px;border-radius:0 0 ${r}px ${r}px"></div></div></div>`;
    const layer = $(`.layer[data-l=${st}]`).cloneNode(true);
    layer.querySelectorAll('[id]').forEach(e => e.removeAttribute('id'));
    layer.querySelectorAll('button').forEach(b => b.tabIndex = -1);
    layer.classList.add('on');
    fig.querySelector('.zisland').append(layer);
    if (st === 'charging') layer.querySelector('rect[fill="#30d158"]').setAttribute('width', 17.6);
    if (st === 'alert') sprite(layer.querySelector('canvas'), 'wave1', 2.25, '#ff9f0a');
    if (st === 'agent' || st === 'timer') layer.querySelector('.tint').textContent = st === 'agent' ? '2:14' : '4:00';
    let cv = null;
    if (z.bot) { cv = document.createElement('canvas'); cv.className = 'zbot'; fig.querySelector('.zscene').append(cv); }
    const pose = f => { if (!cv) return; sprite(cv, f, 2, z.a); cv.style.top = 32 - (15 - below(f)) * 2 + 'px'; };
    // Moves when you point at it
    let t = null, n = 0;
    fig.addEventListener('pointerenter', () => { if (reduce || !z.bot) return; t = setInterval(() => pose(z.bot[++n % 2]), z.bot[0] === 'stretch' ? 900 : 300); });
    fig.addEventListener('pointerleave', () => { clearInterval(t); n = 0; if (z.bot) pose(z.bot[0]); });
    const zz = {fig, st, w, h, z, cv, pose};
    return zz;
  });
  function layoutZoom({fig, w, h, z, cv}) {
    const W = fig.clientWidth, s = Math.min(2.5, (W - 60) / (w + 120)), sceneW = W / s, left = (sceneW - w) / 2 + 30;
    const narrow = W < 640, sceneH = Math.max(h, 32) + 16, labelTop = narrow ? sceneH * s - 22 : sceneH * s + 36;
    const wrap = fig.querySelector('.zwrap'), scene = fig.querySelector('.zscene');
    wrap.style.height = labelTop + 34 + 'px';
    Object.assign(scene.style, {width: sceneW + 'px', height: sceneH + 'px', transform: `scale(${s})`});
    fig.querySelector('.zband').style.width = sceneW + 'px';
    fig.querySelector('.zisland').style.left = left + 'px';
    if (cv) cv.style.left = left - 26 - 24 + 'px';
    wrap.querySelectorAll('.callout').forEach(c => c.remove());
    fig.querySelector('.zlist')?.remove();
    if (narrow) {
      const ul = document.createElement('ul'); ul.className = 'zlist';
      ul.innerHTML = z.parts.map(p => `<li>${p[2]}</li>`).join('');
      fig.append(ul);
      return;
    }
    z.parts.forEach(([x, y, text]) => {
      const c = document.createElement('span'), px = (left + x) * s;
      c.className = 'callout' + (px < 120 ? ' l' : px > W - 160 ? ' r' : '');
      c.textContent = text;
      c.style.left = (c.classList.contains('l') ? px - 12 : c.classList.contains('r') ? px + 12 : px) + 'px';
      c.style.top = labelTop + 'px';
      c.style.setProperty('--len', labelTop - 6 - y * s + 'px');
      wrap.append(c);
    });
  }
  zooms.forEach(zz => { if (zz.z.bot) zz.pose(zz.z.bot[0]); layoutZoom(zz); });
  addEventListener('resize', () => zooms.forEach(layoutZoom));

  // ===================== bits =====================
  function clock() {
    const d = new Date();
    $('#clockDay').textContent = d.toLocaleDateString([], {weekday: 'short', day: 'numeric', month: 'short'});
    $('#clockTime').textContent = fmtTime(d);
  }
  clock(); setInterval(clock, 15000);
  $('#noteDate').textContent = shortDate(0);
  $('#treeDay1').textContent = dayStart(-1).toLocaleDateString('sv') + '.txt';
  $('#treeDay2').textContent = dayStart(0).toLocaleDateString('sv') + '.txt';
  $('#copy').onclick = async () => {
    await navigator.clipboard.writeText('xcode-select --install\ngit clone https://github.com/vipulpandey7860/notch-island.git\ncd notch-island/apps/mac && ./build.sh run');
    $('#copy').textContent = 'Copied'; setTimeout(() => $('#copy').textContent = 'Copy', 1600);
  };
  // The island is only interactive while it's open: keep its controls out of the tab order otherwise
  const ws = $('.ws');
  new MutationObserver(() => ws.querySelectorAll('button,input,[contenteditable]').forEach(el => el.tabIndex = island.dataset.s === 'expanded' ? 0 : -1))
    .observe(island, {attributes: true, attributeFilter: ['data-s']});
  for (const al of island.querySelectorAll('.alert')) {
    new MutationObserver(() => al.querySelectorAll('button').forEach(el => el.tabIndex = island.dataset.s === al.dataset.l ? 0 : -1))
      .observe(island, {attributes: true, attributeFilter: ['data-s']});
  }
  island.removeAttribute('aria-hidden');

  renderList(); countWords(); tickPlayer(); bdraw('stand'); scale();
  behave('idle');
}
