#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';

loadEnvFile('.env.local');
loadEnvFile('.env');

const cfg = {
  tsHost: env('TS_HOST', '35.168.128.177'),
  tsPort: Number(env('TS_QUERY_PORT', '10022')),
  tsUser: env('TS_QUERY_USER', 'serveradmin'),
  virtualServerId: env('TS_VIRTUAL_SERVER_ID', '1'),
  channelId: env('TS_CHANNEL_ID', '4'),
  botClientId: env('TS_BOT_CLIENT_ID', ''),
  prefix: env('APOLLO_BRIDGE_PREFIX', '@Apollo'),
  commandPrefix: env('APOLLO_BRIDGE_COMMAND_PREFIX', '!apollo'),
  botNickname: env('APOLLO_BRIDGE_NICKNAME', 'Apollo'),
  outboxDir: env('APOLLO_BRIDGE_OUTBOX_DIR', '/opt/apollo-bridge/outbox'),
  outboxIntervalMs: Number(env('APOLLO_BRIDGE_OUTBOX_INTERVAL_MS', '2500')),
  mode: env('APOLLO_BRIDGE_MODE', 'openclaw'),
  openclawBin: env('OPENCLAW_BIN', 'openclaw'),
  openclawSessionId: env('OPENCLAW_SESSION_ID', 'teamspeak-apollo'),
  openclawArgs: splitArgs(env('OPENCLAW_AGENT_ARGS', '--local --json')),
  openaiApiKey: env('OPENAI_API_KEY', ''),
  openaiModel: env('OPENAI_MODEL', 'gpt-4.1-mini'),
  cooldownMs: Number(env('APOLLO_BRIDGE_COOLDOWN_MS', '1500')),
  replyMode: env('APOLLO_REPLY_MODE', 'serverquery'),
  guiSendCommand: env('APOLLO_GUI_SEND_COMMAND', ''),
};

const state = {
  ssh: null,
  ready: false,
  setupDone: false,
  botClientId: cfg.botClientId,
  lastHandledAt: 0,
  queue: Promise.resolve(),
};

main().catch((err) => {
  console.error('[apollo-bridge] fatal:', err?.stack || err);
  process.exit(1);
});

