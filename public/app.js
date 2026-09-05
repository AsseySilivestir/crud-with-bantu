// ─────────────────────────────────────────────────────────────────────
//  Bantu FS & Power Demo — frontend logic (vanilla JS, no framework)
// ─────────────────────────────────────────────────────────────────────

const API = '';

// ─── Helpers ────────────────────────────────────────────────────
async function getJSON(url) {
  const r = await fetch(API + url);
  if (!r.ok) {
    let detail = '';
    try { detail = (await r.json()).error || ''; } catch (_) {}
    throw new Error(`${r.status} ${r.statusText} — ${detail}`);
  }
  return r.json();
}

async function postJSON(url, body) {
  const r = await fetch(API + url, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(body),
  });
  if (!r.ok) {
    let detail = '';
    try { detail = (await r.json()).error || ''; } catch (_) {}
    throw new Error(`${r.status} ${r.statusText} — ${detail}`);
  }
  return r.json();
}

async function deleteJSON(url) {
  const r = await fetch(API + url, { method: 'DELETE' });
  if (!r.ok) {
    let detail = '';
    try { detail = (await r.json()).error || ''; } catch (_) {}
    throw new Error(`${r.status} ${r.statusText} — ${detail}`);
  }
  return r.json();
}

function fmtSize(bytes) {
  if (typeof bytes === 'string') bytes = parseInt(bytes, 10);
  if (isNaN(bytes)) return '—';
  if (bytes < 1024)   return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(1)} MB`;
}

function fmtDate(date, time) {
  if (!date) return '—';
  return `${date} ${time || ''}`.trim();
}

// ─── Health check on load ───────────────────────────────────────
async function checkHealth() {
  const pill = document.getElementById('status-pill');
  try {
    const h = await getJSON('/api/health');
    pill.className = 'pill pill-ok';
    pill.textContent = `✓ Bantu v${h.version} — ${h.platform.trim()} — ${h.hostname.trim()}`;
    pill.title = `FFI: ${h.ffi ? 'ready' : 'unavailable'} · workspace: ${h.workspace}`;
  } catch (e) {
    pill.className = 'pill pill-error';
    pill.textContent = `✗ offline — ${e.message}`;
  }
}

// ─── System info ────────────────────────────────────────────────
async function fetchSysInfo() {
  const out = document.getElementById('sysinfo');
  const btn = document.getElementById('btn-sysinfo');
  btn.disabled = true;
  out.textContent = 'Fetching…';
  try {
    const s = await getJSON('/api/sysinfo');
    out.textContent =
      `Kernel     : ${s.kernel.trim()}\n` +
      `Release    : ${s.release.trim()}\n` +
      `Machine    : ${s.machine.trim()}\n` +
      `Hostname   : ${s.hostname.trim()}\n` +
      `Whoami     : ${s.whoami.trim()}\n` +
      `Date       : ${s.date.trim()}\n` +
      `Uptime     : ${s.uptime.trim()}\n` +
      `Load avg   : ${s.load.trim()}\n` +
      `Memory     : ${s.meminfo.trim().replace(/\n/g, '\n             ')}\n` +
      `CPU        : ${s.cpuinfo.trim()}\n` +
      `Disk (/)   : ${s.disk.trim()}\n` +
      `Container  : ${s.container ? 'yes (power actions will be simulated)' : 'no (power actions execute for real)'}`;
  } catch (e) {
    out.textContent = `Error: ${e.message}`;
  } finally {
    btn.disabled = false;
  }
}

// ─── Files: list ────────────────────────────────────────────────
async function refreshFiles() {
  const tbody = document.querySelector('#files-table tbody');
  const count = document.getElementById('file-count');
  tbody.innerHTML = '<tr><td colspan="6" class="muted">Loading…</td></tr>';
  try {
    const r = await getJSON('/api/files');
    count.textContent = `${r.count} file${r.count === 1 ? '' : 's'}`;
    if (r.count === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="muted">No files yet — create one below</td></tr>';
      return;
    }
    tbody.innerHTML = r.files.map(f => `
      <tr>
        <td><code>${escapeHtml(f.name)}</code></td>
        <td>${fmtSize(f.size)}</td>
        <td>${fmtDate(f.date, f.time)}</td>
        <td>${escapeHtml(f.perms)}</td>
        <td>${f.isDir ? '📁 dir' : '📄 file'}</td>
        <td>
          <a title="Read" data-read="${escapeHtml(f.name)}">read</a>
          <button class="btn-delete" data-delete="${escapeHtml(f.name)}">delete</button>
        </td>
      </tr>
    `).join('');
    // Wire up the per-row actions
    tbody.querySelectorAll('[data-read]').forEach(a => {
      a.addEventListener('click', () => readFile(a.getAttribute('data-read')));
    });
    tbody.querySelectorAll('[data-delete]').forEach(btn => {
      btn.addEventListener('click', () => deleteFile(btn.getAttribute('data-delete')));
    });
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="6" class="muted">Error: ${escapeHtml(e.message)}</td></tr>`;
  }
}

