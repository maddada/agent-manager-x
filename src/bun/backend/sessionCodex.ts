import {
  existsSync,
  readdirSync,
  readFileSync,
  statSync,
} from 'node:fs';
import { basename, extname, join } from 'node:path';
import type { AgentProcess, Session } from './types';

interface CodexSessionFile {
  path: string;
  modifiedMs: number;
  cwd: string | null;
  sessionId: string | null;
  lastMessage: string | null;
  lastRole: string | null;
  lastActivityAt: string | null;
}

function safeParseJson(line: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(line) as unknown;
    return parsed && typeof parsed === 'object' ? (parsed as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function truncateMessage(text: string, maxChars: number): string {
  const chars = [...text];
  if (chars.length <= maxChars) {
    return text;
  }
  return `${chars.slice(0, maxChars).join('')}...`;
}

function extractTextFromPayload(payload: Record<string, unknown>): string | null {
  const content = payload.content;
  if (!Array.isArray(content)) {
    return null;
  }

  for (const item of content) {
    if (!item || typeof item !== 'object') {
      continue;
    }
    const itemObj = item as Record<string, unknown>;
    const contentType = asString(itemObj.type);
    if (contentType !== 'output_text' && contentType !== 'input_text') {
      continue;
    }
    const text = asString(itemObj.text);
    if (text) {
      return text;
    }
  }

  return null;
}

function normalizeCodexMessageText(text: string): string | null {
  const trimmed = text.trim();
  if (!trimmed) {
    return null;
  }

  if (
    trimmed.startsWith('<environment_context>')
    || trimmed.startsWith('<permissions instructions>')
    || trimmed.startsWith('# AGENTS.md instructions')
  ) {
    return null;
  }

  return truncateMessage(trimmed, 200);
}

function extractCwdFromEnvironmentContext(text: string): string | null {
  if (!text.includes('<cwd>')) {
    return null;
  }

  const match = text.match(/<cwd>([\s\S]*?)<\/cwd>/);
  if (!match) {
    return null;
  }

  const cwd = match[1].trim();
  return cwd.length > 0 ? cwd : null;
}

function selectBestCwd(
  cwdTurn: string | null,
  cwdEnv: string | null,
  cwdMeta: string | null,
): string | null {
  for (const candidate of [cwdTurn, cwdEnv, cwdMeta]) {
    if (candidate && candidate.trim() && candidate.trim() !== '/') {
      return candidate.trim();
    }
  }

  for (const candidate of [cwdTurn, cwdEnv, cwdMeta]) {
    if (candidate && candidate.trim()) {
      return candidate.trim();
    }
  }

  return null;
}

function parseCodexSessionFile(path: string, modifiedMs: number): CodexSessionFile | null {
  let content: string;
  try {
    content = readFileSync(path, 'utf8');
  } catch {
    return null;
  }

  let sessionId: string | null = null;
  let cwdMeta: string | null = null;
  let cwdTurn: string | null = null;
  let cwdEnv: string | null = null;
  let lastMessage: string | null = null;
  let lastRole: string | null = null;
  let lastActivityAt: string | null = null;

  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }

    const parsed = safeParseJson(trimmed);
    if (!parsed) {
      continue;
    }

    const lineType = asString(parsed.type) ?? '';

    if (lineType === 'session_meta') {
      const payload = parsed.payload;
      if (payload && typeof payload === 'object') {
        const payloadObj = payload as Record<string, unknown>;
        sessionId = sessionId ?? asString(payloadObj.id);
        cwdMeta = cwdMeta ?? asString(payloadObj.cwd);
      }
      continue;
    }

    if (lineType === 'turn_context') {
      const payload = parsed.payload;
      if (payload && typeof payload === 'object') {
        const cwd = asString((payload as Record<string, unknown>).cwd);
        if (cwd) {
          cwdTurn = cwd;
        }
      }
      continue;
    }

    if (lineType === 'response_item') {
      const payload = parsed.payload;
      if (!payload || typeof payload !== 'object') {
        continue;
      }

      const payloadObj = payload as Record<string, unknown>;
      if (asString(payloadObj.type) !== 'message') {
        continue;
      }

      const text = extractTextFromPayload(payloadObj);
      if (!text) {
        continue;
      }

      const cwd = extractCwdFromEnvironmentContext(text);
      if (cwd) {
        cwdEnv = cwd;
      }

      const role = asString(payloadObj.role);
      if (role === 'assistant' || role === 'user') {
        const cleaned = normalizeCodexMessageText(text);
        if (cleaned) {
          lastMessage = cleaned;
          lastRole = role;
          lastActivityAt = asString(parsed.timestamp);
        }
      }
      continue;
    }

    if (lineType === 'event_msg') {
      const payload = parsed.payload;
      if (!payload || typeof payload !== 'object') {
        continue;
      }

      const payloadObj = payload as Record<string, unknown>;
      if (asString(payloadObj.type) !== 'user_message') {
        continue;
      }

      const message = asString(payloadObj.message);
      if (!message) {
        continue;
      }

      const cwd = extractCwdFromEnvironmentContext(message);
      if (cwd) {
        cwdEnv = cwd;
      }

      const cleaned = normalizeCodexMessageText(message);
      if (cleaned) {
        lastMessage = cleaned;
        lastRole = 'user';
        lastActivityAt = asString(parsed.timestamp);
      }
    }
  }

  return {
    path,
    modifiedMs,
    cwd: selectBestCwd(cwdTurn, cwdEnv, cwdMeta),
    sessionId,
    lastMessage,
    lastRole,
    lastActivityAt,
  };
}

