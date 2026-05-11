const express = require('express');
const { exec, execSync, execFileSync } = require('child_process');
const { Client } = require('ssh2');
const path = require('path');
const os = require('os');
const fs = require('fs');
const crypto = require('crypto');
const https = require('https');
const { pathToFileURL } = require('url');

const app = express();
app.use(express.json({ limit: '20mb' }));
const UPLOADS_DIR = path.join(__dirname, 'public', 'uploads');
fs.mkdirSync(UPLOADS_DIR, { recursive: true });
app.use('/uploads/:file', (req, res, next) => {
  try {
    const file = path.basename(req.params.file || '');
    const full = path.join(UPLOADS_DIR, file);
    if (!full.startsWith(UPLOADS_DIR) || !fs.existsSync(full)) return next();
    const stat = fs.statSync(full);
    const ext = path.extname(file).toLowerCase();
    if (['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'].includes(ext) && stat.size > 0 && stat.size < 64) {
      res.type('image/svg+xml').send(uploadPlaceholderSvg(file));
      return;
    }
  } catch {}
  next();
});
app.use(express.static(path.join(__dirname, 'public')));

const CONFIG_PATH = path.join(__dirname, 'config.json');
const CONFIG_EXAMPLE_PATH = path.join(__dirname, 'config.example.json');
const CHAT_LOG_PATH = path.join(__dirname, 'chat_log.json');
const LESSONS_PATH = path.join(__dirname, 'agent_lessons.json');
const SHARED_OUT = process.env.DASHBOARD_SHARED_OUT || path.join(__dirname, 'output');
fs.mkdirSync(SHARED_OUT, { recursive: true });
const MUSIC_LIBRARY_PATH = path.join(SHARED_OUT, 'music_library.json');
const VERSION_PATH = path.join(__dirname, 'version.json');
const DEV_PROGRESS_PATH = path.join(__dirname, 'dev_progress.json');
const CODEX_HANDOFF_PATH = path.join(__dirname, 'codex_handoff.md');
const BACKUPS_DIR = path.join(__dirname, 'backups');
fs.mkdirSync(BACKUPS_DIR, { recursive: true });

function firstLanAddress() {
  for (const nets of Object.values(os.networkInterfaces())) {
    for (const net of nets || []) {
      if (net.family === 'IPv4' && !net.internal) return net.address;
    }
  }
  return '127.0.0.1';
}

function publicBaseUrl(port) {
  const configured = String(process.env.DASHBOARD_PUBLIC_BASE_URL || '').trim().replace(/\/+$/, '');
  return configured || `http://${firstLanAddress()}:${port}`;
}

function loadVersion() {
  try { return JSON.parse(fs.readFileSync(VERSION_PATH, 'utf-8')); }
  catch { return { version: '1.0.0', history: [] }; }
}
function saveVersion(v) { fs.writeFileSync(VERSION_PATH, JSON.stringify(v, null, 2), 'utf-8'); }

function loadDevProgress() {
  try {
    const data = JSON.parse(fs.readFileSync(DEV_PROGRESS_PATH, 'utf-8'));
    if (!Array.isArray(data.items)) data.items = [];
    return data;
  } catch {
    return { items: [] };
  }
}

function saveDevProgress(data) {
  fs.writeFileSync(DEV_PROGRESS_PATH, JSON.stringify(data, null, 2), 'utf-8');
}

function upsertDevProgress(item) {
  const data = loadDevProgress();
  const now = new Date().toISOString();
  const idx = data.items.findIndex(x => x.id === item.id);
  const next = {
    ...(idx >= 0 ? data.items[idx] : {}),
    ...item,
    updatedAt: now
  };
  if (!next.createdAt) next.createdAt = now;
  if (idx >= 0) data.items[idx] = next;
  else data.items.unshift(next);
  data.items = data.items.slice(0, 80);
  saveDevProgress(data);
  return next;
}

function publicDevProgress() {
  const data = loadDevProgress();
  const now = Date.now();
  const items = (data.items || []).map(item => {
    if (item.status === 'running') {
      const started = Date.parse(item.startedAt || item.createdAt || '');
      if (started && now - started > 45 * 60 * 1000) {
        return { ...item, status: 'stale', statusText: '可能已中断' };
      }
    }
    return item;
  });
  return {
    active: items.filter(x => x.status === 'running' || x.status === 'stale'),
    items
  };
}

const BACKUP_EXCLUDE = ['node_modules', 'backups', 'uploads', '.git', 'chat_log.json'];
// Serve shared output directory as static files
app.use('/files', express.static(SHARED_OUT));
// Uploads directory for images / audio
function uploadPlaceholderSvg(name = 'invalid upload') {
  const label = xmlEscape(String(name || 'invalid upload').slice(0, 80));
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="420" height="140" viewBox="0 0 420 140">
  <rect width="420" height="140" rx="14" fill="#141b26"/>
  <rect x="10" y="10" width="400" height="120" rx="10" fill="#1f2a38" stroke="#f06565" stroke-opacity=".55"/>
  <text x="210" y="58" text-anchor="middle" font-size="18" font-weight="700" fill="#ffb4b4">图片文件无效</text>
  <text x="210" y="88" text-anchor="middle" font-size="12" fill="#c7d6df">${label}</text>
</svg>`;
}
app.use('/uploads/:file', (req, res, next) => {
  try {
    const file = path.basename(req.params.file || '');
    const full = path.join(UPLOADS_DIR, file);
    if (!full.startsWith(UPLOADS_DIR) || !fs.existsSync(full)) return next();
    const stat = fs.statSync(full);
    const ext = path.extname(file).toLowerCase();
    if (['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'].includes(ext) && stat.size > 0 && stat.size < 64) {
      res.type('image/svg+xml').send(uploadPlaceholderSvg(file));
      return;
    }
  } catch {}
  next();
});
app.use('/uploads', express.static(UPLOADS_DIR));

// Image/audio upload endpoint (base64 JSON)
app.post('/api/upload', (req, res) => {
  const { data, mime } = req.body;
  if (!data || !mime) return res.status(400).json({ error: '缺少 data 或 mime' });
  const ext = mime.split('/')[1] || 'bin';
  const fname = `${Date.now()}.${ext}`;
  const buf = Buffer.from(data, 'base64');
  if (/^image\//.test(mime) && buf.length < 64) {
    return res.status(400).json({ error: '图片数据无效或为空' });
  }
  fs.writeFileSync(path.join(UPLOADS_DIR, fname), buf);
  const config = loadConfig();
  const port = config.server.port || 3456;
  const fullUrl = `${publicBaseUrl(port)}/uploads/${fname}`;
  res.json({ ok: true, url: fullUrl });
});

const SECRETS_PATH = path.join(__dirname, 'secrets.json');

function loadSecrets() {
  try { return JSON.parse(fs.readFileSync(SECRETS_PATH, 'utf-8')); }
  catch { return { hostPasswords: {} }; }
}

function saveSecrets(secrets) {
  fs.writeFileSync(SECRETS_PATH, JSON.stringify(secrets, null, 2), 'utf-8');
}

function loadConfig() {
  const sourcePath = fs.existsSync(CONFIG_PATH) ? CONFIG_PATH : CONFIG_EXAMPLE_PATH;
  if (!fs.existsSync(sourcePath)) {
    throw new Error('Missing config.json. Copy config.example.json to config.json and update local settings.');
  }
  const config = JSON.parse(fs.readFileSync(sourcePath, 'utf-8'));
  // Merge secrets (passwords) from separate file
  try {
    const secrets = loadSecrets();
    if (secrets.hostPasswords) {
      for (const [hostId, password] of Object.entries(secrets.hostPasswords)) {
        if (config.hosts[hostId]) config.hosts[hostId].password = password;
      }
    }
  } catch { /* secrets file optional — hosts without password won't connect */ }
  return config;
}
function saveConfig(config) {
  const publicConfig = JSON.parse(JSON.stringify(config));
  for (const h of Object.values(publicConfig.hosts || {})) {
    delete h.password;
    delete h.hasPassword;
  }
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(publicConfig, null, 2), 'utf-8');
}
function loadChatHistory() {
  try {
    const data = JSON.parse(fs.readFileSync(CHAT_LOG_PATH, 'utf-8'));
    if (!data.messages) data.messages = [];
    if (!data.topics) data.topics = [];
    return data;
  } catch { return { topics: [], messages: [] }; }
}
function saveChatHistory(history) {
  const MAX_SIZE = 5 * 1024 * 1024; // keep complete multi-agent meetings available for review
  const MAX_MESSAGES = 2000;
  // Rotate if file too large
  if (history.messages.length > MAX_MESSAGES) {
    history.messages = history.messages.slice(-MAX_MESSAGES / 2);
  }
  const json = JSON.stringify(history, null, 2);
  if (Buffer.byteLength(json, 'utf-8') > MAX_SIZE) {
    // Archive old messages
    const half = Math.floor(history.messages.length / 2);
    history.messages = history.messages.slice(half);
    fs.writeFileSync(CHAT_LOG_PATH, JSON.stringify(history, null, 2), 'utf-8');
  } else {
    fs.writeFileSync(CHAT_LOG_PATH, json, 'utf-8');
  }
}
let chatHistory = loadChatHistory();

// Single entry point: push message + broadcast + persist
function addChatMessage(msg) {
  // Truncate agent responses to prevent context pollution
  if (msg.content && msg.from !== '你' && msg.from !== 'user') {
    msg.content = compactAgentText(msg.content, 2000);
  }
  // Strip lone surrogates that would corrupt JSON
  if (msg.content) {
    msg.content = msg.content.replace(/[\uD800-\uDFFF]/g, '�');
  }
  chatHistory.messages.push(msg);
  broadcastSSE('chat', msg);
  saveChatHistory(chatHistory);
}

// ── SSE (Server-Sent Events) for real-time big screen ─────────

const sseClients = new Set();

function broadcastSSE(event, data) {
  const payload = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const client of sseClients) {
    try { client.write(payload); } catch { sseClients.delete(client); }
  }
}

app.get('/api/chat/stream', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'Access-Control-Allow-Origin': '*'
  });
  res.write('event: connected\ndata: {}\n\n');
  sseClients.add(res);
  req.on('close', () => sseClients.delete(res));
});

app.post('/api/doudizhu/continue', async (req, res) => {
  try {
    const config = loadConfig();
    const resumeState = latestUnfinishedDoudizhuGame();
    if (!resumeState) {
      return res.status(404).json({ ok: false, error: '没有可继续的斗地主牌局；已结束牌局或旧牌局缺少手牌状态时无法续局。' });
    }
    const reporter = pickAutoRepairReporterAgent(config);
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `🔁 已点击继续斗地主：从第 ${resumeState.nextTurnNo} 手恢复最近未完成牌局。`,
      timestamp: new Date().toISOString(),
      type: 'roundtable',
      topic: '斗地主流程',
      doudizhu: ddzPublicState(resumeState.players, resumeState.landlordIndex, resumeState.nextTurnNo, resumeState.lastPlay, resumeState.players[resumeState.currentIndex])
    });
    const result = await runDoudizhuFlow({
      plan: {
        participants: resumeState.players.map(p => p.agent),
        reporter,
        maxTurns: resumeState.maxTurns,
        topic: '斗地主流程',
        resumeState,
        resumed: true
      },
      message: '继续斗地主',
      mode: 'roundtable',
      config
    });
    res.json({ ...result, resumed: true });
  } catch (err) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `❌ 继续斗地主失败：${err.message}`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: '斗地主流程'
    });
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ── Local exec ──────────────────────────────────────────────────

function extractCode(text) {
  // Strip markdown code fences — extract the largest code block if present
  const fenceRe = /```[\w-]*\r?\n([\s\S]*?)```/g;
  const blocks = [];
  let m;
  while ((m = fenceRe.exec(text)) !== null) {
    blocks.push(m[1].trim());
  }
  if (blocks.length > 0) {
    // Return the largest block (most likely the actual code)
    blocks.sort((a, b) => b.length - a.length);
    return blocks[0];
  }
  return text;
}

function extractPythonScript(text) {
  // Extract python-pptx script from agent output
  // Priority: ```python fence > ```py fence > any fence with prs.save > raw text if it looks like a python script
  const fenceRe = /```(?:python|py)\r?\n([\s\S]*?)```/g;
  const blocks = [];
  let m;
  while ((m = fenceRe.exec(text)) !== null) {
    blocks.push(m[1].trim());
  }
  if (blocks.length > 0) {
    blocks.sort((a, b) => b.length - a.length);
    const best = blocks.find(b => /prs\.save|pptx\.Presentation|from\s+pptx/i.test(b));
    return best || blocks[0];
  }
  // Fallback: any code fence containing pptx keywords
  const anyFenceRe = /```[\w-]*\r?\n([\s\S]*?)```/g;
  while ((m = anyFenceRe.exec(text)) !== null) {
    if (/prs\.save|pptx\.Presentation|from\s+pptx|slide_layouts/i.test(m[1])) {
      return m[1].trim();
    }
  }
  return '';
}

function detectCodeExt(code) {
  const head = code.slice(0, 800);
  if (/<!DOCTYPE\s+html|<html\b/i.test(head)) return 'html';
  if (/^\s*<\?xml/i.test(head)) return 'xml';
  if (/import\s+\w+|def\s+\w+\s*\(|class\s+\w+[:(]/.test(head) && /\.py|python/i.test(head.slice(0, 200))) return 'py';
  if (/<script\b|<style\b|<\/?\w+[\s>]/.test(head) && !/<html/i.test(head)) return 'html';
  if (/\.jsx?|jsx/.test(head.slice(0, 100)) || /import\s+.*from\s+['"]|export\s+(default\s+)?|const\s+\w+\s*=\s*(\(\)|function|=>)/.test(head)) return 'js';
  if (/\.tsx?|typescript/i.test(head.slice(0, 100)) || /interface\s+\w+\s*\{|type\s+\w+\s*=/.test(head)) return 'ts';
  if (/package\.json|"dependencies"\s*:/.test(head)) return 'json';
  if (/^#!/.test(head)) return 'sh';
  if (/^\s*\.\w+[\s{]/m.test(head) && /[:;]/.test(head)) return 'css';
  return 'txt';
}

function execPromise(cmd, timeout = 10000) {
  return new Promise((resolve) => {
    exec(cmd, { timeout, windowsHide: true, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
      resolve({ ok: !err, stdout: stdout.trim(), stderr: stderr.trim(), code: err?.code });
    });
  });
}

// ── SSH2 Connection Pool ────────────────────────────────────────
// Reuse connections, but aggressively discard dead sockets. A stale SSH
// object in the pool is the most common reason agents look offline on LAN.
const sshPool = {}; // "host:port" -> { conns: Client[], queue: [], max: 2 }

function poolKey(hostConfig) {
  return `${hostConfig.host}:${hostConfig.port || 22}`;
}

function getPool(hostConfig) {
  const key = poolKey(hostConfig);
  let entry = sshPool[key];
  if (!entry) {
    entry = sshPool[key] = { conns: [], queue: [], max: hostConfig.maxConnections || 2, hostConfig };
  }
  return entry;
}

function isConnUsable(conn) {
  return conn && !conn._dead && (conn._authed || conn._connecting || conn._pendingAuth);
}

function dropConnection(conn, entry, reason = '') {
  if (!conn || conn._dead) return;
  conn._dead = true;
  conn.busy = false;
  conn._authed = false;
  conn._connecting = false;
  conn._pendingAuth = false;
  entry.conns = entry.conns.filter(c => c !== conn);
  try { conn.end(); } catch {}
  try { conn.destroy(); } catch {}
  if (reason) console.error(`[SSH] drop ${poolKey(entry.hostConfig)}: ${reason}`);
  pumpSshQueue(entry);
}

function attachConnLifecycle(conn, entry) {
  if (conn._lifecycleAttached) return;
  conn._lifecycleAttached = true;
  conn.on('close', () => dropConnection(conn, entry, 'closed'));
  conn.on('end', () => dropConnection(conn, entry, 'ended'));
  conn.on('error', (err) => dropConnection(conn, entry, err.message || 'error'));
}

function getPoolConnection(hostConfig) {
  const entry = getPool(hostConfig);
  entry.conns = entry.conns.filter(isConnUsable);

  const idle = entry.conns.find(c => c._authed && !c.busy && !c._dead);
  if (idle) {
    idle.busy = true;
    return { conn: idle, entry };
  }

  if (entry.conns.filter(isConnUsable).length < entry.max) {
    const conn = new Client();
    conn._connecting = true;
    conn.busy = true;
    attachConnLifecycle(conn, entry);
    entry.conns.push(conn);
    return { conn, entry };
  }

  return { conn: null, entry };
}

function releaseConnection(conn, entry, reusable = true) {
  if (!conn || !entry) return;
  if (!reusable || conn._dead || !conn._authed) {
    dropConnection(conn, entry, 'not reusable');
    return;
  }
  conn.busy = false;
  pumpSshQueue(entry);
}

function createPoolConnection(entry) {
  const conn = new Client();
  conn._connecting = true;
  conn.busy = true;
  attachConnLifecycle(conn, entry);
  entry.conns.push(conn);
  return conn;
}

function pumpSshQueue(entry) {
  if (!entry || entry.queue.length === 0) return;
  entry.conns = entry.conns.filter(isConnUsable);

  while (entry.queue.length > 0) {
    const idle = entry.conns.find(c => c._authed && !c.busy && !c._dead);
    if (idle) {
      const waiter = entry.queue.shift();
      idle.busy = true;
      waiter.resolve(idle);
      continue;
    }

    if (entry.conns.filter(isConnUsable).length < entry.max) {
      const waiter = entry.queue.shift();
      waiter.resolve(createPoolConnection(entry));
      continue;
    }

    break;
  }
}

function waitForConnection(entry, timeout = 30000) {
  return new Promise((resolve, reject) => {
    const waiter = { resolve, reject };
    const timer = setTimeout(() => {
      const idx = entry.queue.indexOf(waiter);
      if (idx >= 0) entry.queue.splice(idx, 1);
      reject(new Error('等待可用连接超时'));
    }, timeout);
    waiter.resolve = (conn) => { clearTimeout(timer); resolve(conn); };
    waiter.reject = (err) => { clearTimeout(timer); reject(err); };
    entry.queue.push(waiter);
    pumpSshQueue(entry);
  });
}

async function acquireConnection(hostConfig, timeout = 30000) {
  const entry = getPool(hostConfig);
  const { conn } = getPoolConnection(hostConfig);
  if (conn) {
    return conn;
  }
  return waitForConnection(entry, timeout);
}

function ensureConnected(conn, hostConfig) {
  if (conn._authed && !conn._dead) return Promise.resolve(conn);
  return new Promise((resolve, reject) => {
    if (conn._pendingAuth) {
      const check = setInterval(() => {
        if (conn._dead || conn._authError) { clearInterval(check); reject(conn._authError || new Error('SSH 连接已断开')); }
        if (conn._authed) { clearInterval(check); resolve(conn); }
      }, 50);
      return;
    }
    conn._pendingAuth = true;
    conn._connecting = false;
    const timer = setTimeout(() => {
      conn._pendingAuth = false;
      conn._authError = new Error('Timed out while waiting for handshake');
      const entry = getPool(hostConfig);
      dropConnection(conn, entry, conn._authError.message);
      reject(conn._authError);
    }, 30000);

    conn.once('ready', () => {
      clearTimeout(timer);
      conn._authed = true;
      conn._pendingAuth = false;
      conn._authError = null;
      conn.busy = true;
      resolve(conn);
    });
    conn.once('error', (err) => {
      clearTimeout(timer);
      conn._pendingAuth = false;
      conn._authError = err;
      const entry = getPool(hostConfig);
      dropConnection(conn, entry, err.message);
      reject(err);
    });
    conn.connect({
      host: hostConfig.host,
      port: hostConfig.port || 22,
      username: hostConfig.user,
      password: hostConfig.password || undefined,
      readyTimeout: hostConfig.readyTimeout || 30000,
      keepaliveInterval: hostConfig.keepaliveInterval || 15000,
      keepaliveCountMax: hostConfig.keepaliveCountMax || 4
    });
  });
}

function sshExec(hostConfig, command, timeout = 15000) {
  return new Promise(async (resolve) => {
    let conn;
    let settled = false;
    const done = (value, reusable = true) => {
      if (settled) return;
      settled = true;
      const entry = getPool(hostConfig);
      releaseConnection(conn, entry, reusable);
      resolve(value);
    };
    try {
      conn = await acquireConnection(hostConfig, timeout);
      await ensureConnected(conn, hostConfig);
    } catch (e) {
      return resolve({ ok: false, stdout: '', stderr: e.message });
    }

    const cmdTimer = setTimeout(() => {
      done({ ok: false, stdout: '', stderr: 'SSH 命令执行超时' }, false);
    }, timeout);

    conn.exec(command, (err, stream) => {
      if (err) {
        clearTimeout(cmdTimer);
        return done({ ok: false, stdout: '', stderr: err.message }, false);
      }
      let stdout = '', stderr = '';
      stream.on('data', (d) => { stdout += d.toString(); });
      stream.stderr.on('data', (d) => { stderr += d.toString(); });
      stream.on('error', (err) => {
        clearTimeout(cmdTimer);
        done({ ok: false, stdout: stdout.trim(), stderr: err.message || stderr.trim() }, false);
      });
      stream.on('close', (code) => {
        clearTimeout(cmdTimer);
        done({ ok: code === 0, stdout: stdout.trim(), stderr: stderr.trim(), code }, true);
      });
    });
  });
}

// ── Agent helpers ───────────────────────────────────────────────

function getHostGroup(agentId) {
  const config = loadConfig();
  for (const [group, agents] of Object.entries(config.agents)) {
    if (agents.some(a => a.id === agentId)) return group;
  }
  return null;
}

function findAgent(agentId) {
  const config = loadConfig();
  for (const agents of Object.values(config.agents)) {
    const found = agents.find(a => a.id === agentId);
    if (found) return found;
  }
  return null;
}

function allConfiguredAgents(config = loadConfig()) {
  return Object.values(config.agents || {}).flat();
}

function normalizeAgentMatchText(value) {
  return String(value || '').toLowerCase().replace(/[^a-z0-9\u4e00-\u9fa5_-]+/g, '');
}

function agentAliasTokens(agent) {
  const id = String(agent?.id || '').toLowerCase();
  const explicit = {
    xiaoliu: ['小六', '小6', '小刘'],
    xiaoma: ['小马', '小馬'],
    lobster: ['龙虾小弟', '龙虾'],
    doma: ['Doma', '多玛', '多马']
  };
  const aliases = [...(explicit[id] || [])];
  if (/xiaoliu/.test(id)) aliases.push('小六', '小6', '小刘');
  if (/xiaoma/.test(id)) aliases.push('小马', '小馬');
  if (/lobster/.test(id)) aliases.push('龙虾小弟', '龙虾');
  return aliases;
}

function agentMatchTokens(agent) {
  return [agent?.name, agent?.id, agent?.executable, agent?.containerName, ...agentAliasTokens(agent)]
    .map(normalizeAgentMatchText)
    .filter(Boolean);
}

function findConsultTarget(message, requesterIds, config) {
  const text = String(message || '');
  if (!/(咨询|问问|询问|联系|请教|转问|问一下|问下)/.test(text)) return null;
  const normalized = normalizeAgentMatchText(text);
  const excluded = new Set(requesterIds || []);
  const candidates = allConfiguredAgents(config)
    .filter(a => a?.id && !excluded.has(a.id) && !a.disabled)
    .map(a => {
      const names = agentMatchTokens(a);
      const score = names.reduce((best, n) => {
        if (!n) return best;
        if (normalized.includes(n)) return Math.max(best, n.length);
        return best;
      }, 0);
      return { agent: a, score };
    })
    .filter(x => x.score > 0)
    .sort((a, b) => b.score - a.score);
  return candidates[0]?.agent || null;
}

function isGomokuText(message) {
  return /(五子棋|连五子|gomoku|下棋|对弈|棋盘|棋局|第\s*\d+\s*手)/i.test(String(message || ''));
}

function isDoudizhuText(message) {
  return /(斗地主|斗地|打牌|扑克牌|扑克|牌局|地主)/i.test(String(message || ''));
}

function isGomokuResumeText(message) {
  const text = String(message || '');
  return isGomokuText(text) && /(继续|恢复|接着|续上|没下|卡住|不下|第\s*\d+\s*手)/.test(text);
}

function isDoudizhuResumeText(message) {
  const text = String(message || '');
  return isDoudizhuText(text)
    && /(继续|恢复|接着|续上|没打完|没出完|卡住|不下|不出|第\s*\d+\s*手)/.test(text)
    && !/(重新|重开|再来|再开|新开|开始|开局)/.test(text);
}

function isGomokuResultQuery(message) {
  const text = String(message || '');
  return isGomokuText(text)
    && /(前面|刚才|之前|下过|胜负|输赢|谁赢|结果|战况|赢了吗|输了吗)/.test(text)
    && !/(让|请|开始|发起|组织|安排).*(五子棋|下棋|对弈)/.test(text);
}

function latestUnfinishedGomokuGame() {
  let startIndex = -1;
  let startGame = null;
  for (let i = chatHistory.messages.length - 1; i >= 0; i--) {
    const g = chatHistory.messages[i]?.gomoku;
    if (!g) continue;
    if (g.status === 'finished') return null;
    if (g.status === 'started') {
      startIndex = i;
      startGame = g;
      break;
    }
  }
  if (startIndex < 0 || !startGame?.blackAgentId || !startGame?.whiteAgentId) return null;
  const blackAgent = findAgent(startGame.blackAgentId);
  const whiteAgent = findAgent(startGame.whiteAgentId);
  if (!blackAgent || !whiteAgent) return null;

  const byNo = new Map();
  for (const msg of chatHistory.messages.slice(startIndex + 1)) {
    const g = msg?.gomoku;
    if (!g) continue;
    if (g.status === 'finished') return null;
    if (Array.isArray(g.moves)) {
      for (const m of g.moves) {
        if (m?.moveNo) byNo.set(Number(m.moveNo), m);
      }
    } else if (g.move?.moveNo) {
      byNo.set(Number(g.move.moveNo), g.move);
    }
  }
  const initialMoves = Array.from(byNo.values())
    .map(m => ({
      moveNo: Number(m.moveNo),
      agentId: m.agentId,
      row: Number(m.row),
      col: Number(m.col),
      stone: m.stone === 'W' ? 'W' : 'B',
      source: m.source || '恢复历史'
    }))
    .filter(m => m.moveNo && m.row >= 1 && m.row <= 15 && m.col >= 1 && m.col <= 15)
    .sort((a, b) => a.moveNo - b.moveNo);
  if (!initialMoves.length) return null;
  return { blackAgent, whiteAgent, startGame, initialMoves };
}

function parseGomokuFlow(message, requester, config) {
  const text = String(message || '');
  if (!isGomokuText(text)) return null;
  if (isGomokuResultQuery(text)) return { queryOnly: true, requester, topic: '五子棋对弈截图流程' };
  const resumeGame = isGomokuResumeText(text) ? latestUnfinishedGomokuGame() : null;
  if (resumeGame) {
    return {
      queryOnly: false,
      requester,
      participants: [resumeGame.blackAgent, resumeGame.whiteAgent],
      reporter: requester,
      size: resumeGame.startGame.size || 15,
      maxMoves: resumeGame.startGame.maxMoves || 45,
      initialMoves: resumeGame.initialMoves,
      resumed: true,
      topic: '五子棋对弈截图流程'
    };
  }

  const named = findNamedAgentsInText(text, config, []);
  let participants = [];
  if (/你和|和你/.test(text)) participants.push(requester);
  for (const agent of named) {
    if (agent.id !== requester.id && !participants.find(a => a.id === agent.id)) participants.push(agent);
  }
  if (!participants.find(a => a.id === requester.id) && participants.length < 2 && /(你|@)/.test(text)) {
    participants.unshift(requester);
  }
  participants = uniqueAgents(participants).slice(0, 2);
  if (participants.length < 2 && /(重新|重开|再来|再开|新开|开始|开局)/.test(text)) {
    for (let i = chatHistory.messages.length - 1; i >= 0; i--) {
      const g = chatHistory.messages[i]?.gomoku;
      if (!g || !g.blackAgentId || !g.whiteAgentId) continue;
      const black = findAgent(g.blackAgentId);
      const white = findAgent(g.whiteAgentId);
      if (black && white) {
        participants = uniqueAgents([black, white]).slice(0, 2);
        break;
      }
    }
  }
  if (participants.length < 2) return null;

  const reporter = participants.some(a => a.id === requester.id) ? null : requester;
  const maxMovesMatch = text.match(/(?:最多|限制)?\s*(\d+)\s*(?:手|步|回合)/);
  const maxMoves = Math.max(9, Math.min(80, parseInt(maxMovesMatch?.[1] || '45', 10) || 45));
  return {
    queryOnly: false,
    requester,
    participants,
    reporter,
    size: 15,
    maxMoves,
    topic: '五子棋对弈截图流程'
  };
}

function gomokuEmptyBoard(size = 15) {
  return Array.from({ length: size }, () => Array(size).fill(null));
}

function gomokuColumnName(col) {
  return String.fromCharCode('A'.charCodeAt(0) + col - 1);
}

function gomokuCoord(row, col) {
  return `${gomokuColumnName(col)}${row}`;
}

function parseGomokuMove(text, size = 15) {
  const raw = String(text || '').trim();
  if (/天元|中心|中央/.test(raw)) {
    const mid = Math.ceil(size / 2);
    return { row: mid, col: mid };
  }
  const json = extractJsonObject(raw);
  if (json) {
    const row = parseInt(json.row ?? json.r ?? json.y, 10);
    let col = json.col ?? json.column ?? json.c ?? json.x;
    if (typeof col === 'string' && /^[a-o]$/i.test(col.trim())) {
      col = col.trim().toUpperCase().charCodeAt(0) - 'A'.charCodeAt(0) + 1;
    } else {
      col = parseInt(col, 10);
    }
    if (row >= 1 && row <= size && col >= 1 && col <= size) return { row, col };
  }
  let m = raw.match(/\b([A-Oa-o])\s*[-:]?\s*(1[0-5]|[1-9])\b/);
  if (m) return { row: parseInt(m[2], 10), col: m[1].toUpperCase().charCodeAt(0) - 'A'.charCodeAt(0) + 1 };
  m = raw.match(/(?:第)?\s*(1[0-5]|[1-9])\s*(?:行|排|,|，|\s)+\s*(?:第)?\s*(1[0-5]|[1-9])\s*(?:列|路)?/);
  if (m) return { row: parseInt(m[1], 10), col: parseInt(m[2], 10) };
  m = raw.match(/\b(1[0-5]|[1-9])\s*[,，]\s*(1[0-5]|[1-9])\b/);
  if (m) return { row: parseInt(m[1], 10), col: parseInt(m[2], 10) };
  return null;
}

function isLegalGomokuMove(board, move) {
  return !!move
    && move.row >= 1 && move.row <= board.length
    && move.col >= 1 && move.col <= board.length
    && !board[move.row - 1][move.col - 1];
}

function placeGomokuMove(board, move, stone) {
  board[move.row - 1][move.col - 1] = stone;
}

function checkGomokuWin(board, move, stone) {
  const dirs = [[1, 0], [0, 1], [1, 1], [1, -1]];
  const size = board.length;
  for (const [dr, dc] of dirs) {
    let count = 1;
    for (const sign of [1, -1]) {
      let r = move.row - 1 + dr * sign;
      let c = move.col - 1 + dc * sign;
      while (r >= 0 && r < size && c >= 0 && c < size && board[r][c] === stone) {
        count++;
        r += dr * sign;
        c += dc * sign;
      }
    }
    if (count >= 5) return true;
  }
  return false;
}

function gomokuBoardText(board) {
  const cols = Array.from({ length: board.length }, (_, i) => gomokuColumnName(i + 1)).join(' ');
  const rows = board.map((row, idx) => {
    const n = String(idx + 1).padStart(2, '0');
    const cells = row.map(v => v === 'B' ? '●' : v === 'W' ? '○' : '·').join(' ');
    return `${n} ${cells}`;
  });
  return `   ${cols}\n${rows.join('\n')}`;
}

function gomokuCandidateMoves(board) {
  const size = board.length;
  const occupied = [];
  for (let r = 0; r < size; r++) {
    for (let c = 0; c < size; c++) if (board[r][c]) occupied.push({ row: r + 1, col: c + 1 });
  }
  if (!occupied.length) {
    const mid = Math.ceil(size / 2);
    return [{ row: mid, col: mid }];
  }
  const seen = new Set();
  const moves = [];
  for (const p of occupied) {
    for (let dr = -2; dr <= 2; dr++) {
      for (let dc = -2; dc <= 2; dc++) {
        const row = p.row + dr;
        const col = p.col + dc;
        const key = `${row},${col}`;
        if (row < 1 || row > size || col < 1 || col > size || seen.has(key)) continue;
        if (!board[row - 1][col - 1]) {
          seen.add(key);
          moves.push({ row, col });
        }
      }
    }
  }
  return moves;
}

function gomokuLineScore(board, move, stone) {
  const size = board.length;
  const dirs = [[1, 0], [0, 1], [1, 1], [1, -1]];
  let total = 0;
  for (const [dr, dc] of dirs) {
    let count = 1;
    let open = 0;
    for (const sign of [1, -1]) {
      let r = move.row - 1 + dr * sign;
      let c = move.col - 1 + dc * sign;
      while (r >= 0 && r < size && c >= 0 && c < size && board[r][c] === stone) {
        count++;
        r += dr * sign;
        c += dc * sign;
      }
      if (r >= 0 && r < size && c >= 0 && c < size && !board[r][c]) open++;
    }
    total += Math.pow(10, count) + open * Math.pow(3, count);
  }
  const mid = (size + 1) / 2;
  total += 20 - Math.abs(move.row - mid) - Math.abs(move.col - mid);
  return total;
}

function chooseGomokuFallbackMove(board, stone, agent) {
  const opponent = stone === 'B' ? 'W' : 'B';
  const candidates = gomokuCandidateMoves(board);
  for (const move of candidates) {
    const copy = board.map(row => row.slice());
    placeGomokuMove(copy, move, stone);
    if (checkGomokuWin(copy, move, stone)) return move;
  }
  for (const move of candidates) {
    const copy = board.map(row => row.slice());
    placeGomokuMove(copy, move, opponent);
    if (checkGomokuWin(copy, move, opponent)) return move;
  }
  const seed = String(agent?.id || agent?.name || '').split('').reduce((n, ch) => n + ch.charCodeAt(0), 0);
  return candidates
    .map(move => ({
      move,
      score: gomokuLineScore(board, move, stone) + gomokuLineScore(board, move, opponent) * 0.82 + ((move.row * 17 + move.col * 31 + seed) % 11)
    }))
    .sort((a, b) => b.score - a.score)[0]?.move || null;
}

function summarizeGomokuScore(board) {
  const scoreFor = (stone) => {
    let best = 0;
    for (let r = 1; r <= board.length; r++) {
      for (let c = 1; c <= board.length; c++) {
        if (board[r - 1][c - 1] !== stone) continue;
        for (const [dr, dc] of [[1, 0], [0, 1], [1, 1], [1, -1]]) {
          let count = 0;
          let rr = r - 1;
          let cc = c - 1;
          while (rr >= 0 && rr < board.length && cc >= 0 && cc < board.length && board[rr][cc] === stone) {
            count++;
            rr += dr;
            cc += dc;
          }
          best = Math.max(best, count);
        }
      }
    }
    return best;
  };
  return { blackLine: scoreFor('B'), whiteLine: scoreFor('W') };
}

function xmlEscape(value) {
  return String(value || '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[ch]));
}

function saveGomokuBoardSvg({ board, blackAgent, whiteAgent, winner, moves, reason }) {
  const size = board.length;
  const cell = 34;
  const margin = 48;
  const boardPx = cell * (size - 1);
  const width = margin * 2 + boardPx + 220;
  const height = margin * 2 + boardPx;
  const last = moves[moves.length - 1];
  const lines = [];
  for (let i = 0; i < size; i++) {
    const p = margin + i * cell;
    lines.push(`<line x1="${margin}" y1="${p}" x2="${margin + boardPx}" y2="${p}" stroke="#59422a" stroke-width="1.4"/>`);
    lines.push(`<line x1="${p}" y1="${margin}" x2="${p}" y2="${margin + boardPx}" stroke="#59422a" stroke-width="1.4"/>`);
    lines.push(`<text x="${p}" y="${margin - 18}" text-anchor="middle" font-size="12" fill="#5b4630">${gomokuColumnName(i + 1)}</text>`);
    lines.push(`<text x="${margin - 20}" y="${p + 4}" text-anchor="middle" font-size="12" fill="#5b4630">${i + 1}</text>`);
  }
  const starPoints = [[4, 4], [4, 8], [4, 12], [8, 4], [8, 8], [8, 12], [12, 4], [12, 8], [12, 12]];
  for (const [r, c] of starPoints) {
    lines.push(`<circle cx="${margin + (c - 1) * cell}" cy="${margin + (r - 1) * cell}" r="3.3" fill="#5b4630"/>`);
  }
  for (let r = 1; r <= size; r++) {
    for (let c = 1; c <= size; c++) {
      const stone = board[r - 1][c - 1];
      if (!stone) continue;
      const x = margin + (c - 1) * cell;
      const y = margin + (r - 1) * cell;
      const isBlack = stone === 'B';
      lines.push(`<circle cx="${x}" cy="${y}" r="14.5" fill="${isBlack ? '#151515' : '#f7f1e5'}" stroke="${isBlack ? '#000' : '#b9ad9a'}" stroke-width="1.5"/>`);
      if (last && last.row === r && last.col === c) {
        lines.push(`<circle cx="${x}" cy="${y}" r="5" fill="${isBlack ? '#f3d36b' : '#8d2f2f'}"/>`);
      }
    }
  }
  const sideX = margin + boardPx + 42;
  const winnerText = winner ? `${winner.agent.name} 获胜` : '本局未分胜负';
  const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <rect width="100%" height="100%" fill="#efe0bd"/>
  <rect x="20" y="20" width="${boardPx + margin + 6}" height="${height - 40}" rx="10" fill="#e6c98f" stroke="#9b7441"/>
  ${lines.join('\n  ')}
  <rect x="${sideX - 18}" y="28" width="180" height="${height - 56}" rx="8" fill="#fff8e7" stroke="#c5aa76"/>
  <text x="${sideX}" y="62" font-size="18" font-weight="700" fill="#3f2d1c">五子棋结果</text>
  <text x="${sideX}" y="100" font-size="14" fill="#2f2418">黑棋: ${xmlEscape(blackAgent.name)}</text>
  <text x="${sideX}" y="126" font-size="14" fill="#2f2418">白棋: ${xmlEscape(whiteAgent.name)}</text>
  <text x="${sideX}" y="166" font-size="15" font-weight="700" fill="#7b2f16">${xmlEscape(winnerText)}</text>
  <text x="${sideX}" y="194" font-size="13" fill="#5f4b34">手数: ${moves.length}</text>
  <text x="${sideX}" y="220" font-size="13" fill="#5f4b34">最后: ${last ? xmlEscape(`${last.agent.name} ${gomokuCoord(last.row, last.col)}`) : '-'}</text>
  <text x="${sideX}" y="248" font-size="12" fill="#6f5b42">${xmlEscape(reason || '')}</text>
</svg>`;
  const filename = `gomoku-${Date.now()}-${crypto.randomBytes(4).toString('hex')}.svg`;
  fs.writeFileSync(path.join(UPLOADS_DIR, filename), svg, 'utf-8');
  return `/uploads/${filename}`;
}

