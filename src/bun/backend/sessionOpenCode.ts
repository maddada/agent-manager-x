import {
  existsSync,
  readdirSync,
  readFileSync,
} from 'node:fs';
import { basename, extname, join } from 'node:path';
import type { AgentProcess, Session } from './types';

interface OpenCodeProject {
  id: string;
  worktree: string;
  sandboxes?: string[];
}

interface OpenCodeSessionData {
  id: string;
  directory?: string;
  title?: string;
  time?: {
    updated?: number;
  };
}

interface OpenCodeMessage {
  id: string;
  role: string;
  time?: {
    created?: number;
  };
}

interface OpenCodePart {
  type: string;
  text?: string;
}

function safeParse<T>(content: string): T | null {
  try {
    return JSON.parse(content) as T;
  } catch {
    return null;
  }
}

function loadProjects(storagePath: string): OpenCodeProject[] {
  const projectDir = join(storagePath, 'project');
  if (!existsSync(projectDir)) {
    return [];
  }

  const projects: OpenCodeProject[] = [];
  for (const entry of readdirSync(projectDir, { withFileTypes: true })) {
    if (!entry.isFile() || extname(entry.name) !== '.json') {
      continue;
    }

    const parsed = safeParse<OpenCodeProject>(readFileSync(join(projectDir, entry.name), 'utf8'));
    if (parsed && typeof parsed.id === 'string' && typeof parsed.worktree === 'string') {
      projects.push(parsed);
    }
  }

  return projects;
}

function findLatestSessionInDir(
  sessionDir: string,
  filterDirectory: string | null,
): OpenCodeSessionData | null {
  if (!existsSync(sessionDir)) {
    return null;
  }

  let latest: OpenCodeSessionData | null = null;
  let latestUpdated = -1;

  for (const entry of readdirSync(sessionDir, { withFileTypes: true })) {
    if (!entry.isFile() || extname(entry.name) !== '.json') {
      continue;
    }

    const parsed = safeParse<OpenCodeSessionData>(readFileSync(join(sessionDir, entry.name), 'utf8'));
    if (!parsed) {
      continue;
    }

    const directory = parsed.directory ?? '';
    if (filterDirectory) {
      if (directory !== filterDirectory && !filterDirectory.startsWith(`${directory}/`)) {
        continue;
      }
    }

    const updated = parsed.time?.updated ?? 0;
    if (updated > latestUpdated) {
      latest = parsed;
      latestUpdated = updated;
    }
  }

  return latest;
}

function truncateChars(text: string, maxChars: number): string {
  const chars = [...text];
  if (chars.length <= maxChars) {
    return text;
  }
  return `${chars.slice(0, maxChars).join('')}...`;
}

function getMessageText(storagePath: string, messageId: string): string | null {
  const partDir = join(storagePath, 'part', messageId);
  if (!existsSync(partDir)) {
    return null;
  }

  let textContent: string | null = null;
  let reasoningContent: string | null = null;

  for (const entry of readdirSync(partDir, { withFileTypes: true })) {
    if (!entry.isFile() || extname(entry.name) !== '.json') {
      continue;
    }

    const parsed = safeParse<OpenCodePart>(readFileSync(join(partDir, entry.name), 'utf8'));
    if (!parsed || typeof parsed.type !== 'string') {
      continue;
    }

    if (parsed.type === 'text' && typeof parsed.text === 'string') {
      textContent = parsed.text;
    } else if (parsed.type === 'reasoning' && typeof parsed.text === 'string' && !reasoningContent) {
      reasoningContent = parsed.text;
    }
  }

  const content = textContent ?? reasoningContent;
  if (!content) {
    return null;
  }

  const trimmed = content.trim();
  if (trimmed.startsWith('<') && (trimmed.includes('ultrawork') || trimmed.includes('mode>'))) {
    return null;
  }

  return truncateChars(content, 200);
}

function getLastMessage(storagePath: string, sessionId: string): {
  role: string | null;
  text: string | null;
  created: number;
} {
  const messageDir = join(storagePath, 'message', sessionId);
  if (!existsSync(messageDir)) {
    return { role: null, text: null, created: 0 };
  }

  const messages: Array<{ role: string; id: string; created: number }> = [];

  for (const entry of readdirSync(messageDir, { withFileTypes: true })) {
    if (!entry.isFile() || extname(entry.name) !== '.json') {
      continue;
    }

    const parsed = safeParse<OpenCodeMessage>(readFileSync(join(messageDir, entry.name), 'utf8'));
    if (!parsed || typeof parsed.id !== 'string' || typeof parsed.role !== 'string') {
      continue;
    }

    messages.push({
      role: parsed.role,
      id: parsed.id,
      created: parsed.time?.created ?? 0,
    });
  }

  messages.sort((a, b) => b.created - a.created);

  for (const message of messages) {
    const text = getMessageText(storagePath, message.id);
    if (text) {
      return { role: message.role, text, created: message.created };
    }
  }

  return { role: null, text: null, created: 0 };
}

