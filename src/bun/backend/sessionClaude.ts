import {
  existsSync,
  readdirSync,
  readFileSync,
  statSync,
} from 'node:fs';
import { basename, extname, join } from 'node:path';
import { determineStatus, hasToolResult, hasToolUse, isInterruptedRequest, isLocalSlashCommand, statusSortPriority } from './status';
import type { AgentProcess, Session } from './types';
import { convertDirNameToPath, convertPathToDirName } from './utils/pathConversion';
import { runCommand } from './utils/shell';

interface JsonlMessage {
  sessionId?: unknown;
  gitBranch?: unknown;
  timestamp?: unknown;
  type?: unknown;
  message?: {
    role?: unknown;
    content?: unknown;
  } | null;
}

interface ExtractedMessageData {
  sessionId: string | null;
  gitBranch: string | null;
  lastTimestamp: string | null;
  lastMessage: string | null;
  lastUserMessage: string | null;
  lastRole: string | null;
  lastMsgType: string | null;
  lastHasToolUse: boolean;
  lastHasToolResult: boolean;
  lastIsLocalCommand: boolean;
  lastIsInterrupted: boolean;
}

const STALE_MESSAGE_SECONDS = 30;
const FILE_RECENT_SECONDS = 3;
const IDLE_THRESHOLD_SECONDS = 5 * 60;
const STALE_THRESHOLD_SECONDS = 10 * 60;