async function askGomokuMove(agent, board, stone, moveNo, maxMoves, opponent, config) {
  const prompt = buildChatPrompt(
    agent,
    '五子棋对弈截图流程',
    `[五子棋对弈]\n你执${stone === 'B' ? '黑棋' : '白棋'}，对手是 ${opponent.name}。\n棋盘坐标为 A-O 列、1-15 行。当前棋盘：\n${gomokuBoardText(board)}\n\n请给出第 ${moveNo}/${maxMoves} 手落子。必须只返回一个 JSON 对象，例如 {"row":8,"col":"H","note":"占据中心"}。不要替对手落子。`,
    'roundtable',
    chatHistory.messages
  );
  const start = Date.now();
  const result = await runAgentChat({ ...agent, chatTimeout: Math.min(agent.chatTimeout || 120000, 45000) }, prompt, config);
  const responseTime = Date.now() - start;
  const move = result.ok ? parseGomokuMove(result.stdout, board.length) : null;
  return { result, responseTime, move };
}

async function runGomokuFlow({ plan, message, mode, config }) {
  const [blackAgent, whiteAgent] = plan.participants;
  const board = gomokuEmptyBoard(plan.size);
  const moves = [];
  const responses = [];
  let winner = null;
  let finishReason = '';
  const flowType = mode && mode !== 'chat' ? mode : 'roundtable';
  const initialMoves = Array.isArray(plan.initialMoves) ? plan.initialMoves : [];
  for (const m of initialMoves) {
    const agent = m.stone === 'B' ? blackAgent : whiteAgent;
    const move = { row: Number(m.row), col: Number(m.col) };
    if (!isLegalGomokuMove(board, move)) continue;
    placeGomokuMove(board, move, m.stone);
    moves.push({
      moveNo: Number(m.moveNo) || moves.length + 1,
      agent,
      stone: m.stone === 'W' ? 'W' : 'B',
      row: move.row,
      col: move.col,
      source: m.source || '恢复历史'
    });
  }

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `${plan.resumed ? `♻️ 五子棋对弈截图流程恢复，已载入 ${moves.length} 手历史棋。` : '🧭 五子棋对弈截图流程启动。'}\n黑棋: ${blackAgent.icon || ''} ${blackAgent.name}\n白棋: ${whiteAgent.icon || ''} ${whiteAgent.name}\n裁判/汇报: ${plan.reporter ? `${plan.reporter.icon || ''} ${plan.reporter.name}` : '系统裁判'}\n最多 ${plan.maxMoves} 手；每次落子、裁判修正和最终棋盘都会公开打印。`,
    timestamp: new Date().toISOString(),
    type: flowType,
    topic: plan.topic,
    gomoku: {
      status: 'started',
      blackAgentId: blackAgent.id,
      blackAgentName: blackAgent.name,
      whiteAgentId: whiteAgent.id,
      whiteAgentName: whiteAgent.name,
      reporterAgentId: plan.reporter?.id || null,
      reporterAgentName: plan.reporter?.name || null,
      size: plan.size,
      maxMoves: plan.maxMoves,
      moves: moves.map(m => ({ moveNo: m.moveNo, agentId: m.agent.id, agentName: m.agent.name, row: m.row, col: m.col, stone: m.stone, source: m.source }))
    }
  });

  for (let i = moves.length; i < plan.maxMoves; i++) {
    const agent = i % 2 === 0 ? blackAgent : whiteAgent;
    const opponent = i % 2 === 0 ? whiteAgent : blackAgent;
    const stone = i % 2 === 0 ? 'B' : 'W';
    const moveNo = i + 1;
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `🔄 第 ${moveNo} 手：请 ${agent.icon || ''} ${agent.name} 执${stone === 'B' ? '黑' : '白'}落子...`,
      timestamp: new Date().toISOString(),
      type: flowType,
      topic: plan.topic,
      gomoku: {
        status: 'waiting',
        blackAgentId: blackAgent.id,
        blackAgentName: blackAgent.name,
        whiteAgentId: whiteAgent.id,
        whiteAgentName: whiteAgent.name,
        size: plan.size,
        maxMoves: plan.maxMoves,
        waiting: { moveNo, agentId: agent.id, agentName: agent.name, stone },
        moves: moves.map(m => ({ moveNo: m.moveNo, agentId: m.agent.id, agentName: m.agent.name, row: m.row, col: m.col, stone: m.stone, source: m.source }))
      }
    });

    const asked = await askGomokuMove(agent, board, stone, moveNo, plan.maxMoves, opponent, config);
    let move = isLegalGomokuMove(board, asked.move) ? asked.move : null;
    let source = 'agent';
    if (!move) {
      move = chooseGomokuFallbackMove(board, stone, agent);
      source = '裁判引擎修正';
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `⚠️ ${agent.name} 本手未返回合法坐标，裁判引擎改为 ${gomokuCoord(move.row, move.col)}。\n原始回复: ${compactAgentText(asked.result.stderr || asked.result.stdout || '无响应', 500)}`,
        timestamp: new Date().toISOString(),
        responseTime: asked.responseTime,
        type: flowType,
        topic: plan.topic
      });
    }
    placeGomokuMove(board, move, stone);
    const record = { moveNo, agent, stone, row: move.row, col: move.col, source };
    moves.push(record);
    responses.push({
      agentId: agent.id,
      agentName: agent.name,
      ok: asked.result.ok,
      stdout: asked.result.stdout,
      stderr: asked.result.stderr,
      responseTime: asked.responseTime,
      move: gomokuCoord(move.row, move.col)
    });
    addChatMessage({
      id: crypto.randomUUID(),
      from: agent.id,
      fromName: `${agent.icon || ''} ${agent.name}`,
      content: `第 ${moveNo} 手 ${stone === 'B' ? '黑棋' : '白棋'}落在 ${gomokuCoord(move.row, move.col)}。${source === 'agent' ? compactAgentText(asked.result.stdout, 180) : '由裁判引擎给出合法补棋。'}`,
      timestamp: new Date().toISOString(),
      responseTime: asked.responseTime,
      type: flowType,
      topic: plan.topic,
      gomoku: {
        status: 'running',
        blackAgentId: blackAgent.id,
        blackAgentName: blackAgent.name,
        whiteAgentId: whiteAgent.id,
        whiteAgentName: whiteAgent.name,
        size: plan.size,
        maxMoves: plan.maxMoves,
        move: { moveNo, agentId: agent.id, agentName: agent.name, row: move.row, col: move.col, stone, source },
        moves: moves.map(m => ({ moveNo: m.moveNo, agentId: m.agent.id, agentName: m.agent.name, row: m.row, col: m.col, stone: m.stone, source: m.source }))
      }
    });
    if (checkGomokuWin(board, move, stone)) {
      winner = { agent, stone, move };
      finishReason = `${agent.name} 在 ${gomokuCoord(move.row, move.col)} 形成五连。`;
      break;
    }
  }

  if (!winner) {
    const score = summarizeGomokuScore(board);
    finishReason = `达到 ${moves.length} 手上限，未形成五连；最长连线黑 ${score.blackLine}、白 ${score.whiteLine}，判为和棋。`;
  }
  const imageUrl = saveGomokuBoardSvg({ board, blackAgent, whiteAgent, winner, moves, reason: finishReason });
  const finalText = `${winner ? `🏁 五子棋结束：${winner.agent.name}（${winner.stone === 'B' ? '黑棋' : '白棋'}）获胜。` : '🏁 五子棋结束：本局和棋。'}\n${finishReason}\n最后棋盘截图：\n![五子棋棋盘](${imageUrl})`;
  const finalMsg = {
    id: crypto.randomUUID(),
    from: plan.reporter ? plan.reporter.id : 'system',
    fromName: plan.reporter ? `${plan.reporter.icon || ''} ${plan.reporter.name}` : '🔔 系统',
    content: finalText,
    timestamp: new Date().toISOString(),
    type: flowType,
    topic: plan.topic,
    gomoku: {
      status: 'finished',
      blackAgentId: blackAgent.id,
      whiteAgentId: whiteAgent.id,
      winnerAgentId: winner?.agent?.id || null,
      winnerName: winner?.agent?.name || null,
      moves: moves.map(m => ({ moveNo: m.moveNo, agentId: m.agent.id, row: m.row, col: m.col, stone: m.stone })),
      imageUrl,
      reason: finishReason
    }
  };
  addChatMessage(finalMsg);
  return { ok: true, gomoku: true, responses, imageUrl, winner: winner?.agent?.name || null };
}

function latestGomokuResultFor(message, requester, config) {
  const named = findNamedAgentsInText(message, config, []);
  const ids = new Set([requester.id, ...named.map(a => a.id)]);
  for (let i = chatHistory.messages.length - 1; i >= 0; i--) {
    const g = chatHistory.messages[i]?.gomoku;
    if (!g || g.status !== 'finished') continue;
    const gameIds = new Set([g.blackAgentId, g.whiteAgentId].filter(Boolean));
    const matches = [...ids].filter(id => gameIds.has(id)).length;
    if (matches >= Math.min(ids.size, 2)) return { msg: chatHistory.messages[i], game: g };
  }
  return null;
}

async function runGomokuResultQuery({ requester, message, mode, topic, config }) {
  const currentTopic = topic || '五子棋对弈截图流程';
  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `🔎 正在查询最近的五子棋对弈记录，并公开答复胜负。`,
    timestamp: new Date().toISOString(),
    type: mode || 'chat',
    topic: currentTopic
  });
  const latest = latestGomokuResultFor(message, requester, config);
  const content = latest
    ? `查到了最近一局五子棋：${latest.game.winnerName ? `${latest.game.winnerName} 获胜` : '和棋'}。\n${latest.game.reason || ''}\n棋盘截图：\n![五子棋棋盘](${latest.game.imageUrl})`
    : `我没有查到我和 Doma 已经完成的五子棋记录；前面的流程是在研发补通阶段，还没有产生正式胜负。现在可以重试：让小六和 Doma 下五子棋，并让龙虾小弟发送最后棋盘截图。`;
  addChatMessage({
    id: crypto.randomUUID(),
    from: requester.id,
    fromName: `${requester.icon || ''} ${requester.name}`,
    content,
    timestamp: new Date().toISOString(),
    type: mode || 'chat',
    topic: currentTopic
  });
  return { ok: true, gomokuQuery: true, responses: [{ agentId: requester.id, agentName: requester.name, ok: true, stdout: content, stderr: '', responseTime: 0 }] };
}

const DDZ_RANKS = ['3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A', '2', 'SJ', 'BJ'];
const DDZ_VALUE = Object.fromEntries(DDZ_RANKS.map((rank, idx) => [rank, idx + 3]));
const DDZ_SUITS = ['S', 'H', 'C', 'D'];
const DDZ_AGENT_TURN_TIMEOUT_MS = 15000;

function ddzDeck() {
  const deck = [];
  for (const rank of DDZ_RANKS.slice(0, 13)) {
    for (const suit of DDZ_SUITS) deck.push(`${rank}${suit}`);
  }
  deck.push('SJ', 'BJ');
  for (let i = deck.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

function ddzRank(card) {
  if (card === 'SJ' || card === 'BJ') return card;
  return String(card || '').slice(0, -1);
}

function ddzCardValue(card) {
  return DDZ_VALUE[ddzRank(card)] || 0;
}

function ddzSortCards(cards) {
  const suitOrder = { S: 0, H: 1, C: 2, D: 3, J: 4 };
  return [...(cards || [])].sort((a, b) =>
    ddzCardValue(a) - ddzCardValue(b) || (suitOrder[a.slice(-1)] || 0) - (suitOrder[b.slice(-1)] || 0)
  );
}

function ddzDisplayCard(card) {
  if (card === 'SJ') return '小王';
  if (card === 'BJ') return '大王';
  const suitMap = { S: '♠', H: '♥', C: '♣', D: '♦' };
  return `${ddzRank(card)}${suitMap[String(card).slice(-1)] || ''}`;
}

function ddzCardsText(cards) {
  return ddzSortCards(cards).map(card => `${card}(${ddzDisplayCard(card)})`).join(' ');
}

function ddzCountRanks(cards) {
  const map = new Map();
  for (const card of cards || []) {
    const rank = ddzRank(card);
    if (!map.has(rank)) map.set(rank, []);
    map.get(rank).push(card);
  }
  for (const list of map.values()) list.sort((a, b) => ddzCardValue(a) - ddzCardValue(b));
  return map;
}

function ddzIsConsecutive(values) {
  for (let i = 1; i < values.length; i++) {
    if (values[i] !== values[i - 1] + 1) return false;
  }
  return true;
}

function analyzeDdzCombo(cards) {
  const sorted = ddzSortCards(cards || []);
  const n = sorted.length;
  if (!n) return null;
  const counts = [...ddzCountRanks(sorted).entries()]
    .map(([rank, list]) => ({ rank, count: list.length, value: DDZ_VALUE[rank] || 0 }))
    .sort((a, b) => a.value - b.value);
  const countValues = counts.map(x => x.count).sort((a, b) => b - a);
  const values = counts.map(x => x.value);
  const noHigh = values.every(v => v > 0 && v < DDZ_VALUE['2']);
  if (n === 2 && sorted.includes('SJ') && sorted.includes('BJ')) return { type: 'rocket', main: DDZ_VALUE.BJ, length: 1, cards: sorted };
  if (n === 4 && counts.length === 1) return { type: 'bomb', main: counts[0].value, length: 1, cards: sorted };
  if (n === 1) return { type: 'single', main: values[0], length: 1, cards: sorted };
  if (n === 2 && counts.length === 1) return { type: 'pair', main: values[0], length: 1, cards: sorted };
  if (n === 3 && counts.length === 1) return { type: 'triple', main: values[0], length: 1, cards: sorted };
  if (n === 4 && countValues[0] === 3) {
    const triple = counts.find(x => x.count === 3);
    return { type: 'triple-single', main: triple.value, length: 1, cards: sorted };
  }
  if (n === 5 && countValues[0] === 3 && countValues[1] === 2) {
    const triple = counts.find(x => x.count === 3);
    return { type: 'triple-pair', main: triple.value, length: 1, cards: sorted };
  }
  if (n >= 5 && counts.length === n && noHigh && ddzIsConsecutive(values)) {
    return { type: 'straight', main: values[values.length - 1], length: n, cards: sorted };
  }
  if (n >= 6 && n % 2 === 0 && counts.every(x => x.count === 2) && noHigh && ddzIsConsecutive(values)) {
    return { type: 'pair-straight', main: values[values.length - 1], length: counts.length, cards: sorted };
  }
  if (n >= 6 && n % 3 === 0 && counts.every(x => x.count === 3) && noHigh && ddzIsConsecutive(values)) {
    return { type: 'triple-straight', main: values[values.length - 1], length: counts.length, cards: sorted };
  }
  return null;
}

function ddzComboBeats(combo, lastCombo) {
  if (!combo) return false;
  if (!lastCombo) return true;
  if (combo.type === 'rocket') return lastCombo.type !== 'rocket';
  if (lastCombo.type === 'rocket') return false;
  if (combo.type === 'bomb' && lastCombo.type !== 'bomb') return true;
  if (combo.type !== lastCombo.type) return false;
  if (combo.length !== lastCombo.length) return false;
  return combo.main > lastCombo.main;
}

function latestUnfinishedDoudizhuGame() {
  let startIndex = -1;
  let hasDdz = false;
  for (let i = chatHistory.messages.length - 1; i >= 0; i--) {
    const d = chatHistory.messages[i]?.doudizhu;
    if (!d) continue;
    hasDdz = true;
    if (d.status === 'finished') return null;
    if (d.status === 'started') {
      startIndex = i;
      break;
    }
  }
  if (!hasDdz || startIndex < 0) return null;

  const slice = chatHistory.messages.slice(startIndex);
  let latest = null;
  let latestMsg = null;
  let lastPlay = null;
  let consecutivePasses = 0;
  let currentAgentId = null;
  let currentAgentName = '';
  let nextTurnNo = 1;

  for (const msg of slice) {
    const d = msg?.doudizhu;
    const text = String(msg?.content || '');
    if (d) {
      if (d.status === 'finished') return null;
      latest = d;
      latestMsg = msg;
      if (Number(d.turnNo)) nextTurnNo = Number(d.turnNo) + 1;
      if (d.currentAgentId) {
        currentAgentId = d.currentAgentId;
        currentAgentName = d.currentAgentName || '';
        nextTurnNo = Number(d.turnNo) || nextTurnNo;
      }
      if (d.lastPlay) {
        lastPlay = d.lastPlay;
      } else if (/本轮无人压过|清空桌面/.test(text)) {
        lastPlay = null;
        consecutivePasses = 0;
      }
    }
    if (/第\s*\d+\s*手：请/.test(text)) {
      const m = text.match(/第\s*(\d+)\s*手：请\s*(.*?)（/);
      if (m) {
        nextTurnNo = Number(m[1]) || nextTurnNo;
        currentAgentName = normalizeAgentMatchText(m[2] || '');
        currentAgentId = null;
      }
    } else if (/第\s*\d+\s*手过牌/.test(text)) {
      consecutivePasses++;
      currentAgentId = null;
    } else if (/第\s*\d+\s*手出牌/.test(text)) {
      consecutivePasses = 0;
      currentAgentId = null;
    }
  }

  const rawPlayers = latest?.handCounts || latest?.players || [];
  if (!rawPlayers.length || !rawPlayers.every(p => Array.isArray(p.cards))) return null;
  const players = rawPlayers.map(p => {
    const agent = findAgent(p.agentId);
    if (!agent) return null;
    return {
      agent,
      role: p.role || (p.agentId === latest.landlordAgentId ? '地主' : '农民'),
      hand: ddzSortCards(p.cards || [])
    };
  }).filter(Boolean);
  if (players.length !== 3) return null;
  const landlordIndex = players.findIndex(p => p.agent.id === latest.landlordAgentId || p.role === '地主');
  if (landlordIndex < 0) return null;

  let currentIndex = -1;
  if (currentAgentId) currentIndex = players.findIndex(p => p.agent.id === currentAgentId);
  if (currentIndex < 0 && currentAgentName) {
    currentIndex = players.findIndex(p => normalizeAgentMatchText(p.agent.name) === currentAgentName
      || normalizeAgentMatchText(`${p.agent.icon || ''} ${p.agent.name}`).includes(currentAgentName));
  }
  if (currentIndex < 0 && lastPlay?.agentId) {
    const lastIdx = players.findIndex(p => p.agent.id === lastPlay.agentId);
    currentIndex = lastIdx >= 0 ? (lastIdx + 1) % players.length : landlordIndex;
  }
  if (currentIndex < 0) currentIndex = landlordIndex;

  let resumeLastPlay = null;
  if (lastPlay?.cards?.length) {
    const player = players.find(p => p.agent.id === lastPlay.agentId);
    const combo = analyzeDdzCombo(lastPlay.cards);
    if (player && combo) resumeLastPlay = { player, cards: ddzSortCards(lastPlay.cards), combo };
  }

  return {
    players,
    landlordIndex,
    currentIndex,
    lastPlay: resumeLastPlay,
    consecutivePasses,
    nextTurnNo: Math.max(1, Number(nextTurnNo) || 1),
    reporter: null,
    topic: latestMsg?.topic || '斗地主流程',
    maxTurns: 180,
    resumed: true
  };
}

function parseDoudizhuFlow(message, requester, config) {
  const text = String(message || '');
  if (!isDoudizhuText(text)) return null;
  const resumeGame = isDoudizhuResumeText(text) ? latestUnfinishedDoudizhuGame() : null;
  if (resumeGame) {
    return {
      requester,
      participants: resumeGame.players.map(p => p.agent),
      reporter: requester,
      maxTurns: resumeGame.maxTurns,
      topic: '斗地主流程',
      resumeState: resumeGame,
      resumed: true
    };
  }
  const named = findNamedAgentsInText(text, config, []);
  let participants = named.filter(a => a.id !== requester.id);
  if (/(你和|和你|你也|一起)/.test(text) && !participants.find(a => a.id === requester.id)) {
    participants.unshift(requester);
  }
  participants = uniqueAgents(participants).slice(0, 3);
  if (participants.length < 3) return null;
  const reporter = participants.some(a => a.id === requester.id) ? null : requester;
  return {
    requester,
    participants,
    reporter,
    maxTurns: 180,
    topic: '斗地主流程'
  };
}

function ddzHeuristicBid(hand) {
  const counts = ddzCountRanks(hand);
  let score = 0;
  if (hand.includes('BJ')) score += 4;
  if (hand.includes('SJ')) score += 3;
  score += (counts.get('2') || []).length * 1.4;
  score += (counts.get('A') || []).length;
  for (const list of counts.values()) if (list.length === 4) score += 4;
  if (score >= 10) return 3;
  if (score >= 7) return 2;
  if (score >= 4.5) return 1;
  return 0;
}

function parseDdzBid(text) {
  const json = extractJsonObject(text);
  const raw = String(text || '');
  const value = json ? (json.bid ?? json.score ?? json.call) : null;
  const n = parseInt(value, 10);
  if (n >= 0 && n <= 3) return n;
  const m = raw.match(/([0-3])\s*分/);
  if (m) return parseInt(m[1], 10);
  if (/(不叫|不抢|pass|弃权)/i.test(raw)) return 0;
  const call = raw.match(/(?:叫|抢)\s*([123])/);
  if (call) return parseInt(call[1], 10);
  return null;
}

async function askDdzBid(player, hand, config) {
  const prompt = buildChatPrompt(
    player,
    '斗地主流程',
    `[斗地主叫地主]\n你的手牌编号如下，只能根据这些牌叫分：\n${ddzCardsText(hand)}\n\n请叫地主分数 0-3。必须只返回 JSON，例如 {"bid":2,"note":"有双王"}。`,
    'roundtable',
    chatHistory.messages
  );
  const start = Date.now();
  const result = await runAgentChat({ ...player, chatTimeout: Math.min(player.chatTimeout || 120000, DDZ_AGENT_TURN_TIMEOUT_MS) }, prompt, config);
  return { result, responseTime: Date.now() - start, bid: result.ok ? parseDdzBid(result.stdout) : null };
}

function ddzNormalizeCardToken(token, hand, used) {
  let t = String(token || '').trim().toUpperCase();
  t = t.replace(/黑桃|♠|SPADE/g, 'S')
    .replace(/红桃|♥|HEART/g, 'H')
    .replace(/梅花|♣|CLUB/g, 'C')
    .replace(/方块|♦|DIAMOND/g, 'D')
    .replace(/大王|REDJOKER|JOKERB/g, 'BJ')
    .replace(/小王|BLACKJOKER|JOKERS/g, 'SJ');
  if (t === 'JOKER') t = 'SJ';
  if (hand.includes(t) && !used.has(t)) return t;
  const rankOnly = t.match(/^(10|[3-9JQKA2]|SJ|BJ)$/)?.[1];
  if (rankOnly) {
    const found = ddzSortCards(hand).find(card => ddzRank(card) === rankOnly && !used.has(card));
    if (found) return found;
  }
  return null;
}

function parseDdzPlay(text, hand) {
  const raw = String(text || '');
  const json = extractJsonObject(raw);
  if (json && (json.pass === true || json.action === 'pass')) return { pass: true, cards: [], note: json.note || '' };
  let values = [];
  if (json) {
    const cards = json.cards || json.card || json.play || json.out || [];
    values = Array.isArray(cards) ? cards : String(cards || '').split(/[,\s，、]+/);
  }
  if (!values.length) {
    values = [];
    const re = /\b(?:10|[3-9JQKA2])[SHCD]\b|\b[SB]J\b|大王|小王/ig;
    let m;
    while ((m = re.exec(raw)) !== null) values.push(m[0]);
  }
  if (!values.length && /(不出|不要|过|pass)/i.test(raw)) return { pass: true, cards: [], note: '' };
  const used = new Set();
  const cards = [];
  for (const value of values) {
    const card = ddzNormalizeCardToken(value, hand, used);
    if (card) {
      used.add(card);
      cards.push(card);
    }
  }
  return { pass: false, cards, note: json?.note || '' };
}

function ddzRemoveCards(hand, cards) {
  for (const card of cards) {
    const idx = hand.indexOf(card);
    if (idx >= 0) hand.splice(idx, 1);
  }
  hand.sort((a, b) => ddzCardValue(a) - ddzCardValue(b));
}

function ddzLowestByRank(hand, rank, count) {
  return ddzSortCards(hand).filter(card => ddzRank(card) === rank).slice(0, count);
}

function ddzFindSequence(hand, countPerRank, length, minMain) {
  const counts = [...ddzCountRanks(hand).entries()]
    .map(([rank, cards]) => ({ rank, cards, value: DDZ_VALUE[rank] || 0 }))
    .filter(x => x.value < DDZ_VALUE['2'] && x.cards.length >= countPerRank)
    .sort((a, b) => a.value - b.value);
  for (let i = 0; i <= counts.length - length; i++) {
    const seq = counts.slice(i, i + length);
    const values = seq.map(x => x.value);
    if (ddzIsConsecutive(values) && values[values.length - 1] > (minMain || 0)) {
      return seq.flatMap(x => ddzSortCards(x.cards).slice(0, countPerRank));
    }
  }
  return null;
}

function ddzFindLead(hand) {
  const all = ddzSortCards(hand);
  if (analyzeDdzCombo(all)) return all;
  return all.slice(0, 1);
}

function ddzFindBeat(hand, lastCombo) {
  if (!lastCombo) return ddzFindLead(hand);
  const counts = [...ddzCountRanks(hand).entries()]
    .map(([rank, cards]) => ({ rank, cards: ddzSortCards(cards), value: DDZ_VALUE[rank] || 0 }))
    .sort((a, b) => a.value - b.value);
  const byCount = (n) => counts.filter(x => x.cards.length >= n && x.value > lastCombo.main);
  let candidate = null;
  if (lastCombo.type === 'single') candidate = byCount(1)[0]?.cards.slice(0, 1);
  if (lastCombo.type === 'pair') candidate = byCount(2)[0]?.cards.slice(0, 2);
  if (lastCombo.type === 'triple') candidate = byCount(3)[0]?.cards.slice(0, 3);
  if (lastCombo.type === 'triple-single') {
    const triple = byCount(3)[0];
    const kicker = triple && ddzSortCards(hand).find(card => ddzRank(card) !== triple.rank);
    if (triple && kicker) candidate = [...triple.cards.slice(0, 3), kicker];
  }
  if (lastCombo.type === 'triple-pair') {
    const triple = byCount(3)[0];
    const pair = triple && counts.find(x => x.rank !== triple.rank && x.cards.length >= 2);
    if (triple && pair) candidate = [...triple.cards.slice(0, 3), ...pair.cards.slice(0, 2)];
  }
  if (lastCombo.type === 'straight') candidate = ddzFindSequence(hand, 1, lastCombo.length, lastCombo.main);
  if (lastCombo.type === 'pair-straight') candidate = ddzFindSequence(hand, 2, lastCombo.length, lastCombo.main);
  if (lastCombo.type === 'triple-straight') candidate = ddzFindSequence(hand, 3, lastCombo.length, lastCombo.main);
  if (candidate && ddzComboBeats(analyzeDdzCombo(candidate), lastCombo)) return candidate;
  const bomb = counts.find(x => x.cards.length === 4 && (lastCombo.type !== 'bomb' || x.value > lastCombo.main));
  if (bomb && lastCombo.type !== 'rocket') return bomb.cards.slice(0, 4);
  if (hand.includes('SJ') && hand.includes('BJ') && lastCombo.type !== 'rocket') return ['SJ', 'BJ'];
  return null;
}

async function askDdzPlay(player, hand, lastPlay, lastPlayer, config) {
  const lastText = lastPlay
    ? `${lastPlayer.name} 出 ${ddzCardsText(lastPlay.cards)}（${lastPlay.combo.type}），你必须压牌或 pass`
    : '你是本轮先手，可以出任意合法牌型，不能 pass';
  const prompt = buildChatPrompt(
    player,
    '斗地主流程',
    `[斗地主出牌]\n你的手牌编号如下，只能从这些编号里出牌：\n${ddzCardsText(hand)}\n\n当前局面：${lastText}\n支持牌型：单张、对子、三张、三带一、三带二、顺子、连对、飞机不带、炸弹、王炸。\n必须只返回 JSON，例如 {"cards":["7S"],"note":"顶上"}；如果不能压牌，返回 {"pass":true}。不要编造不在手里的牌。`,
    'roundtable',
    chatHistory.messages
  );
  const start = Date.now();
  const result = await runAgentChat({ ...player, chatTimeout: Math.min(player.chatTimeout || 120000, DDZ_AGENT_TURN_TIMEOUT_MS) }, prompt, config);
  return { result, responseTime: Date.now() - start, play: result.ok ? parseDdzPlay(result.stdout, hand) : null };
}

function ddzPublicState(players, landlordIndex, turnNo, lastPlay, currentPlayer = null) {
  return {
    status: 'running',
    turnNo,
    landlordAgentId: players[landlordIndex]?.agent.id || null,
    landlordName: players[landlordIndex]?.agent.name || null,
    currentAgentId: currentPlayer?.agent?.id || null,
    currentAgentName: currentPlayer?.agent?.name || null,
    handCounts: players.map(p => ({
      agentId: p.agent.id,
      agentName: p.agent.name,
      role: p.role,
      count: p.hand.length,
      cards: ddzSortCards(p.hand)
    })),
    lastPlay: lastPlay ? {
      agentId: lastPlay.player.agent.id,
      agentName: lastPlay.player.agent.name,
      cards: lastPlay.cards,
      type: lastPlay.combo.type
    } : null
  };
}

async function runDoudizhuFlow({ plan, message, mode, config }) {
  const flowType = mode && mode !== 'chat' ? mode : 'roundtable';
  const resumed = !!plan.resumeState;
  const players = resumed
    ? plan.resumeState.players.map(p => ({ agent: p.agent, hand: ddzSortCards(p.hand), role: p.role || '农民' }))
    : plan.participants.map(agent => ({ agent, hand: [], role: '农民' }));
  const deck = resumed ? [] : ddzDeck();
  if (!resumed) {
    for (let i = 0; i < 51; i++) players[i % 3].hand.push(deck[i]);
  }
  const bottomCards = resumed ? [] : deck.slice(51);
  players.forEach(p => { p.hand = ddzSortCards(p.hand); });
  const responses = [];

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `${resumed ? '♻️ 斗地主流程恢复。' : '🧭 斗地主流程启动。'}\n玩家: ${players.map(p => `${p.agent.icon || ''} ${p.agent.name}`).join('、')}\n裁判/汇报: ${plan.reporter ? `${plan.reporter.icon || ''} ${plan.reporter.name}` : '系统裁判'}\n${resumed ? `已从最近未完成牌局恢复：第 ${plan.resumeState.nextTurnNo} 手继续，手牌、地主、桌面牌已载入。` : '系统已洗牌发牌，牌局状态、叫地主、合法出牌和胜负由裁判引擎记录；所有叫分、出牌、裁定和结果都会公开打印。'}`,
    timestamp: new Date().toISOString(),
    type: flowType,
    topic: plan.topic,
    doudizhu: {
      status: 'started',
      players: players.map(p => ({
        agentId: p.agent.id,
        agentName: p.agent.name,
        role: p.role,
        count: p.hand.length,
        cards: ddzSortCards(p.hand)
      })),
      bottomCount: bottomCards.length
    }
  });

  let landlordIndex = resumed ? plan.resumeState.landlordIndex : -1;
  if (!resumed) {
    const bids = [];
    for (const player of players) {
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `🔄 请 ${player.agent.icon || ''} ${player.agent.name} 叫地主（0-3 分）...`,
        timestamp: new Date().toISOString(),
        type: flowType,
        topic: plan.topic
      });
      const asked = await askDdzBid(player.agent, player.hand, config);
      const fallbackBid = ddzHeuristicBid(player.hand);
      const bid = asked.bid === null ? fallbackBid : asked.bid;
      bids.push({ player, bid, response: asked });
      responses.push({ agentId: player.agent.id, agentName: player.agent.name, ok: asked.result.ok, stdout: asked.result.stdout, stderr: asked.result.stderr, responseTime: asked.responseTime, bid });
      addChatMessage({
        id: crypto.randomUUID(),
        from: player.agent.id,
        fromName: `${player.agent.icon || ''} ${player.agent.name}`,
        content: `叫地主：${bid} 分。${asked.bid === null ? `裁判引擎按手牌强度补判；原始回复: ${compactAgentText(asked.result.stderr || asked.result.stdout || '无响应', 220)}` : compactAgentText(asked.result.stdout, 160)}`,
        timestamp: new Date().toISOString(),
        responseTime: asked.responseTime,
        type: flowType,
        topic: plan.topic
      });
    }

    let landlordBid = bids.slice().sort((a, b) => b.bid - a.bid)[0];
    if (!landlordBid || landlordBid.bid <= 0) {
      landlordBid = bids.map(b => ({ ...b, bid: ddzHeuristicBid(b.player.hand) || 1 })).sort((a, b) => b.bid - a.bid)[0];
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `⚠️ 三家都未主动叫地主，裁判引擎按手牌强度指定 ${landlordBid.player.agent.name} 为地主。`,
        timestamp: new Date().toISOString(),
        type: flowType,
        topic: plan.topic
      });
    }
    landlordIndex = players.findIndex(p => p.agent.id === landlordBid.player.agent.id);
    players[landlordIndex].role = '地主';
    players[landlordIndex].hand = ddzSortCards([...players[landlordIndex].hand, ...bottomCards]);
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `✅ 地主确定：${players[landlordIndex].agent.icon || ''} ${players[landlordIndex].agent.name}（${landlordBid.bid} 分）。\n底牌: ${ddzCardsText(bottomCards)}\n${players.map(p => `${p.agent.name}: ${p.role}，${p.hand.length} 张`).join('；')}`,
      timestamp: new Date().toISOString(),
      type: flowType,
      topic: plan.topic,
      doudizhu: ddzPublicState(players, landlordIndex, 0, null)
    });
  } else {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `✅ 已恢复斗地主牌局。\n地主: ${players[landlordIndex].agent.name}\n${players.map(p => `${p.agent.name}: ${p.role}，${p.hand.length} 张`).join('；')}`,
      timestamp: new Date().toISOString(),
      type: flowType,
      topic: plan.topic,
      doudizhu: ddzPublicState(players, landlordIndex, plan.resumeState.nextTurnNo, plan.resumeState.lastPlay, players[plan.resumeState.currentIndex])
    });
  }

  let current = resumed ? plan.resumeState.currentIndex : landlordIndex;
  let lastPlay = resumed ? plan.resumeState.lastPlay : null;
  let consecutivePasses = resumed ? (plan.resumeState.consecutivePasses || 0) : 0;
  let winner = null;
  let finishReason = '';
  const plays = [];

  for (let turnNo = resumed ? plan.resumeState.nextTurnNo : 1; turnNo <= plan.maxTurns; turnNo++) {
    if (lastPlay && consecutivePasses >= players.length - 1) {
      const leadPlayer = lastPlay.player;
      current = players.findIndex(p => p.agent.id === leadPlayer.agent.id);
      lastPlay = null;
      consecutivePasses = 0;
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `🔄 本轮无人压过 ${leadPlayer.agent.name}，清空桌面，由 ${leadPlayer.agent.name} 继续先手。`,
        timestamp: new Date().toISOString(),
        type: flowType,
        topic: plan.topic,
        doudizhu: ddzPublicState(players, landlordIndex, turnNo, null, players[current])
      });
      continue;
    }

    const player = players[current];
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `🔄 第 ${turnNo} 手：请 ${player.agent.icon || ''} ${player.agent.name}（${player.role}，余 ${player.hand.length} 张）出牌...`,
      timestamp: new Date().toISOString(),
      type: flowType,
      topic: plan.topic,
      doudizhu: ddzPublicState(players, landlordIndex, turnNo, lastPlay, player)
    });

    const asked = await askDdzPlay(player.agent, player.hand, lastPlay, lastPlay?.player?.agent || null, config);
    let source = 'agent';
    let cards = asked.play?.pass ? [] : (asked.play?.cards || []);
    let combo = analyzeDdzCombo(cards);
    let pass = !!asked.play?.pass;
    const ownsCards = cards.every(card => player.hand.includes(card));
    if (pass && !lastPlay) pass = false;
    if (!pass && (!ownsCards || !combo || !ddzComboBeats(combo, lastPlay?.combo || null))) {
      const fallback = ddzFindBeat(player.hand, lastPlay?.combo || null);
      if (fallback) {
        cards = fallback;
        combo = analyzeDdzCombo(cards);
        pass = false;
        source = '裁判引擎补牌';
        addChatMessage({
          id: crypto.randomUUID(),
          from: 'system',
          fromName: '🔔 系统',
          content: `⚠️ ${player.agent.name} 本手未返回合法出牌，裁判引擎改为 ${ddzCardsText(cards)}。\n原始回复: ${compactAgentText(asked.result.stderr || asked.result.stdout || '无响应', 500)}`,
          timestamp: new Date().toISOString(),
          responseTime: asked.responseTime,
          type: flowType,
          topic: plan.topic
        });
      } else {
        cards = [];
        combo = null;
        pass = true;
        source = '裁判引擎判定过牌';
      }
    }

    responses.push({ agentId: player.agent.id, agentName: player.agent.name, ok: asked.result.ok, stdout: asked.result.stdout, stderr: asked.result.stderr, responseTime: asked.responseTime, cards, pass });

    if (pass) {
      consecutivePasses++;
      addChatMessage({
        id: crypto.randomUUID(),
        from: player.agent.id,
        fromName: `${player.agent.icon || ''} ${player.agent.name}`,
        content: `第 ${turnNo} 手过牌。${source === 'agent' ? compactAgentText(asked.result.stdout, 160) : source}`,
        timestamp: new Date().toISOString(),
        responseTime: asked.responseTime,
        type: flowType,
        topic: plan.topic,
        doudizhu: ddzPublicState(players, landlordIndex, turnNo, lastPlay, players[(current + 1) % players.length])
      });
      current = (current + 1) % players.length;
      continue;
    }

    ddzRemoveCards(player.hand, cards);
    lastPlay = { player, cards, combo };
    consecutivePasses = 0;
    plays.push({ turnNo, agentId: player.agent.id, agentName: player.agent.name, role: player.role, cards, type: combo.type, source });
    addChatMessage({
      id: crypto.randomUUID(),
      from: player.agent.id,
      fromName: `${player.agent.icon || ''} ${player.agent.name}`,
      content: `第 ${turnNo} 手出牌：${ddzCardsText(cards)}（${combo.type}），剩 ${player.hand.length} 张。${source === 'agent' ? compactAgentText(asked.result.stdout, 160) : source}`,
      timestamp: new Date().toISOString(),
      responseTime: asked.responseTime,
      type: flowType,
      topic: plan.topic,
      doudizhu: ddzPublicState(players, landlordIndex, turnNo, lastPlay, players[(current + 1) % players.length])
    });

    if (player.hand.length === 0) {
      winner = player;
      finishReason = winner.role === '地主'
        ? `${winner.agent.name} 作为地主先出完手牌，地主获胜。`
        : `${winner.agent.name} 作为农民先出完手牌，农民阵营获胜。`;
      break;
    }
    current = (current + 1) % players.length;
  }

  if (!winner) {
    const fewest = players.slice().sort((a, b) => a.hand.length - b.hand.length)[0];
    winner = fewest;
    finishReason = `达到 ${plan.maxTurns} 手上限，按剩余手牌最少判定：${fewest.agent.name} 所在${fewest.role}阵营获胜。`;
  }

  const winnerTeam = winner.role === '地主' ? '地主' : '农民';
  const finalText = `🏁 斗地主结束：${winnerTeam}获胜。\n${finishReason}\n地主: ${players[landlordIndex].agent.name}\n剩余手牌: ${players.map(p => `${p.agent.name} ${p.hand.length} 张`).join('；')}\n关键牌局: ${plays.slice(-8).map(p => `${p.agentName} 出 ${ddzCardsText(p.cards)}`).join(' / ') || '无'}`;
  addChatMessage({
    id: crypto.randomUUID(),
    from: plan.reporter ? plan.reporter.id : 'system',
    fromName: plan.reporter ? `${plan.reporter.icon || ''} ${plan.reporter.name}` : '🔔 系统',
    content: finalText,
    timestamp: new Date().toISOString(),
    type: flowType,
    topic: plan.topic,
    doudizhu: {
      ...ddzPublicState(players, landlordIndex, plays.length, lastPlay),
      status: 'finished',
      winnerAgentId: winner.agent.id,
      winnerName: winner.agent.name,
      winnerTeam,
      reason: finishReason,
      plays
    }
  });
  return { ok: true, doudizhu: true, responses, winner: winner.agent.name, winnerTeam };
}

