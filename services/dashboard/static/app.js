const MAX_ROWS = 200;
let es = null;
let activeTopic = '';
let apiServerUrl = '';

function truncate(hex, n) {
  if (!hex || hex.length <= n + 2) return hex;
  return hex.slice(0, n + 2) + '…' + hex.slice(-4);
}

function fmtTime(ts) {
  if (!ts) return '';
  try { return new Date(ts).toISOString().replace('T', ' ').slice(0, 19); } catch { return ts; }
}

function addRow(ev, prepend) {
  const tbody = document.getElementById('events-body');
  const table = document.getElementById('events-table');
  const empty = document.getElementById('empty');

  table.style.display = '';
  empty.style.display = 'none';

  const tr = document.createElement('tr');
  tr.className = 'new-row';

  const dataStr = JSON.stringify(ev.data || {}, null, 2);
  const dataId = 'data-' + Math.random().toString(36).slice(2);

  tr.innerHTML = `
    <td>${fmtTime(ev.timestamp)}</td>
    <td>${ev.block_number ?? ''}</td>
    <td class="hash">${truncate(ev.tx_hash, 10)}</td>
    <td class="hash">${truncate(ev.contract_address, 10)}</td>
    <td>${ev.topic ?? ''}</td>
    <td>
      <span class="data-toggle" onclick="toggleData('${dataId}')">{ … }</span>
      <pre class="data-content" id="${dataId}">${dataStr}</pre>
    </td>`;

  if (prepend && tbody.firstChild) {
    tbody.insertBefore(tr, tbody.firstChild);
  } else {
    tbody.appendChild(tr);
  }

  // trim old rows
  while (tbody.rows.length > MAX_ROWS) tbody.deleteRow(tbody.rows.length - 1);

  // flash effect: remove class after CSS transition kicks in
  requestAnimationFrame(() => requestAnimationFrame(() => tr.classList.remove('new-row')));
}

function toggleData(id) {
  const el = document.getElementById(id);
  if (el) el.classList.toggle('open');
}

function setStatus(text, cls) {
  const el = document.getElementById('status');
  el.textContent = text;
  el.className = cls || '';
}

function clearTable() {
  document.getElementById('events-body').innerHTML = '';
  document.getElementById('events-table').style.display = 'none';
  document.getElementById('empty').style.display = '';
}

async function backfill(topic) {
  if (!apiServerUrl || !topic) return;
  try {
    const url = `${apiServerUrl}/search/${encodeURIComponent(topic)}?limit=50`;
    const res = await fetch(url);
    if (!res.ok) return;
    const rows = await res.json();
    if (!Array.isArray(rows)) return;
    // rows are newest-first from API
    for (const row of rows) addRow(row, false);
  } catch (e) {
    console.warn('backfill failed:', e);
  }
}

function connectSSE(topic) {
  if (es) { es.close(); es = null; }
  setStatus('connecting…');

  const url = '/events' + (topic ? '?topic=' + encodeURIComponent(topic) : '');
  es = new EventSource(url);

  es.onopen = () => setStatus('connected', 'connected');
  es.onerror = () => setStatus('reconnecting…', 'error');
  es.onmessage = (e) => {
    try { addRow(JSON.parse(e.data), true); } catch {}
  };
}

function switchTab(topic) {
  activeTopic = topic;
  document.querySelectorAll('.tab').forEach(t => {
    t.classList.toggle('active', t.dataset.topic === topic);
  });
  clearTable();
  connectSSE(topic);
  backfill(topic);
}

async function init() {
  let topics = [];
  try {
    const cfg = await fetch('/config').then(r => r.json());
    topics = cfg.topics || [];
    apiServerUrl = cfg.apiServerUrl || '';
  } catch (e) {
    console.warn('config fetch failed:', e);
  }

  const nav = document.getElementById('tabs');

  // "All" tab
  const allTab = document.createElement('div');
  allTab.className = 'tab';
  allTab.dataset.topic = '';
  allTab.textContent = 'All';
  allTab.onclick = () => switchTab('');
  nav.appendChild(allTab);

  for (const t of topics) {
    const tab = document.createElement('div');
    tab.className = 'tab';
    tab.dataset.topic = t;
    tab.textContent = t;
    tab.onclick = () => switchTab(t);
    nav.appendChild(tab);
  }

  switchTab('');
}

init().catch(err => console.error('init failed:', err));