// ─── Files: create ──────────────────────────────────────────────
document.getElementById('form-create').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const name = document.getElementById('input-name').value.trim();
  const content = document.getElementById('input-content').value;
  if (!name) return;
  try {
    await postJSON('/api/files', { name, content });
    document.getElementById('input-name').value = '';
    document.getElementById('input-content').value = '';
    refreshFiles();
  } catch (e) {
    alert(`Could not create file: ${e.message}`);
  }
});

// ─── Files: read ────────────────────────────────────────────────
async function readFile(name) {
  const box = document.getElementById('file-reader');
  const nm = document.getElementById('reader-name');
  const ct = document.getElementById('reader-content');
  nm.textContent = name;
  ct.textContent = 'Loading…';
  box.classList.remove('hidden');
  try {
    const r = await getJSON(`/api/files/${encodeURIComponent(name)}`);
    ct.textContent = r.content || '(empty file)';
  } catch (e) {
    ct.textContent = `Error: ${e.message}`;
  }
}

// ─── Files: delete ──────────────────────────────────────────────
async function deleteFile(name) {
  if (!confirm(`Delete "${name}"?`)) return;
  try {
    await deleteJSON(`/api/files/${encodeURIComponent(name)}`);
    refreshFiles();
  } catch (e) {
    alert(`Could not delete: ${e.message}`);
  }
}

// ─── Power: send action ─────────────────────────────────────────
document.querySelectorAll('.power-btn').forEach(btn => {
  btn.addEventListener('click', async () => {
    const action = btn.getAttribute('data-action');
    if (!confirm(`Issue "${action}" command?\n\n(In a container this is simulated; on bare metal it executes for real.)`)) return;
    const out = document.getElementById('power-result');
    out.classList.remove('hidden');
    out.textContent = `Sending ${action}…`;
    try {
      const r = await postJSON('/api/power', { action });
      const tag = r.simulated ? '⚠ SIMULATED' : '✓ EXECUTED';
      out.textContent =
        `${tag}  —  ${r.action.toUpperCase()}\n` +
        `Description : ${r.description}\n` +
        `Command     : ${r.command}\n` +
        `Kernel      : ${r.kernel.trim()}\n` +
        `Container   : ${r.container ? 'yes' : 'no'}\n` +
        `Executed    : ${r.executed ? 'yes' : 'no'}\n` +
        `Exit code   : ${r.rc}\n` +
        `Timestamp   : ${new Date(r.timestamp).toISOString()}\n` +
        `\n${r.message}`;
      refreshPowerLog();
    } catch (e) {
      out.textContent = `Error: ${e.message}`;
    }
  });
});

// ─── Power: audit log ───────────────────────────────────────────
async function refreshPowerLog() {
  const out = document.getElementById('power-log');
  try {
    const r = await getJSON('/api/power/log');
    if (r.count === 0) {
      out.textContent = '— no entries yet —';
      return;
    }
    out.textContent = r.entries.join('\n');
  } catch (e) {
    out.textContent = `Error: ${e.message}`;
  }
}

// ─── Utility ────────────────────────────────────────────────────
function escapeHtml(s) {
  if (s === null || s === undefined) return '';
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ─── Wire up static buttons ─────────────────────────────────────
document.getElementById('btn-refresh').addEventListener('click', refreshFiles);
document.getElementById('btn-sysinfo').addEventListener('click', fetchSysInfo);
document.getElementById('btn-log').addEventListener('click', refreshPowerLog);

// ─── On load ────────────────────────────────────────────────────
checkHealth();
refreshFiles();
refreshPowerLog();