async function runVisibleConsult({ requester, target, message, mode, topic, config }) {
  const currentTopic = topic || '可见Agent咨询';
  const relayId = crypto.randomUUID();
  const responses = [];
  addChatMessage({
    id: relayId,
    from: 'system',
    fromName: '🔔 系统',
    content: `🔁 可见咨询开始：${requester.icon || ''} ${requester.name} → ${target.icon || ''} ${target.name}\n所有转问、回复、汇总都会打印在消息流里。`,
    timestamp: new Date().toISOString(),
    type: mode || 'chat',
    topic: currentTopic
  });

  if (target.disabled) {
    const content = `❌ 无法咨询 ${target.name}：${target.disabledReason || '该智能体已禁用'}`;
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content, timestamp: new Date().toISOString(), type: mode || 'chat', topic: currentTopic
    });
    return { ok: true, responses: [{ agentId: target.id, agentName: target.name, ok: false, stderr: content }] };
  }

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `📨 已公开转问 ${target.icon || ''} ${target.name}，等待回复...`,
    timestamp: new Date().toISOString(),
    type: mode || 'chat',
    topic: currentTopic
  });

  const targetPrompt = buildChatPrompt(
    target,
    currentTopic,
    `[可见咨询]\n用户要求 ${requester.name} 向你咨询，平台正在公开中转，所有内容都会显示给用户。\n\n用户原话：${message}\n\n请你直接回答被咨询的问题。如果涉及你的容器/服务器/运行状态，请根据你能看到的环境和历史上下文说明；不要要求私下沟通。200字以内。`,
    mode || 'chat',
    chatHistory.messages
  );
  const targetStart = Date.now();
  const targetResult = await runAgentChat(target, targetPrompt, config);
  const targetResponseTime = Date.now() - targetStart;
  const targetContent = targetResult.ok ? targetResult.stdout : `❌ ${targetResult.stderr || targetResult.stdout || '无响应'}`;
  addChatMessage({
    id: crypto.randomUUID(),
    from: target.id,
    fromName: `${target.icon || ''} ${target.name}`,
    content: targetContent,
    timestamp: new Date().toISOString(),
    responseTime: targetResponseTime,
    type: mode || 'chat',
    topic: currentTopic
  });
  responses.push({ agentId: target.id, agentName: target.name, ...targetResult, responseTime: targetResponseTime });

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `📩 已把 ${target.name} 的公开回复交回 ${requester.name} 汇总...`,
    timestamp: new Date().toISOString(),
    type: mode || 'chat',
    topic: currentTopic
  });

  const requesterPrompt = buildChatPrompt(
    requester,
    currentTopic,
    `[可见咨询回执]\n你刚才被用户要求去咨询 ${target.name}。平台已经完成公开转问，下面是 ${target.name} 的可见回复：\n\n${compactAgentText(targetContent, 2000)}\n\n请向用户汇报结论和下一步建议。不要再说你无法直接联系 ${target.name}，因为平台已经替你完成了可见中转。200字以内。`,
    mode || 'chat',
    chatHistory.messages
  );
  const requesterStart = Date.now();
  const requesterResult = await runAgentChat(requester, requesterPrompt, config);
  const requesterResponseTime = Date.now() - requesterStart;
  addChatMessage({
    id: crypto.randomUUID(),
    from: requester.id,
    fromName: `${requester.icon || ''} ${requester.name}`,
    content: requesterResult.ok ? requesterResult.stdout : `❌ ${requesterResult.stderr || requesterResult.stdout || '无响应'}`,
    timestamp: new Date().toISOString(),
    responseTime: requesterResponseTime,
    type: mode || 'chat',
    topic: currentTopic
  });
  responses.push({ agentId: requester.id, agentName: requester.name, ...requesterResult, responseTime: requesterResponseTime });

  return { ok: true, responses, consult: { requesterId: requester.id, targetId: target.id } };
}

function agentMentionScore(message, agent) {
  const normalized = normalizeAgentMatchText(message);
  const names = agentMatchTokens(agent);
  return names.reduce((best, n) => normalized.includes(n) ? Math.max(best, n.length) : best, 0);
}

function findNamedAgentsInText(message, config, excludedIds = []) {
  const excluded = new Set(excludedIds);
  return allConfiguredAgents(config)
    .filter(a => a?.id && !excluded.has(a.id) && !a.disabled)
    .map(a => ({ agent: a, score: agentMentionScore(message, a) }))
    .filter(x => x.score > 0)
    .sort((a, b) => b.score - a.score)
    .map(x => x.agent);
}

function parseDelegatedDiscussion(message, requester, config) {
  const text = String(message || '');
  if (!/(讨论|辩论|开会|圆桌|裁判|评判|汇报|活动|接龙|发布|小红书|文案|配图|图片|整合|分配|安排|协作|任务)/.test(text)) return null;
  const named = findNamedAgentsInText(text, config, [requester.id]);
  if (!named.length) return null;
  const judgeMatch = text.match(/让\s*([a-zA-Z0-9_\-\u4e00-\u9fa5]+)\s*(?:做|当)?\s*(?:裁判|评委|总结人|汇报人)/);
  let judge = null;
  if (judgeMatch?.[1]) {
    const rawJudge = normalizeAgentMatchText(judgeMatch[1]);
    judge = named.find(a => agentMatchTokens(a)
      .some(n => n === rawJudge || n.includes(rawJudge) || rawJudge.includes(n))) || null;
  }
  const hostOnly = /(主持人|你当主持|你做主持|你来主持|你是主持|举办.*活动|结束活动|主持)/.test(text);
  const participants = [(hostOnly ? null : requester), ...named.filter(a => !judge || a.id !== judge.id)]
    .filter((a, idx, arr) => a && arr.findIndex(x => x.id === a.id) === idx);
  if (participants.length < (hostOnly ? 1 : 2)) return null;
  const roundsMatch = text.match(/(?:讨论|辩论|开会)?\s*(\d+)\s*轮/);
  const rounds = Math.max(1, Math.min(10, parseInt(roundsMatch?.[1] || '3', 10) || 3));
  const activityType = /成语接龙|接龙/.test(text) ? 'idiom-chain' : 'discussion';
  const topic = text
    .replace(/@\S+\s*/g, '')
    .replace(/让\s*[a-zA-Z0-9_\-\u4e00-\u9fa5]+\s*(?:做|当)?\s*(?:裁判|评委|总结人|汇报人)/g, '')
    .replace(/讨论\s*\d+\s*轮/g, '')
    .trim() || text.trim();
  return { participants, judge, rounds, topic, hostOnly, host: requester, activityType };
}

function isContentPublishText(message) {
  const text = String(message || '');
  const lookupLike = /(草稿包|发布包|预览图|预览|链接|截图).{0,16}(发我|给我|给我看|打开|查看|看一下|在哪|看不到|重新发|再发)|(?:发我|给我|给我看|打开|查看|看一下|重新发|再发).{0,16}(草稿包|发布包|预览图|预览|链接|截图)/.test(text);
  const produceLike = /(新建|创建|生成|制作|写|准备|策划|整合|发布到|发布小红书|发小红书|做一篇|来一篇)/.test(text);
  if (lookupLike && !produceLike) return false;
  return /(小红书|公众号|朋友圈|内容|笔记|帖子|图文|文案|配图|海报)/.test(text)
    && /(发布|发出去|发给|准备|生成|整合|排版|草稿)/.test(text);
}

function inferPublishPlatform(message) {
  const text = String(message || '');
  if (/小红书/.test(text)) return '小红书';
  if (/公众号/.test(text)) return '公众号';
  if (/朋友圈/.test(text)) return '朋友圈';
  return '通用内容';
}

function inferPublishTopic(message) {
  const text = String(message || '').replace(/\s+/g, ' ').trim();
  const m = text.match(/(?:主题|主体|题目|标题)[：:]\s*([^，,。；;\n]+)/);
  if (m?.[1]) return m[1].trim();
  return text
    .replace(/@\S+\s*/g, '')
    .replace(/让[^，,。；;]{1,24}(?:准备|负责|处理|执行|完成|写|做|画|生成|整理|整合|发布|汇报)[^，,。；;]*/g, '')
    .replace(/发布到?[^，,。；;]*/g, '')
    .trim()
    .slice(0, 160) || text.slice(0, 160);
}

function findAgentByPreferredIds(ids, fallback = null) {
  for (const id of ids) {
    const a = findAgent(id);
    if (a && !a.disabled) return a;
  }
  return fallback;
}

function pickRoleAgentFromText(text, config, roleRe, fallbackIds, requester = null) {
  const named = findNamedAgentsInText(text, config, []);
  for (const agent of named) {
    const tokens = agentMatchTokens(agent).filter(Boolean);
    const hitName = tokens.find(t => t && text.includes(t));
    if (!hitName) continue;
    const idx = text.indexOf(hitName);
    const around = text.slice(Math.max(0, idx - 24), Math.min(text.length, idx + hitName.length + 32));
    if (roleRe.test(around)) return agent;
  }
  return findAgentByPreferredIds(fallbackIds, requester || named[0] || null);
}

function parseContentPublishFlow(message, requester, config) {
  const text = String(message || '');
  if (!isContentPublishText(text)) return null;
  const copyAgent = pickRoleAgentFromText(text, config, /(文案|正文|标题|笔记|写)/, ['xiaoma', 'doma'], requester);
  const imageAgent = pickRoleAgentFromText(text, config, /(配图|图片|图|海报|封面|视觉)/, ['vbbot', 'openclaw-20032', 'xiaoliu'], requester);
  const integratorAgent = pickRoleAgentFromText(text, config, /(整合|排版|汇总|汇报|给主人)/, ['lobster', 'xiaoliu'], requester);
  const reviewerAgent = pickRoleAgentFromText(text, config, /(审核|审稿|检查|评审|把关)/, ['doma', 'xiaoma'], null);
  if (!copyAgent || !imageAgent || !integratorAgent) return null;
  return {
    platform: inferPublishPlatform(text),
    topic: inferPublishTopic(text),
    copyAgent,
    imageAgent,
    integratorAgent,
    reviewerAgent,
    coordinator: requester,
    publishMode: /自动发布|直接发布/.test(text) ? 'auto' : (/复制|手动/.test(text) ? 'manual' : 'draft'),
    feishuNotify: true
  };
}

function shouldUseFlowPlanner(message) {
  const text = String(message || '');
  if (text.length < 8) return false;
  if (shouldTriggerAutoFlowRepair(text)) return false;
  if (isGomokuResultQuery(text)) return false;
  const config = loadConfig();
  const mentionedAgents = findNamedAgentsInText(text, config, []);
  const explicitMentions = (text.match(/@[^\s，,。；;：:]+/g) || []).length;
  const multiAgentLike = mentionedAgents.length >= 2 || explicitMentions >= 2;
  const assignmentLike = /(让|请|安排|分配|交给|通知|叫|找).{0,18}(准备|负责|处理|执行|完成|写|做|画|生成|整理|整合|发布|汇报|审核|评审|测试|总结)/.test(text)
    || /(文案|配图|图片|海报|脚本|发布|整合|审核|评审|测试|汇报|总结).{0,12}(文案|配图|图片|海报|脚本|发布|整合|审核|评审|测试|汇报|总结)/.test(text);
  const actionLike = /(举办|组织|安排|发起|召集|开会|圆桌|活动|接龙|讨论|辩论|评审|投票|裁判|评委|汇报|总结|主持|比赛|对弈|下棋|五子棋|斗地主|打牌|牌局|棋盘|截图|发图|发截图|发布|小红书|文案|配图|图片|整合|分配|协作|任务|准备)/.test(text);
  const delegatedLike = /(@|参加人|参与|让|请|安排|分配|你和|和.+(?:讨论|辩论|评审|接龙|比赛|对弈|下棋|五子棋|斗地主|打牌|牌局|文案|配图|发布|整合|协作)|找.+(?:讨论|辩论|评审|接龙|比赛|对弈|下棋|五子棋|斗地主|打牌|牌局|文案|配图|发布|整合|协作))/.test(text);
  const questionOnly = /^(为什么|怎么|如何|能不能|可以吗|是否|是不是|你前面|你刚才|前面|刚才|之前|真的)/.test(text.trim())
    && !/(举办|组织|安排|发起|召集|开始|执行|运行|让.+(?:比赛|对弈|下棋|五子棋|斗地主|打牌|牌局)|截图)/.test(text);
  return ((actionLike && delegatedLike) || (multiAgentLike && assignmentLike)) && !questionOnly;
}

function detectForcedAutoRepairFlow(message) {
  const text = String(message || '');
  if (isGomokuResultQuery(text)) return null;
  if (/(五子棋|围棋|象棋|下棋|对弈|棋盘)/.test(text)) {
    return {
      retryHint: '五子棋对弈截图流程',
      reason: '需要专用棋盘状态、轮流落子规则和截图生成能力，不能用成语接龙/普通讨论引擎代替。'
    };
  }
  if (/(截图|发图|图片结果|生成图片)/.test(text) && /(最后|结果|汇报|发送|发给我)/.test(text)) {
    return {
      retryHint: '可视化结果截图流程',
      reason: '需要生成或捕获可视化结果图片，不能只用文本讨论引擎完成。'
    };
  }
  return null;
}

function startAutoRepairForFlow({ message, triggerAgent, config, retryHint, reason, responseTime = 0 }) {
  const repairAgent = pickCodexRepairAgent(config);
  const repairName = repairAgent ? `${repairAgent.icon || ''} ${repairAgent.name}` : '自动修复工程师';
  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `🧭 流程审核结论：当前流程需要补研发才能稳定执行。\n原因: ${reason || '现有引擎不完整'}\n${repairName} 已转入自动研发，完成后会提示主人重试：${retryHint}`,
    timestamp: new Date().toISOString(),
    responseTime,
    type: 'workflow',
    topic: '流程自修复'
  });
  runAutoFlowRepair({
    requirement: message,
    triggerAgent,
    config,
    retryHint
  }).catch(err => {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `❌ 流程自修复后台任务异常: ${err.message}`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: '流程自修复'
    });
  });
  return {
    ok: true,
    flowPlanner: true,
    autoRepair: true,
    responses: [{
      agentId: triggerAgent.id,
      agentName: triggerAgent.name,
      ok: true,
      stdout: `${repairName} 已在抓紧研发该流程。完成后会汇报，并提示主人重试：${retryHint}`,
      stderr: '',
      responseTime
    }]
  };
}

function pickCodexPlannerAgent(config) {
  const localAgents = config.agents?.local || [];
  return localAgents.find(a => a.id === 'codex-cli' && !a.disabled)
    || localAgents.find(a => /codex/i.test(`${a.id || ''} ${a.name || ''}`) && !a.disabled)
    || localAgents.find(a => a.id === 'claude-code' && !a.disabled)
    || localAgents.find(a => /claude/i.test(`${a.id || ''} ${a.name || ''}`) && !a.disabled)
    || localAgents.find(a => !a.disabled);
}

function extractJsonObject(text) {
  const raw = String(text || '').trim();
  const fence = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) {
    try { return JSON.parse(fence[1].trim()); } catch {}
  }
  let start = -1;
  let depth = 0;
  let inString = false;
  let quote = '';
  let escaped = false;
  for (let i = 0; i < raw.length; i++) {
    const ch = raw[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === quote) {
        inString = false;
      }
      continue;
    }
    if (ch === '"' || ch === "'") {
      inString = true;
      quote = ch;
      continue;
    }
    if (ch === '{') {
      if (depth === 0) start = i;
      depth++;
    } else if (ch === '}' && depth > 0) {
      depth--;
      if (depth === 0 && start >= 0) {
        const candidate = raw.slice(start, i + 1);
        try { return JSON.parse(candidate); } catch {}
      }
    }
  }
  return null;
}

function describeAgentsForPlanner(config) {
  return Object.entries(config.agents || {}).flatMap(([group, agents]) =>
    (agents || []).map(a => ({
      id: a.id,
      name: a.name,
      aliases: agentAliasTokens(a),
      group,
      disabled: !!a.disabled,
      description: a.description || ''
    }))
  );
}

function resolveAgentRef(ref, config, excludedIds = []) {
  const text = normalizeAgentMatchText(ref);
  if (!text) return null;
  const excluded = new Set(excludedIds);
  const candidates = allConfiguredAgents(config).filter(a => a?.id && !a.disabled && !excluded.has(a.id));
  return candidates.find(a => normalizeAgentMatchText(a.id) === text)
    || candidates.find(a => normalizeAgentMatchText(a.name) === text)
    || candidates.find(a => agentMatchTokens(a)
      .some(n => n === text || n.includes(text) || text.includes(n)))
    || null;
}

function uniqueAgents(agents) {
  return (agents || []).filter((a, idx, arr) => a && arr.findIndex(x => x.id === a.id) === idx);
}

function pickClaudeFallbackAgent(config) {
  const localAgents = config.agents?.local || [];
  return localAgents.find(a => a.id === 'claude-code' && !a.disabled)
    || localAgents.find(a => /claude/i.test(`${a.id || ''} ${a.name || ''}`) && !a.disabled)
    || null;
}

async function tryPlanFlow(plannerAgent, prompt, config, topic) {
  const plannerStart = Date.now();
  const result = await runAgentChat({ ...plannerAgent, chatTimeout: Math.min(plannerAgent.chatTimeout || 120000, 120000) }, prompt, config);
  const responseTime = Date.now() - plannerStart;
  if (!result.ok) return { result, responseTime, plan: null };
  const plan = extractJsonObject(result.stdout);
  return { result, responseTime, plan };
}

async function planFlowWithCodex({ requester, message, mode, topic, config }) {
  const plannerAgent = pickCodexPlannerAgent(config);
  if (!plannerAgent) return null;

  const agents = describeAgentsForPlanner(config);
  const buildPrompt = (agent) => `你是 AI Agent Dashboard 的流程调度审核器。请只返回一个 JSON 对象，不要 Markdown，不要解释。

用户在群聊中只选中了/艾特了发起 agent，想让它组织其他 agent 完成一个流程。你要判断该走哪个现有引擎，并给出机器可执行计划。

发起 agent:
${JSON.stringify({ id: requester.id, name: requester.name }, null, 2)}

用户原话:
${message}

当前模式: ${mode || 'chat'}
当前话题: ${topic || ''}

可用 agents（只能从这里选择，disabled=true 的不要选）:
${JSON.stringify(agents, null, 2)}

返回 JSON 字段固定如下:
{
  “supported”: true,
  “engine”: “delegated-activity”,
  “reason”: “”,
  “topic”: “”,
  “activityType”: “idiom-chain”,
  “hostOnly”: true,
  “participants”: [“xiaoma”,”doma”,”xiaoliu”],
  “judge”: “”,
  “reporter”: “lobster”,
  “rounds”: 3,
  “ordered”: true,
  “retryHint”: “”
}

规则:
1. 成语接龙/接龙/活动优先 engine=delegated-activity，activityType=idiom-chain，ordered=true。
2. 普通讨论/辩论/评审/发布小红书/写文案/配图/整合发布/内容生产协作优先 engine=delegated-discussion，activityType=discussion；参与者按用户要求的分工进入 participants，发起 agent 如果是主持/协调者则 hostOnly=true、reporter 填发起 agent。
3. 不要依赖固定业务关键词判断流程。只要用户让多个 agent 分工做事，或消息中出现多个 agent 名称并带有”准备/负责/执行/整理/发布/汇报”等任务动词，就必须视为可调度流程。
4. 用户说”你当主持人/你做主持/举办活动/结束后向我汇报”时，hostOnly=true，发起 agent 不放进 participants，reporter 填发起 agent id。
5. 用户说”你和某某讨论”时，hostOnly=false，participants 必须包含发起 agent 和被点名 agent。
6. 只有用户明确说”让 X 做裁判/评委/总结人/汇报人”时，judge/reporter 才填 X；不要把普通”向我汇报”误判成某个 agent 裁判。
7. rounds 取用户要求，默认 3，范围 1-10。
8. 五子棋/象棋/围棋/下棋/比赛/对弈/需要最终棋盘截图/需要图片结果的流程，不能用普通聊天伪造结果；如果系统没有专用游戏引擎、状态记录、SSE公开打印、大屏实时可视化和历史恢复能力，必须 supported=false，engine=auto-repair，retryHint 写对应可重试流程名。
9. 斗地主/打牌/牌局已有专用 engine=doudizhu-game；三名玩家放 participants，发起 agent 若只是”你汇报结果”则填 reporter，不放 participants。
10. 任何新游戏、图片结果、演示场景、项目流水线、需要过程可见的流程，只有同时具备后端引擎、消息元数据、大屏可视化面板、历史回放/刷新恢复，才允许 supported=true；否则必须 auto-repair。
11. 如果现有 delegated 或 doudizhu-game 引擎能跑，supported=true；如果必须新增代码才跑得通，supported=false，engine=auto-repair，retryHint 写用户应重试的流程名。
12. participants、judge、reporter 必须用 agent id。`;

  const prompt = buildPrompt(plannerAgent);

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `🧭 ${plannerAgent.icon || ''} ${plannerAgent.name} 正在前置审核流程：识别参与者、主持人、裁判/汇报人、轮次和可用引擎...`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: topic || '流程审核'
  });

  // Try primary (Codex)
  let { result, responseTime, plan } = await tryPlanFlow(plannerAgent, prompt, config, topic);

  // Fallback to Claude Code
  if (!plan) {
    const fallback = pickClaudeFallbackAgent(config);
    if (fallback && fallback.id !== plannerAgent.id) {
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `⚠️ ${plannerAgent.name} 流程审核未成功（${result && !result.ok ? '无响应或超时' : '返回不可解析'}），切换到 ${fallback.icon || ''} ${fallback.name} 重试...`,
        timestamp: new Date().toISOString(),
        responseTime,
        type: 'workflow',
        topic: topic || '流程审核'
      });
      const retry = await tryPlanFlow(fallback, prompt, config, topic);
      result = retry.result; responseTime = (responseTime || 0) + (retry.responseTime || 0); plan = retry.plan;
      if (plan) {
        addChatMessage({
          id: crypto.randomUUID(),
          from: 'system',
          fromName: '🔔 系统',
          content: `✅ ${fallback.icon || ''} ${fallback.name} 接管流程审核成功。`,
          timestamp: new Date().toISOString(),
          type: 'workflow',
          topic: topic || '流程审核'
        });
      }
    }
  }

  if (!plan) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `⚠️ 流程审核失败（Codex 和 Claude Code 均未返回可解析计划），降级使用内置规则。\n${compactAgentText((result && result.stdout) || (result && result.stderr) || '无响应', 1200)}`,
      timestamp: new Date().toISOString(),
      responseTime,
      type: 'workflow',
      topic: topic || '流程审核'
    });
    return null;
  }
  return { plan, plannerAgent, responseTime };
}

function buildDelegatedPlanFromCodex(plan, requester, config, originalMessage) {
  if (!plan || plan.supported === false) return null;
  if (!/delegated-(activity|discussion)|roundtable|debate/i.test(String(plan.engine || ''))) return null;
  const hostOnly = !!plan.hostOnly;
  let judge = resolveAgentRef(plan.judge, config, [requester.id]);
  const reporter = resolveAgentRef(plan.reporter, config, []);
  if (!judge && reporter && reporter.id !== requester.id) judge = reporter;

  const requestedParticipants = Array.isArray(plan.participants) ? plan.participants : [];
  let participants = uniqueAgents(requestedParticipants
    .map(ref => resolveAgentRef(ref, config, []))
    .filter(a => a && (!judge || a.id !== judge.id)));

  if (!hostOnly && !participants.find(a => a.id === requester.id)) {
    participants.unshift(requester);
  }
  if (hostOnly) {
    participants = participants.filter(a => a.id !== requester.id);
  }

  const minimum = hostOnly ? 1 : 2;
  if (participants.length < minimum) return null;
  const rounds = Math.max(1, Math.min(10, parseInt(plan.rounds || '3', 10) || 3));
  const activityType = plan.activityType === 'idiom-chain' || /成语接龙|接龙/.test(originalMessage)
    ? 'idiom-chain'
    : 'discussion';
  const topic = String(plan.topic || '').trim()
    || String(originalMessage || '').replace(/@\S+\s*/g, '').trim()
    || '委托讨论';
  return { participants, judge, rounds, topic, hostOnly, host: requester, activityType };
}

function summarizeCodexFlowPlan(plan, delegatedPlan, requester) {
  const engine = plan?.engine || 'delegated';
  const participants = delegatedPlan?.participants?.map(a => a.name).join('、') || '未识别';
  const reporter = delegatedPlan?.judge?.name || (delegatedPlan?.hostOnly ? requester.name : (plan?.reporter || '未指定'));
  return `✅ Codex 流程审核完成：${engine}\n主持人: ${delegatedPlan?.hostOnly ? requester.name : '无独立主持'}\n参与者: ${participants}\n裁判/汇报: ${reporter}\n轮次: ${delegatedPlan?.rounds || plan?.rounds || 3}\n执行方式: ${delegatedPlan?.activityType === 'idiom-chain' ? '按顺序逐个接龙' : '按轮次顺序发言'}`;
}

function shouldTriggerAutoFlowRepair(message) {
  const text = String(message || '');
  return /(流程|工作流|会议|讨论|协作|调度|转问|咨询|流水线)/.test(text)
    && /(走不下去|走不通|卡住|无法继续|不能继续|失败|不支持|实现|研发|补上|修复|优化)/.test(text)
    && /(codex|Codex|CODEX|自动|自己迭代|系统)/.test(text);
}

function inferRetryHint(message) {
  const text = String(message || '');
  if (/斗地主|打牌|牌局/.test(text)) return '斗地主流程';
  if (/讨论|辩论|裁判|汇报/.test(text)) return '委托讨论/辩论流程';
  if (/咨询|转问|联系/.test(text)) return 'Agent可见咨询流程';
  if (/代码审查|审查流水线/.test(text)) return '代码审查流水线';
  if (/项目改造|改造流水线/.test(text)) return '项目改造流水线';
  if (/会议|圆桌/.test(text)) return '圆桌会议流程';
  return '刚才卡住的流程';
}

function pickCodexRepairAgent(config) {
  const localAgents = config.agents?.local || [];
  return localAgents.find(a => a.id === 'codex-cli' && !a.disabled)
    || localAgents.find(a => /codex/i.test(a.id || '') && !a.disabled)
    || localAgents.find(a => a.id === 'claude-code' && !a.disabled)
    || localAgents.find(a => /claude/i.test(`${a.id || ''} ${a.name || ''}`) && !a.disabled)
    || localAgents.find(a => !a.disabled);
}

function pickWorkflowDesignAgent(config, preferred) {
  const localAgents = config.agents?.local || [];
  const key = String(preferred || '').trim();
  if (key) {
    const normalized = normalizeAgentMatchText(key);
    const exact = localAgents.find(a => !a.disabled && (
      a.id === key || a.name === key || `${a.icon || ''} ${a.name}`.trim() === key
    ));
    if (exact) return exact;
    const fuzzy = localAgents.find(a => !a.disabled && normalizeAgentMatchText(`${a.id || ''} ${a.name || ''}`).includes(normalized));
    if (fuzzy) return fuzzy;
  }
  return pickCodexRepairAgent(config);
}

function pickAutoRepairReporterAgent(config) {
  return allConfiguredAgents(config).find(a => a.id === 'xiaoma' && !a.disabled)
    || allConfiguredAgents(config).find(a => /小马|xiaoma/i.test(`${a.name || ''} ${a.id || ''}`) && !a.disabled)
    || null;
}

async function sendAutoRepairFeishuReport({ requirement, retryHint, oldVersion, newVersion, backupId, repairAgent, repairOutput, config }) {
  const webhook = config.notifications?.feishuWebhook;
  const reporter = pickAutoRepairReporterAgent(config);
  const fallback = `${repairAgent?.name || '自动修复工程师'} 已完成自动流程研发。\n\n流程: ${retryHint}\n版本: ${oldVersion} → ${newVersion}\n备份: ${backupId}\n执行者: ${repairAgent?.name || '自动修复工程师'}\n\n原始需求:\n${compactAgentText(requirement, 600)}\n\n请主人刷新页面后重试：${retryHint}`;

  let report = fallback;
  let reporterNote = reporter ? `${reporter.icon || ''} ${reporter.name}` : '系统兜底';

  if (reporter) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `📨 自修复已成功，正在请 ${reporter.icon || ''} ${reporter.name} 生成飞书汇报...`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: '流程自修复'
    });
    const prompt = buildChatPrompt(
      reporter,
      '流程自修复',
      `[飞书通知汇报]\n${repairAgent?.name || '自动修复工程师'} 已完成一个不可继续流程的自动研发。请你以”小马”的口吻给主人写一段飞书通知，要求清楚、简短、可执行。\n\n原始需求：${requirement}\n重试流程：${retryHint}\n版本：${oldVersion} → ${newVersion}\n备份：${backupId}\n执行者：${repairAgent?.name || '自动修复工程师'}\n修复摘要：\n${compactAgentText(repairOutput, 1800)}\n\n请包含：已完成、让主人重试什么、备份在哪里、如果未生效刷新/重启 dashboard。300字以内。`,
      'workflow',
      chatHistory.messages
    );
    const start = Date.now();
    const result = await runAgentChat({ ...reporter, chatTimeout: Math.min(reporter.chatTimeout || 120000, 90000) }, prompt, config);
    const responseTime = Date.now() - start;
    if (result.ok && result.stdout?.trim()) {
      report = result.stdout.trim();
      addChatMessage({
        id: crypto.randomUUID(),
        from: reporter.id,
        fromName: `${reporter.icon || ''} ${reporter.name} (飞书汇报)`,
        content: report,
        timestamp: new Date().toISOString(),
        responseTime,
        type: 'workflow',
        topic: '流程自修复'
      });
    } else {
      reporterNote = `系统兜底（${reporter.name} 未能生成汇报）`;
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `⚠️ ${reporter.name} 飞书汇报生成失败，改用系统兜底通知。\n${compactAgentText(result.stderr || result.stdout || '无响应', 900)}`,
        timestamp: new Date().toISOString(),
        responseTime,
        type: 'workflow',
        topic: '流程自修复'
      });
    }
  }

  if (!webhook) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `⚠️ 飞书 webhook 未配置，无法发送给主人。\n已生成汇报人: ${reporterNote}\n可在 config.json 的 notifications.feishuWebhook 配置后自动发送。`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: '流程自修复'
    });
    return;
  }

  notifyFeishu(`✅ ${retryHint} 已研发完成`, `汇报人: ${reporterNote}\n\n${report}`);
  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `📨 已通过飞书通知主人。\n汇报人: ${reporterNote}\n重试: ${retryHint}`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: '流程自修复'
  });
}

async function runAutoFlowRepair({ requirement, triggerAgent, config, retryHint }) {
  const repairAgent = pickCodexRepairAgent(config);
  if (!repairAgent) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `❌ 当前流程无法继续，但没有可用的本机 Codex/Claude Code 执行 agent，无法自动研发修复。\n请启用本机 Codex CLI 或 Claude Code CLI 后重试。`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: '流程自修复'
    });
    return;
  }

  const ver = loadVersion();
  const oldVersion = ver.version;
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const backupId = `autorepair_${oldVersion}_${ts}`;
  const backupDir = path.join(BACKUPS_DIR, backupId);
  const projectDir = __dirname;
  const progressId = backupId;
  fs.mkdirSync(backupDir);
  let copied = 0;
  for (const f of fs.readdirSync(projectDir)) {
    if (BACKUP_EXCLUDE.includes(f)) continue;
    const src = path.join(projectDir, f);
    const dst = path.join(backupDir, f);
    try {
      const st = fs.statSync(src);
      if (st.isDirectory()) copyDirSync(src, dst);
      else fs.copyFileSync(src, dst);
      copied++;
    } catch(e) { console.error(`[AUTO-REPAIR] backup skip ${f}:`, e.message); }
  }
  fs.writeFileSync(path.join(backupDir, 'manifest.json'), JSON.stringify({
    version: oldVersion, timestamp: new Date().toISOString(), requirement, backupId, files: copied
  }, null, 2), 'utf-8');
  upsertDevProgress({
    id: progressId,
    kind: 'auto-repair',
    status: 'running',
    title: retryHint || '自动流程研发',
    requirement: compactAgentText(requirement, 1200),
    triggerAgent: triggerAgent ? triggerAgent.name : '',
    executor: repairAgent.name,
    backup: backupId,
    oldVersion,
    startedAt: new Date().toISOString()
  });

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `🛠️ 当前流程无法继续，正在自动研发该流程。\n触发 agent: ${triggerAgent ? `${triggerAgent.icon || ''} ${triggerAgent.name}` : '未指定'}\n执行者: ${repairAgent.icon || ''} ${repairAgent.name}\n备份: backups/${backupId}\n完成后会在这里汇报，并提示主人重试：${retryHint}`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: '流程自修复'
  });

  const projectFiles = fs.readdirSync(projectDir).filter(f => {
    if (BACKUP_EXCLUDE.includes(f)) return false;
    try { return fs.statSync(path.join(projectDir, f)).isFile(); } catch { return false; }
  }).join(', ');

  const recent = chatHistory.messages.slice(-12).map(m =>
    `[${m.fromName || m.from}] ${compactAgentText(m.content, 600)}`
  ).join('\n');

  const buildRepairPrompt = `你是 AI Agent Dashboard 的自动流程修复工程师。

用户在群聊中发现流程走不下去，要求系统自动把流程补通。你需要直接修改本项目文件。

用户原始要求：
${requirement}

建议完成后让主人重试：
${retryHint}

最近聊天上下文：
${recent}

项目位置：${projectDir}
主要文件：${projectFiles}

实现要求：
1. 先阅读 server.js、public/index.html、config.json 的相关部分，定位流程卡住原因。
2. 直接修改项目文件，让该类流程后续可以从群聊/大屏中走通。
3. 所有自动调度/转问/修复进度必须通过 addChatMessage/SSE 打印，用户可见。
4. 修改要小而完整，不要破坏现有大屏、群聊、历史、工作流、系统升级。
5. 必须同步完成”大屏可视化契约”：后端每个关键步骤写入结构化元数据；前端 public/index.html 有对应实时面板/渲染函数；SSE 新消息能即时更新；刷新页面能从 /api/chat/history 恢复最近状态；长流程要显示等待中、进行中、完成/失败，并提供”继续/恢复”按钮或等价入口，不能让用户再次触发时误开新流程。
6. 游戏/牌局/棋局/图片结果类流程，不能只输出文字结果；必须可视化核心状态，例如棋盘、牌桌、玩家、手牌/剩余数、当前回合、最后一步和最终结果。确实不适合可视化的流程，也要在研发汇报里明确说明原因。
7. 研发完成消息必须明确写出：后端引擎是否接入、消息流是否可见、大屏可视化是否接入、刷新后是否可恢复、主人应如何重试。
8. 完成后运行 node --check server.js，并检查 public/index.html 脚本可解析。
9. 最后用中文汇报：修了什么、如何重试、验证结果、剩余风险。

注意：
- 已备份到 backups/${backupId}。
- 不要删除 backups、node_modules、chat_log.json。`;

  let effectiveAgent = repairAgent;
  let start = Date.now();
  let result = await runAgentChat(repairAgent, buildRepairPrompt, config);
  let responseTime = Date.now() - start;

  // Fallback to Claude Code if primary (Codex) fails
  if (!result.ok) {
    const fallback = pickClaudeFallbackAgent(config);
    if (fallback && fallback.id !== repairAgent.id) {
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `⚠️ ${repairAgent.name} 自动研发失败（${result.stderr || result.stdout || '无响应或超时'}），切换到 ${fallback.icon || ''} ${fallback.name} 继续...`,
        timestamp: new Date().toISOString(),
        type: 'workflow',
        topic: '流程自修复'
      });
      effectiveAgent = fallback;
      start = Date.now();
      result = await runAgentChat(fallback, buildRepairPrompt, config);
      responseTime += Date.now() - start;
    }
  }
  addChatMessage({
    id: crypto.randomUUID(),
    from: effectiveAgent.id,
    fromName: `${effectiveAgent.icon || ''} ${effectiveAgent.name} (流程自修复)`,
    content: result.ok ? compactAgentText(result.stdout, 5000) : `❌ ${result.stderr || result.stdout || '无响应'}`,
    timestamp: new Date().toISOString(),
    responseTime,
    type: 'workflow',
    topic: '流程自修复'
  });

  if (result.ok) {
    const parts = oldVersion.split('.').map(Number);
    parts[2] = (parts[2] || 0) + 1;
    const newVersion = parts.join('.');
    ver.version = newVersion;
    ver.history.unshift({
      version: newVersion,
      previous: oldVersion,
      task: `流程自修复: ${requirement}`,
      agent: effectiveAgent.name,
      backup: backupId,
      timestamp: new Date().toISOString()
    });
    saveVersion(ver);
    upsertDevProgress({
      id: progressId,
      status: 'completed',
      title: retryHint || '自动流程研发',
      requirement: compactAgentText(requirement, 1200),
      executor: effectiveAgent.name,
      backup: backupId,
      oldVersion,
      newVersion,
      completedAt: new Date().toISOString(),
      summary: compactAgentText(result.stdout, 1800)
    });
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `✅ ${effectiveAgent.name} 已完成流程自修复: ${oldVersion} → ${newVersion}\n备份: ${backupId}\n验收要求: 后端引擎、消息流公开打印、大屏可视化、刷新恢复都必须在研发汇报中说明。\n请主人重试：${retryHint}\n如果本次修复改到了 server.js，请刷新页面；如未生效，请重启 dashboard。`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: '流程自修复'
    });
    await sendAutoRepairFeishuReport({
      requirement,
      retryHint,
      oldVersion,
      newVersion,
      backupId,
      repairAgent: effectiveAgent,
      repairOutput: result.stdout,
      config
    });
  } else {
    upsertDevProgress({
      id: progressId,
      status: 'failed',
      title: retryHint || '自动流程研发',
      requirement: compactAgentText(requirement, 1200),
      executor: effectiveAgent.name,
      backup: backupId,
      oldVersion,
      failedAt: new Date().toISOString(),
      error: compactAgentText(result.stderr || result.stdout || '无响应', 1800)
    });
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `❌ 流程自修复失败（${effectiveAgent.name} 也无法完成），已保留备份: ${backupId}\n请主人查看上方错误，或改用工作流设计师手动指定需求。`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: '流程自修复'
    });
  }
}