async function main() {
  const password = getQueryPassword();
  const askpass = makeAskpass(password);

  const sshArgs = [
    '-T',
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', 'PreferredAuthentications=password',
    '-o', 'PubkeyAuthentication=no',
    '-p', String(cfg.tsPort),
    `${cfg.tsUser}@${cfg.tsHost}`,
  ];

  console.log(`[apollo-bridge] connecting to ${cfg.tsUser}@${cfg.tsHost}:${cfg.tsPort}`);
  state.ssh = spawn('setsid', ['ssh', ...sshArgs], {
    stdio: ['pipe', 'pipe', 'pipe'],
    env: {
      ...process.env,
      DISPLAY: process.env.DISPLAY || ':0',
      SSH_ASKPASS: askpass.script,
      TS_PASSFILE: askpass.passFile,
      SSH_ASKPASS_REQUIRE: 'force',
    },
  });

  state.ssh.on('exit', (code, signal) => {
    console.error(`[apollo-bridge] ssh exited code=${code} signal=${signal}`);
    askpass.cleanup();
    process.exit(code || 1);
  });

  state.ssh.stderr.on('data', (buf) => {
    const s = stripAnsi(String(buf)).trim();
    if (s) console.error(`[ssh] ${s}`);
  });

  const rl = createInterface({ input: state.ssh.stdout, crlfDelay: Infinity });
  rl.on('line', onQueryLine);

  await sleep(500);
  send(`use sid=${cfg.virtualServerId}`);
  await sleep(250);
  send('whoami');

  startOutboxPump();

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

function onQueryLine(raw) {
  const line = stripAnsi(raw).replace(/\r/g, '').trim();
  if (!line) return;

  if (line.startsWith('error id=')) {
    if (!line.includes('id=0')) console.warn(`[query] ${line}`);
    return;
  }
  if (line === 'TS3' || line.startsWith('Welcome to')) return;

  console.log(`[query] ${line}`);

  if (line.includes(' client_id=') && line.includes(' client_nickname=')) {
    const who = parseTsPairs(line);
    state.botClientId = who.client_id || state.botClientId;
    finishSetup().catch((err) => console.error('[apollo-bridge] setup error:', err?.stack || err));
    return;
  }

  if (!line.startsWith('notifytextmessage ')) return;
  const event = parseTsPairs(line.slice('notifytextmessage '.length));
  handleTextEvent(event).catch((err) => console.error('[apollo-bridge] event error:', err?.stack || err));
}

async function handleTextEvent(event) {
  const invokerId = event.invokerid || event.invoker_id || '';
  const invokerUid = event.invokeruid || '';
  if (state.botClientId && invokerId === state.botClientId) return;
  if (invokerUid === 'serveradmin') return;

  const invoker = event.invokername || 'unknown';
  const text = event.msg || '';
  if (!text) return;

  const trimmed = text.trim();
  const addressed = trimmed.toLowerCase().startsWith(cfg.prefix.toLowerCase());

  const now = Date.now();
  if (now - state.lastHandledAt < cfg.cooldownMs) return;
  state.lastHandledAt = now;

  const userMessage = addressed ? (trimmed.slice(cfg.prefix.length).trim() || trimmed) : trimmed;
  console.log(`[apollo-bridge] ${invoker}: ${userMessage}`);

  state.queue = state.queue.then(async () => {
    const commandReply = handleCommand(userMessage);
    if (commandReply) {
      await postChannelMessage(commandReply);
      return;
    }
    const reply = await askOpenClaw(invoker, userMessage);
    await postChannelMessage(reply);
  });
  await state.queue;
}

function handleCommand(message) {
  const trimmed = message.trim();
  const lower = trimmed.toLowerCase();
  if (!lower.startsWith(cfg.commandPrefix.toLowerCase())) return null;
  const rest = trimmed.slice(cfg.commandPrefix.length).trim().toLowerCase();
  if (!rest || rest === 'help') {
    return [
      'ApolloBridge commands:',
      `${cfg.commandPrefix} help — show this help`,
      `${cfg.commandPrefix} status — show bridge status`,
      `${cfg.commandPrefix} ping — health check`,
      'Otherwise, just ask a question in this channel.',
    ].join('\n');
  }
  if (rest === 'ping') return 'pong';
  if (rest === 'status') {
    return `ApolloBridge online. mode=${cfg.mode}, model=${cfg.mode === 'openai' ? cfg.openaiModel : 'openclaw'}, channel=${cfg.channelId}, nickname=${cfg.botNickname}`;
  }
  return `Unknown command. Try: ${cfg.commandPrefix} help`;
}

async function finishSetup() {
  if (state.setupDone) return;
  state.setupDone = true;
  if (cfg.botNickname) {
    send(`clientupdate client_nickname=${tsEscape(cfg.botNickname)}`);
    await sleep(250);
  }
  if (state.botClientId) {
    send(`clientmove clid=${state.botClientId} cid=${cfg.channelId}`);
    await sleep(250);
  }
  send(`servernotifyregister event=textchannel id=${cfg.channelId}`);
  await sleep(250);
  await postChannelMessage('Apollo online. Ask me anything here, or use !apollo help.');
  state.ready = true;
}

async function postChannelMessage(message) {
  for (const part of chunk(message, 900)) {
    if (cfg.replyMode === 'gui') {
      await sendViaGui(part);
    } else {
      send(`sendtextmessage targetmode=2 target=${cfg.channelId} msg=${tsEscape(part)}`);
    }
    await sleep(300);
  }
}

async function sendViaGui(message) {
  if (!cfg.guiSendCommand) throw new Error('APOLLO_REPLY_MODE=gui requires APOLLO_GUI_SEND_COMMAND.');
  const result = spawnSync(cfg.guiSendCommand, [message], {
    shell: true,
    encoding: 'utf8',
    timeout: 60_000,
    maxBuffer: 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`GUI send failed (${result.status}): ${result.stderr || result.stdout}`);
  }
}

function startOutboxPump() {
  mkdirSync(cfg.outboxDir, { recursive: true });
  setInterval(() => {
    if (!state.ready) return;
    state.queue = state.queue.then(processOutbox).catch((err) => console.error('[apollo-bridge] outbox error:', err?.stack || err));
  }, cfg.outboxIntervalMs).unref();
}

async function processOutbox() {
  const files = readdirSync(cfg.outboxDir)
    .filter((name) => name.endsWith('.txt'))
    .sort();
  for (const name of files) {
    const path = join(cfg.outboxDir, name);
    const processing = join(cfg.outboxDir, `${name}.processing`);
    try {
      if (!existsSync(path)) continue;
      renameSync(path, processing);
      const text = readFileSync(processing, 'utf8').trim();
      if (text) await postChannelMessage(text);
      renameSync(processing, join(cfg.outboxDir, `${name}.sent`));
    } catch (err) {
      console.error(`[apollo-bridge] failed outbox file ${name}:`, err?.stack || err);
      try { if (existsSync(processing)) renameSync(processing, join(cfg.outboxDir, `${name}.failed`)); } catch {}
    }
  }
}

async function askOpenClaw(invoker, message) {
  const prompt = [
    'You are Apollo speaking in a TeamSpeak text channel.',
    'Be concise, direct, analytical, clear, warm, and precise. Plain text only; no markdown tables.',
    `The TeamSpeak user ${invoker} says: ${message}`,
  ].join('\n');

  if (cfg.mode === 'openai') return askOpenAI(prompt);
  return askOpenClawCli(prompt);
}

async function askOpenAI(prompt) {
  if (!cfg.openaiApiKey || cfg.openaiApiKey === 'replace-me') {
    throw new Error('APOLLO_BRIDGE_MODE=openai requires OPENAI_API_KEY in /opt/apollo-bridge/.env.local');
  }
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      'authorization': `Bearer ${cfg.openaiApiKey}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: cfg.openaiModel,
      input: prompt,
      instructions: 'You are Apollo: brilliant, ordered, direct, analytical, clear, precise, and musical. Answer as a capable teammate in a TeamSpeak text channel.',
      max_output_tokens: 800,
    }),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`OpenAI ${response.status}: ${text}`);
  const data = JSON.parse(text);
  return data.output_text || extractResponseText(data) || '(no response)';
}

function askOpenClawCli(prompt) {
  const args = [
    'agent',
    ...cfg.openclawArgs,
    '--session-id', cfg.openclawSessionId,
    '--message', prompt,
  ];

  const result = spawnSync(cfg.openclawBin, args, {
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024,
    timeout: 600_000,
  });

  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`openclaw exited ${result.status}: ${result.stderr || result.stdout}`);
  }

  if (cfg.openclawArgs.includes('--json')) {
    const parsed = JSON.parse(result.stdout);
    return (parsed.payloads || []).map((p) => p.text).filter(Boolean).join('\n').trim() || '(no response)';
  }
  return result.stdout.trim();
}

function extractResponseText(data) {
  const parts = [];
  for (const item of data.output || []) {
    for (const content of item.content || []) {
      if (content.type === 'output_text' && content.text) parts.push(content.text);
    }
  }
  return parts.join('\n').trim();
}

function send(command) {
  console.log(`[send] ${redact(command)}`);
  state.ssh.stdin.write(`${command}\n`);
}

function shutdown() {
  try { send('quit'); } catch {}
  setTimeout(() => process.exit(0), 250).unref();
}

function getQueryPassword() {
  if (process.env.TS_QUERY_PASSWORD) return process.env.TS_QUERY_PASSWORD;
  const command = process.env.TS_QUERY_PASSWORD_COMMAND;
  if (!command) throw new Error('Set TS_QUERY_PASSWORD or TS_QUERY_PASSWORD_COMMAND.');
  const result = spawnSync(command, { shell: true, encoding: 'utf8', timeout: 30_000 });
  if (result.status !== 0) throw new Error(`TS_QUERY_PASSWORD_COMMAND failed: ${result.stderr || result.stdout}`);
  const password = result.stdout.trim();
  if (!password) throw new Error('TS_QUERY_PASSWORD_COMMAND returned an empty password.');
  return password;
}

function makeAskpass(password) {
  const dir = mkdtempSync(join(tmpdir(), 'apollo-bridge-'));
  const script = join(dir, 'askpass.sh');
  const passFile = join(dir, 'password');
  writeFileSync(passFile, password, { mode: 0o600 });
  writeFileSync(script, '#!/bin/sh\ncat "$TS_PASSFILE"\n', { mode: 0o700 });
  chmodSync(script, 0o700);
  return {
    script,
    passFile,
    cleanup() { rmSync(dir, { recursive: true, force: true }); },
  };
}

function tsEscape(value) {
  return String(value)
    .replace(/\\/g, '\\\\')
    .replace(/\//g, '\\/')
    .replace(/\|/g, '\\p')
    .replace(/ /g, '\\s')
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/\t/g, '\\t');
}

function tsUnescape(value) {
  return String(value).replace(/\\([snpvrtf\\/|])/g, (_, c) => ({
    s: ' ', n: '\n', r: '\r', t: '\t', p: '|', '/': '/', '\\': '\\', v: '\v', f: '\f',
  }[c] ?? c));
}

function parseTsPairs(s) {
  const obj = {};
  for (const part of s.split(' ')) {
    const idx = part.indexOf('=');
    if (idx < 0) continue;
    obj[part.slice(0, idx)] = tsUnescape(part.slice(idx + 1));
  }
  return obj;
}

function stripAnsi(s) {
  return s.replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, '');
}

function splitArgs(s) {
  return s.match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g)?.map((x) => x.replace(/^['"]|['"]$/g, '')) || [];
}

function chunk(s, size) {
  const out = [];
  let rest = String(s).trim();
  while (rest.length > size) {
    let cut = rest.lastIndexOf('\n', size);
    if (cut < size * 0.5) cut = rest.lastIndexOf(' ', size);
    if (cut < size * 0.5) cut = size;
    out.push(rest.slice(0, cut).trim());
    rest = rest.slice(cut).trim();
  }
  if (rest) out.push(rest);
  return out;
}

function loadEnvFile(path) {
  try {
    const text = spawnSync('cat', [path], { encoding: 'utf8' });
    if (text.status !== 0) return;
    for (const line of text.stdout.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const idx = trimmed.indexOf('=');
      if (idx < 0) continue;
      const key = trimmed.slice(0, idx).trim();
      let value = trimmed.slice(idx + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      if (!(key in process.env)) process.env[key] = value;
    }
  } catch {}
}

function env(key, fallback) {
  return process.env[key] ?? fallback;
}

function redact(s) {
  return s.replace(/PASSWORD=[^\s]+/g, 'PASSWORD=<redacted>');
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