function collectCodexSessionFiles(codexDir: string): CodexSessionFile[] {
  const out: CodexSessionFile[] = [];
  const stack: string[] = [codexDir];

  while (stack.length > 0) {
    const current = stack.pop();
    if (!current) {
      continue;
    }

    let entries;
    try {
      entries = readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      const path = join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(path);
        continue;
      }
      if (!entry.isFile() || extname(entry.name) !== '.jsonl') {
        continue;
      }

      let modifiedMs: number;
      try {
        modifiedMs = statSync(path).mtimeMs;
      } catch {
        continue;
      }

      const parsed = parseCodexSessionFile(path, modifiedMs);
      if (parsed) {
        out.push(parsed);
      }
    }
  }

  return out;
}

function determineStatus(cpuUsage: number, lastRole: string | null, modifiedMs: number): Session['status'] {
  const ageSecs = Math.floor((Date.now() - modifiedMs) / 1000);

  let status: Session['status'];
  if (cpuUsage > 15 || lastRole === 'user') {
    status = 'processing';
  } else {
    status = 'waiting';
  }

  if (status === 'waiting') {
    if (ageSecs >= 10 * 60) {
      status = 'stale';
    } else if (ageSecs >= 5 * 60) {
      status = 'idle';
    }
  }

  return status;
}

function buildSessionFromFile(file: CodexSessionFile, process: AgentProcess): Session {
  const projectPath = file.cwd ?? process.cwd ?? '/';
  const projectName = basename(projectPath) || 'Unknown';

  const sessionId =
    basename(file.path, '.jsonl')
    || file.sessionId
    || `codex-${process.pid}`;

  const status = determineStatus(process.cpuUsage, file.lastRole, file.modifiedMs);

  return {
    id: sessionId,
    agentType: 'codex',
    projectName,
    projectPath,
    gitBranch: null,
    githubUrl: null,
    status,
    lastMessage: file.lastMessage,
    lastMessageRole: file.lastRole === 'assistant' || file.lastRole === 'user' ? file.lastRole : null,
    lastActivityAt: file.lastActivityAt ?? new Date(file.modifiedMs).toISOString(),
    pid: process.pid,
    cpuUsage: process.cpuUsage,
    memoryBytes: process.memoryBytes,
    activeSubagentCount: 0,
    isBackground:
      projectPath === '/'
      && (!file.lastMessage || file.lastMessage.trim().length === 0),
  };
}

function fallbackSession(process: AgentProcess): Session {
  const projectPath = process.cwd ?? '/';
  const projectName = basename(projectPath) || 'Unknown';

  return {
    id: `codex-${process.pid}`,
    agentType: 'codex',
    projectName,
    projectPath,
    gitBranch: null,
    githubUrl: null,
    status: process.cpuUsage > 15 ? 'processing' : 'stale',
    lastMessage: null,
    lastMessageRole: null,
    lastActivityAt: new Date().toISOString(),
    pid: process.pid,
    cpuUsage: process.cpuUsage,
    memoryBytes: process.memoryBytes,
    activeSubagentCount: 0,
    isBackground: projectPath === '/',
  };
}

export function getCodexSessions(processes: AgentProcess[]): Session[] {
  const sessions: Session[] = [];
  if (processes.length === 0) {
    return sessions;
  }

  const home = process.env.HOME;
  if (!home) {
    return sessions;
  }

  const codexDir = join(home, '.codex', 'sessions');
  if (!existsSync(codexDir)) {
    return sessions;
  }

  const files = collectCodexSessionFiles(codexDir);
  const filesByCwd = new Map<string, number[]>();

  files.forEach((file, index) => {
    if (!file.cwd) {
      return;
    }
    const list = filesByCwd.get(file.cwd) ?? [];
    list.push(index);
    filesByCwd.set(file.cwd, list);
  });

  for (const [cwd, indices] of filesByCwd) {
    indices.sort((a, b) => files[b].modifiedMs - files[a].modifiedMs);
    filesByCwd.set(cwd, indices);
  }

  const fallbackQueue = files
    .map((_, index) => index)
    .sort((a, b) => files[b].modifiedMs - files[a].modifiedMs);

  const used = new Array(files.length).fill(false);

  for (const process of processes) {
    let assigned: number | null = null;

    if (process.cwd) {
      const queue = filesByCwd.get(process.cwd);
      if (queue) {
        while (queue.length > 0) {
          const idx = queue.shift();
          if (idx !== undefined && !used[idx]) {
            assigned = idx;
            break;
          }
        }
      }
    }

    if (assigned === null) {
      while (fallbackQueue.length > 0) {
        const idx = fallbackQueue.shift();
        if (idx !== undefined && !used[idx]) {
          assigned = idx;
          break;
        }
      }
    }

    if (assigned !== null) {
      used[assigned] = true;
      sessions.push(buildSessionFromFile(files[assigned], process));
      continue;
    }

    sessions.push(fallbackSession(process));
  }

  return sessions;
}