async function runDelegatedDiscussion({ requester, plan, message, mode, config }) {
  const chatMode = mode && mode !== 'chat' ? mode : 'roundtable';
  const label = chatMode === 'debate' ? '辩论' : '委托讨论';
  const responses = [];
  const hostName = plan.hostOnly ? requester.name : '未指定';
  const orderedNames = plan.participants.map(a => a.name).join(' → ');
  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `🧭 委托${plan.activityType === 'idiom-chain' ? '活动' : '讨论'}启动：${requester.name} 已公开邀请 ${plan.participants.map(a => a.name).join('、')} 参与。\n主持人: ${hostName}\n顺序: ${orderedNames}\n裁判/汇报: ${plan.judge ? plan.judge.name : (plan.hostOnly ? requester.name : '未指定')} | ${plan.rounds} 轮\n所有发言都会按顺序打印在消息流里。`,
    timestamp: new Date().toISOString(),
    type: chatMode,
    topic: plan.topic
  });
  if (!chatHistory.topics.find(t => t.text === plan.topic)) {
    chatHistory.topics.push({ text: plan.topic, setAt: new Date().toISOString() });
  }

  const turns = [];
  if (plan.activityType === 'idiom-chain') {
    for (let i = 0; i < plan.rounds; i++) {
      turns.push({ round: i + 1, agent: plan.participants[i % plan.participants.length], turnInRound: 1 });
    }
  } else {
    for (let round = 1; round <= plan.rounds; round++) {
      for (const agent of plan.participants) turns.push({ round, agent, turnInRound: 1 });
    }
  }

  let lastContent = '';
  for (const turn of turns) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `🔄 ${plan.activityType === 'idiom-chain' ? '成语接龙' : label}第 ${turn.round}/${plan.rounds} 轮：请 ${turn.agent.icon || ''} ${turn.agent.name} 发言...`,
      timestamp: new Date().toISOString(),
      type: chatMode,
      topic: plan.topic
    });

    const activityRule = plan.activityType === 'idiom-chain'
      ? `这是成语接龙活动。你是当前接龙人「${turn.agent.name}」，不是主持人。主持人是「${requester.name}」。只输出你本轮接的一个成语和简短说明；必须承接上一条成语的最后一个字/同音字。不要邀请别人，不要总结，不要自己开新场。\n上一条可见发言：${compactAgentText(lastContent, 1000)}`
      : `你是当前发言人「${turn.agent.name}」。请按顺序发言，不要替其他 agent 发言，不要主持全局。`;
    const prompt = buildChatPrompt(
      turn.agent,
      plan.topic,
      `[委托${plan.activityType === 'idiom-chain' ? '活动' : '讨论'}]\n用户原话：${message}\n发起者/主持人：${requester.name}\n参与顺序：${orderedNames}\n${plan.judge ? `裁判/汇报人：${plan.judge.name}\n` : ''}${activityRule}\n\n请进行第 ${turn.round}/${plan.rounds} 轮发言。200字以内。`,
      chatMode,
      chatHistory.messages
    );
    const startTime = Date.now();
    const result = await runAgentChat(turn.agent, prompt, config);
    const responseTime = Date.now() - startTime;
    lastContent = result.ok ? result.stdout : `❌ ${result.stderr || result.stdout || '无响应'}`;
    const msg = {
      id: crypto.randomUUID(),
      from: turn.agent.id,
      fromName: `${turn.agent.icon || ''} ${turn.agent.name}`,
      content: lastContent,
      timestamp: new Date().toISOString(),
      responseTime,
      type: chatMode,
      topic: plan.topic
    };
    addChatMessage(msg);
    responses.push({ agentId: turn.agent.id, agentName: turn.agent.name, ...result, responseTime });
  }

  const reporter = plan.judge || (plan.hostOnly ? requester : null);
  if (reporter) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `📝 请 ${reporter.icon || ''} ${reporter.name} ${plan.judge ? '裁判并' : '结束活动并'}向用户汇报...`,
      timestamp: new Date().toISOString(),
      type: chatMode,
      topic: plan.topic
    });
    const judgePrompt = buildChatPrompt(
      reporter,
      plan.topic,
      `[委托${plan.activityType === 'idiom-chain' ? '活动' : '讨论'}最终汇报]\n用户原话：${message}\n请基于刚才按顺序完成的 ${plan.rounds} 轮公开${plan.activityType === 'idiom-chain' ? '活动' : '讨论'}，向用户汇报详情。${plan.judge ? '如果你是裁判，请给出裁判结论。' : '如果你是主持人，只做主持汇报，不再参与活动。'}300字以内。`,
      chatMode,
      chatHistory.messages
    );
    const startTime = Date.now();
    const result = await runAgentChat(reporter, judgePrompt, config);
    const responseTime = Date.now() - startTime;
    addChatMessage({
      id: crypto.randomUUID(),
      from: reporter.id,
      fromName: `${reporter.icon || ''} ${reporter.name}`,
      content: result.ok ? result.stdout : `❌ ${result.stderr || result.stdout || '无响应'}`,
      timestamp: new Date().toISOString(),
      responseTime,
      type: chatMode,
      topic: plan.topic
    });
    responses.push({ agentId: reporter.id, agentName: reporter.name, ...result, responseTime });
  }

  return { ok: true, responses, delegatedDiscussion: true };
}

// Check status of one local agent
function checkLocalAgent(agent) {
  try {
    const exe = agent.executable;
    const ver = execSync(`where ${exe} 2>nul & ${exe} --version 2>nul`, {
      timeout: 5000, windowsHide: true, shell: 'cmd.exe'
    });
    const lines = ver.toString().trim().split('\n').filter(Boolean);
    const version = lines[lines.length - 1] || 'installed';
    let processRunning = false;
    try {
      const tasklist = execSync(`tasklist /FI "IMAGENAME eq ${exe}.exe" 2>nul`, {
        timeout: 3000, windowsHide: true, shell: 'cmd.exe'
      });
      processRunning = tasklist.toString().includes(`${exe}.exe`);
    } catch { /* ignore */ }
    return { status: 'available', version, processRunning };
  } catch {
    return { status: 'not_found', version: null, processRunning: false };
  }
}

function isSuccessfulAgentMessage(m, agentId) {
  if (!m || m.from !== agentId) return false;
  const text = String(m.content || '').trim();
  if (!text || text.startsWith('❌')) return false;
  if (/等待可用连接超时|SSH 命令执行超时|Not logged in|Module not found|Reading prompt from stdin/i.test(text)) return false;
  return true;
}

function recentSuccessStatus(agent, maxAgeMs = 6 * 60 * 60 * 1000) {
  const now = Date.now();
  for (let i = chatHistory.messages.length - 1; i >= 0; i--) {
    const m = chatHistory.messages[i];
    if (!isSuccessfulAgentMessage(m, agent.id)) continue;
    const ts = Date.parse(m.timestamp || '');
    if (!Number.isFinite(ts) || now - ts > maxAgeMs) return null;
    return {
      status: 'available',
      version: '最近回复成功',
      info: `最近回复: ${new Date(ts).toLocaleString('zh-CN')}`,
      lastSuccessAt: m.timestamp
    };
  }
  return null;
}

function dc(hostConfig) { return hostConfig.dockerPath || 'docker'; }

function shQuote(value) {
  return `'${String(value || '').replace(/'/g, `'\\''`)}'`;
}

function shIdent(value, fallback = '') {
  const s = String(value || '').trim();
  return /^[A-Za-z0-9_./:-]+$/.test(s) ? s : fallback;
}

// Check status of a remote agent (via SSH)
async function checkRemoteAgent(agent, hostConfig) {
  try {
    if (hostConfig.type === 'docker') {
      const dockerStatus = await checkDockerAgent(agent, hostConfig);
      if (dockerStatus.status === 'stopped' || dockerStatus.status === 'not_found' || dockerStatus.status === 'error') {
        return recentSuccessStatus(agent) || dockerStatus;
      }
      return dockerStatus;
    }
    const exe = shIdent(agent.executable || agent.chatCmd?.split(' ')[0], 'bash');
    const exists = await sshExec(hostConfig, `command -v ${exe} >/dev/null 2>&1`, 5000);
    if (!exists.ok) {
      const recent = recentSuccessStatus(agent);
      if (recent) return recent;
      return { status: 'checking', info: `${exe} 未确认；可尝试发送消息验证` };
    }
    return { status: 'available', version: `${exe} installed` };
  } catch (e) {
    const recent = recentSuccessStatus(agent);
    if (recent) return recent;
    return { status: 'checking', info: e.message || '检测失败，可尝试发送消息验证' };
  }
}

async function checkDockerAgent(agent, hostConfig) {
  const cn = shIdent(agent.containerName);
  const d = shIdent(dc(hostConfig), 'docker');
  if (!cn) return { status: 'not_found', info: '容器名无效', containerName: agent.containerName };
  const running = await sshExec(hostConfig, `${d} ps --filter ${shQuote('name=' + cn)} --format '{{.Status}}'`, 10000);
  if (running.ok && running.stdout.trim()) {
    return { status: 'running', info: running.stdout.trim(), containerName: cn };
  }
  const all = await sshExec(hostConfig, `${d} ps -a --filter ${shQuote('name=' + cn)} --format '{{.Status}}'`, 10000);
  if (all.ok && all.stdout.trim()) {
    return { status: 'stopped', info: all.stdout.trim(), containerName: cn };
  }
  return { status: 'not_found', info: '容器未找到', containerName: cn };
}

// ── Chat Engine ─────────────────────────────────────────────────

function getAllAgents(config) {
  const all = [];
  for (const agents of Object.values(config.agents)) {
    all.push(...agents);
  }
  return all;
}

function safe(s) {
  // Sanitize text for injection into agent prompts — strip control chars, limit length
  return (s || '').replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '').slice(0, 200);
}

const PROJECT_SCAN_EXCLUDE = new Set(['node_modules', '.git', '__pycache__', '.venv', 'venv', 'dist', 'build', 'backups']);

function extractLocalProjectPath(text) {
  const m = String(text || '').match(/[A-Za-z]:\\[^\r\n"'<>|?*]+/);
  if (!m) return null;
  let candidate = m[0].trim().replace(/[，。；;、）)\]}]+$/g, '');
  while (candidate.length > 3 && !fs.existsSync(candidate)) {
    candidate = candidate.slice(0, -1).trim().replace(/[，。；;、）)\]}]+$/g, '');
  }
  if (!fs.existsSync(candidate)) return null;
  try { return fs.realpathSync(candidate); } catch { return candidate; }
}

function listProjectFiles(root, maxFiles = 160) {
  const out = [];
  function walk(dir, depth) {
    if (out.length >= maxFiles || depth > 5) return;
    let entries = [];
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    entries.sort((a, b) => Number(b.isDirectory()) - Number(a.isDirectory()) || a.name.localeCompare(b.name));
    for (const ent of entries) {
      if (out.length >= maxFiles) break;
      if (PROJECT_SCAN_EXCLUDE.has(ent.name)) continue;
      const full = path.join(dir, ent.name);
      const rel = path.relative(root, full).replace(/\\/g, '/');
      if (ent.isDirectory()) {
        out.push(rel + '/');
        walk(full, depth + 1);
      } else {
        let size = 0;
        try { size = fs.statSync(full).size; } catch {}
        out.push(`${rel} (${size} bytes)`);
      }
    }
  }
  walk(root, 0);
  return out;
}

function publishLocalProjectForAgents(topic, config) {
  const projectPath = extractLocalProjectPath(topic);
  if (!projectPath) return null;
  const stat = fs.statSync(projectPath);
  const root = stat.isDirectory() ? projectPath : path.dirname(projectPath);
  const base = path.basename(root).replace(/[^a-zA-Z0-9._-]+/g, '_') || 'project';
  const stamp = new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14);
  const zipName = `${base}_${stamp}.zip`;
  const zipPath = path.join(SHARED_OUT, zipName);
  const manifest = listProjectFiles(root);
  execFileSync('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-Command',
    'Compress-Archive -LiteralPath $env:DASH_PROJECT_SRC -DestinationPath $env:DASH_PROJECT_ZIP -Force'
  ], {
    timeout: 120000,
    windowsHide: true,
    env: { ...process.env, DASH_PROJECT_SRC: root, DASH_PROJECT_ZIP: zipPath }
  });
  const port = config.server.port || 3456;
  const url = `${publicBaseUrl(port)}/files/${encodeURIComponent(zipName)}`;
  return { path: root, zipPath, zipName, url, manifest };
}

// ── Collective Memory ────────────────────────────────────────────
const MEMORY_PATH = path.join(__dirname, 'MEMORY.md');

function loadMemoryContext(maxEntries = 3) {
  try {
    const raw = fs.readFileSync(MEMORY_PATH, 'utf-8');
    // Extract ## sections (each is a memory entry)
    const sections = raw.split(/\n## /).slice(1); // skip the "# Memory" header
    const recent = sections.slice(-maxEntries);
    if (recent.length === 0) return '';
    // Build compact context
    const lines = recent.map(s => {
      const hdrEnd = s.indexOf('\n');
      const title = hdrEnd > 0 ? s.slice(0, hdrEnd).trim() : s.slice(0, 80).trim();
      // Grab first 2-3 substantive lines after the header
      const body = s.slice(hdrEnd > 0 ? hdrEnd + 1 : 0).trim().split('\n').filter(l => l.trim()).slice(0, 3).join(' ');
      return `[${title}]: ${body.slice(0, 300)}`;
    });
    return `(集体记忆: ${lines.join(' | ')}) `;
  } catch {
    return '';
  }
}

function appendToMemory(topic, summaryContent) {
  const date = new Date().toISOString().slice(0, 10);
  const entry = `\n## ${date}: ${topic}\n\n${summaryContent}\n`;
  try {
    fs.appendFileSync(MEMORY_PATH, entry, 'utf-8');
    console.error(`[MEMORY] Saved: ${topic}`);
  } catch (e) {
    console.error(`[MEMORY] Failed to save: ${e.message}`);
  }
}

// ── Agent Lessons ───────────────────────────────────────────────
function loadLessons() {
  try {
    const data = JSON.parse(fs.readFileSync(LESSONS_PATH, 'utf-8'));
    if (!Array.isArray(data.lessons)) data.lessons = [];
    return data;
  } catch {
    return { lessons: [] };
  }
}

function saveLessons(data) {
  const lessons = Array.isArray(data.lessons) ? data.lessons : [];
  const trimmed = lessons.slice(-1000);
  fs.writeFileSync(LESSONS_PATH, JSON.stringify({ lessons: trimmed }, null, 2), 'utf-8');
}

function clipLessonField(value, max = 900) {
  return String(value || '')
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
    .trim()
    .slice(0, max);
}

function parseLessonText(text) {
  const raw = clipLessonField(text, 1600);
  const pick = (patterns) => {
    for (const re of patterns) {
      const m = raw.match(re);
      if (m?.[1]) return clipLessonField(m[1], 700);
    }
    return '';
  };
  return {
    raw,
    cause: pick([/原因链[:：]\s*([\s\S]*?)(?:\n\s*(?:教训|下次动作|行动)[:：]|$)/i, /原因[:：]\s*([\s\S]*?)(?:\n\s*(?:教训|下次动作|行动)[:：]|$)/i]),
    lesson: pick([/教训[:：]\s*([\s\S]*?)(?:\n\s*(?:下次动作|行动|原因链|原因)[:：]|$)/i, /结论[:：]\s*([\s\S]*?)(?:\n\s*(?:下次动作|行动|原因链|原因)[:：]|$)/i]),
    nextAction: pick([/下次动作[:：]\s*([\s\S]*?)(?:\n\s*(?:原因链|原因|教训)[:：]|$)/i, /行动[:：]\s*([\s\S]*?)(?:\n\s*(?:原因链|原因|教训)[:：]|$)/i])
  };
}

function addAgentLesson(input, source = 'manual') {
  const agentId = clipLessonField(input.agentId, 120);
  if (!agentId) throw new Error('agentId is required');
  const agent = findAgent(agentId);
  const parsed = parseLessonText(input.raw || input.content || input.lesson || '');
  const lesson = {
    id: crypto.randomUUID(),
    agentId,
    agentName: clipLessonField(input.agentName || agent?.name || agentId, 120),
    topic: clipLessonField(input.topic, 200),
    source,
    date: new Date().toISOString().slice(0, 10),
    timestamp: new Date().toISOString(),
    cause: clipLessonField(input.cause || parsed.cause, 700),
    lesson: clipLessonField(input.lesson || parsed.lesson || parsed.raw, 900),
    nextAction: clipLessonField(input.nextAction || parsed.nextAction, 700),
    raw: clipLessonField(input.raw || input.content || parsed.raw, 1600)
  };
  if (!lesson.lesson && !lesson.cause && !lesson.nextAction) throw new Error('lesson is required');
  const data = loadLessons();
  data.lessons.push(lesson);
  saveLessons(data);
  return lesson;
}

function loadAgentLessonContext(agentId, maxItems = 5) {
  const lessons = loadLessons().lessons
    .filter(l => l.agentId === agentId || l.agentId === 'global')
    .slice(-maxItems);
  if (lessons.length === 0) return '';
  const lines = lessons.map(l => {
    const parts = [];
    if (l.cause) parts.push(`因果链: ${l.cause}`);
    if (l.lesson) parts.push(`教训: ${l.lesson}`);
    if (l.nextAction) parts.push(`下次: ${l.nextAction}`);
    return `[${l.date}] ${parts.join('；').slice(0, 260)}`;
  });
  return `(agent复盘教训: ${lines.join(' | ')}。回答前先检查是否在重复这些问题。) `;
}

function notifyFeishu(title, content) {
  const config = loadConfig();
  const webhook = config.notifications?.feishuWebhook;
  if (!webhook) return;
  const keyword = String(config.notifications?.feishuKeyword || '').trim();
  let safeTitle = String(title || '');
  let safeContent = String(content || '');
  if (keyword && !(safeTitle + safeContent).includes(keyword)) {
    safeTitle = `${keyword} | ${safeTitle}`;
  }
  const body = JSON.stringify({
    msg_type: 'interactive',
    card: {
      header: { title: { content: safeTitle, tag: 'plain_text' } },
      elements: [{ tag: 'markdown', content: safeContent.slice(0, 3000) }]
    }
  });
  const url = new URL(webhook);
  const req = https.request({
    hostname: url.hostname, path: url.pathname, method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, (res) => {
    let d = ''; res.on('data', c => d += c);
    res.on('end', () => console.error(`[FEISHU] ${res.statusCode} ${d.slice(0, 100)}`));
  });
  req.on('error', e => console.error('[FEISHU] Error:', e.message));
  req.write(body); req.end();
}

function pickRecentContextMessages(recentMessages, topic, mode) {
  if (!recentMessages?.length) return [];
  const wantedTopic = String(topic || '').trim();
  const wantedMode = mode || 'chat';
  return recentMessages
    .filter(m => !m.room)
    .filter(m => m.from !== 'system')
    .filter(m => {
      if (!wantedTopic) return wantedMode === 'chat' ? (m.type || 'chat') === 'chat' : false;
      if (m.topic === wantedTopic) return true;
      const content = String(m.content || '');
      return (m.type === wantedMode || m.type === 'roundtable' || m.type === 'debate')
        && content.includes(wantedTopic);
    })
    .slice(-6);
}

function buildChatPrompt(agent, topic, userMessage, mode, recentMessages, extraContext = '') {
  const config = loadConfig();
  const port = config.server.port || 3456;
  const uploadsDir = UPLOADS_DIR;

  // Detect image URLs in user message and provide real image context
  let imageContext = '';
  const isLocal = !agent.hostId && (!agent.type || agent.type === 'cli');
  const isVisionAgent = agent.id === 'qwen-vision';
  const isClaudeCLI = isLocal && /(claude|deepseek)/i.test((agent.executable || '') + ' ' + (agent.chatCmd || ''));
  const imageUrlRe = /https?:\/\/[\d.]+:?\d*\/uploads\/[\w.-]+\.(jpe?g|png|gif|webp|bmp)/gi;
  const imageUrls = (userMessage || '').match(imageUrlRe) || [];

  if (imageUrls.length > 0) {
    const imgInfo = [];
    for (const url of imageUrls) {
      try {
        const urlPath = new URL(url).pathname;
        const fname = require('path').basename(urlPath);
        const fpath = require('path').join(uploadsDir, fname);
        if (fs.existsSync(fpath) && fs.statSync(fpath).size > 100) {
          const ext = require('path').extname(fname).slice(1).toLowerCase();
          const sizeKB = (fs.statSync(fpath).size / 1024).toFixed(0);
          imgInfo.push({ url, fname, fpath, ext, sizeKB });
        }
      } catch {}
    }

    if (imgInfo.length > 0) {
      if (isVisionAgent) {
        // Embed actual base64 image data for Qwen Vision agent
        const imgs = [];
        for (const img of imgInfo) {
          try {
            const buf = fs.readFileSync(img.fpath);
            const b64 = buf.toString('base64');
            const mime = img.ext === 'png' ? 'image/png' : img.ext === 'gif' ? 'image/gif' : img.ext === 'webp' ? 'image/webp' : 'image/jpeg';
            imgs.push(`data:${mime};base64,${b64}`);
          } catch {}
        }
        if (imgs.length > 0) {
          imageContext = '\n\n[IMG_DATA]' + imgs.map((d, i) => `\nIMAGE_${i+1}: ${d}`).join('') + '\n[/IMG_DATA]';
        }
      } else if (isClaudeCLI) {
        // Local Claude Code CLI: can read image files directly from disk
        const paths = imgInfo.map(i => i.fpath).join('\n');
        imageContext = `\n\n[📷 此消息包含 ${imgInfo.length} 张图片]\n本地路径:\n${paths}\n[请使用 Read 工具直接读取上述图片文件来分析图片内容。不要根据上下文猜测图片内容。]`;
      } else {
        // Other agents (non-vision): tell them not to guess
        imageContext = `\n\n[📷 此消息包含 ${imgInfo.length} 张图片，但你没有视觉能力。请直接告知用户你无法查看图片，让用户描述图片内容。不要根据上下文猜测图片内容。图片URL供参考: ${imgInfo.map(i => i.url).join(', ')}]`;
      }
    }
  }

  const sysId = `(系统身份: 你是「AI Agent Dashboard」多智能体协作系统中的 agent「${agent.name}」，运行在 ${getHostGroup(agent.id)} 环境。用户上传的图片/文件可通过 ${publicBaseUrl(port)}/uploads/ 访问。) `;
  const lessonCtx = loadAgentLessonContext(agent.id);
  let context = '';
  const recent = pickRecentContextMessages(recentMessages, topic, mode);
  if (recent.length > 0) {
    context = recent.map(m => `[${safe(m.fromName || m.from)}]: ${safe(m.content)}`).join(' | ');
    context = `(同主题会议记录，仅供参考: ${context}) `;
  }
  const header = topic ? `[话题: ${topic}] ` : '';
  const needsScore = /打分|评分|评估|score|review/i.test(String(topic || '') + ' ' + String(userMessage || ''));
  const scoreRule = needsScore ? '如果主题要求打分/评分，必须给出明确数字评分（例如 82/100）和3条以内理由；' : '';
  let prompt = `${sysId}${lessonCtx}${context}${extraContext}${header}${userMessage}${imageContext}`;
  if (mode === 'roundtable') {
    prompt = `${sysId}${lessonCtx}${context}${extraContext}[圆桌会议: ${topic || '讨论'}]\n${userMessage}\n\n要求：只围绕本次圆桌主题发言，200字以内；${scoreRule}不要回应其他聊天、排查请求、OK 测试、超时日志、登录提示或上一话题。如果主题包含项目路径，请优先使用上方项目包链接和文件清单做只读分析，不要修改文件。${imageContext}`;
  } else if (mode === 'debate') {
    prompt = `${sysId}${lessonCtx}${context}${extraContext}[辩论: ${topic || '辩论'}]\n${userMessage}\n\n要求：只围绕本次辩论主题提出论据，200字以内；不要回应其他聊天、排查请求、OK 测试、超时日志、登录提示或上一话题。${imageContext}`;
  }
  return prompt;
}

function hasUsefulAgentOutput(result) {
  if (!result?.ok) return false;
  const text = String(result.stdout || '').trim();
  if (!text) return false;
  if (/^(ok|收到|好的|明白)$/i.test(text)) return false;
  return true;
}

function compactAgentText(text, max = 1600) {
  const cleaned = String(text || '')
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
    .trim();
  return cleaned.length > max ? cleaned.slice(0, max) + '\n...（已截断）' : cleaned;
}

function isCodexLikeAgent(agent) {
  const raw = `${agent?.id || ''} ${agent?.name || ''} ${agent?.executable || ''} ${agent?.chatCmd || ''}`.toLowerCase();
  return /\bcodex\b|codex-cli|codex exec/.test(raw);
}

function recentHandoffMessages(limit = 12) {
  return (chatHistory.messages || []).slice(-limit).map(m => {
    const who = m.fromName || m.from || 'unknown';
    const time = m.timestamp ? new Date(m.timestamp).toLocaleString('zh-CN') : '';
    return `- ${time} ${who}: ${compactAgentText(m.content, 360).replace(/\n/g, ' / ')}`;
  });
}

function buildCodexHandoffMarkdown(reason = 'auto') {
  const version = loadVersion();
  const codexCfg = getLocalCodexModelConfig();
  const progress = publicDevProgress();
  const activeProgress = (progress.active || []).slice(0, 8).map(item =>
    `- [${item.status}] ${item.title || item.id}: ${compactAgentText(item.requirement || item.summary || '', 260).replace(/\n/g, ' / ')}`
  );
  const latestProgress = (progress.items || []).slice(0, 10).map(item =>
    `- [${item.status}] ${item.title || item.id} (${item.updatedAt || item.createdAt || item.startedAt || ''})`
  );
  const lessons = (loadLessons().lessons || []).slice(-10).reverse().map(l => {
    const parts = [];
    if (l.cause) parts.push(`原因: ${compactAgentText(l.cause, 140)}`);
    if (l.lesson) parts.push(`教训: ${compactAgentText(l.lesson, 160)}`);
    if (l.nextAction) parts.push(`下次: ${compactAgentText(l.nextAction, 140)}`);
    return `- ${l.date || ''} ${l.agentName || l.agentId}: ${parts.join('；')}`;
  });
  const notes = [
    '这份文件由 AI Agent Dashboard 自动生成，用于让 dashboard 内的 Codex CLI 尽量接上桌面 Codex 的工作上下文。',
    '它不是桌面 Codex App 的完整会话记忆，只是从本项目文件、聊天记录、研发进度和复盘教训汇总出的交接摘要。',
    '如果用户问“你是否继承桌面记忆”，应说明：不能无缝继承，但已读取本交接文件和项目文件。'
  ];

  return `# Codex Dashboard Handoff

生成时间: ${new Date().toLocaleString('zh-CN')}
触发原因: ${reason}
项目目录: ${__dirname}
Dashboard 地址: http://127.0.0.1:${loadConfig().server?.port || 3456}

## 桌面 Codex 配置

- 配置目录: ${path.join(os.homedir(), '.codex')}
- 默认模型: ${codexCfg.model || '未读取到'}
- Provider: ${codexCfg.provider || '未读取到'}
- 当前 Dashboard 版本: ${version.version || 'unknown'}

## 使用说明

${notes.map(x => `- ${x}`).join('\n')}

## 当前研发进度

${activeProgress.length ? activeProgress.join('\n') : '- 无进行中或中断的研发任务。'}

## 最近研发记录

${latestProgress.length ? latestProgress.join('\n') : '- 暂无研发记录。'}

## 最近聊天上下文

${recentHandoffMessages(14).join('\n') || '- 暂无聊天记录。'}

## 近期复盘教训

${lessons.length ? lessons.join('\n') : '- 暂无复盘教训。'}

## 给 Codex 的工作约定

- 优先读取本项目文件后再回答，不要假装知道桌面 App 私聊里的完整上下文。
- 涉及文件修改时先确认目标目录，备份关键文件，修改后做语法检查或接口验证。
- 自动研发、继续研发、失败和完成都必须通过 dashboard 消息流公开打印，不能只发私有结论。
- 如果结果需要截图或文件，应先落到 dashboard 可访问的文件/上传目录，再通知飞书或用户。
`;
}

function refreshCodexHandoff(reason = 'auto') {
  const text = buildCodexHandoffMarkdown(reason);
  fs.writeFileSync(CODEX_HANDOFF_PATH, text, 'utf-8');
  return text;
}

function attachCodexHandoff(agent, prompt) {
  if (!isCodexLikeAgent(agent)) return prompt;
  if (!/^\s*(\(系统身份:|\[私聊\])/.test(String(prompt || ''))) return prompt;
  const handoff = refreshCodexHandoff(`prompt:${agent.id || agent.name || 'codex'}`);
  const clipped = compactAgentText(handoff, 7000);
  return `【Codex 桌面/协作系统交接上下文】\n以下内容来自 ${CODEX_HANDOFF_PATH}，用于弥补 dashboard 私聊 Codex 与 Windows 桌面版 Codex App 之间不能自动共享完整会话记忆的问题。请把它当作当前项目的工作交接摘要，而不是用户直接输入的新任务。\n\n${clipped}\n【交接上下文结束】\n\n${prompt}`;
}

function buildReplyContext(replyTo) {
  if (!replyTo || !replyTo.content) return '';
  const fromName = replyTo.fromName || replyTo.from || '上一条消息';
  const quote = compactAgentText(replyTo.content, 900);
  return `【本次消息是在回复 ${fromName} 的这条消息】\n${quote}\n\n`;
}

function buildMeetingTranscript(responses) {
  const list = (responses || []).filter(Boolean);
  if (list.length === 0) return '';
  const blocks = list.map((r, idx) => {
    const status = r.useful ? '有效' : '无效/失败';
    const text = r.ok ? r.stdout : (r.stderr || r.stdout || '无响应');
    return `---\n[${idx + 1}] ${r.agentName || r.agentId} / 第${r.round}轮 / ${status}\n${compactAgentText(text, 1400)}`;
  });
  return `\n【本次会议完整转录，供总结使用】\n${blocks.join('\n')}\n【转录结束】\n`;
}

async function runAgentChat(agent, prompt, config) {
  const timeout = agent.chatTimeout || 120000;
  const group = getHostGroup(agent.id);
  let result;
  prompt = attachCodexHandoff(agent, prompt);

  // For long prompts on local Windows, write to temp file to avoid ENAMETOOLONG
  const isLocal = group === 'local';
  let tempFile = null;
  if (prompt.length > 2000 && isLocal) {
    tempFile = path.join(os.tmpdir(), `dash-prompt-${Date.now()}.txt`);
    fs.writeFileSync(tempFile, prompt, 'utf-8');
  }

  const promptB64 = tempFile ? `@${tempFile}` : Buffer.from(prompt).toString('base64');
  let fullCmd = agent.chatCmd.replace(/\{prompt_b64\}/g, promptB64);
  if (!isLocal && fullCmd.includes('{prompt}')) {
    // Never splice the raw prompt into a remote shell command. Markdown fences,
    // quotes, and backticks from prior chat history can otherwise break bash.
    fullCmd = fullCmd
      .replace(/"\{prompt\}"/g, '"$DASH_PROMPT"')
      .replace(/'\{prompt\}'/g, '"$DASH_PROMPT"')
      .replace(/\{prompt\}/g, '"$DASH_PROMPT"');
    fullCmd = `DASH_PROMPT=$(printf %s ${shQuote(promptB64)} | base64 -d)\n${fullCmd}`;
  } else {
    const promptArg = prompt.replace(/"/g, '\\"');
    fullCmd = fullCmd.replace(/\{prompt\}/g, promptArg);
  }

  // If using temp file, replace the inline decode logic with file read
  if (tempFile) {
    // Replace base64 decode pattern with file read
    fullCmd = fullCmd
      .replace(
        /\$t=\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\('[^']*'\)\)/,
        `$t=Get-Content '${tempFile}' -Raw`
      )
      .replace(
        /\{prompt_b64\}/g, ''
      );
  }

  console.error(`[DEBUG] agent=${agent.id} promptLen=${prompt.length} fullCmd=${fullCmd.slice(0,120)}`);

  if (group === 'local') {
    result = await execPromise(fullCmd, timeout);
    if (tempFile) try { fs.unlinkSync(tempFile); } catch {}
  } else {
    const hostConfig = config.hosts[group];
    if (!hostConfig || !hostConfig.enabled) {
      return { ok: false, stdout: '', stderr: `主机 ${group} 未配置或未启用` };
    }
    if (hostConfig.type === 'docker') {
      const cn = shIdent(agent.containerName);
      const d = shIdent(dc(hostConfig), 'docker');
      const userFlag = agent.runAs ? `--user ${shIdent(agent.runAs)}` : '';
      if (!cn) return { ok: false, stdout: '', stderr: '容器名无效' };
      const b64 = Buffer.from(fullCmd).toString('base64');
      result = await sshExec(hostConfig, `printf %s ${shQuote(b64)} | base64 -d | ${d} exec -i ${userFlag} ${cn} bash`, timeout);
    } else {
      const runAs = shIdent(agent.runAs);
      const shell = runAs ? `su ${runAs} -c bash` : 'bash';
      const b64r = Buffer.from(fullCmd).toString('base64');
      result = await sshExec(hostConfig, `printf %s ${shQuote(b64r)} | base64 -d | ${shell}`, timeout);
    }
  }

  // Parse response if agent has a responseParser
  if (agent.responseParser === 'openclaw-json') {
    try {
      const parsed = JSON.parse(result.stdout);
      const text = parsed?.payloads?.[0]?.text || parsed?.text || result.stdout;
      const finalResult = { ...result, ok: true, stdout: text };
      // Update status cache: agent responded successfully
      if (finalResult.ok) cacheAgentStatus(agent.id, { status: 'available', version: result.version || '' });
      return finalResult;
    } catch { /* fallback to raw */ }
  }
  // Claude Code writes warnings to stderr but actual response to stdout — treat as ok
  if (!result.ok && result.stdout && result.stdout.length > 20) {
    result = { ...result, ok: true };
  }
  // Update status cache based on result
  if (result.ok) {
    cacheAgentStatus(agent.id, { status: 'available', version: '' });
  }
  return result;
}

// ── API: Config ─────────────────────────────────────────────────

app.get('/api/config', (req, res) => {
  const config = loadConfig();
  // Mask passwords
  const safe = JSON.parse(JSON.stringify(config));
  for (const h of Object.values(safe.hosts)) {
    h.hasPassword = !!h.password;
    if (h.password) h.password = '••••••';
  }
  res.json(safe);
});

app.put('/api/hosts/:hostId', (req, res) => {
  const config = loadConfig();
  const hostId = req.params.hostId;
  if (!config.hosts[hostId]) {
    return res.status(404).json({ error: 'Host not found' });
  }
  const updates = { ...req.body };
  if (Object.prototype.hasOwnProperty.call(updates, 'password')) {
    const secrets = loadSecrets();
    secrets.hostPasswords = secrets.hostPasswords || {};
    if (updates.password && updates.password !== '••••••') {
      secrets.hostPasswords[hostId] = updates.password;
    } else if (updates.password === '') {
      delete secrets.hostPasswords[hostId];
    }
    saveSecrets(secrets);
    delete updates.password;
  }
  Object.assign(config.hosts[hostId], updates);
  saveConfig(config);
  res.json({ ok: true });
});

app.post('/api/hosts/:hostId/exec', async (req, res) => {
  const config = loadConfig();
  const host = config.hosts[req.params.hostId];
  if (!host) return res.status(404).json({ error: 'Host not found' });
  const { cmd } = req.body;
  if (!cmd) return res.status(400).json({ error: 'cmd required' });
  const result = await sshExec(host, cmd, 15000);
  res.json(result);
});

app.post('/api/hosts/:hostId/test', async (req, res) => {
  const config = loadConfig();
  const host = config.hosts[req.params.hostId];
  if (!host) return res.status(404).json({ error: 'Host not found' });

  let result;
  if (host.type === 'docker') {
    const d = dc(host);
    result = await sshExec(host, `echo OK && ${d} ps --format "{{.Names}}"`, 15000);
  } else {
    result = await sshExec(host, 'echo OK && ver 2>nul || uname -a', 15000);
  }
  if (result.ok) {
    const containers = result.stdout.split('\n').filter(l => l && l !== 'OK');
    res.json({ ok: true, output: '连接成功！' + (containers.length ? ' 容器: ' + containers.join(', ') : '') });
  } else {
    res.json({ ok: false, output: result.stderr || result.stdout || '连接失败' });
  }
});

// ── Timeout wrapper ────────────────────────────────────────────

function withTimeout(promise, ms, fallback) {
  const timer = new Promise((resolve) => setTimeout(() => resolve(fallback), ms));
  return Promise.race([promise, timer]);
}

async function mapLimit(items, limit, worker) {
  const results = new Array(items.length);
  let next = 0;
  const runners = Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, async () => {
    while (next < items.length) {
      const idx = next++;
      results[idx] = await worker(items[idx], idx);
    }
  });
  await Promise.all(runners);
  return results;
}

function agentRunLimit(agent, config) {
  const group = getHostGroup(agent.id);
  if (group === 'local') return config.localAgentConcurrency || 3;
  const host = config.hosts[group] || {};
  return Math.max(1, host.agentConcurrency || host.chatConcurrency || host.maxConnections || 2);
}

async function mapAgentsWithHostLimits(items, config, worker) {
  const results = new Array(items.length);
  const buckets = new Map();

  items.forEach((item, idx) => {
    const agent = item.agent || item;
    const group = agent?.id ? (getHostGroup(agent.id) || 'unknown') : 'unknown';
    if (!buckets.has(group)) buckets.set(group, []);
    buckets.get(group).push({ item, idx, agent });
  });

  await Promise.all([...buckets.values()].map((bucket) => {
    const agent = bucket.find(b => b.agent?.id)?.agent;
    const limit = agent ? agentRunLimit(agent, config) : 1;
    return mapLimit(bucket, limit, async ({ item, idx }) => {
      results[idx] = await worker(item, idx);
    });
  }));

  return results;
}

// ── Agent status cache ─────────────────────────────────────────

const agentStatusCache = {}; // agentId -> { status, version, ... }

function cacheAgentStatus(agentId, status) {
  agentStatusCache[agentId] = { ...status, cachedAt: Date.now() };
}

function getCachedAgentStatus(agent) {
  const cached = agentStatusCache[agent.id];
  if (cached && (Date.now() - cached.cachedAt) < 120000) {
    return { ...agent, ...cached, cached: true, hostGroup: getHostGroup(agent.id) };
  }
  return null;
}

function disabledAgentStatus(agent) {
  return {
    status: 'disabled',
    info: agent.disabledReason || '已禁用',
    version: null
  };
}

let localCodexModelCache = null;
function getLocalCodexModelConfig() {
  if (localCodexModelCache) return localCodexModelCache;
  const cfgPath = path.join(os.homedir(), '.codex', 'config.toml');
  try {
    const text = fs.readFileSync(cfgPath, 'utf-8');
    const model = text.match(/^\s*model\s*=\s*"([^"]+)"/m)?.[1] || '';
    const provider = text.match(/^\s*model_provider\s*=\s*"([^"]+)"/m)?.[1] || '';
    localCodexModelCache = { model, provider };
  } catch {
    localCodexModelCache = { model: '', provider: '' };
  }
  return localCodexModelCache;
}