function parseJsonLine(line: string): JsonlMessage | null {
  try {
    return JSON.parse(line) as JsonlMessage;
  } catch {
    return null;
  }
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function getTextFromContent(content: unknown): string | null {
  if (typeof content === 'string' && content.length > 0) {
    return content;
  }
  if (Array.isArray(content)) {
    for (const item of content) {
      if (!item || typeof item !== 'object') {
        continue;
      }
      const text = (item as { text?: unknown }).text;
      if (typeof text === 'string' && text.length > 0) {
        return text;
      }
    }
  }
  return null;
}

function extractMessageData(jsonlPath: string): ExtractedMessageData | null {
  let content: string;
  try {
    content = readFileSync(jsonlPath, 'utf8');
  } catch {
    return null;
  }

  const allLines = content.split('\n').filter(Boolean);
  const lastLines = allLines.slice(-100);

  let sessionId: string | null = null;
  let gitBranch: string | null = null;
  let lastTimestamp: string | null = null;
  let lastMessage: string | null = null;
  let lastUserMessage: string | null = null;
  let lastRole: string | null = null;
  let lastMsgType: string | null = null;
  let lastHasToolUse = false;
  let lastHasToolResult = false;
  let lastIsLocalCommand = false;
  let lastIsInterrupted = false;
  let foundStatusInfo = false;

  for (let i = lastLines.length - 1; i >= 0; i -= 1) {
    const msg = parseJsonLine(lastLines[i]);
    if (!msg) {
      continue;
    }

    if (!sessionId) {
      sessionId = asString(msg.sessionId);
    }
    if (!gitBranch) {
      gitBranch = asString(msg.gitBranch);
    }
    if (!lastTimestamp) {
      lastTimestamp = asString(msg.timestamp);
    }

    if (!foundStatusInfo && msg.message && typeof msg.message === 'object') {
      const contentValue = msg.message.content;
      const hasContent =
        (typeof contentValue === 'string' && contentValue.length > 0) ||
        (Array.isArray(contentValue) && contentValue.length > 0);

      if (hasContent) {
        lastMsgType = asString(msg.type);
        lastRole = asString(msg.message.role);
        lastHasToolUse = hasToolUse(contentValue);
        lastHasToolResult = hasToolResult(contentValue);
        lastIsLocalCommand = isLocalSlashCommand(contentValue);
        lastIsInterrupted = isInterruptedRequest(contentValue);
        foundStatusInfo = true;
      }
    }

    if (sessionId && foundStatusInfo) {
      break;
    }
  }

  for (let i = lastLines.length - 1; i >= 0; i -= 1) {
    const msg = parseJsonLine(lastLines[i]);
    if (!msg || !msg.message || typeof msg.message !== 'object') {
      continue;
    }

    const text = getTextFromContent(msg.message.content);
    if (!text) {
      continue;
    }

    if (!lastMessage) {
      lastMessage = text;
    }

    if (!lastUserMessage && asString(msg.message.role) === 'user') {
      lastUserMessage = text;
    }

    if (lastMessage && lastUserMessage) {
      break;
    }
  }

  return {
    sessionId,
    gitBranch,
    lastTimestamp,
    lastMessage,
    lastUserMessage,
    lastRole,
    lastMsgType,
    lastHasToolUse,
    lastHasToolResult,
    lastIsLocalCommand,
    lastIsInterrupted,
  };
}

function truncateChars(text: string, maxChars: number): string {
  const chars = [...text];
  if (chars.length <= maxChars) {
    return text;
  }
  return `${chars.slice(0, maxChars).join('')}...`;
}

function ageSecondsFromTimestamp(timestamp: string | null): number | null {
  if (!timestamp) {
    return null;
  }
  const millis = Date.parse(timestamp);
  if (!Number.isFinite(millis)) {
    return null;
  }
  return Math.floor((Date.now() - millis) / 1000);
}

function getGithubUrl(projectPath: string): string | null {
  const result = runCommand(['git', 'remote', 'get-url', 'origin'], { cwd: projectPath });
  if (!result.success) {
    return null;
  }

  const remoteUrl = result.stdout.trim();
  if (remoteUrl.startsWith('git@github.com:')) {
    const pathPart = remoteUrl.slice('git@github.com:'.length).replace(/\.git$/, '');
    return `https://github.com/${pathPart}`;
  }

  if (remoteUrl.startsWith('https://github.com/')) {
    return remoteUrl.replace(/\.git$/, '');
  }

  return null;
}

function shouldShowLastUserMessage(status: Session['status'], lastMessage: string | null): boolean {
  if (status !== 'thinking' && status !== 'processing') {
    return false;
  }

  if (!lastMessage) {
    return true;
  }

  const trimmed = lastMessage.trim().toLowerCase();
  return trimmed.length === 0 || trimmed === '(no content)' || trimmed === 'no content';
}

function parseSessionFile(
  jsonlPath: string,
  projectPath: string,
  pid: number,
  cpuUsage: number,
  memoryBytes: number,
): Session | null {
  const data = extractMessageData(jsonlPath);
  if (!data || !data.sessionId) {
    return null;
  }

  const fileAgeSeconds = (() => {
    try {
      const modifiedMs = statSync(jsonlPath).mtimeMs;
      return (Date.now() - modifiedMs) / 1000;
    } catch {
      return Number.POSITIVE_INFINITY;
    }
  })();

  const fileRecentlyModified = fileAgeSeconds < FILE_RECENT_SECONDS;
  const messageAgeSeconds = ageSecondsFromTimestamp(data.lastTimestamp);
  const messageIsStale = messageAgeSeconds === null || messageAgeSeconds > STALE_MESSAGE_SECONDS;

  let status = determineStatus(
    data.lastMsgType,
    data.lastHasToolUse,
    data.lastHasToolResult,
    data.lastIsLocalCommand,
    data.lastIsInterrupted,
    fileRecentlyModified,
    messageIsStale,
  );

  if ((status === 'waiting' || status === 'idle') && messageAgeSeconds !== null) {
    if (messageAgeSeconds >= STALE_THRESHOLD_SECONDS) {
      status = 'stale';
    } else if (messageAgeSeconds >= IDLE_THRESHOLD_SECONDS) {
      status = 'idle';
    }
  }

  let lastMessage = data.lastMessage;
  let lastMessageRole: Session['lastMessageRole'] =
    data.lastRole === 'assistant' || data.lastRole === 'user'
      ? data.lastRole
      : null;

  if (shouldShowLastUserMessage(status, lastMessage) && data.lastUserMessage) {
    lastMessage = data.lastUserMessage;
    lastMessageRole = 'user';
  }

  if (lastMessage) {
    lastMessage = truncateChars(lastMessage, 5000);
  }

  return {
    id: data.sessionId,
    agentType: 'claude',
    projectName: basename(projectPath) || 'Unknown',
    projectPath,
    gitBranch: data.gitBranch,
    githubUrl: getGithubUrl(projectPath),
    status,
    lastMessage,
    lastMessageRole,
    lastActivityAt: data.lastTimestamp ?? 'Unknown',
    pid,
    cpuUsage,
    memoryBytes,
    activeSubagentCount: 0,
    isBackground: false,
  };
}

function isSubagentFile(path: string): boolean {
  const name = basename(path);
  return name.startsWith('agent-') && name.endsWith('.jsonl');
}

function getSubagentSessionId(path: string): string | null {
  let content: string;
  try {
    content = readFileSync(path, 'utf8');
  } catch {
    return null;
  }

  const lines = content.split('\n').slice(0, 5);
  for (const line of lines) {
    const parsed = parseJsonLine(line);
    const value = parsed ? asString(parsed.sessionId) : null;
    if (value) {
      return value;
    }
  }

  return null;
}

function countActiveSubagents(projectDir: string, parentSessionId: string): number {
  const thresholdMs = 30_000;
  let count = 0;

  const entries = readdirSync(projectDir, { withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isFile()) {
      continue;
    }

    const path = join(projectDir, entry.name);
    if (!isSubagentFile(path)) {
      continue;
    }

    const modifiedMs = statSync(path).mtimeMs;
    if (Date.now() - modifiedMs > thresholdMs) {
      continue;
    }

    if (getSubagentSessionId(path) === parentSessionId) {
      count += 1;
    }
  }

  return count;
}

function getRecentlyActiveJsonlFiles(projectDir: string): string[] {
  const entries = readdirSync(projectDir, { withFileTypes: true });
  const files: Array<{ path: string; modifiedMs: number }> = [];

  for (const entry of entries) {
    if (!entry.isFile()) {
      continue;
    }

    if (extname(entry.name) !== '.jsonl') {
      continue;
    }

    const path = join(projectDir, entry.name);
    if (isSubagentFile(path)) {
      continue;
    }

    try {
      files.push({ path, modifiedMs: statSync(path).mtimeMs });
    } catch {
      // Ignore unreadable files.
    }
  }

  files.sort((a, b) => b.modifiedMs - a.modifiedMs);
  return files.map((file) => file.path);
}

function findSessionForProcess(
  jsonlFiles: string[],
  projectDir: string,
  projectPath: string,
  process: AgentProcess,
  index: number,
): Session | null {
  const primaryJsonl = jsonlFiles[index];
  if (!primaryJsonl) {
    return null;
  }

  const session = parseSessionFile(
    primaryJsonl,
    projectPath,
    process.pid,
    process.cpuUsage,
    process.memoryBytes,
  );

  if (!session) {
    return null;
  }

  session.activeSubagentCount = countActiveSubagents(projectDir, session.id);

  const now = Date.now();
  const activeThresholdMs = 10_000;

  for (const jsonlPath of jsonlFiles) {
    if (jsonlPath === primaryJsonl) {
      continue;
    }

    let modifiedMs: number;
    try {
      modifiedMs = statSync(jsonlPath).mtimeMs;
    } catch {
      continue;
    }

    if (now - modifiedMs >= activeThresholdMs) {
      continue;
    }

    const otherSession = parseSessionFile(
      jsonlPath,
      projectPath,
      process.pid,
      process.cpuUsage,
      process.memoryBytes,
    );

    if (!otherSession || otherSession.id !== session.id) {
      continue;
    }

    const currentPriority = statusSortPriority(session.status);
    const otherPriority = statusSortPriority(otherSession.status);
    if (otherPriority < currentPriority) {
      session.status = otherSession.status;
    }
  }

  const messageAgeSeconds = ageSecondsFromTimestamp(session.lastActivityAt);
  const messageIsStaleForCpu = messageAgeSeconds === null || messageAgeSeconds > STALE_MESSAGE_SECONDS;

  if (
    session.status === 'waiting'
    && process.cpuUsage > 15
    && !messageIsStaleForCpu
  ) {
    session.status = 'processing';
  }

  return session;
}

export function getClaudeSessions(processes: AgentProcess[]): Session[] {
  const sessions: Session[] = [];

  const cwdToProcesses = new Map<string, AgentProcess[]>();
  for (const process of processes) {
    if (!process.cwd) {
      continue;
    }
    const existing = cwdToProcesses.get(process.cwd) ?? [];
    existing.push(process);
    cwdToProcesses.set(process.cwd, existing);
  }

  const home = process.env.HOME;
  if (!home) {
    return sessions;
  }

  const claudeProjectsDir = join(home, '.claude', 'projects');
  if (!existsSync(claudeProjectsDir)) {
    return sessions;
  }

  const entries = readdirSync(claudeProjectsDir, { withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }

    const dirName = entry.name;
    const dirPath = join(claudeProjectsDir, dirName);
    const projectPath = convertDirNameToPath(dirName);

    let matchingProcesses = cwdToProcesses.get(projectPath);

    if (!matchingProcesses) {
      const matchingCwd = [...cwdToProcesses.keys()].find((cwd) => {
        const cwdAsDir = convertPathToDirName(cwd);
        if (cwdAsDir === dirName) {
          return true;
        }
        const normalizedCwd = cwdAsDir.replace(/_/g, '-').toLowerCase();
        const normalizedDir = dirName.replace(/_/g, '-').toLowerCase();
        return normalizedCwd === normalizedDir;
      });
      if (matchingCwd) {
        matchingProcesses = cwdToProcesses.get(matchingCwd);
      }
    }

    if (!matchingProcesses || matchingProcesses.length === 0) {
      continue;
    }

    const jsonlFiles = getRecentlyActiveJsonlFiles(dirPath);

    matchingProcesses.forEach((process, index) => {
      const actualPath = process.cwd ?? projectPath;
      const session = findSessionForProcess(jsonlFiles, dirPath, actualPath, process, index);
      if (session) {
        sessions.push(session);
      }
    });
  }

  return sessions;
}