function determineStatus(process: AgentProcess, lastRole: string | null, updatedMs: number): Session['status'] {
  let status: Session['status'];
  if (process.cpuUsage > 15) {
    status = 'processing';
  } else if (lastRole === 'assistant') {
    status = 'waiting';
  } else if (lastRole === 'user') {
    status = 'processing';
  } else {
    status = 'waiting';
  }

  if (status === 'waiting') {
    const ageSecs = Math.floor(Date.now() / 1000) - Math.floor(updatedMs / 1000);
    if (ageSecs >= 10 * 60) {
      status = 'stale';
    } else if (ageSecs >= 5 * 60) {
      status = 'idle';
    }
  }

  return status;
}

function buildSession(
  storagePath: string,
  sessionData: OpenCodeSessionData,
  process: AgentProcess,
  projectPath: string,
): Session {
  const { role, text } = getLastMessage(storagePath, sessionData.id);
  const updatedMs = sessionData.time?.updated ?? 0;

  const status = determineStatus(process, role, updatedMs);
  const fallbackTitle = sessionData.title && sessionData.title.length > 0 ? sessionData.title : null;

  return {
    id: sessionData.id,
    agentType: 'opencode',
    projectName: basename(projectPath) || 'Unknown',
    projectPath,
    gitBranch: null,
    githubUrl: null,
    status,
    lastMessage: text ?? fallbackTitle,
    lastMessageRole: role === 'assistant' || role === 'user' ? role : null,
    lastActivityAt: updatedMs > 0 ? new Date(updatedMs).toISOString() : 'Unknown',
    pid: process.pid,
    cpuUsage: process.cpuUsage,
    memoryBytes: process.memoryBytes,
    activeSubagentCount: 0,
    isBackground: false,
  };
}

function findMatchingProcess(
  processByCwd: Map<string, AgentProcess>,
  project: OpenCodeProject,
): AgentProcess | null {
  for (const [cwd, process] of processByCwd) {
    if (cwd === project.worktree || cwd.startsWith(`${project.worktree}/`)) {
      return process;
    }

    const sandboxes = project.sandboxes ?? [];
    for (const sandbox of sandboxes) {
      if (cwd === sandbox || cwd.startsWith(`${sandbox}/`)) {
        return process;
      }
    }
  }

  return null;
}

function getLatestSessionForProject(
  storagePath: string,
  project: OpenCodeProject,
  process: AgentProcess,
): Session | null {
  const sessionDir = join(storagePath, 'session', project.id);
  const latest = findLatestSessionInDir(sessionDir, null);
  if (!latest) {
    return null;
  }

  const projectPath = process.cwd ?? project.worktree;
  return buildSession(storagePath, latest, process, projectPath);
}

function getGlobalSessionForDirectory(
  storagePath: string,
  directory: string,
  process: AgentProcess,
): Session | null {
  const sessionDir = join(storagePath, 'session', 'global');
  const latest = findLatestSessionInDir(sessionDir, directory);
  if (!latest) {
    return null;
  }

  return buildSession(storagePath, latest, process, latest.directory ?? directory);
}

export function getOpenCodeSessions(processes: AgentProcess[]): Session[] {
  const sessions: Session[] = [];
  if (processes.length === 0) {
    return sessions;
  }

  const home = process.env.HOME;
  if (!home) {
    return sessions;
  }

  const storagePath = join(home, '.local', 'share', 'opencode', 'storage');
  if (!existsSync(storagePath)) {
    return sessions;
  }

  const processByCwd = new Map<string, AgentProcess>();
  for (const process of processes) {
    if (process.cwd) {
      processByCwd.set(process.cwd, process);
    }
  }

  const projects = loadProjects(storagePath);
  const matchedPids = new Set<number>();

  for (const project of projects) {
    if (project.id === 'global') {
      continue;
    }

    const process = findMatchingProcess(processByCwd, project);
    if (!process) {
      continue;
    }

    matchedPids.add(process.pid);
    const session = getLatestSessionForProject(storagePath, project, process);
    if (session) {
      sessions.push(session);
    }
  }

  for (const process of processes) {
    if (matchedPids.has(process.pid) || !process.cwd) {
      continue;
    }

    const session = getGlobalSessionForDirectory(storagePath, process.cwd, process);
    if (session) {
      sessions.push(session);
    }
  }

  return sessions;
}