function inferAgentRuntimeInfo(agent, group = '') {
  const raw = [
    agent.model, agent.modelName, agent.modelProvider, agent.engine, agent.executable,
    agent.containerName, agent.chatCmd, agent.name, agent.description
  ].filter(Boolean).join(' ').toLowerCase();

  let engineLabel = agent.engineLabel || agent.engine || agent.executable || agent.containerName || agent.type || 'agent';
  let modelLabel = agent.model || agent.modelName || '';
  let modelSource = modelLabel ? 'config' : 'inferred';

  if (/cc-deepseek/.test(raw)) {
    engineLabel = 'Claude Code CLI (cc-deepseek)';
    if (!modelLabel) modelLabel = 'DeepSeek';
  } else if (/\bcodex\b|codex cli/.test(raw)) {
    engineLabel = 'Codex CLI';
    if (!modelLabel) {
      const cfg = group === 'local' ? getLocalCodexModelConfig() : {};
      modelLabel = cfg?.model
        ? `${cfg.model}${cfg.provider ? ` / ${cfg.provider}` : ''}`
        : 'Codex 默认模型（未配置具体型号）';
      modelSource = cfg?.model ? 'local-codex-config' : 'inferred';
    }
  } else if (/cc-haha|claude code|\bclaude\b/.test(raw)) {
    engineLabel = /cc-haha/.test(raw) ? 'Claude Code CLI (cc-haha)' : 'Claude Code CLI';
    if (!modelLabel) modelLabel = 'Claude Code 默认模型（未配置具体型号）';
  } else if (/openclaw/.test(raw)) {
    engineLabel = 'OpenClaw';
    if (!modelLabel) modelLabel = 'OpenClaw 默认模型（未配置具体型号）';
  } else if (/hermes/.test(raw)) {
    engineLabel = 'Hermes';
    if (!modelLabel) modelLabel = 'Hermes 默认模型（未配置具体型号）';
  } else if (!modelLabel) {
    modelLabel = agent.type === 'docker' ? 'Docker Agent（未配置具体模型）' : 'CLI Agent（未配置具体模型）';
    modelSource = 'missing';
  }

  return { engineLabel, modelLabel, modelSource };
}

function withAgentRuntimeInfo(agent, group) {
  return { ...agent, ...inferAgentRuntimeInfo(agent, group) };
}

// ── API: Agents ─────────────────────────────────────────────────

app.get('/api/agents', async (req, res) => {
  const config = loadConfig();
  const result = {};

  // Return cache immediately for fast page load, stale is better than waiting
  const useCache = req.query.cache !== '0';

  await Promise.all(Object.entries(config.agents).map(async ([group, agents]) => {
    const hostConfig = config.hosts[group];

    if (group === 'local') {
      const localRows = [];
      for (const agent of agents) {
        if (agent.disabled) {
          localRows.push({ ...agent, ...disabledAgentStatus(agent), hostGroup: group });
          continue;
        }
        if (useCache) {
          const cached = getCachedAgentStatus(agent);
          if (cached) { localRows.push(cached); continue; }
        }
        const status = checkLocalAgent(agent);
        cacheAgentStatus(agent.id, status);
        localRows.push({ ...agent, ...status, hostGroup: group });
      }
      result[group] = localRows;
    } else {
      // Remote CLI status checks are intentionally throttled per host. Some
      // NAS SSH servers drop sessions when several CLI probes start together.
      if (!hostConfig || !hostConfig.enabled) {
        result[group] = agents.map(agent => ({ ...agent, status: 'error', info: '主机未配置或未启用', hostGroup: group }));
        return;
      }
      const statusConcurrency = hostConfig.statusConcurrency || 1;
      const results = await mapLimit(agents, statusConcurrency, async (agent) => {
        if (agent.disabled) return { ...agent, ...disabledAgentStatus(agent), hostGroup: group };
        if (useCache) {
          const cached = getCachedAgentStatus(agent);
          if (cached) return cached;
        }
        const recent = recentSuccessStatus(agent);
        if (recent) {
          cacheAgentStatus(agent.id, recent);
          return { ...agent, ...recent, hostGroup: group };
        }
        const status = await withTimeout(
          checkRemoteAgent(agent, hostConfig),
          hostConfig.statusTimeout || 10000,
          { status: 'checking', info: '检测中...' }
        );
        if (status.status !== 'checking') cacheAgentStatus(agent.id, status);
        return { ...agent, ...status, hostGroup: group };
      });
      result[group] = results;
    }
  }));

  for (const [group, rows] of Object.entries(result)) {
    result[group] = (rows || []).map(agent => withAgentRuntimeInfo(agent, group));
  }

  // Host info (mask passwords)
  result._hosts = {};
  for (const [id, h] of Object.entries(config.hosts)) {
    result._hosts[id] = {
      name: h.name, type: h.type, host: h.host, port: h.port,
      user: h.user, enabled: h.enabled, hasPassword: !!h.password
    };
  }
  res.json(result);
});

app.get('/api/agents/:id', async (req, res) => {
  const config = loadConfig();
  const agent = findAgent(req.params.id);
  if (!agent) return res.status(404).json({ error: 'Not found' });
  const group = getHostGroup(req.params.id);
  if (group === 'local') {
    res.json({ ...agent, ...checkLocalAgent(agent), hostGroup: group });
  } else {
    const status = await checkRemoteAgent(agent, config.hosts[group]);
    res.json({ ...agent, ...status, hostGroup: group });
  }
});

app.put('/api/agents/:id/enabled', (req, res) => {
  const config = loadConfig();
  const agentId = req.params.id;
  let found = null;
  for (const agents of Object.values(config.agents)) {
    found = agents.find(a => a.id === agentId);
    if (found) break;
  }
  if (!found) return res.status(404).json({ error: 'Agent not found' });
  const enabled = req.body?.enabled !== false;
  if (enabled) {
    delete found.disabled;
    delete found.disabledReason;
    delete agentStatusCache[agentId];
  } else {
    found.disabled = true;
    found.disabledReason = req.body?.reason || found.disabledReason || '手动禁用';
    cacheAgentStatus(agentId, disabledAgentStatus(found));
  }
  saveConfig(config);
  res.json({ ok: true, id: agentId, enabled });
});

app.post('/api/agents/:id/action', async (req, res) => {
  const config = loadConfig();
  const agent = findAgent(req.params.id);
  if (!agent) return res.status(404).json({ error: 'Not found' });
  const { actionIndex } = req.body;
  const action = agent.actions?.[actionIndex];
  if (!action) return res.status(400).json({ error: 'Invalid action' });
  const result = await execPromise(action.cmd, 15000);
  res.json({ ...result, action: action.label });
});

// Agent restart/health check
app.post('/api/agents/:id/restart', async (req, res) => {
  const config = loadConfig();
  const agent = findAgent(req.params.id);
  if (!agent) return res.status(404).json({ error: 'Not found' });
  const group = getHostGroup(req.params.id);
  if (group === 'local') {
    // Check if agent executable exists
    const check = await execPromise(`where ${agent.executable || agent.id} 2>nul || echo NOT_FOUND`, 5000);
    const found = !check.stdout.includes('NOT_FOUND');
    res.json({ ok: found, stdout: found ? `${agent.executable || agent.id} 可访问` : '未找到可执行文件', status: found ? 'available' : 'not_found' });
  } else {
    const hostConfig = config.hosts[group];
    if (!hostConfig) return res.status(404).json({ error: 'Host not found' });
    const testCmd = hostConfig.type === 'docker'
      ? `docker exec ${agent.containerName} echo ok 2>&1`
      : `which ${agent.executable || 'bash'} 2>/dev/null && echo ok || echo NOT_FOUND`;
    const result = await sshExec(hostConfig, testCmd, 10000);
    res.json({ ok: result.ok && result.stdout.includes('ok'), stdout: result.stdout, stderr: result.stderr, status: result.ok ? 'available' : 'error' });
  }
});

// Agent lesson book: one causal-chain lesson per agent/day can be collected here.
app.get('/api/lessons', (req, res) => {
  const { agentId, limit } = req.query;
  let lessons = loadLessons().lessons;
  if (agentId) lessons = lessons.filter(l => l.agentId === agentId);
  lessons = lessons.slice(-(parseInt(limit, 10) || 200)).reverse();
  res.json({ lessons });
});

app.post('/api/lessons', (req, res) => {
  try {
    const lesson = addAgentLesson(req.body || {}, req.body?.source || 'manual');
    res.json({ ok: true, lesson });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

app.delete('/api/lessons/:id', (req, res) => {
  const data = loadLessons();
  const before = data.lessons.length;
  data.lessons = data.lessons.filter(l => l.id !== req.params.id);
  saveLessons(data);
  res.json({ ok: true, deleted: before - data.lessons.length });
});

app.post('/api/lessons/collect', async (req, res) => {
  try {
    const config = loadConfig();
    const { agentIds, topic } = req.body || {};
    if (!agentIds?.length) return res.status(400).json({ error: '请选择至少一个 agent' });
    const selectedAgents = agentIds.map(agentId => ({ agentId, agent: findAgent(agentId) }));
    const collectTopic = topic || '每日复盘';
    const promptTopic = clipLessonField(collectTopic, 200);
    const prompt = `请为你自己记录一条“昨日教训”因果链，用于 AI Agent Dashboard 的长期复盘。

背景主题：${promptTopic}

只输出三行，不要展开寒暄：
原因链: 昨天/上次哪里出现了偏差，以及为什么会发生
教训: 这件事说明以后要避免什么
下次动作: 下一次遇到相似任务时第一步怎么做`;

    const settled = await mapAgentsWithHostLimits(selectedAgents, config, async ({ agentId, agent }) => {
      try {
        if (!agent) return { agentId, ok: false, stderr: '未找到该智能体' };
        if (agent.disabled) {
          return { agentId, agentName: agent.name, ok: false, stderr: agent.disabledReason || '该智能体已禁用' };
        }
        const result = await runAgentChat(agent, prompt, config);
        let lesson = null;
        if (result.ok && result.stdout?.trim()) {
          lesson = addAgentLesson({
            agentId: agent.id,
            agentName: agent.name,
            topic: promptTopic,
            raw: result.stdout
          }, 'daily-collect');
        }
        return {
          agentId: agent.id,
          agentName: agent.name,
          ok: !!result.ok,
          lesson,
          stdout: compactAgentText(result.stdout || '', 1200),
          stderr: compactAgentText(result.stderr || '', 1200),
          responseTime: result.responseTime || null
        };
      } catch (e) {
        return {
          agentId,
          agentName: agent?.name || agentId,
          ok: false,
          lesson: null,
          stderr: compactAgentText(e?.stack || e?.message || String(e), 1200)
        };
      }
    });
    res.json({ ok: true, results: settled });
  } catch (e) {
    res.status(500).json({ ok: false, error: compactAgentText(e?.message || String(e), 1200) });
  }
});

// Docker container actions
app.post('/api/docker/:hostId/:action', async (req, res) => {
  const config = loadConfig();
  const host = config.hosts[req.params.hostId];
  if (!host || host.type !== 'docker') return res.status(400).json({ error: 'Invalid host' });
  const { agentId } = req.body;
  const agent = config.agents[req.params.hostId]?.find(a => a.id === agentId);
  if (!agent) return res.status(404).json({ error: 'Agent not found' });
  const cn = agent.containerName;
  const d = dc(host);
  const cmds = {
    start: `${d} start ${cn}`,
    stop: `${d} stop ${cn}`,
    restart: `${d} restart ${cn}`,
    logs: `${d} logs --tail 50 ${cn}`,
    inspect: `${d} inspect ${cn} --format '{{.State.Status}}|{{.Config.Image}}|{{.Created}}'`
  };
  if (!cmds[req.params.action]) return res.status(400).json({ error: 'Unknown action' });
  res.json(await sshExec(host, cmds[req.params.action], 15000));
});

// ── API: Chat ───────────────────────────────────────────────────

app.get('/api/chat/history', (req, res) => {
  res.json(chatHistory);
});

app.delete('/api/chat/history', (req, res) => {
  chatHistory = { topics: [], messages: [] };
  saveChatHistory(chatHistory);
  res.json({ ok: true });
});

app.post('/api/chat/send', async (req, res) => {
  const config = loadConfig();
  const { agentIds, message, mode, topic, room, replyTo } = req.body;

  if (!agentIds?.length) return res.status(400).json({ error: '请选择至少一个智能体' });
  if (!message?.trim()) return res.status(400).json({ error: '消息不能为空' });

  const replyContext = buildReplyContext(replyTo);
  const agentMessage = replyContext ? `${replyContext}我的回复：${message}` : message;
  const userMsg = {
    id: crypto.randomUUID(),
    from: 'user',
    fromName: '你',
    content: message,
    timestamp: new Date().toISOString(),
    type: mode || 'chat',
    topic: topic || null,
    room: room || null,
    replyTo: replyTo ? {
      from: replyTo.from || null,
      fromName: replyTo.fromName || null,
      content: compactAgentText(replyTo.content, 500),
      timestamp: replyTo.timestamp || null
    } : null
  };
  addChatMessage(userMsg);

  if (topic && !chatHistory.topics.find(t => t.text === topic)) {
    chatHistory.topics.push({ text: topic, setAt: new Date().toISOString() });
  }
  const currentTopic = topic || ((mode && mode !== 'chat') ? (chatHistory.topics[chatHistory.topics.length - 1]?.text || '') : '');

  const selectedAgents = agentIds.map(agentId => ({ agentId, agent: findAgent(agentId) }));
  if (!room && selectedAgents.length === 1 && selectedAgents[0].agent) {
    const publishPlan = parseContentPublishFlow(message, selectedAgents[0].agent, config);
    if (publishPlan) {
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `✅ 已识别为内容发布流水线\n平台: ${publishPlan.platform}\n主题: ${publishPlan.topic}\n文案: ${publishPlan.copyAgent.name}\n图片: ${publishPlan.imageAgent.name}\n整合: ${publishPlan.integratorAgent.name}${publishPlan.reviewerAgent ? `\n审核: ${publishPlan.reviewerAgent.name}` : ''}\n说明: 当前先生成待确认发布包；如需真实自动发布，需要平台授权/登录态。`,
        timestamp: new Date().toISOString(),
        type: 'workflow',
        topic: `${publishPlan.platform}发布: ${publishPlan.topic}`
      });
      const result = await runContentPublishWorkflow(publishPlan, config);
      return res.json({ ...result, contentPublish: true });
    }

    const doudizhuPlan = parseDoudizhuFlow(message, selectedAgents[0].agent, config);
    if (doudizhuPlan && doudizhuPlan.participants?.length === 3) {
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `✅ 内置流程审核完成：斗地主专用引擎\n玩家: ${doudizhuPlan.participants.map(a => a.name).join('、')}\n裁判/汇报: ${doudizhuPlan.reporter ? doudizhuPlan.reporter.name : '系统裁判'}\n执行方式: 发牌、叫地主、合法出牌、胜负裁定全程公开打印。`,
        timestamp: new Date().toISOString(),
        type: 'workflow',
        topic: doudizhuPlan.topic
      });
      const result = await runDoudizhuFlow({
        plan: doudizhuPlan,
        message,
        mode: mode || 'chat',
        config
      });
      return res.json(result);
    }

    const gomokuPlan = parseGomokuFlow(message, selectedAgents[0].agent, config);
    if (gomokuPlan?.queryOnly) {
      return res.json(await runGomokuResultQuery({
        requester: selectedAgents[0].agent,
        message,
        mode: mode || 'chat',
        topic: currentTopic,
        config
      }));
    }
    if (gomokuPlan && gomokuPlan.participants?.length >= 2) {
      const result = await runGomokuFlow({
        plan: gomokuPlan,
        message,
        mode: mode || 'chat',
        config
      });
      return res.json(result);
    }

    if (shouldTriggerAutoFlowRepair(message)) {
      const retryHint = inferRetryHint(message);
      const repairAgent = pickCodexRepairAgent(config);
      const repairName = repairAgent ? `${repairAgent.icon || ''} ${repairAgent.name}` : '自动修复工程师';
      runAutoFlowRepair({
        requirement: message,
        triggerAgent: selectedAgents[0].agent,
        config,
        retryHint
      }).catch(err => {
        addChatMessage({
          id: crypto.randomUUID(),
          from: 'system',
          fromName: '🔔 系统',
          content: `❌ 流程自修复后台任务异常: ${err.message}`,
          timestamp: new Date().toISOString(),
          type: 'workflow',
          topic: '流程自修复'
        });
      });
      return res.json({
        ok: true,
        autoRepair: true,
        responses: [{
          agentId: selectedAgents[0].agent.id,
          agentName: selectedAgents[0].agent.name,
          ok: true,
          stdout: `${repairName} 已在抓紧研发该流程。完成后会汇报，并提示主人重试：${retryHint}`,
          stderr: '',
          responseTime: 0
        }]
      });
    }
    if (shouldUseFlowPlanner(message)) {
      const planned = await planFlowWithCodex({
        requester: selectedAgents[0].agent,
        message,
        mode: mode || 'chat',
        topic: currentTopic,
        config
      });
      const forcedRepair = detectForcedAutoRepairFlow(message);
      if (forcedRepair) {
        if (planned?.plan && planned.plan.supported !== false && !/auto-repair/i.test(String(planned.plan.engine || ''))) {
          addChatMessage({
            id: crypto.randomUUID(),
            from: 'system',
            fromName: '🔔 系统',
            content: `⚠️ Codex 初步计划被后端安全规则纠正。\n原计划: ${planned.plan.engine || 'unknown'} / ${planned.plan.activityType || 'unknown'}\n纠正原因: ${forcedRepair.reason}`,
            timestamp: new Date().toISOString(),
            responseTime: planned.responseTime,
            type: 'workflow',
            topic: '流程自修复'
          });
        }
        return res.json(startAutoRepairForFlow({
          message,
          triggerAgent: selectedAgents[0].agent,
          config,
          retryHint: forcedRepair.retryHint,
          reason: forcedRepair.reason,
          responseTime: planned?.responseTime || 0
        }));
      }
      if (planned?.plan) {
        const engine = String(planned.plan.engine || '');
        if (planned.plan.supported === false || /auto-repair/i.test(engine)) {
          const retryHint = planned.plan.retryHint || inferRetryHint(message);
          return res.json(startAutoRepairForFlow({
            message,
            triggerAgent: selectedAgents[0].agent,
            config,
            retryHint,
            reason: planned.plan.reason || '现有引擎不完整',
            responseTime: planned.responseTime
          }));
        }

        if (/visible-consult/i.test(engine)) {
          const target = (Array.isArray(planned.plan.participants) ? planned.plan.participants : [])
            .map(ref => resolveAgentRef(ref, config, [selectedAgents[0].agent.id]))
            .find(Boolean) || findConsultTarget(message, [selectedAgents[0].agent.id], config);
          if (target) {
            addChatMessage({
              id: crypto.randomUUID(),
              from: 'system',
              fromName: '🔔 系统',
              content: `✅ Codex 流程审核完成：可见咨询\n发起: ${selectedAgents[0].agent.name}\n咨询对象: ${target.name}\n所有转问和回复都会打印。`,
              timestamp: new Date().toISOString(),
              type: 'workflow',
              topic: currentTopic || 'Codex流程审核'
            });
            const consultResult = await runVisibleConsult({
              requester: selectedAgents[0].agent,
              target,
              message,
              mode: mode || 'chat',
              topic: currentTopic,
              config
            });
            return res.json({ ...consultResult, flowPlanner: true });
          }
        }

        if (/doudizhu-game/i.test(engine)) {
          const participants = uniqueAgents((Array.isArray(planned.plan.participants) ? planned.plan.participants : [])
            .map(ref => resolveAgentRef(ref, config, []))
            .filter(Boolean))
            .filter(a => a.id !== selectedAgents[0].agent.id || /(你和|和你|你也|一起)/.test(message))
            .slice(0, 3);
          if (participants.length === 3) {
            const reporter = resolveAgentRef(planned.plan.reporter, config, []) || (participants.some(a => a.id === selectedAgents[0].agent.id) ? null : selectedAgents[0].agent);
            const doudizhuPlan = {
              requester: selectedAgents[0].agent,
              participants,
              reporter,
              maxTurns: 180,
              topic: planned.plan.topic || '斗地主流程'
            };
            addChatMessage({
              id: crypto.randomUUID(),
              from: 'system',
              fromName: '🔔 系统',
              content: `✅ Codex 流程审核完成：斗地主专用引擎\n玩家: ${participants.map(a => a.name).join('、')}\n裁判/汇报: ${reporter ? reporter.name : '系统裁判'}\n执行方式: 发牌、叫地主、合法出牌、胜负裁定全程公开打印。`,
              timestamp: new Date().toISOString(),
              responseTime: planned.responseTime,
              type: 'workflow',
              topic: doudizhuPlan.topic
            });
            const doudizhuResult = await runDoudizhuFlow({
              plan: doudizhuPlan,
              message,
              mode: mode || 'roundtable',
              config
            });
            return res.json({ ...doudizhuResult, flowPlanner: true });
          }
        }

        const delegatedPlan = buildDelegatedPlanFromCodex(planned.plan, selectedAgents[0].agent, config, message);
        if (delegatedPlan) {
          addChatMessage({
            id: crypto.randomUUID(),
            from: 'system',
            fromName: '🔔 系统',
            content: summarizeCodexFlowPlan(planned.plan, delegatedPlan, selectedAgents[0].agent),
            timestamp: new Date().toISOString(),
            responseTime: planned.responseTime,
            type: 'workflow',
            topic: delegatedPlan.topic
          });
          const discussionResult = await runDelegatedDiscussion({
            requester: selectedAgents[0].agent,
            plan: delegatedPlan,
            message,
            mode: mode || 'roundtable',
            config
          });
          return res.json({ ...discussionResult, flowPlanner: true });
        }

        addChatMessage({
          id: crypto.randomUUID(),
          from: 'system',
          fromName: '🔔 系统',
          content: `⚠️ Codex 已完成流程审核，但计划无法映射到现有引擎，降级使用内置规则。\n${compactAgentText(JSON.stringify(planned.plan), 1200)}`,
          timestamp: new Date().toISOString(),
          responseTime: planned.responseTime,
          type: 'workflow',
          topic: currentTopic || 'Codex流程审核'
        });
      }
    }
    const discussionPlan = parseDelegatedDiscussion(message, selectedAgents[0].agent, config);
    if (discussionPlan) {
      const discussionResult = await runDelegatedDiscussion({
        requester: selectedAgents[0].agent,
        plan: discussionPlan,
        message,
        mode: mode || 'roundtable',
        config
      });
      return res.json(discussionResult);
    }
    const consultTarget = findConsultTarget(message, [selectedAgents[0].agent.id], config);
    if (consultTarget) {
      const consultResult = await runVisibleConsult({
        requester: selectedAgents[0].agent,
        target: consultTarget,
        message,
        mode: mode || 'chat',
        topic: currentTopic,
        config
      });
      return res.json(consultResult);
    }
  }

  async function dispatchSelectedAgents() {
    return await mapAgentsWithHostLimits(selectedAgents, config, async ({ agentId, agent }) => {
      if (!agent) {
        return { agentId, agentName: agentId, ok: false, stdout: '', stderr: '未找到该智能体' };
      }
      if (agent.disabled) {
        return { agentId, agentName: agent.name, ok: false, stdout: '', stderr: agent.disabledReason || '该智能体已禁用' };
      }
      const prompt = room
      ? `[私聊] ${agentMessage}`
      : buildChatPrompt(agent, currentTopic, agentMessage, mode || 'chat', chatHistory.messages);

    // Broadcast "thinking" status via SSE
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `⏳ ${agent.icon} ${agent.name} 正在思考...`,
      timestamp: new Date().toISOString(),
      type: mode || 'chat',
      topic: currentTopic || null,
      room: room || null
    });

    const startTime = Date.now();
    const result = await runAgentChat(agent, prompt, config);
    const responseTime = Date.now() - startTime;

    const agentMsg = {
      id: crypto.randomUUID(),
      from: agent.id,
      fromName: `${agent.icon} ${agent.name}`,
      content: result.ok ? result.stdout : `❌ ${result.stderr || result.stdout || '无响应'}`,
      timestamp: new Date().toISOString(),
      responseTime,
      type: mode || 'chat',
      topic: currentTopic || null,
      room: room || null
    };
    addChatMessage(agentMsg);
    return { agentId, agentName: agent.name, ...result, responseTime };
  });
  }

  if ((mode || 'chat') === 'chat') {
    dispatchSelectedAgents().catch(err => {
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `❌ 聊天后台分发失败: ${err.message}`,
        timestamp: new Date().toISOString(),
        type: mode || 'chat',
        topic: currentTopic || null,
        room: room || null
      });
    });
    return res.json({
      ok: true,
      accepted: true,
      queued: true,
      responses: selectedAgents.map(({ agentId, agent }) => ({
        agentId,
        agentName: agent?.name || agentId,
        ok: true,
        queued: true,
        stdout: '',
        stderr: '',
        responseTime: 0
      }))
    });
  }

  const responses = await dispatchSelectedAgents();
  res.json({ ok: true, responses });
});

// Private chat history for a specific agent
app.get('/api/chat/private/:agentId', (req, res) => {
  const { agentId } = req.params;
  const msgs = chatHistory.messages.filter(
    m => m.room === agentId && (m.from === 'user' || m.from === agentId)
  );
  res.json({ agentId, messages: msgs.slice(-100) });
});

app.post('/api/chat/roundtable', async (req, res) => {
  const config = loadConfig();
  const { agentIds, topic, rounds, mode, summarizerId } = req.body;

  if (!agentIds?.length) return res.status(400).json({ error: '请选择参与智能体' });
  if (!topic?.trim()) return res.status(400).json({ error: '请设定会议主题' });

  const chatMode = mode || 'roundtable';
  const requestedParticipants = agentIds.map(id => findAgent(id)).filter(Boolean);
  const skippedParticipants = requestedParticipants.filter(a => a.disabled);
  const participants = requestedParticipants.filter(a => !a.disabled);
  if (skippedParticipants.length > 0) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `⚠️ 已跳过禁用智能体: ${skippedParticipants.map(a => `${a.name}（${a.disabledReason || '已禁用'}）`).join('、')}`,
      timestamp: new Date().toISOString(),
      type: mode || 'roundtable'
    });
  }
  if (participants.length === 0) return res.status(400).json({ error: '没有可用的参与智能体' });
  const isDebate = chatMode === 'debate';
  const isChat = chatMode === 'chat';
  const icon = isDebate ? '⚔️' : (isChat ? '💬' : '🏛️');
  const label = isDebate ? '辩论' : (isChat ? '自由讨论' : '圆桌会议');
  let projectBundle = null;
  let projectContext = '';
  try {
    projectBundle = publishLocalProjectForAgents(topic, config);
    if (projectBundle) {
      projectContext =
        `(本次会议项目包: ${projectBundle.url}\n` +
        `本机原路径: ${projectBundle.path}\n` +
        `远程 agent 看不到 Windows 本机路径，必须通过上面的 HTTP 链接下载 zip 后分析。\n` +
        `文件清单预览:\n- ${projectBundle.manifest.slice(0, 80).join('\n- ')}\n) `;
    }
  } catch (e) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `⚠️ 检测到本地项目路径，但自动发布失败：${e.message}`,
      timestamp: new Date().toISOString(),
      type: chatMode,
      topic
    });
  }

  let summaryNote = '';
  if (summarizerId) {
    const s = findAgent(summarizerId);
    if (s) summaryNote = `\n📝 总结: ${s.name}`;
  }
  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `${icon} ${label}: 「${topic}」\n参与: ${participants.map(a => a.name).join('、')} | ${rounds || 1} 轮${summaryNote}${projectBundle ? `\n📦 项目包: ${projectBundle.url}` : ''}`,
    timestamp: new Date().toISOString(),
    type: chatMode,
    topic
  });
  if (!chatHistory.topics.find(t => t.text === topic)) {
    chatHistory.topics.push({ text: topic, setAt: new Date().toISOString() });
  }

  const maxRounds = rounds || 1;
  const allResponses = [];
  let completedRounds = 0;

  for (let round = 1; round <= maxRounds; round++) {
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `🔄 第 ${round}/${maxRounds} 轮开始...`,
      timestamp: new Date().toISOString(), type: chatMode, topic
    });
    // Run participants in parallel across hosts, while limiting each SSH host.
    const roundResults = await mapAgentsWithHostLimits(participants, config, async (agent) => {
      const prompt = buildChatPrompt(agent, topic, `请就「${topic}」发表你的观点（第${round}轮）`, chatMode, chatHistory.messages, projectContext);
      const startTime = Date.now();
      const result = await runAgentChat(agent, prompt, config);
      const responseTime = Date.now() - startTime;
      const useful = hasUsefulAgentOutput(result);

      const msg = {
        id: crypto.randomUUID(),
        from: agent.id,
        fromName: `${agent.icon} ${agent.name}`,
        content: result.ok ? result.stdout : `❌ ${result.stderr || '无响应'}`,
        timestamp: new Date().toISOString(),
        responseTime,
        type: chatMode,
        topic
      };
      addChatMessage(msg);
      return { agentId: agent.id, agentName: agent.name, round, useful, ...result, responseTime };
    });
    allResponses.push(...roundResults);

    const usefulCount = roundResults.filter(r => r?.useful).length;
    const failed = roundResults.filter(r => !r?.useful);
    completedRounds = round;
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `✅ 第 ${round}/${maxRounds} 轮结束：有效发言 ${usefulCount}/${participants.length}${failed.length ? `；无效/失败：${failed.map(r => r.agentName).join('、')}` : ''}`,
      timestamp: new Date().toISOString(),
      type: chatMode,
      topic
    });
    if (usefulCount === 0 && round < maxRounds) {
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `⛔ 本轮没有任何有效发言，已停止后续轮次，避免空转到第 ${round + 1} 轮。请先检查参与 agent 的登录、SSH 或命令超时问题。`,
        timestamp: new Date().toISOString(),
        type: chatMode,
        topic
      });
      break;
    }
  }

  const usefulResponses = allResponses.filter(r => r?.useful);

  // ── Summarizer: designated agent summarizes the discussion ──
  if (summarizerId && usefulResponses.length === 0) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system', fromName: '🔔 系统',
      content: '📝 没有有效发言，已跳过总结。',
      timestamp: new Date().toISOString(),
      type: chatMode,
      topic
    });
  } else if (summarizerId) {
    const summarizer = findAgent(summarizerId);
    if (summarizer && summarizer.disabled) {
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system', fromName: '🔔 系统',
        content: `⚠️ 总结智能体 ${summarizer.name} 已禁用，跳过总结`,
        timestamp: new Date().toISOString(),
        type: chatMode,
        topic
      });
    } else if (summarizer) {
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system', fromName: '🔔 系统',
        content: `📝 请 ${summarizer.icon} ${summarizer.name} 总结汇报...`,
        timestamp: new Date().toISOString(),
        type: chatMode,
        topic
      });
      const meetingTranscript = buildMeetingTranscript(allResponses);
      const summaryPrompt = buildChatPrompt(summarizer, topic,
        `讨论已结束。请严格根据【本次会议完整转录】做总结报告。如果议题要求打分，请列出每个有效发言 agent 的评分；没有明确评分的 agent 标注“未给出评分”，不要说只收到你自己的评分。最后给出平均分、主要分歧、整改建议。`,
        'chat', chatHistory.messages, projectContext + meetingTranscript);
      const startTime = Date.now();
      const result = await runAgentChat(summarizer, summaryPrompt, config);
      const responseTime = Date.now() - startTime;
      const summaryMsg = {
        id: crypto.randomUUID(),
        from: summarizer.id,
        fromName: `📝 ${summarizer.icon} ${summarizer.name} (总结)`,
        content: result.ok ? result.stdout : `❌ ${result.stderr || '无响应'}`,
        timestamp: new Date().toISOString(),
        responseTime,
        type: chatMode,
        topic
      };
      addChatMessage(summaryMsg);
      allResponses.push({ agentId: summarizer.id, agentName: summarizer.name, round: 'summary', ...result, responseTime });
      // Auto-save summary to collective memory
      if (result.ok && result.stdout) {
        appendToMemory(topic, result.stdout);
      }
    }
  }

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system', fromName: '🔔 系统',
    content: `${icon} ${label}结束。实际 ${completedRounds}/${maxRounds} 轮，${participants.length} 人，${usefulResponses.length}/${allResponses.length} 条有效发言`,
    timestamp: new Date().toISOString(),
    type: chatMode,
    topic
  });
  res.json({ ok: true, responses: allResponses });
});

// ── Workflow Engine ──────────────────────────────────────────────

function parseScore(text) {
  // Match patterns: "分数: 85", "评分: 90/100", "得分: 75分", "分数：85"
  const patterns = [/分数[：:]\s*(\d+)/, /评分[：:]\s*(\d+)/, /得分[：:]\s*(\d+)/, /(\d+)\s*分/];
  for (const re of patterns) {
    const m = text.match(re);
    if (m) { const s = parseInt(m[1]); if (s >= 0 && s <= 100) return s; }
  }
  return null;
}

function execPromiseCwd(cmd, cwd, timeout = 120000) {
  return new Promise((resolve) => {
    exec(cmd, { cwd, timeout, windowsHide: true, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
      resolve({ ok: !err, stdout: stdout.trim(), stderr: stderr.trim(), code: err?.code });
    });
  });
}

function resolveExistingDir(dir) {
  if (!dir || !String(dir).trim()) return null;
  const resolved = path.resolve(String(dir).trim());
  if (!fs.existsSync(resolved)) return null;
  const st = fs.statSync(resolved);
  return st.isDirectory() ? fs.realpathSync(resolved) : null;
}

function backupProjectDirectory(projectDir) {
  const base = path.basename(projectDir).replace(/[^a-zA-Z0-9._-]+/g, '_') || 'project';
  const stamp = new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14);
  const zipName = `${base}_pipeline_backup_${stamp}.zip`;
  const zipPath = path.join(SHARED_OUT, zipName);
  execFileSync('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-Command',
    'Compress-Archive -LiteralPath $env:DASH_PROJECT_SRC -DestinationPath $env:DASH_PROJECT_ZIP -Force'
  ], {
    timeout: 180000,
    windowsHide: true,
    env: { ...process.env, DASH_PROJECT_SRC: projectDir, DASH_PROJECT_ZIP: zipPath }
  });
  const config = loadConfig();
  const port = config.server.port || 3456;
  return { zipPath, zipName, url: `${publicBaseUrl(port)}/files/${encodeURIComponent(zipName)}` };
}

function getProjectDiff(projectDir) {
  try {
    const status = execFileSync('git', ['-C', projectDir, 'status', '--short'], { timeout: 10000, windowsHide: true }).toString().trim();
    const stat = execFileSync('git', ['-C', projectDir, 'diff', '--stat'], { timeout: 10000, windowsHide: true }).toString().trim();
    const diff = execFileSync('git', ['-C', projectDir, 'diff', '--', '.'], { timeout: 20000, windowsHide: true, maxBuffer: 3 * 1024 * 1024 }).toString();
    return [
      status ? `git status:\n${status}` : 'git status: clean',
      stat ? `git diff --stat:\n${stat}` : '',
      diff ? `git diff:\n${compactAgentText(diff, 12000)}` : ''
    ].filter(Boolean).join('\n\n');
  } catch {
    const manifest = listProjectFiles(projectDir, 220).join('\n');
    return `项目未检测到可用 git diff，文件清单如下：\n${manifest}`;
  }
}

function formatReviewFeedback(reviews) {
  return (reviews || []).map(r => {
    const score = r.score ?? '?';
    return `[${r.reviewerName} ${score}/100 ${r.passed ? '通过' : '不通过'}]\n${compactAgentText(r.feedback, 1600)}`;
  }).join('\n\n');
}

function dashboardKeyFilesChangedSinceBackup(backupDir) {
  const files = ['server.js', 'public/index.html', 'config.json', 'scripts/run-codex.ps1'];
  return files.some(rel => {
    const current = path.join(__dirname, rel);
    const backed = path.join(backupDir, rel);
    try {
      if (!fs.existsSync(current) || !fs.existsSync(backed)) return fs.existsSync(current) !== fs.existsSync(backed);
      return fs.readFileSync(current).compare(fs.readFileSync(backed)) !== 0;
    } catch {
      return false;
    }
  });
}

async function validateDashboardSyntax() {
  const serverCheck = await execPromise('node --check server.js', 30000);
  if (!serverCheck.ok) return { ok: false, error: serverCheck.stderr || serverCheck.stdout || 'server.js 语法检查失败' };
  try {
    const html = fs.readFileSync(path.join(__dirname, 'public', 'index.html'), 'utf-8');
    const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map(m => m[1]);
    for (const script of scripts) new Function(script);
    return { ok: true, detail: `server.js 与 ${scripts.length} 个内联脚本解析通过` };
  } catch (e) {
    return { ok: false, error: `public/index.html 脚本解析失败: ${e.message}` };
  }
}

function contentPublishPackageUrl(filename, config) {
  const port = config.server.port || 3456;
  return `${publicBaseUrl(port)}/files/${encodeURIComponent(filename)}`;
}

function htmlEscape(text) {
  return String(text || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function stripMdInline(text) {
  return String(text || '')
    .replace(/!\[[^\]]*]\([^)]+\)/g, '')
    .replace(/\[([^\]]+)]\([^)]+\)/g, '$1')
    .replace(/[`*_>#]/g, '')
    .replace(/^\s*[-*]\s+/gm, '')
    .trim();
}

function pickContentTitle(topic, copyText, finalText) {
  const text = `${finalText || ''}\n${copyText || ''}`;
  const boldNumbered = text.match(/\d+[.、]\s*\*\*([^*\n]{8,80})\*\*/);
  if (boldNumbered) return stripMdInline(boldNumbered[1]).slice(0, 80);
  const quoted = text.match(/^>\s*([^\n]{8,80})$/m);
  if (quoted) return stripMdInline(quoted[1]).slice(0, 80);
  const bold = text.match(/\*\*([^*\n]{8,80})\*\*/);
  if (bold) return stripMdInline(bold[1]).slice(0, 80);
  return stripMdInline(topic || '小红书发布预览').slice(0, 80);
}

function pickContentBody(copyText, finalText) {
  let text = finalText || copyText || '';
  const bodyMatch = text.match(/(?:最终正文|正文)\s*[：:\n]([\s\S]+)/);
  if (bodyMatch) text = bodyMatch[1];
  const stopWords = ['最终标签', '标签', '配图', '发布前确认', '当前状态', '确认清单'];
  for (const word of stopWords) {
    const idx = text.indexOf(word);
    if (idx > 180) text = text.slice(0, idx);
  }
  text = stripMdInline(text)
    .replace(/^标题候选[\s\S]*?(?=\n{2,}|$)/, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  if (text.length < 120 && copyText) text = stripMdInline(copyText).slice(0, 1200);
  return text.slice(0, 1600);
}

function pickContentTags(copyText, finalText) {
  const tags = [...String(`${finalText || ''}\n${copyText || ''}`).matchAll(/#([A-Za-z0-9\u4e00-\u9fa5]+)/g)]
    .map(m => `#${m[1]}`);
  return [...new Set(tags)].slice(0, 10);
}

function pickImageIdeas(imageText) {
  const lines = String(imageText || '').split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  const ideas = [];
  for (let i = 0; i < lines.length && ideas.length < 5; i++) {
    const line = lines[i];
    const isTitle = /^\*\*[^*]{2,40}\*\*/.test(line) || /^#{2,4}\s+/.test(line);
    if (!isTitle) continue;
    const name = stripMdInline(line).replace(/[：:].*$/, '').replace(/[—–-].*$/, '').trim();
    let desc = '';
    for (let j = i + 1; j < Math.min(i + 7, lines.length); j++) {
      const clean = stripMdInline(lines[j]).replace(/^画面[：:]\s*/, '').trim();
      if (clean.length >= 18) {
        desc = clean;
        break;
      }
    }
    if (name && desc && !ideas.find(x => x.name === name)) ideas.push({ name, desc });
  }
  if (ideas.length === 0) {
    ideas.push(
      { name: '封面图', desc: '围绕主题生成一张醒目的封面视觉，突出核心卖点和场景。' },
      { name: '正文配图', desc: '用卡片、流程和场景图补充正文信息，方便读者快速理解。' }
    );
  }
  return ideas.slice(0, 5);
}

function buildXhsPreviewHtml({ topic, copyText, imageText, finalText }) {
  const title = pickContentTitle(topic, copyText, finalText);
  const body = pickContentBody(copyText, finalText);
  const tags = pickContentTags(copyText, finalText);
  const ideas = pickImageIdeas(imageText);
  const paragraphs = body.split(/\n{2,}/).map(p => p.trim()).filter(Boolean).slice(0, 14)
    .map(p => `<p>${htmlEscape(p).replace(/\n/g, '<br>')}</p>`).join('');
  const ideaCards = ideas.map((it, i) => `
    <div class="shot">
      <div class="shot-art">${i === 0 ? '封面' : `图${i}`}</div>
      <div><b>${htmlEscape(it.name)}</b><small>${htmlEscape(it.desc).slice(0, 110)}</small></div>
    </div>
  `).join('');
  return `<!doctype html><html><head><meta charset="utf-8"><style>
*{box-sizing:border-box}body{margin:0;background:#f4f4f7;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",Arial,sans-serif;color:#232323}.wrap{width:900px;margin:0 auto;padding:34px 0 46px}.phone{width:430px;margin:0 auto;background:#fff;border-radius:34px;box-shadow:0 30px 80px rgba(17,24,39,.20);overflow:hidden;border:1px solid #ececf1}.top{height:56px;display:flex;align-items:center;justify-content:space-between;padding:0 20px;border-bottom:1px solid #f0f0f2;font-size:14px;color:#555}.brand{font-weight:800;color:#ff2442;letter-spacing:.5px}.cover{height:520px;position:relative;overflow:hidden;background:linear-gradient(145deg,#fdf2f5 0%,#e9f7ff 52%,#fff8e7 100%)}.grid{position:absolute;inset:0;background-image:linear-gradient(rgba(255,36,66,.09) 1px,transparent 1px),linear-gradient(90deg,rgba(255,36,66,.09) 1px,transparent 1px);background-size:28px 28px}.bubble{position:absolute;border-radius:999px}.b1{width:180px;height:180px;background:#ffccd7;left:-38px;top:42px}.b2{width:220px;height:220px;background:#c8eaff;right:-70px;bottom:38px}.desk{position:absolute;left:55px;right:55px;bottom:58px;height:128px;background:#fff;border:4px solid #222;border-radius:65px;box-shadow:0 16px 0 rgba(35,35,35,.08)}.bot{position:absolute;width:82px;height:108px}.bot:before{content:"";position:absolute;left:13px;top:0;width:56px;height:48px;border-radius:20px;background:#fff;border:4px solid #222}.bot:after{content:"";position:absolute;left:2px;top:44px;width:78px;height:58px;border-radius:24px;background:var(--c);border:4px solid #222}.bot i{position:absolute;left:29px;top:20px;width:8px;height:8px;background:#222;border-radius:50%;box-shadow:17px 0 #222;z-index:2}.bot span{position:absolute;left:19px;top:72px;font-size:11px;font-weight:800;z-index:2}.bot1{--c:#72ddff;left:86px;bottom:135px}.bot2{--c:#ffb9c8;left:174px;bottom:174px}.bot3{--c:#ffd76a;right:84px;bottom:135px}.card{position:absolute;background:#fff;border:3px solid #222;border-radius:16px;padding:10px 13px;font-weight:800;font-size:18px;box-shadow:7px 7px 0 rgba(34,34,34,.10)}.c1{left:44px;top:74px;transform:rotate(-8deg)}.c2{right:54px;top:108px;transform:rotate(7deg)}.c3{left:110px;top:196px;transform:rotate(3deg);color:#ff2442}.cover-title{position:absolute;left:30px;right:30px;top:300px;text-align:center;font-size:32px;line-height:1.18;font-weight:900;color:#171717;text-shadow:0 2px 0 rgba(255,255,255,.9)}.content{padding:18px 22px 26px}.author{display:flex;align-items:center;gap:10px;margin-bottom:12px}.avatar{width:38px;height:38px;border-radius:50%;background:linear-gradient(135deg,#ff2442,#ff9db0);display:grid;place-items:center;color:#fff;font-weight:900}.name{font-weight:800}.meta{font-size:12px;color:#999}.title{font-size:22px;line-height:1.3;font-weight:900;margin:10px 0 12px}.text{font-size:16px;line-height:1.72;color:#333}.text p{margin:0 0 13px}.shots{display:grid;gap:10px;margin:18px 0}.shot{display:flex;gap:11px;padding:10px;border-radius:16px;background:#fafafa;border:1px solid #eee}.shot-art{width:76px;height:76px;border-radius:14px;display:grid;place-items:center;flex:none;background:linear-gradient(135deg,#ffe0e7,#d9f3ff);font-weight:900;color:#ff2442}.shot small{display:block;margin-top:5px;line-height:1.45;color:#666}.tags{display:flex;flex-wrap:wrap;gap:8px;margin-top:15px}.tags span{color:#3264d9;background:#f4f7ff;border-radius:999px;padding:5px 8px;font-size:13px}.actions{border-top:1px solid #f0f0f2;display:flex;justify-content:space-around;padding:13px;color:#777;font-size:14px}.note{width:430px;margin:16px auto 0;color:#666;font-size:13px;text-align:center}
  </style></head><body><div class="wrap"><div class="phone"><div class="top"><span>9:41</span><span class="brand">小红书预览</span><span>•••</span></div><section class="cover"><div class="grid"></div><div class="bubble b1"></div><div class="bubble b2"></div><div class="card c1">策划</div><div class="card c2">执行</div><div class="card c3">审核</div><div class="desk"></div><div class="bot bot1"><i></i><span>PM</span></div><div class="bot bot2"><i></i><span>写作</span></div><div class="bot bot3"><i></i><span>配图</span></div><div class="cover-title">${htmlEscape(title)}</div></section><section class="content"><div class="author"><div class="avatar">AI</div><div><div class="name">AI Agent Dashboard</div><div class="meta">发布前预览 · 待确认</div></div></div><div class="title">${htmlEscape(title)}</div><div class="text">${paragraphs}</div><div class="shots">${ideaCards}</div><div class="tags">${tags.map(t => `<span>${htmlEscape(t)}</span>`).join('')}</div></section><div class="actions"><span>♡ 收藏</span><span>💬 评论</span><span>↗ 分享</span></div></div><div class="note">${htmlEscape(topic || '内容发布')} · 自动生成预览图</div></div></body></html>`;
}

async function generateContentPublishPreview({ platform, topic, copyText, imageText, finalText }, config) {
  if (!String(platform || '').includes('小红书')) return null;
  const stamp = Date.now();
  const htmlName = `content_preview_${stamp}.html`;
  const pngName = `content_preview_${stamp}.png`;
  const htmlPath = path.join(SHARED_OUT, htmlName);
  const pngPath = path.join(SHARED_OUT, pngName);
  fs.writeFileSync(htmlPath, buildXhsPreviewHtml({ topic, copyText, imageText, finalText }), 'utf-8');
  const pageUrl = pathToFileURL(htmlPath).href;
  const cmd = `npx --yes playwright screenshot --full-page "${pageUrl}" "${pngPath}"`;
  const shot = await execPromise(cmd, 120000);
  if (!shot.ok || !fs.existsSync(pngPath) || fs.statSync(pngPath).size < 1024) {
    return {
      ok: false,
      htmlUrl: contentPublishPackageUrl(htmlName, config),
      error: compactAgentText(shot.stderr || shot.stdout || '截图生成失败', 800)
    };
  }
  return {
    ok: true,
    htmlUrl: contentPublishPackageUrl(htmlName, config),
    imageUrl: contentPublishPackageUrl(pngName, config),
    imageName: pngName,
    htmlName
  };
}

async function runContentPublishWorkflow({ platform, topic, copyAgent, imageAgent, integratorAgent, reviewerAgent = null, coordinator = null, publishMode = 'draft', feishuNotify = true, source = 'workflow' }, config) {
  const currentTopic = `${platform || '内容'}发布: ${topic}`;
  const modeText = publishMode === 'auto'
    ? '尝试自动发布（如果没有平台授权，则降级为待确认草稿）'
    : (publishMode === 'manual' ? '生成可复制发布包' : '生成草稿，主人确认后发布');

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `📣 内容发布流水线启动\n平台: ${platform}\n主题: ${topic}\n协调: ${coordinator ? coordinator.icon + ' ' + coordinator.name : '系统'}\n文案: ${copyAgent.icon || ''} ${copyAgent.name}\n图片: ${imageAgent.icon || ''} ${imageAgent.name}\n整合: ${integratorAgent.icon || ''} ${integratorAgent.name}${reviewerAgent ? `\n审核: ${reviewerAgent.icon || ''} ${reviewerAgent.name}` : ''}\n发布方式: ${modeText}`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: currentTopic
  });
  if (feishuNotify) notifyFeishu(`📣 内容发布启动: ${topic}`, `平台: ${platform}\n文案: ${copyAgent.name}\n图片: ${imageAgent.name}\n整合: ${integratorAgent.name}\n发布方式: ${modeText}`);

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `✍️ ${copyAgent.name} 正在准备 ${platform} 文案...`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: currentTopic
  });
  const copyPrompt = `你是${platform}内容文案 agent。请围绕主题写一篇可发布草稿。\n\n主题：${topic}\n平台：${platform}\n\n要求：\n1. 输出标题 3 个候选。\n2. 输出正文，适合${platform}语气，结构清晰。\n3. 输出 8-12 个标签。\n4. 不要声称已经真实发布。\n5. 如果涉及产品/系统能力，写得具体、可信、适合用户直接审核。`;
  const copyStart = Date.now();
  const copyResult = await runAgentChat(copyAgent, copyPrompt, config);
  const copyText = copyResult.ok ? copyResult.stdout : `文案生成失败：${copyResult.stderr || copyResult.stdout || '无响应'}`;
  addChatMessage({
    id: crypto.randomUUID(),
    from: copyAgent.id,
    fromName: `${copyAgent.icon || ''} ${copyAgent.name} (文案)`,
    content: compactAgentText(copyText, 3500),
    timestamp: new Date().toISOString(),
    responseTime: Date.now() - copyStart,
    type: 'workflow',
    topic: currentTopic
  });

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `🖼️ ${imageAgent.name} 正在准备配图方案...`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: currentTopic
  });
  const imagePrompt = `你是${platform}配图 agent。请基于主题和文案，输出可执行的配图/封面方案。\n\n主题：${topic}\n文案草稿：\n${compactAgentText(copyText, 2200)}\n\n要求：\n1. 输出封面图方案 1 个。\n2. 输出正文配图 3-5 张的画面说明。\n3. 给出每张图的中文生成提示词，适合后续图像生成或设计师执行。\n4. 不要声称已经生成真实图片文件，除非你确实返回了可访问图片链接。`;
  const imageStart = Date.now();
  const imageResult = await runAgentChat(imageAgent, imagePrompt, config);
  const imageText = imageResult.ok ? imageResult.stdout : `配图方案生成失败：${imageResult.stderr || imageResult.stdout || '无响应'}`;
  addChatMessage({
    id: crypto.randomUUID(),
    from: imageAgent.id,
    fromName: `${imageAgent.icon || ''} ${imageAgent.name} (配图)`,
    content: compactAgentText(imageText, 3500),
    timestamp: new Date().toISOString(),
    responseTime: Date.now() - imageStart,
    type: 'workflow',
    topic: currentTopic
  });

  let reviewText = '';
  if (reviewerAgent) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `🔍 ${reviewerAgent.name} 正在审核文案和配图方案...`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: currentTopic
    });
    const reviewPrompt = `你是内容审核 agent。请审核以下${platform}发布材料，指出风险和修改建议，最后给出是否建议发布。\n\n主题：${topic}\n\n文案：\n${compactAgentText(copyText, 2600)}\n\n配图方案：\n${compactAgentText(imageText, 2600)}\n\n输出：1.是否建议发布 2.必须修改 3.可选优化 4.最终评分 0-100。`;
    const reviewStart = Date.now();
    const reviewResult = await runAgentChat(reviewerAgent, reviewPrompt, config);
    reviewText = reviewResult.ok ? reviewResult.stdout : `审核失败：${reviewResult.stderr || reviewResult.stdout || '无响应'}`;
    addChatMessage({
      id: crypto.randomUUID(),
      from: reviewerAgent.id,
      fromName: `${reviewerAgent.icon || ''} ${reviewerAgent.name} (审核)`,
      content: compactAgentText(reviewText, 3000),
      timestamp: new Date().toISOString(),
      responseTime: Date.now() - reviewStart,
      type: 'workflow',
      topic: currentTopic
    });
  }

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `🧩 ${integratorAgent.name} 正在整合为最终发布包...`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: currentTopic
  });
  const integratePrompt = `你是内容发布整合 agent。请把文案、配图方案和审核意见整合成给主人确认的最终${platform}发布包。\n\n主题：${topic}\n发布方式：${modeText}\n\n文案草稿：\n${compactAgentText(copyText, 3000)}\n\n配图方案：\n${compactAgentText(imageText, 3000)}\n\n${reviewText ? `审核意见：\n${compactAgentText(reviewText, 2200)}\n\n` : ''}要求：\n1. 输出最终标题。\n2. 输出最终正文。\n3. 输出标签。\n4. 输出配图清单和每张图的用途。\n5. 输出发布前确认清单。\n6. 明确说明当前状态是“待主人确认”，不要声称已经发布。`;
  const integrateStart = Date.now();
  const integrateResult = await runAgentChat(integratorAgent, integratePrompt, config);
  const finalText = integrateResult.ok ? integrateResult.stdout : `整合失败：${integrateResult.stderr || integrateResult.stdout || '无响应'}`;
  addChatMessage({
    id: crypto.randomUUID(),
    from: integratorAgent.id,
    fromName: `${integratorAgent.icon || ''} ${integratorAgent.name} (整合发布)`,
    content: compactAgentText(finalText, 5000),
    timestamp: new Date().toISOString(),
    responseTime: Date.now() - integrateStart,
    type: 'workflow',
    topic: currentTopic
  });

  let preview = null;
  if (String(platform || '').includes('小红书')) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: '🖼️ 正在生成小红书发布预览图...',
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: currentTopic
    });
    preview = await generateContentPublishPreview({ platform, topic, copyText, imageText, finalText }, config);
  }

  const safeBase = String(topic || platform).replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, '_').slice(0, 50) || 'content_publish';
  const filename = `content_publish_${Date.now()}_${safeBase}.md`;
  const previewText = preview?.ok
    ? `## 发布预览图\n![小红书发布预览图](${preview.imageUrl})\n\n预览图链接：${preview.imageUrl}\n预览HTML：${preview.htmlUrl}\n\n`
    : (preview ? `## 发布预览图\n预览图生成失败：${preview.error || '未知错误'}\n预览HTML：${preview.htmlUrl || '-'}\n\n` : '');
  const packageText = `# ${platform}发布包\n\n## 主题\n${topic}\n\n## 状态\n待主人确认。当前系统未检测平台授权，不自动真实发布。\n\n${previewText}## 文案输出\n${copyText}\n\n## 配图输出\n${imageText}\n\n${reviewText ? `## 审核意见\n${reviewText}\n\n` : ''}## 最终整合稿\n${finalText}\n`;
  fs.writeFileSync(path.join(SHARED_OUT, filename), packageText, 'utf-8');
  const packageUrl = contentPublishPackageUrl(filename, config);
  const status = publishMode === 'auto' ? 'pending-auth' : 'pending-confirm';

  const previewLine = preview?.ok
    ? `\n预览图: ${preview.imageUrl}\n![小红书发布预览图](${preview.imageUrl})`
    : (preview ? `\n预览图: 生成失败，${preview.error || '请查看服务日志'}` : '');
  const endText = `📣 内容发布流水线完成\n平台: ${platform}\n主题: ${topic}\n状态: ${status === 'pending-auth' ? '需要平台授权/登录后才能自动发布' : '待主人确认'}\n发布包: ${packageUrl}${previewLine}`;
  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: endText,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: currentTopic
  });
  if (feishuNotify) notifyFeishu(`📣 内容发布待确认: ${topic}`, `${endText}\n\n整合人: ${integratorAgent.name}\n\n${compactAgentText(finalText, 1200)}`);

  return { ok: true, status, packageUrl, previewUrl: preview?.imageUrl || null, previewHtmlUrl: preview?.htmlUrl || null, previewError: preview?.ok === false ? preview.error : null, copyText, imageText, reviewText, finalText };
}

function extractPptSlides(deckText, topic, expectedCount = 10) {
  const text = String(deckText || '').replace(/\r/g, '');
  const lines = text.split('\n');
  const slides = [];
  let current = null;
  const slideRe = /^(?:#{1,4}\s*)?(?:第\s*(\d+)\s*[页张]|幻灯片\s*(\d+)|slide\s*(\d+))\s*[：:.\-、]?\s*(.*)$/i;
  for (const raw of lines) {
    const line = raw.trim();
    const m = line.match(slideRe);
    if (m) {
      if (current) slides.push(current);
      current = { title: (m[4] || '').trim() || `第${slides.length + 1}页`, lines: [] };
      continue;
    }
    if (current && line) current.lines.push(line);
  }
  if (current) slides.push(current);

  if (slides.length === 0) {
    const blocks = text.split(/\n{2,}/).map(x => x.trim()).filter(Boolean);
    for (const block of blocks.slice(0, Math.max(1, expectedCount))) {
      const blockLines = block.split('\n').map(x => x.trim()).filter(Boolean);
      if (!blockLines.length) continue;
      slides.push({
        title: stripMdInline(blockLines[0]).slice(0, 72) || `第${slides.length + 1}页`,
        lines: blockLines.slice(1, 8)
      });
    }
  }

  if (slides.length === 0) {
    slides.push({ title: topic || 'PPT方案', lines: ['请查看完整制作包。'] });
  }

  return slides.slice(0, 24).map((s, idx) => ({
    no: idx + 1,
    title: stripMdInline(s.title || `第${idx + 1}页`).slice(0, 90),
    bullets: (s.lines || [])
      .map(x => stripMdInline(x).replace(/^[-*•]\s*/, '').trim())
      .filter(Boolean)
      .slice(0, 6)
  }));
}

function buildPptPreviewHtml({ topic, audience, goal, style, finalText, slideCount }) {
  const slides = extractPptSlides(finalText, topic, slideCount);
  const pages = slides.map(slide => `
    <section class="page slide-page">
      <div class="slide-top">
        <div class="badge">Slide ${slide.no.toString().padStart(2, '0')}</div>
        <div class="chip">${htmlEscape(style || '商务清晰')}</div>
      </div>
      <div class="slide-body">
        <div class="slide-main">
          <h2>${htmlEscape(slide.title)}</h2>
          <ul>${slide.bullets.map(b => `<li>${htmlEscape(b)}</li>`).join('')}</ul>
        </div>
        <aside class="slide-side">
          <div class="side-card"><span>受众</span><strong>${htmlEscape(audience || '未指定')}</strong></div>
          <div class="side-card"><span>目标</span><strong>${htmlEscape(goal || '未指定')}</strong></div>
          <div class="side-card"><span>页数</span><strong>${slides.length} 页</strong></div>
        </aside>
      </div>
      <div class="page-foot">AI Agent Dashboard · PPT 交付预览</div>
    </section>
  `).join('');
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${htmlEscape(topic || 'PPT预览')}</title><style>
*{box-sizing:border-box}html,body{margin:0;padding:0;background:#d8dee9;font-family:"Microsoft YaHei","Segoe UI",Arial,sans-serif;color:#101828}@page{size:A4 landscape;margin:10mm}body{padding:22px}.deck{display:grid;gap:22px}.page{width:100%;min-height:690px;border-radius:24px;overflow:hidden;position:relative;page-break-after:always;break-after:page;box-shadow:0 18px 45px rgba(15,23,42,.16)}.page:last-child{page-break-after:auto;break-after:auto}.cover{padding:44px 54px;background:linear-gradient(135deg,#17324d 0%,#1a6c7f 55%,#d78d35 100%);color:#f8fbff;display:flex;flex-direction:column;justify-content:space-between}.cover:before{content:"";position:absolute;right:-60px;top:-70px;width:280px;height:280px;border-radius:50%;background:rgba(255,255,255,.10)}.cover:after{content:"";position:absolute;left:-30px;bottom:-90px;width:300px;height:220px;border-radius:45% 55% 60% 40%;background:rgba(255,255,255,.08)}.eyebrow{font-size:16px;letter-spacing:.12em;text-transform:uppercase;color:#c8f3ef;font-weight:700}.cover h1{margin:18px 0 20px;font-size:46px;line-height:1.12;max-width:900px}.cover-grid{display:grid;grid-template-columns:1.4fr .9fr;gap:18px;position:relative;z-index:1}.cover-card{background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.18);border-radius:20px;padding:18px 20px;backdrop-filter:blur(8px)}.cover-card span{display:block;font-size:13px;color:#d9f7f4;margin-bottom:8px}.cover-card strong{display:block;font-size:22px;line-height:1.35}.cover-tags{display:flex;gap:10px;flex-wrap:wrap;margin-top:20px}.cover-tags b{display:inline-flex;align-items:center;padding:8px 14px;border-radius:999px;background:rgba(11,18,32,.22);border:1px solid rgba(255,255,255,.18);font-size:14px}.slide-page{padding:32px 34px;background:linear-gradient(180deg,#fcfdff 0%,#eef4fb 100%)}.slide-page:before{content:"";position:absolute;left:0;top:0;right:0;height:10px;background:linear-gradient(90deg,#1d4ed8,#0f766e,#eab308)}.slide-top{display:flex;justify-content:space-between;align-items:center;margin-bottom:24px}.badge,.chip{display:inline-flex;align-items:center;padding:8px 14px;border-radius:999px;font-weight:700;font-size:14px}.badge{background:#dbeafe;color:#1d4ed8}.chip{background:#ecfdf3;color:#047857}.slide-body{display:grid;grid-template-columns:1.45fr .75fr;gap:24px;align-items:stretch}.slide-main{background:#fff;border:1px solid #dbe3ef;border-radius:22px;padding:30px 30px 26px;box-shadow:0 12px 28px rgba(15,23,42,.08)}.slide-main h2{margin:0 0 22px;font-size:34px;line-height:1.2;color:#0f172a}.slide-main ul{margin:0;padding-left:24px;display:grid;gap:14px}.slide-main li{font-size:22px;line-height:1.55}.slide-side{display:grid;gap:16px}.side-card{background:#0f172a;color:#eff6ff;border-radius:20px;padding:22px 20px;min-height:146px;display:flex;flex-direction:column;justify-content:space-between;box-shadow:0 10px 22px rgba(15,23,42,.14)}.side-card span{font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#93c5fd}.side-card strong{font-size:24px;line-height:1.35}.page-foot{position:absolute;left:34px;right:34px;bottom:18px;display:flex;justify-content:flex-end;font-size:13px;color:#64748b}.cover-foot{display:flex;justify-content:space-between;align-items:flex-end;position:relative;z-index:1}.cover-foot small{font-size:14px;color:#d2edf6}@media screen and (max-width:1100px){body{padding:12px}.page{min-height:auto}.cover-grid,.slide-body{grid-template-columns:1fr}.slide-main li{font-size:18px}.cover h1{font-size:34px}}
  </style></head><body><main class="deck"><section class="page cover"><div><div class="eyebrow">PPT Delivery Preview</div><h1>${htmlEscape(topic || 'PPT制作与审核')}</h1><div class="cover-tags"><b>受众：${htmlEscape(audience || '未指定')}</b><b>目标：${htmlEscape(goal || '未指定')}</b><b>风格：${htmlEscape(style || '商务清晰')}</b><b>${slides.length} 页</b></div></div><div class="cover-grid"><div class="cover-card"><span>核心叙事</span><strong>${htmlEscape((slides[0] && slides[0].title) || topic || '请查看完整交付')}</strong></div><div class="cover-card"><span>交付说明</span><strong>本预览用于 PDF / HTML 快速审阅，最终内容以工作流交付包为准。</strong></div></div><div class="cover-foot"><small>AI Agent Dashboard 自动生成</small><small>${htmlEscape(style || '商务清晰')} · Landscape PDF</small></div></section>${pages}</main></body></html>`;
}

async function generatePdfFromHtml(htmlPath, pdfPath) {
  const puppeteer = require('puppeteer');
  const browser = await puppeteer.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.goto(pathToFileURL(htmlPath).href, { waitUntil: 'networkidle0' });
    await page.pdf({
      path: pdfPath,
      landscape: true,
      format: 'A4',
      printBackground: true,
      preferCSSPageSize: true,
      margin: { top: '8mm', right: '8mm', bottom: '8mm', left: '8mm' }
    });
  } finally {
    await browser.close();
  }
}

async function runPptWorkflow({ topic, audience = '', goal = '', slideCount = 10, style = '商务清晰', outputFormat = 'markdown', outlineAgent, makerAgent, reviewerAgent, finalizerAgent = null, passScore = 85, maxRetries = 2, feishuNotify = true }, config) {
  const currentTopic = `PPT制作: ${topic}`;
  const fmtLabel = outputFormat === 'pptx' ? 'PPTX (python-pptx脚本 + Markdown预览)' : outputFormat === 'md+pptx' ? 'Markdown + PPTX 双输出' : 'Markdown 文稿';
  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `📊 PPT制作与审核工作流启动\n主题: ${topic}\n受众: ${audience || '未指定'}\n目标: ${goal || '未指定'}\n页数: ${slideCount}\n风格: ${style}\n输出格式: ${fmtLabel}\n策划: ${outlineAgent.icon || ''} ${outlineAgent.name}\n制作: ${makerAgent.icon || ''} ${makerAgent.name}\n审核: ${reviewerAgent.icon || ''} ${reviewerAgent.name}${finalizerAgent ? `\n定稿: ${finalizerAgent.icon || ''} ${finalizerAgent.name}` : ''}\n通过分: ${passScore} | 最多返修 ${maxRetries} 轮`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: currentTopic
  });
  if (feishuNotify) notifyFeishu(`📊 PPT工作流启动: ${topic}`, `制作: ${makerAgent.name}\n审核: ${reviewerAgent.name}\n页数: ${slideCount}\n输出格式: ${fmtLabel}\n通过分: ${passScore}`);

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `🧭 ${outlineAgent.name} 正在规划 PPT 大纲...`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: currentTopic
  });
  const fmtOutlineNote = outputFormat === 'pptx'
    ? `\n\n⚠️ 输出格式声明：PPTX。最终交付物是 python-pptx 生成脚本，大纲需为每页标注图表类型和布局建议，以便制作 agent 写出精确的 slide.layout / add_chart 调用。`
    : outputFormat === 'md+pptx'
    ? `\n\n⚠️ 输出格式声明：Markdown + PPTX 双输出。大纲需同时满足文案阅读和 python-pptx 制作，为每页标注：文案要点 + 图表/布局建议。`
    : '';
  const outlinePrompt = `你是PPT策划 agent。请为下面的PPT制作任务设计清晰大纲。\n\n主题：${topic}\n受众：${audience || '未指定'}\n目标：${goal || '未指定'}\n页数：${slideCount}\n视觉风格：${style}${fmtOutlineNote}\n\n请输出：\n1. 一句话核心叙事\n2. 章节结构\n3. 每页标题和关键内容\n4. 需要补充的数据/素材\n5. 审核重点。`;
  const outlineStart = Date.now();
  const outlineResult = await runAgentChat(outlineAgent, outlinePrompt, config);
  const outlineText = outlineResult.ok ? outlineResult.stdout : `大纲生成失败：${outlineResult.stderr || outlineResult.stdout || '无响应'}`;
  addChatMessage({
    id: crypto.randomUUID(),
    from: outlineAgent.id,
    fromName: `${outlineAgent.icon || ''} ${outlineAgent.name} (PPT策划)`,
    content: compactAgentText(outlineText, 3600),
    timestamp: new Date().toISOString(),
    responseTime: Date.now() - outlineStart,
    type: 'workflow',
    topic: currentTopic
  });

  let deckText = '';
  let reviewText = '';
  let finalScore = null;
  let finalPassed = false;
  let lastFeedback = '';
  const rounds = Math.max(1, Math.min(5, Number(maxRetries) || 2));

  for (let attempt = 1; attempt <= rounds; attempt++) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `🛠️ ${makerAgent.name} 正在制作第 ${attempt}/${rounds} 版 PPT 稿...`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: currentTopic
    });
    const fmtMakeNote = outputFormat === 'pptx'
      ? `\n\n⚠️ 输出格式声明：PPTX。你必须输出完整的 python-pptx 生成脚本（可独立运行），并附 Markdown 预览。脚本要求：\n- 使用 from pptx import Presentation; from pptx.util import Inches, Pt\n- 每页调用 slide_layout 或 add_slide，设置标题、正文、图表\n- 末尾 prs.save('output.pptx')\n- 脚本必须完整可运行，不能有占位符或省略号。`
      : outputFormat === 'md+pptx'
      ? `\n\n⚠️ 输出格式声明：Markdown + PPTX 双输出。你必须同时输出：\n1. 完整 Markdown 逐页文稿（与原来一致）\n2. 完整 python-pptx 生成脚本（可独立运行）\n两个输出必须内容一致，脚本不得有占位符。`
      : '';
    const makePrompt = `你是PPT制作 agent。请基于策划大纲制作完整PPT逐页稿。\n\n主题：${topic}\n受众：${audience || '未指定'}\n目标：${goal || '未指定'}\n页数：${slideCount}\n视觉风格：${style}${fmtMakeNote}\n\n策划大纲：\n${compactAgentText(outlineText, 3600)}\n\n${lastFeedback ? `上一轮审核意见，需要逐条整改：\n${compactAgentText(lastFeedback, 2600)}\n\n` : ''}输出要求：\n1. 使用 Markdown。\n2. 按"第1页：标题"到"第${slideCount}页：标题"组织。\n3. 每页必须包含：页面标题、核心内容3-5条、视觉/图表建议、讲稿备注。\n4. 最后输出"待补素材清单"和"交付检查清单"。${outputFormat === 'markdown' ? '\n5. 不要声称已经真实制作成PPTX文件。' : ''}`;
    const makeStart = Date.now();
    const makeResult = await runAgentChat(makerAgent, makePrompt, config);
    deckText = makeResult.ok ? makeResult.stdout : `PPT制作失败：${makeResult.stderr || makeResult.stdout || '无响应'}`;
    addChatMessage({
      id: crypto.randomUUID(),
      from: makerAgent.id,
      fromName: `${makerAgent.icon || ''} ${makerAgent.name} (PPT制作第${attempt}版)`,
      content: compactAgentText(deckText, 5200),
      timestamp: new Date().toISOString(),
      responseTime: Date.now() - makeStart,
      type: 'workflow',
      topic: currentTopic
    });

    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `🔍 ${reviewerAgent.name} 正在审核第 ${attempt} 版 PPT 稿...`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: currentTopic
    });
    const fmtReviewNote = outputFormat !== 'markdown'
      ? `\n\n⚠️ 输出格式声明：${outputFormat === 'pptx' ? 'PPTX（python-pptx脚本）' : 'Markdown + PPTX 双输出'}。审核时需额外检查：\n- python-pptx 脚本是否完整可运行（无占位符、导入正确、prs.save 存在）\n- 脚本生成的内容是否与 Markdown 预览一致。`
      : '';
    const reviewPrompt = `你是PPT审核 agent。请审核下面的PPT逐页稿。\n\n主题：${topic}\n受众：${audience || '未指定'}\n目标：${goal || '未指定'}\n页数要求：${slideCount}\n风格要求：${style}${fmtReviewNote}\n\nPPT稿：\n${compactAgentText(deckText, 9000)}\n\n请从叙事结构、受众匹配、信息完整性、页面可视化、表达清晰度、风险和事实严谨性评分。必须写”分数: X分”。然后输出：通过/不通过、必须整改项、可选优化、逐页问题。通过分为 ${passScore}。`;
    const reviewStart = Date.now();
    const reviewResult = await runAgentChat(reviewerAgent, reviewPrompt, config);
    reviewText = reviewResult.ok ? reviewResult.stdout : `审核失败：${reviewResult.stderr || reviewResult.stdout || '无响应'}`;
    finalScore = parseScore(reviewText);
    finalPassed = reviewResult.ok && finalScore !== null && finalScore >= passScore;
    addChatMessage({
      id: crypto.randomUUID(),
      from: reviewerAgent.id,
      fromName: `${reviewerAgent.icon || ''} ${reviewerAgent.name} (PPT审核第${attempt}轮)`,
      content: `📊 评分: ${finalScore ?? '?'}/100 ${finalPassed ? '✅ 通过' : '❌ 不通过'}\n${compactAgentText(reviewText, 3200)}`,
      timestamp: new Date().toISOString(),
      responseTime: Date.now() - reviewStart,
      type: 'workflow',
      topic: currentTopic
    });
    if (finalPassed) break;
    lastFeedback = reviewText;
    if (attempt < rounds) {
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `↩️ 第 ${attempt} 版未达到 ${passScore} 分，已打回给 ${makerAgent.name} 返修。`,
        timestamp: new Date().toISOString(),
        type: 'workflow',
        topic: currentTopic
      });
    }
  }

  const finalAgent = finalizerAgent || makerAgent;
  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `🧩 ${finalAgent.name} 正在整合最终 PPT 交付稿...`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: currentTopic
  });
  const fmtFinalNote = outputFormat === 'pptx'
    ? `\n\n⚠️ 输出格式声明：PPTX。最终交付物必须是完整可运行的 python-pptx 脚本。请整合制作稿和审核意见，输出：\n1. 完整 python-pptx 脚本（可独立运行，有 prs.save）\n2. Markdown 逐页预览\n3. 运行说明。`
    : outputFormat === 'md+pptx'
    ? `\n\n⚠️ 输出格式声明：Markdown + PPTX 双输出。请整合制作稿和审核意见，输出：\n1. 完整 Markdown 逐页终稿\n2. 完整 python-pptx 脚本（可独立运行，有 prs.save）\n3. 运行说明。`
    : '';
  const finalPrompt = `你是PPT定稿 agent。请把最后一版PPT稿和审核意见整合成可交付的最终PPT制作稿。\n\n主题：${topic}\n受众：${audience || '未指定'}\n目标：${goal || '未指定'}\n页数：${slideCount}\n风格：${style}${fmtFinalNote}\n\n最后一版PPT稿：\n${compactAgentText(deckText, 9000)}\n\n审核意见：\n${compactAgentText(reviewText, 4000)}\n\n请输出最终稿，按”第1页：标题”逐页列出：页面标题、核心内容、视觉/图表建议、讲稿备注。最后给出待补素材清单和给主人的审核结论。`;
  const finalStart = Date.now();
  const finalResult = await runAgentChat(finalAgent, finalPrompt, config);
  const finalText = finalResult.ok ? finalResult.stdout : deckText;
  addChatMessage({
    id: crypto.randomUUID(),
    from: finalAgent.id,
    fromName: `${finalAgent.icon || ''} ${finalAgent.name} (PPT定稿)`,
    content: compactAgentText(finalText, 5600),
    timestamp: new Date().toISOString(),
    responseTime: Date.now() - finalStart,
    type: 'workflow',
    topic: currentTopic
  });

  const safeBase = String(topic || 'ppt').replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, '_').slice(0, 50) || 'ppt';
  const stamp = Date.now();
  const mdName = `ppt_workflow_${stamp}_${safeBase}.md`;
  const htmlName = `ppt_workflow_${stamp}_${safeBase}.html`;
  const pdfName = `ppt_workflow_${stamp}_${safeBase}.pdf`;
  const pyName = outputFormat !== 'markdown' ? `ppt_workflow_${stamp}_${safeBase}.py` : null;
  const mdText = `# PPT制作与审核交付包\n\n## 主题\n${topic}\n\n## 参数\n- 受众：${audience || '未指定'}\n- 目标：${goal || '未指定'}\n- 页数：${slideCount}\n- 风格：${style}\n- 输出格式：${fmtLabel}\n- 审核分：${finalScore ?? '?'} / 100\n- 状态：${finalPassed ? '审核通过' : '需人工确认'}\n\n## 策划大纲\n${outlineText}\n\n## 审核意见\n${reviewText}\n\n## 最终PPT逐页稿\n${finalText}\n`;
  const htmlPath = path.join(SHARED_OUT, htmlName);
  const pdfPath = path.join(SHARED_OUT, pdfName);
  fs.writeFileSync(path.join(SHARED_OUT, mdName), mdText, 'utf-8');
  fs.writeFileSync(htmlPath, buildPptPreviewHtml({ topic, audience, goal, style, finalText, slideCount }), 'utf-8');
  let pdfUrl = '';
  let pdfError = '';
  try {
    await generatePdfFromHtml(htmlPath, pdfPath);
    if (fs.existsSync(pdfPath) && fs.statSync(pdfPath).size > 1024) {
      pdfUrl = contentPublishPackageUrl(pdfName, config);
    } else {
      pdfError = 'PDF 文件未生成或体积异常';
    }
  } catch (e) {
    pdfError = e.message;
  }
  let pyUrl = '';
  if (pyName) {
    const pyCode = extractPythonScript(finalText);
    if (pyCode) {
      fs.writeFileSync(path.join(SHARED_OUT, pyName), pyCode, 'utf-8');
      pyUrl = contentPublishPackageUrl(pyName, config);
    }
  }
  const packageUrl = pyUrl || contentPublishPackageUrl(mdName, config);
  const previewUrl = contentPublishPackageUrl(htmlName, config);
  const endText = `📊 PPT制作与审核工作流完成\n主题: ${topic}\n输出格式: ${fmtLabel}\n状态: ${finalPassed ? '审核通过' : '需人工确认'}\n最终评分: ${finalScore ?? '?'} / 100\n交付包: ${packageUrl}${pyUrl ? '\nPPTX脚本: ' + pyUrl : ''}${pdfUrl ? '\nPDF交付: ' + pdfUrl : (pdfError ? '\nPDF交付: 生成失败，' + pdfError : '')}\nHTML预览: ${previewUrl}`;
  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: endText,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: currentTopic
  });
  if (feishuNotify) notifyFeishu(`📊 PPT工作流完成: ${topic}`, `${endText}\n\n审核: ${reviewerAgent.name}`);

  return { ok: true, passed: finalPassed, score: finalScore, packageUrl, previewUrl, pdfUrl, pdfError, pyUrl: pyUrl || '', outlineText, reviewText, finalText };
}

app.post('/api/workflow/start', async (req, res) => {
  req.setTimeout?.(0);
  res.setTimeout?.(0);
  const config = loadConfig();
  const { coders: coderList, reviewerIds, summarizerId, task, outputFormat = '', maxRetries = 3, passScore = 80 } = req.body;

  if (!coderList?.length || !reviewerIds?.length || !task?.trim()) {
    return res.status(400).json({ error: '请选择程序员、审查员和任务描述' });
  }

  // Resolve coders
  const coders = coderList.map(c => ({ agent: findAgent(c.id), subTask: c.task })).filter(c => c.agent);
  for (const c of coders) {
    if (c.agent.disabled) return res.status(400).json({ error: `${c.agent.name} 已禁用：${c.agent.disabledReason || '不可用'}` });
  }
  if (coders.length === 0) return res.status(404).json({ error: '程序员未找到' });

  const reviewers = reviewerIds.map(id => findAgent(id)).filter(Boolean);
  for (const r of reviewers) {
    if (r.disabled) return res.status(400).json({ error: `${r.name} 已禁用：${r.disabledReason || '不可用'}` });
  }
  if (reviewers.length === 0) return res.status(400).json({ error: '至少需要一位审查员' });

  const summarizer = summarizerId ? findAgent(summarizerId) : null;
  if (summarizer?.disabled) return res.status(400).json({ error: `${summarizer.name} 已禁用：${summarizer.disabledReason || '不可用'}` });

  // ── PPTX 格式路由：自动切换到 PPT 制作与审核工作流 ──
  if (outputFormat === 'pptx' || outputFormat === 'md+pptx') {
    const makerAgent = coders[0].agent;
    const outlineAgent = coders.length >= 2 ? coders[1].agent : coders[0].agent;
    const reviewerAgent = reviewers[0];
    const finalizerAgent = reviewers.length >= 2 ? reviewers[1] : null;
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `🔄 检测到输出格式声明: ${outputFormat.toUpperCase()}，自动路由到 PPT 制作与审核工作流\n📝 主题: ${task}\n🎨 策划: ${outlineAgent.icon} ${outlineAgent.name}\n🔧 制作: ${makerAgent.icon} ${makerAgent.name}\n🔍 审核: ${reviewerAgent.icon} ${reviewerAgent.name}${finalizerAgent ? `\n📝 定稿: ${finalizerAgent.icon} ${finalizerAgent.name}` : ''}`,
      timestamp: new Date().toISOString(), type: 'workflow'
    });
    if (!chatHistory.topics.find(t => t.text === task)) {
      chatHistory.topics.push({ text: task, setAt: new Date().toISOString() });
    }
    try {
      const pptResult = await runPptWorkflow({
        topic: task.trim(),
        audience: '',
        goal: '',
        slideCount: 10,
        style: '商务清晰',
        outputFormat,
        outlineAgent,
        makerAgent,
        reviewerAgent,
        finalizerAgent,
        passScore,
        maxRetries: Math.min(maxRetries, 5),
        feishuNotify: true
      }, config);
      return res.json(pptResult);
    } catch (e) {
      addChatMessage({
        id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
        content: `❌ PPT 工作流路由失败: ${e.message}`,
        timestamp: new Date().toISOString(), type: 'workflow'
      });
      return res.status(500).json({ ok: false, error: e.message });
    }
  }

  // System message
  const coderInfo = coders.map(c => `${c.agent.icon} ${c.agent.name}: ${c.subTask}`).join('\n');
  addChatMessage({
    id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
    content: `🔗 代码审查流水线启动\n📝 项目: ${task}${outputFormat ? '\n📦 目标输出格式: ' + outputFormat : ''}\n\n👨‍💻 程序员:\n${coderInfo}\n\n🔍 审查员: ${reviewers.map(r => r.icon + ' ' + r.name).join('、')}\n🎯 通过分: ${passScore} | 最多 ${maxRetries} 轮${summarizer ? '\n📝 汇报: ' + summarizer.icon + ' ' + summarizer.name : ''}`,
    timestamp: new Date().toISOString(), type: 'workflow'
  });

  notifyFeishu(`🔗 流水线启动: ${task}`, `程序员: ${coders.map(c=>c.agent.name).join('、')}\n审查员: ${reviewers.map(r=>r.name).join('、')}\n通过分: ${passScore}`);

  if (!chatHistory.topics.find(t => t.text === task)) {
    chatHistory.topics.push({ text: task, setAt: new Date().toISOString() });
  }

  // Per-coder state: { agent, subTask, currentCode, passed, attempt }
  const coderState = coders.map(c => ({ ...c, currentCode: '', fileUrl: '', passed: false, attempt: 0 }));
  let allReviewResults = [];
  let finalPassed = false;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    const pendingCoders = coderState.filter(cs => !cs.passed);
    if (pendingCoders.length === 0) { finalPassed = true; break; }

    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `🔄 第 ${attempt}/${maxRetries} 轮 — ${pendingCoders.map(c => c.agent.name).join('、')} 编写中...`,
      timestamp: new Date().toISOString(), type: 'workflow'
    });

    // Step 1: Pending coders work in parallel across hosts, with per-host limits.
    await mapAgentsWithHostLimits(pendingCoders.map(cs => ({ agent: cs.agent, cs })), config, async ({ cs }) => {
      cs.attempt = attempt;
      addChatMessage({
        id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
        content: `👨‍💻 ${cs.agent.name} 正在编写: ${cs.subTask}`,
        timestamp: new Date().toISOString(), type: 'workflow'
      });

      let coderPrompt;
      const fmtDeclare = outputFormat ? `\n\n📦 目标输出格式: ${outputFormat}。请输出符合该格式的完整代码。` : '';
      if (attempt === 1) {
        coderPrompt = `项目总体需求: ${task}\n\n你的子任务: ${cs.subTask}${fmtDeclare}\n\n请将完整代码直接输出在聊天回复中（不要使用工具写文件，直接把代码贴出来），并说明你的实现思路。`;
      } else {
        const myFeedback = allReviewResults
          .filter(r => r.attempt === attempt - 1 && r.coderId === cs.agent.id)
          .map(r => `[${r.reviewerName} 评分:${r.score}] ${r.feedback}`).join('\n');
        coderPrompt = `你的代码未通过审查（需 ≥${passScore}分），请根据审查意见修改：\n\n${myFeedback}\n\n项目: ${task}\n子任务: ${cs.subTask}${fmtDeclare}\n\n请将完整代码直接输出在聊天回复中（不要使用工具写文件，直接把代码贴出来）。`;
      }

      const startedAt = Date.now();
      const result = await runAgentChat(cs.agent, coderPrompt, config);
      const responseTime = Date.now() - startedAt;
      cs.currentCode = result.ok ? extractCode(result.stdout) : '';

      // Save code to shared directory
      cs.fileUrl = '';
      if (result.ok && cs.currentCode) {
        const safeName = cs.agent.name.replace(/[^a-zA-Z0-9一-鿿_-]/g, '_');
        const ext = detectCodeExt(cs.currentCode);
        const fname = `R${attempt}_${safeName}_${Date.now()}.${ext}`;
        try {
          fs.writeFileSync(path.join(SHARED_OUT, fname), cs.currentCode, 'utf-8');
          cs.fileUrl = `${publicBaseUrl(config.server.port || 3456)}/files/${fname}`;
        } catch(e) { console.error('[WORKFLOW] Failed to save file:', e.message); }
      }

      addChatMessage({
        id: crypto.randomUUID(), from: cs.agent.id,
        fromName: `${cs.agent.icon} ${cs.agent.name} (第${attempt}轮)`,
        content: result.ok
          ? `📦 子任务: ${cs.subTask}\n📄 输出: ${cs.currentCode.length} 字符${cs.fileUrl ? '\n🔗 ' + cs.fileUrl : ''}\n\`\`\`\n${cs.currentCode.slice(0, 600)}${cs.currentCode.length > 600 ? '\n...（截断预览，完整代码见上方链接）' : ''}\n\`\`\``
          : `❌ 失败: ${result.stderr || '无响应'}`,
        timestamp: new Date().toISOString(), responseTime, type: 'workflow'
      });

      if (!result.ok) {
        addChatMessage({
          id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
          content: `❌ ${cs.agent.name} 未能产出代码`,
          timestamp: new Date().toISOString(), type: 'workflow'
        });
      }
    });

    // Step 2: Reviewers score each pending coder's output
    let roundAllPassed = true;
    for (const cs of pendingCoders) {
      if (!cs.currentCode) { roundAllPassed = false; continue; }

      addChatMessage({
        id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
        content: `🔍 审查: ${cs.agent.name} 的代码（${cs.subTask}）`,
        timestamp: new Date().toISOString(), type: 'workflow'
      });

      const reviewSettled = await mapAgentsWithHostLimits(reviewers, config, async (reviewer) => {
        try {
        addChatMessage({
          id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
          content: `⏳ ${reviewer.name} 正在审查 ${cs.agent.name} 的代码...`,
          timestamp: new Date().toISOString(), type: 'workflow'
        });

        // Find the file URL for this coder's latest output
        const coderFileUrl = cs.fileUrl || `${publicBaseUrl(config.server.port || 3456)}/files/`;
        const fmtDeclareReview = outputFormat ? `\n目标格式: ${outputFormat}\n` : '';
        const reviewPrompt = `请审查以下代码。\n\n程序员: ${cs.agent.name}\n子任务: ${cs.subTask}\n项目: ${task}${fmtDeclareReview}\n📄 代码文件: ${coderFileUrl}\n\n=== 代码全文 ===\n${cs.currentCode}\n\n请从功能完整性、代码质量、可运行性三个维度评分（0-100分）。\n\n必须明确写: 分数: X分\n然后写优点、问题、改进建议。`;

        const startedAt = Date.now();
        const reviewResult = await runAgentChat(reviewer, reviewPrompt, config);
        const responseTime = Date.now() - startedAt;
        const reviewText = reviewResult.ok ? reviewResult.stdout : '';
        const score = parseScore(reviewText);
        const passed = score !== null && score >= passScore;

        const reviewData = {
          reviewerId: reviewer.id, reviewerName: reviewer.name,
          coderId: cs.agent.id, coderName: cs.agent.name,
          attempt, score: score ?? '?', feedback: reviewText || reviewResult.stderr || '', passed
        };
        allReviewResults.push(reviewData);

        addChatMessage({
          id: crypto.randomUUID(), from: reviewer.id,
          fromName: `${reviewer.icon} ${reviewer.name} → ${cs.agent.name}`,
          content: `📊 评分: ${score ?? '?'}/100 ${passed ? '✅ 通过' : '❌ 不通过'}\n${(reviewText || '').slice(0, 600)}`,
          timestamp: new Date().toISOString(), responseTime, type: 'workflow'
        });
        return { status: 'fulfilled', value: reviewData };
        } catch (e) {
          return { status: 'rejected', reason: e };
        }
      });

      const reviewResults = reviewSettled.map((item, idx) => {
        if (item.status === 'fulfilled') return item.value;
        const reviewer = reviewers[idx];
        const reviewData = {
          reviewerId: reviewer.id, reviewerName: reviewer.name,
          coderId: cs.agent.id, coderName: cs.agent.name,
          attempt, score: '?', feedback: item.reason?.message || '审查异常', passed: false
        };
        allReviewResults.push(reviewData);
        addChatMessage({
          id: crypto.randomUUID(), from: reviewer.id,
          fromName: `${reviewer.icon} ${reviewer.name} → ${cs.agent.name}`,
          content: `📊 评分: ?/100 ❌ 不通过\n${reviewData.feedback}`,
          timestamp: new Date().toISOString(), responseTime: 0, type: 'workflow'
        });
        return reviewData;
      });
      cs.passed = reviewResults.length > 0 && reviewResults.every(r => r.passed);
      if (!cs.passed) roundAllPassed = false;
    }

    if (roundAllPassed) {
      finalPassed = true;
      coderState.forEach(cs => cs.passed = true);
      addChatMessage({
        id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
        content: `✅ 第 ${attempt} 轮全部通过！所有审查员评分 ≥${passScore}`,
        timestamp: new Date().toISOString(), type: 'workflow'
      });
      break;
    }

    const failedNames = coderState.filter(cs => !cs.passed).map(c => c.agent.name).join('、');
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `❌ 第 ${attempt} 轮未通过。需重写: ${failedNames}。打回重写...`,
      timestamp: new Date().toISOString(), type: 'workflow'
    });
  }

  // Step 3: Summarizer
  if (finalPassed && summarizer) {
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `📝 ${summarizer.name} 最终验收汇报中...`,
      timestamp: new Date().toISOString(), type: 'workflow'
    });

    const allCode = coderState.map(cs =>
      `=== ${cs.agent.name}: ${cs.subTask} ===\n${cs.currentCode.slice(0, 2000)}`
    ).join('\n\n');

    const finalScores = allReviewResults.filter(r => r.attempt === allReviewResults.reduce((max, r2) => Math.max(max, r2.attempt), 0));
    const scoreSummary = [...new Set(finalScores.map(r => `${r.coderName}: ${finalScores.filter(s => s.coderId === r.coderId).map(s => `${s.reviewerName} ${s.score}分`).join(', ')}`))].join(' | ');

    const summaryPrompt = `代码审查流水线已完成。\n项目: ${task}\n最终评分: ${scoreSummary}\n\n所有代码:\n${allCode}\n\n请写出最终验收报告，包括：1.项目概述 2.各模块质量评估 3.整体评分 4.是否建议采用。以汇报形式呈现。`;

    const summaryResult = await runAgentChat(summarizer, summaryPrompt, config);

    addChatMessage({
      id: crypto.randomUUID(), from: summarizer.id,
      fromName: `📝 ${summarizer.icon} ${summarizer.name} (验收汇报)`,
      content: summaryResult.ok ? summaryResult.stdout : `❌ ${summaryResult.stderr || '无响应'}`,
      timestamp: new Date().toISOString(), responseTime: summaryResult.responseTime || 0, type: 'workflow'
    });

    if (summaryResult.ok && summaryResult.stdout) {
      appendToMemory(task, summaryResult.stdout);
      notifyFeishu(`✅ 流水线通过: ${task}`, `汇报人: ${summarizer.name}\n\n${summaryResult.stdout.slice(0, 1500)}`);
    }
  } else if (!finalPassed) {
    notifyFeishu(`❌ 流水线未通过: ${task}`, `已达最大重试次数 ${maxRetries}，请检查审查意见`);
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `💔 已达最大重试次数 (${maxRetries})，流水线未通过`,
      timestamp: new Date().toISOString(), type: 'workflow'
    });
  }

  const totalAttempts = Math.max(...coderState.map(c => c.attempt), 0);
  addChatMessage({
    id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
    content: `🔗 流水线结束。${finalPassed ? '✅ 全部通过' : '❌ 未通过'} | ${totalAttempts} 轮编程 + ${allReviewResults.length} 次审查`,
    timestamp: new Date().toISOString(), type: 'workflow'
  });

  res.json({ ok: true, passed: finalPassed, coderState: coderState.map(c => ({ name: c.agent.name, passed: c.passed, codeLen: c.currentCode.length })), reviews: allReviewResults });
});

app.post('/api/workflow/content-publish', async (req, res) => {
  req.setTimeout?.(0);
  res.setTimeout?.(0);
  try {
    const config = loadConfig();
    const {
      platform = '小红书',
      topic,
      copyAgentId,
      imageAgentId,
      integratorAgentId,
      reviewerAgentId,
      publishMode = 'draft',
      feishuNotify = true
    } = req.body || {};
    if (!topic?.trim()) return res.status(400).json({ ok: false, error: '请填写发布主题' });
    const copyAgent = findAgent(copyAgentId);
    const imageAgent = findAgent(imageAgentId);
    const integratorAgent = findAgent(integratorAgentId);
    const reviewerAgent = reviewerAgentId ? findAgent(reviewerAgentId) : null;
    for (const [label, agent] of [['文案 agent', copyAgent], ['图片 agent', imageAgent], ['整合 agent', integratorAgent]]) {
      if (!agent) return res.status(404).json({ ok: false, error: `${label} 未找到` });
      if (agent.disabled) return res.status(400).json({ ok: false, error: `${agent.name} 已禁用：${agent.disabledReason || '不可用'}` });
    }
    if (reviewerAgent?.disabled) return res.status(400).json({ ok: false, error: `${reviewerAgent.name} 已禁用：${reviewerAgent.disabledReason || '不可用'}` });
    const result = await runContentPublishWorkflow({
      platform,
      topic: topic.trim(),
      copyAgent,
      imageAgent,
      integratorAgent,
      reviewerAgent,
      publishMode,
      feishuNotify,
      source: 'workflow-page'
    }, config);
    res.json(result);
  } catch (e) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `❌ 内容发布流水线异常：${e.message}`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: '内容发布流水线'
    });
    res.status(500).json({ ok: false, error: e.message });
  }
});

app.post('/api/workflow/ppt-review', async (req, res) => {
  req.setTimeout?.(0);
  res.setTimeout?.(0);
  try {
    const config = loadConfig();
    const {
      topic,
      audience = '',
      goal = '',
      slideCount = 10,
      style = '商务清晰',
      outlineAgentId,
      makerAgentId,
      reviewerAgentId,
      finalizerAgentId,
      outputFormat = 'markdown',
      passScore = 85,
      maxRetries = 2,
      feishuNotify = true
    } = req.body || {};
    if (!topic?.trim()) return res.status(400).json({ ok: false, error: '请填写PPT主题/需求' });
    const outlineAgent = findAgent(outlineAgentId);
    const makerAgent = findAgent(makerAgentId);
    const reviewerAgent = findAgent(reviewerAgentId);
    const finalizerAgent = finalizerAgentId ? findAgent(finalizerAgentId) : null;
    for (const [label, agent] of [['策划 agent', outlineAgent], ['制作 agent', makerAgent], ['审核 agent', reviewerAgent]]) {
      if (!agent) return res.status(404).json({ ok: false, error: `${label} 未找到` });
      if (agent.disabled) return res.status(400).json({ ok: false, error: `${agent.name} 已禁用：${agent.disabledReason || '不可用'}` });
    }
    if (finalizerAgent?.disabled) return res.status(400).json({ ok: false, error: `${finalizerAgent.name} 已禁用：${finalizerAgent.disabledReason || '不可用'}` });
    const result = await runPptWorkflow({
      topic: topic.trim(),
      audience: audience.trim(),
      goal: goal.trim(),
      slideCount: Math.max(3, Math.min(30, Number(slideCount) || 10)),
      style,
      outputFormat: outputFormat || 'markdown',
      outlineAgent,
      makerAgent,
      reviewerAgent,
      finalizerAgent,
      passScore: Math.max(0, Math.min(100, Number(passScore) || 85)),
      maxRetries: Math.max(1, Math.min(5, Number(maxRetries) || 2)),
      feishuNotify
    }, config);
    res.json(result);
  } catch (e) {
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `❌ PPT制作与审核工作流异常：${e.message}`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: 'PPT制作与审核'
    });
    res.status(500).json({ ok: false, error: e.message });
  }
});

app.post('/api/workflow/project-pipeline', async (req, res) => {
  req.setTimeout?.(0);
  res.setTimeout?.(0);
  const config = loadConfig();
  const {
    projectDir: rawProjectDir,
    task,
    pmId,
    executorId,
    reviewerIds = [],
    testCommand = '',
    passScore = 80,
    maxRetries = 2,
    feishuNotify = true
  } = req.body;

  const projectDir = resolveExistingDir(rawProjectDir);
  if (!projectDir) return res.status(400).json({ error: '项目目录不存在或不是文件夹' });
  if (!task?.trim()) return res.status(400).json({ error: '请填写改造需求' });
  if (!executorId) return res.status(400).json({ error: '请选择执行 agent' });
  if (!reviewerIds?.length) return res.status(400).json({ error: '请选择至少一个评审 agent' });

  const pm = pmId ? findAgent(pmId) : null;
  const executor = findAgent(executorId);
  const reviewers = reviewerIds.map(id => findAgent(id)).filter(Boolean);
  if (!executor) return res.status(404).json({ error: '执行 agent 未找到' });
  if (executor.disabled) return res.status(400).json({ error: `${executor.name} 已禁用：${executor.disabledReason || '不可用'}` });
  if (getHostGroup(executor.id) !== 'local') {
    return res.status(400).json({ error: '项目改造会直接修改 Windows 本机目录，请选择本机执行 agent' });
  }
  if (pm?.disabled) return res.status(400).json({ error: `${pm.name} 已禁用：${pm.disabledReason || '不可用'}` });
  for (const r of reviewers) {
    if (r.disabled) return res.status(400).json({ error: `${r.name} 已禁用：${r.disabledReason || '不可用'}` });
  }
  if (reviewers.length === 0) return res.status(400).json({ error: '评审 agent 未找到' });

  let backup = null;
  try { backup = backupProjectDirectory(projectDir); } catch (e) {
    return res.status(500).json({ error: `项目备份失败：${e.message}` });
  }

  const title = `项目改造流水线: ${path.basename(projectDir)}`;
  addChatMessage({
    id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
    content: `🏗️ ${title}\n📁 项目目录: ${projectDir}\n🧭 项目经理: ${pm ? pm.icon + ' ' + pm.name : '不使用'}\n👨‍💻 执行: ${executor.icon} ${executor.name}\n🔍 评审: ${reviewers.map(r => r.icon + ' ' + r.name).join('、')}\n🧪 测试命令: ${testCommand || '未设置'}\n💾 启动备份: ${backup.url}`,
    timestamp: new Date().toISOString(), type: 'workflow'
  });
  if (feishuNotify) notifyFeishu(`🏗️ ${title} 已启动`, `项目: ${projectDir}\n需求: ${task}\n执行: ${executor.name}\n评审: ${reviewers.map(r=>r.name).join('、')}\n备份: ${backup.url}`);

  let pmPlan = `用户需求：\n${task}\n\n验收标准：\n- 满足用户需求\n- 不破坏现有功能\n- 测试命令通过${testCommand ? `：${testCommand}` : ''}\n- 评审分数达到 ${passScore}/100`;
  if (pm) {
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `🧭 ${pm.name} 正在拆需求和验收标准...`,
      timestamp: new Date().toISOString(), type: 'workflow'
    });
    const pmPrompt = `你是项目经理。请为下面的项目改造任务拆解需求、风险点和验收标准。\n\n项目目录: ${projectDir}\n项目文件预览:\n- ${listProjectFiles(projectDir, 120).join('\n- ')}\n\n用户需求:\n${task}\n\n请输出：1.需求拆解 2.验收标准 3.重点风险 4.建议测试命令。不要修改文件。`;
    const start = Date.now();
    const result = await runAgentChat(pm, pmPrompt, config);
    pmPlan = result.ok && result.stdout ? result.stdout : `${pmPlan}\n\nPM 输出失败：${result.stderr || '无响应'}`;
    addChatMessage({
      id: crypto.randomUUID(), from: pm.id,
      fromName: `${pm.icon} ${pm.name} (项目经理)`,
      content: compactAgentText(pmPlan, 3000),
      timestamp: new Date().toISOString(), responseTime: Date.now() - start, type: 'workflow'
    });
  }

  let finalPassed = false;
  let allReviews = [];
  let testResult = null;
  let lastFeedback = '';

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `🔄 项目改造第 ${attempt}/${maxRetries} 轮开始，${executor.name} 将直接修改项目目录...`,
      timestamp: new Date().toISOString(), type: 'workflow'
    });

    const executorPrompt = `你是本机执行 agent，需要直接修改已有项目文件。\n\n项目目录：${projectDir}\n\n用户需求：\n${task}\n\n项目经理拆解/验收标准：\n${pmPlan}\n\n${lastFeedback ? `上一轮评审意见，需要逐条整改：\n${lastFeedback}\n\n` : ''}执行要求：\n1. 进入项目目录，阅读相关文件，直接修改项目文件完成需求。\n2. 不要删除用户数据、备份、上传文件、环境文件或无关文件。\n3. 改动尽量小而完整，保留现有风格。\n4. 完成后如可行请运行检查；若无法运行请说明原因。\n5. 最后用中文汇报：修改了哪些文件、实现了什么、测试结果、剩余风险。`;
    const execStart = Date.now();
    const execResult = await runAgentChat(executor, executorPrompt, config);
    addChatMessage({
      id: crypto.randomUUID(), from: executor.id,
      fromName: `${executor.icon} ${executor.name} (执行第${attempt}轮)`,
      content: execResult.ok ? compactAgentText(execResult.stdout, 4000) : `❌ ${execResult.stderr || execResult.stdout || '无响应'}`,
      timestamp: new Date().toISOString(), responseTime: Date.now() - execStart, type: 'workflow'
    });
    if (!execResult.ok) {
      if (feishuNotify) notifyFeishu(`❌ ${title} 执行失败`, `${executor.name} 第 ${attempt} 轮失败：${execResult.stderr || '无响应'}`);
      break;
    }

    if (testCommand.trim()) {
      addChatMessage({
        id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
        content: `🧪 运行测试命令: ${testCommand}`,
        timestamp: new Date().toISOString(), type: 'workflow'
      });
      testResult = await execPromiseCwd(testCommand, projectDir, 300000);
      addChatMessage({
        id: crypto.randomUUID(), from: 'system', fromName: '🧪 测试',
        content: `${testResult.ok ? '✅ 测试通过' : '❌ 测试失败'}\n> ${testCommand}\n${compactAgentText((testResult.stdout || '') + (testResult.stderr ? '\n' + testResult.stderr : ''), 3000)}`,
        timestamp: new Date().toISOString(), type: 'workflow'
      });
      if (!testResult.ok && feishuNotify) {
        notifyFeishu(`⚠️ ${title} 测试失败`, `命令: ${testCommand}\n需要评审/人工确认。\n${compactAgentText(testResult.stderr || testResult.stdout, 1200)}`);
      }
    }

    let projectBundle = null;
    try { projectBundle = publishLocalProjectForAgents(projectDir, config); } catch (e) {
      addChatMessage({
        id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
        content: `⚠️ 评审项目包发布失败：${e.message}`,
        timestamp: new Date().toISOString(), type: 'workflow'
      });
    }
    const diff = getProjectDiff(projectDir);
    const roundReviews = await mapAgentsWithHostLimits(reviewers, config, async (reviewer) => {
      addChatMessage({
        id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
        content: `🔍 ${reviewer.name} 正在评审第 ${attempt} 轮改造结果...`,
        timestamp: new Date().toISOString(), type: 'workflow'
      });
      const reviewPrompt = `你是项目改造评审 agent。请只评审，不要修改文件。\n\n项目目录（本机原路径，仅供识别）：${projectDir}\n${projectBundle ? `项目包下载: ${projectBundle.url}\n` : ''}\n用户需求:\n${task}\n\n项目经理验收标准:\n${pmPlan}\n\n测试结果:\n${testResult ? `${testResult.ok ? '通过' : '失败'} - ${testCommand}\n${compactAgentText((testResult.stdout || '') + (testResult.stderr ? '\n' + testResult.stderr : ''), 1800)}` : '未运行测试'}\n\n改动摘要/diff:\n${compactAgentText(diff, 12000)}\n\n请按 0-100 打分，必须写“分数: X分”。请给出：通过/不通过、关键问题、必须整改项、可选建议。通过分为 ${passScore}。`;
      const start = Date.now();
      const result = await runAgentChat(reviewer, reviewPrompt, config);
      const text = result.ok ? result.stdout : (result.stderr || result.stdout || '无响应');
      const score = parseScore(text);
      const passed = result.ok && score !== null && score >= passScore;
      const data = { attempt, reviewerId: reviewer.id, reviewerName: reviewer.name, score: score ?? '?', feedback: text, passed };
      addChatMessage({
        id: crypto.randomUUID(), from: reviewer.id,
        fromName: `${reviewer.icon} ${reviewer.name} (评审第${attempt}轮)`,
        content: `📊 评分: ${score ?? '?'}/100 ${passed ? '✅ 通过' : '❌ 不通过'}\n${compactAgentText(text, 2200)}`,
        timestamp: new Date().toISOString(), responseTime: Date.now() - start, type: 'workflow'
      });
      return data;
    });
    allReviews.push(...roundReviews);
    const reviewPassed = roundReviews.length > 0 && roundReviews.every(r => r.passed);
    const testsPassed = !testCommand.trim() || !!testResult?.ok;
    if (reviewPassed && testsPassed) {
      finalPassed = true;
      break;
    }

    lastFeedback = formatReviewFeedback(roundReviews);
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `⚠️ 第 ${attempt} 轮未通过，将评审意见打回给 ${executor.name}${attempt < maxRetries ? ' 继续整改' : '；已达到最大轮次，需要人工确认'}`,
      timestamp: new Date().toISOString(), type: 'workflow'
    });
    if (attempt === maxRetries && feishuNotify) {
      notifyFeishu(`🧑‍⚖️ ${title} 需人工确认`, `项目: ${projectDir}\n第 ${attempt} 轮仍未通过。\n测试: ${testResult ? (testResult.ok ? '通过' : '失败') : '未运行'}\n评审:\n${compactAgentText(lastFeedback, 2200)}`);
    }
  }

  const finalScores = allReviews.filter(r => r.attempt === Math.max(...allReviews.map(x => x.attempt), 0));
  const scoreLine = finalScores.map(r => `${r.reviewerName}: ${r.score}`).join('，') || '无评分';
  const finalMsg = `${finalPassed ? '✅ 项目改造流水线通过' : '❌ 项目改造流水线未通过'}\n📁 ${projectDir}\n🧪 测试: ${testCommand ? (testResult?.ok ? '通过' : '失败/未通过') : '未设置'}\n📊 最终评分: ${scoreLine}\n💾 启动备份: ${backup.url}`;
  addChatMessage({
    id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
    content: finalMsg,
    timestamp: new Date().toISOString(), type: 'workflow'
  });
  if (feishuNotify) notifyFeishu(`${finalPassed ? '✅' : '❌'} ${title} 最终汇报`, finalMsg);
  res.json({ ok: true, passed: finalPassed, backup, reviews: allReviews, test: testResult });
});

async function executeWorkflowDesignTask({ requirement, agent, config, resumedFrom = '' }) {
  const ver = loadVersion();
  const oldVersion = ver.version;
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const backupId = `workflow_${oldVersion}_${ts}`;
  const backupDir = path.join(BACKUPS_DIR, backupId);
  const projectDir = __dirname;
  fs.mkdirSync(backupDir);
  let copied = 0;
  for (const f of fs.readdirSync(projectDir)) {
    if (BACKUP_EXCLUDE.includes(f)) continue;
    const src = path.join(projectDir, f);
    const dst = path.join(backupDir, f);
    try {
      const st = fs.statSync(src);
      if (st.isDirectory()) copyDirSync(src, dst);
      else fs.copyFileSync(src, dst);
      copied++;
    } catch(e) { console.error(`[WORKFLOW-DESIGN] backup skip ${f}:`, e.message); }
  }
  fs.writeFileSync(path.join(backupDir, 'manifest.json'), JSON.stringify({
    version: oldVersion, timestamp: new Date().toISOString(), requirement, backupId, files: copied, resumedFrom
  }, null, 2), 'utf-8');
  const startedAt = new Date().toISOString();
  upsertDevProgress({
    id: backupId,
    kind: 'workflow-design',
    status: 'running',
    title: `工作流设计: ${compactAgentText(requirement, 60)}`,
    requirement: compactAgentText(requirement, 1200),
    triggerAgent: resumedFrom ? '继续设计' : '工作流页面',
    executor: agent.name,
    executorId: agent.id,
    backup: backupId,
    oldVersion,
    startedAt,
    resumedFrom
  });

  addChatMessage({
    id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
    content: `🧩 工作流设计师启动\n需求: ${requirement}\n执行者: ${agent.icon} ${agent.name}\n备份: backups/${backupId}${resumedFrom ? `\n继续自: ${resumedFrom}` : ''}`,
    timestamp: new Date().toISOString(), type: 'workflow'
  });

  const projectFiles = fs.readdirSync(projectDir).filter(f => {
    if (BACKUP_EXCLUDE.includes(f)) return false;
    try { return fs.statSync(path.join(projectDir, f)).isFile(); } catch { return false; }
  }).join(', ');

  const designPrompt = `你是 AI Agent Dashboard 的“工作流设计师”和本地代码执行者。

目标：根据用户需求，为这个项目设计并安装一个新的工作流能力，或优化现有工作流能力。

用户需求：
${requirement}

项目位置：${projectDir}
主要文件：${projectFiles}

实现要求：
1. 先阅读 server.js、public/index.html、config.json 的相关部分，理解现有 API、SSE 消息、工作流页和系统升级页。
2. 直接修改项目文件完成需求。优先复用现有 Express API、SSE addChatMessage、runAgentChat、workflow tab 的 UI 风格。
3. 如果新增工作流，要让用户能在页面里直接输入要求/参数并启动，进度要能实时显示在工作流消息区。
4. 修改要尽量小而完整，不要破坏现有大屏、群聊、系统升级、备份恢复。
5. 完成后运行可行的语法检查，例如 node --check server.js，并检查 public/index.html 中脚本可解析。
6. 最后用简短中文报告：新增/修改了什么、怎么使用、验证结果、剩余风险。

注意：
- 当前请求已经在 backups/${backupId} 做过备份。
- 不要删除 backups、node_modules、chat_log.json。
- 如果需要选择默认执行者，优先使用 local agent。`;

  const startTime = Date.now();
  const designAgent = { ...agent, chatTimeout: Math.max(agent.chatTimeout || 300000, 900000) };
  const result = await runAgentChat(designAgent, designPrompt, config);
  const responseTime = Date.now() - startTime;
  const filesChanged = dashboardKeyFilesChangedSinceBackup(backupDir);
  const validation = filesChanged ? await validateDashboardSyntax() : { ok: false, error: '未检测到关键项目文件变化' };
  const effectiveOk = result.ok || (filesChanged && validation.ok);
  const softSuccess = !result.ok && effectiveOk;

  addChatMessage({
    id: crypto.randomUUID(), from: agent.id,
    fromName: `${agent.icon} ${agent.name} (工作流设计师)`,
    content: result.ok
      ? result.stdout
      : (softSuccess
        ? `⚠️ Agent 返回超时/非零退出，但检测到项目文件已修改且验证通过，按完成处理。\n\n原始输出:\n${compactAgentText(result.stderr || result.stdout || '无响应', 2200)}`
        : `❌ ${result.stderr || result.stdout || '无响应'}`),
    timestamp: new Date().toISOString(), responseTime, type: 'workflow'
  });

  if (effectiveOk) {
    const parts = oldVersion.split('.').map(Number);
    parts[2] = (parts[2] || 0) + 1;
    const newVersion = parts.join('.');
    ver.version = newVersion;
    ver.history.unshift({
      version: newVersion,
      previous: oldVersion,
      task: `工作流设计: ${requirement}`,
      agent: agent.name,
      backup: backupId,
      timestamp: new Date().toISOString()
    });
    saveVersion(ver);
    upsertDevProgress({
      id: backupId,
      kind: 'workflow-design',
      status: 'completed',
      title: `工作流设计: ${compactAgentText(requirement, 60)}`,
      requirement: compactAgentText(requirement, 1200),
      executor: agent.name,
      executorId: agent.id,
      backup: backupId,
      oldVersion,
      newVersion,
      completedAt: new Date().toISOString(),
      summary: compactAgentText(result.stdout || validation.detail || '工作流设计完成', 1800)
    });
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `✅ 工作流设计完成: ${oldVersion} → ${newVersion}\n备份: ${backupId}${softSuccess ? '\n说明: 执行 agent 返回超时/非零退出，但文件已变更且语法验证通过。' : ''}\n验证: ${validation.detail || 'agent 已正常返回'}`,
      timestamp: new Date().toISOString(), type: 'workflow'
    });
  } else {
    upsertDevProgress({
      id: backupId,
      kind: 'workflow-design',
      status: 'failed',
      title: `工作流设计: ${compactAgentText(requirement, 60)}`,
      requirement: compactAgentText(requirement, 1200),
      executor: agent.name,
      executorId: agent.id,
      backup: backupId,
      oldVersion,
      failedAt: new Date().toISOString(),
      error: compactAgentText(validation.error || result.stderr || result.stdout || '无响应', 1800)
    });
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `❌ 工作流设计失败，已保留备份: ${backupId}\n原因: ${validation.error || result.stderr || result.stdout || '无响应'}\n可在首页“当前研发进度”里点击继续设计或删除记录。`,
      timestamp: new Date().toISOString(), type: 'workflow'
    });
  }

  return { ok: effectiveOk, backup: backupId, agent: agent.name, output: result.stdout, error: effectiveOk ? undefined : result.stderr, warning: softSuccess ? (result.stderr || result.stdout || 'agent 返回异常但验证通过') : undefined, validation };
}

app.post('/api/workflow/design', async (req, res) => {
  req.setTimeout?.(0);
  res.setTimeout?.(0);
  const config = loadConfig();
  const { requirement, agentId } = req.body;
  if (!requirement?.trim()) return res.status(400).json({ error: '请描述要新增或优化的工作流' });
  if (!agentId) return res.status(400).json({ error: '请选择执行设计的本机 Agent' });

  const agent = findAgent(agentId);
  if (!agent) return res.status(404).json({ error: '智能体未找到' });
  const group = getHostGroup(agent.id);
  if (group !== 'local') {
    return res.status(400).json({ error: '工作流设计会修改本项目文件，请选择本机 Agent（local）执行' });
  }

  const result = await executeWorkflowDesignTask({ requirement, agent, config });
  res.json(result);
});

// ── Music Workflow ─────────────────────────────────────────────

async function generateMusicDraftAudio({ text, audioFile, tempDir, jobId }) {
  const notes = [];
  try {
    const args = ['infer', 'tts', 'convert', '--local', '--json', '--output', audioFile, '--text', text];
    const result = execFileSync('openclaw.cmd', args, {
      encoding: 'utf8',
      windowsHide: true,
      maxBuffer: 12 * 1024 * 1024
    });
    if (fs.existsSync(audioFile) && fs.statSync(audioFile).size > 1024) {
      return { ok: true, mode: 'tts-draft-openclaw', note: result || '' };
    }
    notes.push(result || 'OpenClaw TTS 未生成有效文件');
  } catch (e) {
    notes.push(e.stderr || e.stdout || e.message || String(e));
  }

  const textFile = path.join(tempDir, jobId + '_tts.txt');
  const wavFile = path.join(tempDir, jobId + '.wav');
  const psFile = path.join(tempDir, jobId + '_tts.ps1');
  fs.writeFileSync(textFile, text, 'utf-8');
  const ps = [
    'Add-Type -AssemblyName System.Speech',
    `$text = Get-Content -LiteralPath "${textFile}" -Raw -Encoding UTF8`,
    `$wav = "${wavFile}"`,
    '$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer',
    '$synth.Rate = 0',
    '$synth.Volume = 100',
    '$synth.SetOutputToWaveFile($wav)',
    '$synth.Speak($text)',
    '$synth.Dispose()'
  ].join('\r\n');
  fs.writeFileSync(psFile, ps, 'utf-8');
  const wave = await execPromise(`powershell -NoProfile -ExecutionPolicy Bypass -File "${psFile}"`, 180000);
  if (!wave.ok || !fs.existsSync(wavFile) || fs.statSync(wavFile).size < 1024) {
    return { ok: false, error: compactAgentText(notes.join('\n') + '\n' + (wave.stderr || wave.stdout || 'Windows TTS 兜底失败'), 1200) };
  }
  const transcode = await execPromise(`ffmpeg -y -i "${wavFile}" -codec:a libmp3lame -qscale:a 2 "${audioFile}"`, 180000);
  try { fs.unlinkSync(psFile); } catch {}
  try { fs.unlinkSync(textFile); } catch {}
  try { fs.unlinkSync(wavFile); } catch {}
  if (!transcode.ok || !fs.existsSync(audioFile) || fs.statSync(audioFile).size < 1024) {
    return { ok: false, error: compactAgentText(notes.join('\n') + '\n' + (transcode.stderr || transcode.stdout || 'FFmpeg 转码失败'), 1200) };
  }
  return { ok: true, mode: 'tts-draft-windows', note: 'OpenClaw TTS 不可用，已切换到 Windows 语音兜底。' };
}

function buildFallbackMusicLyrics(song, artist, lyricsStyle) {
  const style = lyricsStyle?.trim() || '流行抒情';
  const singer = artist?.trim() || '某位歌手';
  const theme = song?.trim() || '未命名歌曲';
  return [
    `${theme}`,
    '',
    `夜色慢慢落进窗台，城市灯火排成海`,
    `我把没说完的话，轻轻写进这段独白`,
    `如果你也刚好路过，这旋律就算被听见`,
    `让风把心事吹开，让脚步不再徘徊`,
    '',
    `副歌`,
    `就唱吧，为了今天还没有熄灭的期待`,
    `就唱吧，把沉默变成会发光的节拍`,
    `哪怕只是一个人，也要把天空慢慢打开`,
    `让名字叫做《${theme}》的心情，留在此刻盛开`,
    '',
    `第二段`,
    `${singer}的影子落在脑海，像${style}一样铺展开来`,
    `远处人群来来往往，我把温柔一字一句剪裁`,
    `若终点还没有答案，就先把沿途唱成海`,
    `让所有来不及告白，最后都能被你明白`,
    '',
    `副歌`,
    `就唱吧，为了那些没说出口的热爱`,
    `就唱吧，把孤单也唱成并肩的存在`,
    `哪怕风会绕几圈，梦也会准时回来`,
    `让名字叫做《${theme}》的夜晚，真的慢慢亮起来`
  ].join('\n');
}

function formatMusicDuration(seconds) {
  const total = Number(seconds);
  if (!Number.isFinite(total) || total <= 0) return '';
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = Math.floor(total % 60);
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  return `${m}:${String(s).padStart(2, '0')}`;
}

function loadMusicLibrary() {
  try {
    const raw = JSON.parse(fs.readFileSync(MUSIC_LIBRARY_PATH, 'utf-8'));
    return {
      favorites: Array.isArray(raw?.favorites) ? raw.favorites : [],
      recent: Array.isArray(raw?.recent) ? raw.recent : []
    };
  } catch {
    return { favorites: [], recent: [] };
  }
}

function saveMusicLibrary(lib) {
  const payload = {
    favorites: Array.isArray(lib?.favorites) ? lib.favorites : [],
    recent: Array.isArray(lib?.recent) ? lib.recent : []
  };
  fs.writeFileSync(MUSIC_LIBRARY_PATH, JSON.stringify(payload, null, 2), 'utf-8');
}

function normalizeMusicTrack(track) {
  return {
    id: String(track?.id || '').trim(),
    rawId: String(track?.rawId || '').trim(),
    title: compactAgentText(track?.title || '', 160),
    channel: compactAgentText(track?.channel || '', 120),
    type: compactAgentText(track?.type || '', 40),
    previewUrl: String(track?.previewUrl || '').trim(),
    artwork: String(track?.artwork || '').trim(),
    duration: compactAgentText(track?.duration || '', 24),
    sourceLabel: compactAgentText(track?.sourceLabel || '', 40),
    source: compactAgentText(track?.source || '', 40),
    lyrics: compactAgentText(track?.lyrics || '', 4000)
  };
}

function musicTrackKey(track) {
  const t = normalizeMusicTrack(track);
  return [t.id, t.rawId, t.title, t.channel].join('|');
}

async function fetchJson(url, timeoutMs = 15000) {
  const target = new URL(url);
  const transport = target.protocol === 'http:' ? require('http') : require('https');
  return await new Promise((resolve, reject) => {
    const req = transport.get(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 AgentDashboard/1.0' },
      timeout: timeoutMs
    }, (resp) => {
      let data = '';
      resp.on('data', chunk => { data += chunk; });
      resp.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(new Error('JSON 解析失败'));
        }
      });
    });
    req.on('timeout', () => {
      req.destroy(new Error('请求超时'));
    });
    req.on('error', reject);
  });
}

async function searchMarketSongs(query, limit = 8) {
  const safeQuery = String(query || '').trim();
  if (!safeQuery) return [];
  const items = [];
  try {
    const neteaseBase = String(process.env.NETEASE_API_BASE || '').trim().replace(/\/+$/, '');
    if (neteaseBase) {
      const searchData = await fetchJson(`${neteaseBase}/search?keywords=${encodeURIComponent(safeQuery)}&limit=${Math.max(1, Math.min(limit, 10))}`, 15000);
      const songs = Array.isArray(searchData?.result?.songs) ? searchData.result.songs.slice(0, limit) : [];
      if (songs.length) {
        const songIds = songs.map(song => song.id).filter(Boolean);
        const urlRows = await Promise.all(songs.map(async (song) => {
          try {
            const urlData = await fetchJson(`${neteaseBase}/song/url/v1?id=${encodeURIComponent(song.id)}&level=standard`, 15000);
            return urlData?.data?.[0] || null;
          } catch {
            return null;
          }
        }));
        let detailMap = new Map();
        try {
          const detailData = await fetchJson(`${neteaseBase}/song/detail?ids=${encodeURIComponent(songIds.join(','))}`, 15000);
          detailMap = new Map((detailData?.songs || []).map(item => [String(item.id), item]));
        } catch {}
        songs.forEach((song, idx) => {
          const urlRow = urlRows[idx];
          const detailRow = detailMap.get(String(song.id)) || null;
          const artistList = Array.isArray(song.ar) ? song.ar : (Array.isArray(song.artists) ? song.artists : []);
          const artistText = artistList.map(a => a?.name).filter(Boolean).join(' / ');
          items.push({
            id: `netease_${song.id}`,
            rawId: String(song.id),
            title: compactAgentText(song.name || '未知歌曲', 120),
            duration: formatMusicDuration(((song.dt || song.duration || 0) / 1000)),
            channel: compactAgentText(artistText || '网易云音乐', 80),
            source: 'netease',
            previewUrl: urlRow?.url || '',
            artwork: detailRow?.al?.picUrl || song.al?.picUrl || song.album?.picUrl || '',
            trial: urlRow?.freeTrialInfo?.end ? `${Math.round(Number(urlRow.freeTrialInfo.end || 0))}秒试听` : ''
          });
        });
      }
    }
  } catch {}
  if (items.length) {
    return items.slice(0, limit);
  }

  try {
    const api = `https://itunes.apple.com/search?term=${encodeURIComponent(safeQuery)}&entity=song&limit=${Math.max(1, Math.min(limit, 12))}`;
    const data = await fetchJson(api, 15000);
    for (const row of (data.results || [])) {
      const id = String(row.trackId || row.collectionId || '').trim();
      if (!id || !row.trackName) continue;
      items.push({
        id,
        title: compactAgentText(row.trackName || '未知歌曲', 120),
        duration: formatMusicDuration((row.trackTimeMillis || 0) / 1000),
        channel: compactAgentText(row.artistName || row.collectionName || 'iTunes', 80),
        source: 'itunes',
        previewUrl: row.previewUrl || '',
        artwork: row.artworkUrl100 || row.artworkUrl60 || ''
      });
    }
  } catch {}
  if (items.length) {
    return items.slice(0, limit);
  }

  const cmd = `yt-dlp --flat-playlist --dump-json --no-warnings "ytsearch${Math.max(1, Math.min(limit, 12))}:${safeQuery.replace(/"/g, ' ').replace(/`/g, '')}"`;
  const result = await execPromise(cmd, 60000);
  if (!result.ok && !result.stdout) {
    throw new Error(result.stderr || result.stdout || '在线歌曲搜索失败');
  }
  const lines = String(result.stdout || '')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean);
  for (const line of lines) {
    try {
      const j = JSON.parse(line);
      const id = String(j.id || '').trim();
      if (!id) continue;
      items.push({
        id,
        title: compactAgentText(j.title || 'YouTube 视频', 120),
        duration: formatMusicDuration(j.duration),
        channel: compactAgentText(j.channel || j.uploader || 'YouTube', 80),
        source: 'youtube'
      });
    } catch {}
  }
  const dedup = new Map();
  for (const item of items) {
    if (!dedup.has(item.id)) dedup.set(item.id, item);
  }
  return Array.from(dedup.values()).slice(0, limit);
}

app.post('/api/music/generate', async (req, res) => {
  req.setTimeout?.(0);
  res.setTimeout?.(0);
  const { song, artist, lyricsStyle, agentId, autoPlay } = req.body;
  if (!song?.trim()) return res.status(400).json({ error: '请输入歌曲名称' });

  const config = loadConfig();
  const port = config.server.port || 3456;
  const tempDir = path.join(SHARED_OUT, 'music_temp');
  fs.mkdirSync(tempDir, { recursive: true });

  // Stage 1: lyrics generation via agent
  let lyrics = '';
  if (agentId) {
    try {
      const agent = findAgent(agentId);
      if (agent && agent.hostGroup === 'local') {
        const styleText = lyricsStyle ? `，风格：${lyricsStyle}` : '';
        const lyricsPrompt = `为歌曲「${song}」${artist ? '（'+artist+'）' : ''}${styleText}写一段歌词，要求押韵、有意境，不要太长（不超过60行），只输出歌词不要其他说明。`;
        const result = await runAgentChat({ ...agent, chatTimeout: Math.min(agent.chatTimeout || 120000, 60000) }, lyricsPrompt, config);
        if (result?.stdout) {
          lyrics = result.stdout.trim().split('\n').filter(l => l.trim()).join('\n');
          addChatMessage({
            id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
            content: `🎵 歌词生成完成: ${song}\n${lyrics.slice(0, 150)}${lyrics.length > 150 ? '...' : ''}`,
            timestamp: new Date().toISOString(), type: 'workflow', topic: '音乐工作流'
          });
        }
      }
    } catch (e) {
      console.error('Lyrics generation error:', e.message);
    }
  }

  // Stage 2: generate a stable audio draft through OpenClaw TTS.
  // The previous implementation called a non-existent "openclaw music-generate" command
  // and reported success before any file existed.
  const jobId = 'music_' + Date.now();
  const lyricsFile = path.join(tempDir, jobId + '_lyrics.txt');
  const notesFile = path.join(tempDir, jobId + '_notes.md');
  const audioFile = path.join(tempDir, jobId + '.mp3');
  if (lyrics) fs.writeFileSync(lyricsFile, lyrics, 'utf-8');

  if (!lyrics) {
    lyrics = buildFallbackMusicLyrics(song, artist, lyricsStyle);
  }
  if (lyrics && !fs.existsSync(lyricsFile)) fs.writeFileSync(lyricsFile, lyrics, 'utf-8');
  const draftText = lyrics;

  addChatMessage({
    id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
    content: `🎵 音乐生成启动: ${song}${artist ? ' - ' + artist : ''}${lyrics ? '\n📝 歌词已生成' : ''}\n🎧 正在生成可播放音频小样...`,
    timestamp: new Date().toISOString(), type: 'workflow', topic: '音乐工作流'
  });

  try {
    const audioDraft = await generateMusicDraftAudio({ text: draftText, audioFile, tempDir, jobId });
    if (!audioDraft.ok) throw new Error(audioDraft.error || '音频小样生成失败');
    fs.writeFileSync(notesFile, `# 音乐工作流交付\n\n## 歌曲\n${song}\n\n## 参考歌手/方向\n${artist || '未指定'}\n\n## 风格要求\n${lyricsStyle || '未指定'}\n\n## 说明\n当前系统已生成“可播放音频小样”，便于主人快速试听流程是否跑通。\n当前为语音试唱草稿，不是完整编曲成品；后续若要上升到真正作曲/伴奏生成，需要单独接入专用音乐模型。\n\n## 模式\n${audioDraft.mode}\n\n## 歌词\n${lyrics || '未单独生成歌词，已直接按歌曲需求合成语音小样。'}\n\n## 生成备注\n${audioDraft.note || '无'}\n`, 'utf-8');
    const audioUrl = `${publicBaseUrl(port)}/files/music_temp/${jobId}.mp3`;
    const notesUrl = `${publicBaseUrl(port)}/files/music_temp/${jobId}_notes.md`;
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `✅ 音乐工作流完成: ${song}${artist ? ' - ' + artist : ''}\n交付: ${audioUrl}\n说明文档: ${notesUrl}\n模式: ${audioDraft.mode}\n当前交付为可播放音频小样，可直接试听流程链路。`,
      timestamp: new Date().toISOString(), type: 'workflow', topic: '音乐工作流'
    });
    return res.json({
      ok: true,
      id: jobId,
      title: song,
      artist: artist || '',
      lyrics: lyrics || '',
      audioUrl,
      notesUrl,
      mode: audioDraft.mode,
      autoPlay: !!autoPlay
    });
  } catch (e) {
    const details = compactAgentText(e.stderr || e.stdout || e.message || String(e), 800);
    addChatMessage({
      id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
      content: `❌ 音乐工作流失败: ${song}${artist ? ' - ' + artist : ''}\n原因: ${details}`,
      timestamp: new Date().toISOString(), type: 'workflow', topic: '音乐工作流'
    });
    return res.status(500).json({ ok: false, error: `音频小样生成失败：${details}` });
  }
});

// ── Music Search & Stream ──────────────────────────────────────

app.get('/api/music/search', async (req, res) => {
  const { q, url } = req.query;
  // Direct YouTube URL support: if user pastes a YouTube URL, add it directly
  if (url?.match(/youtube\.com\/watch|youtu\.be\/[a-zA-Z0-9_-]{11}/)) {
    const idMatch = url.match(/[?&]v=([a-zA-Z0-9_-]{11})|youtu\.be\/([a-zA-Z0-9_-]{11})/);
    if (idMatch) {
      const id = idMatch[1] || idMatch[2];
      return res.json({ ok: true, results: [{ id, title: 'YouTube 视频', duration: '', channel: '', url, source: 'youtube' }] });
    }
  }
  if (!q?.trim()) return res.status(400).json({ error: '请输入搜索关键词或直接粘贴YouTube链接' });
  try {
    const musicDir = path.join(SHARED_OUT, 'music_temp');
    fs.mkdirSync(musicDir, { recursive: true });
    const downloaded = fs.readdirSync(musicDir).filter(f => f.endsWith('.mp3') || f.endsWith('.m4a'));
    const localTracks = downloaded
      .filter(f => f.toLowerCase().includes(String(q).toLowerCase()))
      .slice(0, 6)
      .map(f => ({
        id: f.replace(/\.mp3$|\.m4a$/, ''),
        title: f.replace(/\.(mp3|m4a)$/, '').replace(/_/g, ' '),
        duration: '',
        channel: '本地文件',
        url: '/files/music_temp/' + f,
        local: true,
        source: 'local'
      }));
    let marketTracks = [];
    let searchError = '';
    try {
      marketTracks = await searchMarketSongs(q, 8);
    } catch (e) {
      searchError = e.message || String(e);
    }
    const results = [...localTracks, ...marketTracks];
    res.json({
      ok: true,
      results,
      hint: marketTracks.length ? '已包含市场已有歌曲结果，可直接播放试听。优先接入网易云库，部分版权歌曲可能是 30-45 秒试听。' : '在线搜索暂不可用，可先播放本地或直接粘贴 YouTube 链接。',
      searchError
    });
  } catch (e) {
    res.json({ ok: true, results: [], hint: '可直接粘贴YouTube视频链接开始播放' });
  }
});

app.get('/api/music/stream', async (req, res) => {
  const { id, title } = req.query;
  if (!id?.trim()) return res.status(400).json({ error: '缺少音视频ID' });

  const musicDir = path.join(SHARED_OUT, 'music_temp');
  fs.mkdirSync(musicDir, { recursive: true });
  const safeId = id.replace(/[^\w\-]/g, '_').slice(0, 80);
  const outFile = path.join(musicDir, safeId + '.mp3');
  const doneFile = outFile + '.done';

  // If already downloaded, stream it
  if (fs.existsSync(outFile)) {
    res.setHeader('Content-Type', 'audio/mpeg');
    res.setHeader('Content-Disposition', title ? `inline; filename*=UTF-8''${encodeURIComponent(title)}.mp3` : 'inline');
    fs.createReadStream(outFile).pipe(res);
    return;
  }

  // Start download in background if not already started
  if (!fs.existsSync(doneFile)) {
    const dlScript = path.join(__dirname, 'scripts', 'music_dl_' + safeId + '.ps1');
    const dlCmd = `yt-dlp -f bestaudio/best -o "${outFile.replace(/\\/g, '\\\\')}" --extract-audio --audio-format mp3 https://www.youtube.com/watch?v=${id}`;
    const scriptContent = [
      '# Auto-download music: ' + (title || id),
      'yt-dlp -f bestaudio/best -o "' + outFile.replace(/\\/g, '\\\\') + '" --extract-audio --audio-format mp3 https://www.youtube.com/watch?v=' + id,
      'if ($LASTEXITCODE -eq 0) { New-Item "' + doneFile.replace(/\\/g, '\\\\') + '" -ItemType File -Force | Out-Null }',
      'if ($LASTEXITCODE -ne 0) { Write-Error "Download failed" }'
    ].join('\r\n');
    fs.writeFileSync(dlScript, scriptContent, 'utf-8');
    exec(`powershell -NoProfile -ExecutionPolicy Bypass -File "${dlScript}"`, { cwd: musicDir }, (err) => {
      if (err) console.error('Music stream dl error:', err.message);
      else console.log('Music stream downloaded:', id);
    });
  }

  // Return placeholder while downloading
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.send('#DOWNLOADING#');
});

app.get('/api/music/lyrics', async (req, res) => {
  const { song, artist, source, rawId, id } = req.query;
  if (!song?.trim()) return res.status(400).json({ error: '请输入歌曲名称' });
  const neteaseId = String(rawId || id || '').replace(/^netease_/, '').trim();
  if ((source === 'netease' || String(id || '').startsWith('netease_')) && neteaseId) {
    try {
      const neteaseBase = String(process.env.NETEASE_API_BASE || '').trim().replace(/\/+$/, '');
      if (!neteaseBase) throw new Error('NETEASE_API_BASE is not configured');
      const data = await fetchJson(`${neteaseBase}/lyric?id=${encodeURIComponent(neteaseId)}`, 15000);
      const rawLyrics = String(data?.lrc?.lyric || '').trim();
      if (rawLyrics) {
        const entries = rawLyrics
          .split(/\r?\n/)
          .map(line => {
            const tags = [...line.matchAll(/\[(\d+):(\d+(?:\.\d+)?)\]/g)];
            const text = line.replace(/\[[^\]]+\]/g, '').trim();
            if (!tags.length || !text) return null;
            const first = tags[0];
            const timeMs = Number(first[1]) * 60000 + Math.round(Number(first[2]) * 1000);
            return Number.isFinite(timeMs) ? { timeMs, text } : null;
          })
          .filter(Boolean)
          .sort((a, b) => a.timeMs - b.timeMs);
        if (entries.length) {
          return res.json({
            ok: true,
            lyrics: entries.map(item => item.text),
            entries,
            timed: true,
            source: 'netease'
          });
        }
        const lines = rawLyrics
          .split(/\r?\n/)
          .map(line => line.replace(/^\[[^\]]+\]/g, '').trim())
          .filter(Boolean);
        if (lines.length) {
          return res.json({ ok: true, lyrics: lines, timed: false, source: 'netease' });
        }
      }
    } catch (e) {
      console.error('Netease lyrics fetch failed:', e.message);
    }
  }
  const artistVal = artist?.trim() || '';
  const https = require('https');
  const url = `https://api.lyrics.ovh/v1/${encodeURIComponent(artistVal || 'unknown')}/${encodeURIComponent(song)}`;
  try {
    const lyrics = await new Promise((resolve, reject) => {
      https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' }, timeout: 10000 }, (r) => {
        let data = '';
        r.on('data', chunk => data += chunk);
        r.on('end', () => {
          try {
            const j = JSON.parse(data);
            if (j.lyrics) resolve(j.lyrics);
            else reject(new Error(j.error || '未找到歌词'));
          } catch { reject(new Error('歌词解析失败')); }
        });
        r.on('error', reject);
      }).on('error', reject);
    });
    const lines = lyrics.split('\n').filter(l => l.trim());
    res.json({ ok: true, lyrics: lines, timed: false, source: 'lyrics.ovh' });
  } catch (e) {
    res.status(500).json({ ok: false, error: '未找到歌词（' + e.message + '），可尝试在浮动播放器内手动搜索' });
  }
});

app.get('/api/music/status', (req, res) => {
  const { id } = req.query;
  if (!id) return res.status(400).json({ error: '缺少id' });
  const safeId = id.replace(/[^\w\-]/g, '_').slice(0, 80);
  const outFile = path.join(SHARED_OUT, 'music_temp', safeId + '.mp3');
  const doneFile = outFile + '.done';
  const ready = fs.existsSync(outFile);
  res.json({ ok: true, ready, path: ready ? '/files/music_temp/' + safeId + '.mp3' : '' });
});

app.get('/api/music/library', (req, res) => {
  res.json({ ok: true, ...loadMusicLibrary() });
});

app.post('/api/music/library/recent', express.json({ limit: '1mb' }), (req, res) => {
  const track = normalizeMusicTrack(req.body?.track || {});
  if (!track.id && !track.title) return res.status(400).json({ ok: false, error: '缺少歌曲信息' });
  const lib = loadMusicLibrary();
  lib.recent = lib.recent.filter(item => musicTrackKey(item) !== musicTrackKey(track));
  lib.recent.unshift(track);
  lib.recent = lib.recent.slice(0, 20);
  saveMusicLibrary(lib);
  res.json({ ok: true, recent: lib.recent });
});

app.post('/api/music/library/favorites/toggle', express.json({ limit: '1mb' }), (req, res) => {
  const track = normalizeMusicTrack(req.body?.track || {});
  if (!track.id && !track.title) return res.status(400).json({ ok: false, error: '缺少歌曲信息' });
  const lib = loadMusicLibrary();
  const key = musicTrackKey(track);
  const idx = lib.favorites.findIndex(item => musicTrackKey(item) === key);
  let active = false;
  if (idx >= 0) {
    lib.favorites.splice(idx, 1);
  } else {
    lib.favorites.unshift(track);
    lib.favorites = lib.favorites.slice(0, 40);
    active = true;
  }
  saveMusicLibrary(lib);
  res.json({ ok: true, active, favorites: lib.favorites });
});

app.get('/api/music/download', async (req, res) => {
  const title = String(req.query.title || 'music').trim() || 'music';
  const id = String(req.query.id || '').trim();
  const rawId = String(req.query.rawId || '').trim();
  const source = String(req.query.source || '').trim();
  const previewUrl = String(req.query.previewUrl || '').trim();
  const safeName = title.replace(/[<>:"/\\|?*\x00-\x1F]/g, '_').slice(0, 80) || 'music';
  const fileName = encodeURIComponent(safeName) + '.mp3';
  const musicDir = path.join(SHARED_OUT, 'music_temp');
  fs.mkdirSync(musicDir, { recursive: true });

  const sendLocal = (filePath) => {
    if (!fs.existsSync(filePath)) return false;
    res.setHeader('Content-Type', 'audio/mpeg');
    res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${fileName}`);
    fs.createReadStream(filePath).pipe(res);
    return true;
  };

  const safeId = id.replace(/[^\w\-]/g, '_').slice(0, 80);
  if (safeId && sendLocal(path.join(musicDir, safeId + '.mp3'))) return;

  if (source === 'netease' && rawId) {
    try {
      const neteaseBase = String(process.env.NETEASE_API_BASE || '').trim().replace(/\/+$/, '');
      if (!neteaseBase) throw new Error('NETEASE_API_BASE is not configured');
      const urlData = await fetchJson(`${neteaseBase}/song/url/v1?id=${encodeURIComponent(rawId)}&level=standard`, 15000);
      const remoteUrl = String(urlData?.data?.[0]?.url || '').trim();
      if (remoteUrl) {
        const remote = new URL(remoteUrl);
        const transport = remote.protocol === 'http:' ? require('http') : require('https');
        res.setHeader('Content-Type', 'audio/mpeg');
        res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${fileName}`);
        transport.get(remoteUrl, { headers: { 'User-Agent': 'Mozilla/5.0 AgentDashboard/1.0' } }, (r) => {
          r.pipe(res);
        }).on('error', () => {
          if (!res.headersSent) res.status(502).json({ ok: false, error: '歌曲下载失败' });
          else res.end();
        });
        return;
      }
    } catch {}
  }

  if (previewUrl) {
    try {
      const remote = new URL(previewUrl);
      const transport = remote.protocol === 'http:' ? require('http') : require('https');
      res.setHeader('Content-Type', 'audio/mpeg');
      res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${fileName}`);
      transport.get(previewUrl, { headers: { 'User-Agent': 'Mozilla/5.0 AgentDashboard/1.0' } }, (r) => {
        r.pipe(res);
      }).on('error', () => {
        if (!res.headersSent) res.status(502).json({ ok: false, error: '歌曲下载失败' });
        else res.end();
      });
      return;
    } catch {}
  }

  res.status(404).json({ ok: false, error: '当前歌曲暂无可下载文件' });
});

// ── System Upgrade ───────────────────────────────────────────────

app.get('/api/version', (req, res) => {
  res.json(loadVersion());
});

app.get('/api/dev-progress', (req, res) => {
  res.json(publicDevProgress());
});

app.get('/api/codex-handoff', (req, res) => {
  try {
    const text = refreshCodexHandoff('api-view');
    res.json({
      ok: true,
      path: CODEX_HANDOFF_PATH,
      updatedAt: new Date().toISOString(),
      preview: compactAgentText(text, 3000)
    });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

app.post('/api/codex-handoff/refresh', (req, res) => {
  try {
    const text = refreshCodexHandoff(req.body?.reason || 'manual');
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `🔗 Codex 交接上下文已刷新。\n文件: ${CODEX_HANDOFF_PATH}\n后续在系统内私聊 Codex CLI 时会自动附带这份上下文。`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: 'Codex上下文同步'
    });
    res.json({ ok: true, path: CODEX_HANDOFF_PATH, preview: compactAgentText(text, 3000) });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

app.post('/api/dev-progress/:id/resume', (req, res) => {
  const data = loadDevProgress();
  const publicItems = publicDevProgress().items || [];
  const publicItem = publicItems.find(x => x.id === req.params.id);
  const item = (data.items || []).find(x => x.id === req.params.id) || publicItem;
  if (!item) return res.status(404).json({ error: '研发任务不存在' });

  const visibleStatus = publicItem?.status || item.status;
  if (visibleStatus === 'running') {
    return res.status(409).json({ error: '该研发任务仍在进行中，请稍后再试' });
  }

  const requirement = item.requirement || item.title || item.summary || '';
  if (!requirement.trim()) {
    return res.status(400).json({ error: '该研发任务缺少原始需求，无法继续' });
  }

  const config = loadConfig();
  if (item.kind === 'workflow-design') {
    const designAgent = pickWorkflowDesignAgent(config, item.executorId || item.executor);
    if (!designAgent) {
      return res.status(400).json({ error: '没有可用的本机 Agent，无法继续工作流设计' });
    }
    const resumedAt = new Date().toISOString();
    upsertDevProgress({
      id: item.id,
      status: 'resumed',
      resumedAt,
      resumedReason: '用户点击继续设计',
      summary: `${item.summary || ''}\n已在 ${resumedAt} 重新发起继续设计。`.trim()
    });
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `🔁 已继续工作流设计：${item.title || '未命名工作流'}\n原任务: ${item.id}\n执行者: ${designAgent.icon || ''} ${designAgent.name}\n系统会重新备份并启动设计，进度会打印在消息流和“当前研发进度”卡片里。`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: '工作流设计'
    });
    executeWorkflowDesignTask({ requirement, agent: designAgent, config, resumedFrom: item.id }).catch(err => {
      upsertDevProgress({
        id: item.id,
        status: 'failed',
        failedAt: new Date().toISOString(),
        error: compactAgentText(err?.stack || err?.message || String(err), 1800)
      });
      addChatMessage({
        id: crypto.randomUUID(),
        from: 'system',
        fromName: '🔔 系统',
        content: `❌ 继续工作流设计启动失败：${item.title || item.id}\n${err?.message || err}`,
        timestamp: new Date().toISOString(),
        type: 'workflow',
        topic: '工作流设计'
      });
    });
    return res.json({ ok: true, resumed: true, id: item.id, kind: item.kind, executor: designAgent.name });
  }

  const triggerName = item.triggerAgent || '';
  const triggerAgent = allConfiguredAgents(config).find(a => (
    a.id === triggerName || a.name === triggerName || `${a.icon || ''} ${a.name}`.trim() === triggerName
  )) || (triggerName ? { id: 'resume', name: triggerName, icon: '' } : null);
  const retryHint = item.title || '继续自动流程研发';
  const resumedAt = new Date().toISOString();

  upsertDevProgress({
    id: item.id,
    status: 'resumed',
    resumedAt,
    resumedReason: '用户点击继续研发',
    summary: `${item.summary || ''}\n已在 ${resumedAt} 重新发起继续研发。`.trim()
  });

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `🔁 已继续研发任务：${retryHint}\n原任务: ${item.id}\n系统会重新备份并启动 Codex，进度会继续打印在消息流和“当前研发进度”卡片里。`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: '流程自修复'
  });

  runAutoFlowRepair({ requirement, triggerAgent, config, retryHint }).catch(err => {
    upsertDevProgress({
      id: item.id,
      status: 'failed',
      failedAt: new Date().toISOString(),
      error: compactAgentText(err?.stack || err?.message || String(err), 1800)
    });
    addChatMessage({
      id: crypto.randomUUID(),
      from: 'system',
      fromName: '🔔 系统',
      content: `❌ 继续研发启动失败：${retryHint}\n${err?.message || err}`,
      timestamp: new Date().toISOString(),
      type: 'workflow',
      topic: '流程自修复'
    });
  });

  res.json({ ok: true, resumed: true, id: item.id, retryHint });
});

app.delete('/api/dev-progress/:id', (req, res) => {
  const data = loadDevProgress();
  const before = Array.isArray(data.items) ? data.items.length : 0;
  const item = (data.items || []).find(x => x.id === req.params.id);
  if (!item) return res.status(404).json({ error: '研发任务不存在' });

  data.items = (data.items || []).filter(x => x.id !== req.params.id);
  saveDevProgress(data);

  addChatMessage({
    id: crypto.randomUUID(),
    from: 'system',
    fromName: '🔔 系统',
    content: `🗑️ 已从研发进度列表删除记录：${item.title || item.id}\n记录ID: ${item.id}\n说明: 仅删除进度列表记录，未删除项目备份或实际文件。`,
    timestamp: new Date().toISOString(),
    type: 'workflow',
    topic: '研发进度'
  });

  res.json({ ok: true, deleted: before - data.items.length, id: req.params.id });
});

app.get('/api/backups', (req, res) => {
  try {
    const dirs = fs.readdirSync(BACKUPS_DIR).filter(f => {
      const full = path.join(BACKUPS_DIR, f);
      return fs.statSync(full).isDirectory();
    }).sort().reverse();
    const list = dirs.map(d => {
      const manifestPath = path.join(BACKUPS_DIR, d, 'manifest.json');
      let manifest = {};
      try { manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8')); } catch {}
      return { id: d, version: manifest.version || '?', timestamp: manifest.timestamp || d.split('_').slice(1).join('_'), task: manifest.task || '' };
    });
    res.json(list);
  } catch { res.json([]); }
});

app.post('/api/system/upgrade', async (req, res) => {
  const config = loadConfig();
  const { task, agentIds, bumpType = 'patch' } = req.body;
  if (!task?.trim()) return res.status(400).json({ error: '请描述升级内容' });
  if (!agentIds?.length) return res.status(400).json({ error: '请选择执行升级的智能体' });

  const ver = loadVersion();
  const oldVersion = ver.version;
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const backupId = `v${oldVersion}_${ts}`;
  const backupDir = path.join(BACKUPS_DIR, backupId);

  // 1) Create backup
  fs.mkdirSync(backupDir);
  const projectDir = __dirname;
  const files = fs.readdirSync(projectDir);
  let copied = 0;
  for (const f of files) {
    if (BACKUP_EXCLUDE.includes(f)) continue;
    const src = path.join(projectDir, f);
    const dst = path.join(backupDir, f);
    try {
      const st = fs.statSync(src);
      if (st.isDirectory()) {
        copyDirSync(src, dst);
      } else {
        fs.copyFileSync(src, dst);
      }
      copied++;
    } catch(e) { console.error(`[UPGRADE] backup skip ${f}:`, e.message); }
  }
  const manifest = { version: oldVersion, timestamp: new Date().toISOString(), task, backupId, files: copied };
  fs.writeFileSync(path.join(backupDir, 'manifest.json'), JSON.stringify(manifest, null, 2), 'utf-8');

  addChatMessage({
    id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
    content: `📦 备份完成: ${oldVersion} → backups/${backupId} (${copied} 个文件)`,
    timestamp: new Date().toISOString(), type: 'upgrade'
  });

  // 2) Bump version
  const parts = oldVersion.split('.').map(Number);
  if (bumpType === 'major') { parts[0]++; parts[1] = 0; parts[2] = 0; }
  else if (bumpType === 'minor') { parts[1]++; parts[2] = 0; }
  else { parts[2]++; }
  const newVersion = parts.join('.');

  // 3) Build upgrade prompt
  const agent = findAgent(agentIds[0]);
  if (!agent) {
    return res.status(404).json({ error: '智能体未找到' });
  }

  const projectFiles = fs.readdirSync(projectDir).filter(f => {
    if (BACKUP_EXCLUDE.includes(f)) return false;
    try { return fs.statSync(path.join(projectDir, f)).isFile(); } catch { return false; }
  }).join(', ');

  const upgradePrompt = `你需要对项目进行升级。

当前版本: ${oldVersion} → 目标版本: ${newVersion}
项目文件: ${projectFiles}

升级任务: ${task}

请直接修改项目文件来完成升级。修改完成后，简要说明你做了什么修改。
如果升级涉及前端 (public/index.html)，请直接编辑该文件。
如果是 CSS/JS 修改，直接编辑 index.html 中的 <style> 或 <script> 部分。`;

  const startTime = Date.now();
  const result = await runAgentChat(agent, upgradePrompt, config);
  const responseTime = Date.now() - startTime;

  const agentMsg = {
    id: crypto.randomUUID(),
    from: agent.id,
    fromName: `${agent.icon} ${agent.name} (升级)`,
    content: result.ok ? result.stdout : `❌ ${result.stderr || result.stdout || '无响应'}`,
    timestamp: new Date().toISOString(),
    responseTime,
    type: 'upgrade'
  };
  addChatMessage(agentMsg);

  // 4) Save version
  ver.version = newVersion;
  ver.history.unshift({
    version: newVersion,
    previous: oldVersion,
    task,
    agent: agent.name,
    backup: backupId,
    timestamp: new Date().toISOString()
  });
  saveVersion(ver);

  addChatMessage({
    id: crypto.randomUUID(), from: 'system', fromName: '🔔 系统',
    content: `✅ 升级完成: ${oldVersion} → ${newVersion}\n备份: ${backupId}`,
    timestamp: new Date().toISOString(), type: 'upgrade'
  });

  res.json({ ok: true, oldVersion, newVersion, backup: backupId, agentOutput: result.stdout });
});

app.post('/api/backups/:id/restore', (req, res) => {
  const backupId = req.params.id;
  const backupDir = path.join(BACKUPS_DIR, backupId);
  if (!fs.existsSync(backupDir)) {
    return res.status(404).json({ error: '备份不存在' });
  }
  const manifestPath = path.join(backupDir, 'manifest.json');
  let manifest = {};
  try { manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8')); } catch {}

  // Overwrite project files from backup
  const projectDir = __dirname;
  let restored = 0;
  try {
    const entries = fs.readdirSync(backupDir);
    for (const f of entries) {
      if (f === 'manifest.json') continue;
      const src = path.join(backupDir, f);
      const dst = path.join(projectDir, f);
      try {
        const st = fs.statSync(src);
        if (st.isDirectory()) {
          if (fs.existsSync(dst)) fs.rmSync(dst, { recursive: true, force: true });
          copyDirSync(src, dst);
        } else {
          fs.copyFileSync(src, dst);
        }
        restored++;
      } catch(e) { console.error(`[RESTORE] skip ${f}:`, e.message); }
    }
    // Restore old version from manifest
    if (manifest.version) {
      const ver = loadVersion();
      ver.version = manifest.version;
      ver.history.unshift({
        version: manifest.version,
        previous: 'restored',
        task: `从备份恢复: ${backupId}`,
        agent: 'system',
        backup: backupId,
        timestamp: new Date().toISOString()
      });
      saveVersion(ver);
    }
    res.json({ ok: true, restored, version: manifest.version });
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

function copyDirSync(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const f of fs.readdirSync(src)) {
    const s = path.join(src, f);
    const d = path.join(dst, f);
    if (fs.statSync(s).isDirectory()) {
      copyDirSync(s, d);
    } else {
      fs.copyFileSync(s, d);
    }
  }
}

// ── Auto-connect / Health Check ──────────────────────────────────

const hostStatus = {}; // hostId -> { online: bool, lastCheck: ISO, error: string }

async function checkHostHealth(hostId, hostConfig) {
  if (!hostConfig.enabled) {
    hostStatus[hostId] = { online: false, lastCheck: new Date().toISOString(), error: '已禁用' };
    return;
  }
  try {
    const result = await sshExec(hostConfig, 'echo ok', 8000);
    hostStatus[hostId] = {
      online: result.ok,
      lastCheck: new Date().toISOString(),
      error: result.ok ? null : (result.stderr || '连接超时')
    };
    // If host is online, do a quick agent status refresh
    if (result.ok) {
      const config = loadConfig();
      const agents = config.agents[hostId] || [];
      const agentChecks = agents.map(async (agent) => {
        const status = await withTimeout(
          checkRemoteAgent(agent, hostConfig),
          20000,
          { status: 'checking' }
        );
        cacheAgentStatus(agent.id, status);
      });
      await Promise.allSettled(agentChecks);
    }
  } catch (e) {
    hostStatus[hostId] = { online: false, lastCheck: new Date().toISOString(), error: e.message };
  }
}

async function autoConnectAll() {
  const config = loadConfig();
  const checks = Object.entries(config.hosts).map(([id, host]) =>
    checkHostHealth(id, host)
  );
  await Promise.allSettled(checks);
  broadcastSSE('host-status', { type: 'host-status', hosts: hostStatus });
}

// API: get host status
app.get('/api/host-status', (req, res) => {
  res.json(hostStatus);
});

// API: manual reconnect to a host
app.post('/api/hosts/:hostId/reconnect', async (req, res) => {
  const config = loadConfig();
  const host = config.hosts[req.params.hostId];
  if (!host) return res.status(404).json({ error: 'Host not found' });
  await checkHostHealth(req.params.hostId, host);
  broadcastSSE('host-status', { type: 'host-status', hosts: hostStatus });
  res.json({ ok: true, status: hostStatus[req.params.hostId] });
});

// ── Start ───────────────────────────────────────────────────────

const config = loadConfig();
const PORT = config.server.port || 3456;

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🤖 Agent Dashboard at http://localhost:${PORT} (LAN: ${publicBaseUrl(PORT)})`);
  console.log(`   Shared files: ${publicBaseUrl(PORT)}/files/`);
  const groups = Object.entries(config.agents);
  for (const [group, agents] of groups) {
    console.log(`   ${group}: ${agents.map(a => a.name).join(', ')}`);
  }
  // Auto-connect to all hosts on startup
  autoConnectAll();
  // Periodic health check every 3 minutes (reduced from 60s to avoid excessive SSH connections)
  setInterval(autoConnectAll, 180000);
});

