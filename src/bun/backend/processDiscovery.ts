import { basename } from 'node:path';
import type { AgentProcess } from './types';
import { runCommand } from './utils/shell';

interface ProcessRow {
  pid: number;
  ppid: number;
  cpuUsage: number;
  memoryBytes: number;
  command: string;
  firstArg: string;
}

function parseProcessRows(): ProcessRow[] {
  const result = runCommand(['ps', '-axo', 'pid=,ppid=,pcpu=,rss=,command=']);
  if (!result.success || !result.stdout) {
    return [];
  }

  const rows: ProcessRow[] = [];
  for (const line of result.stdout.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }

    const match = trimmed.match(/^(\d+)\s+(\d+)\s+([0-9.]+)\s+(\d+)\s+(.*)$/);
    if (!match) {
      continue;
    }

    const pid = Number.parseInt(match[1], 10);
    const ppid = Number.parseInt(match[2], 10);
    const cpuUsage = Number.parseFloat(match[3]);
    const rssKb = Number.parseInt(match[4], 10);
    const command = match[5] ?? '';
    const firstArg = command.split(/\s+/)[0] ?? '';

    if (Number.isNaN(pid) || Number.isNaN(ppid)) {
      continue;
    }

    rows.push({
      pid,
      ppid,
      cpuUsage: Number.isFinite(cpuUsage) ? cpuUsage : 0,
      memoryBytes: Number.isFinite(rssKb) ? rssKb * 1024 : 0,
      command,
      firstArg,
    });
  }

  return rows;
}

function getCwdForPid(pid: number): string | null {
  const result = runCommand(['lsof', '-a', '-p', String(pid), '-d', 'cwd', '-Fn']);
  if (!result.success || !result.stdout) {
    return null;
  }

  for (const line of result.stdout.split('\n')) {
    if (line.startsWith('n')) {
      const cwd = line.slice(1).trim();
      if (cwd) {
        return cwd;
      }
    }
  }

  return null;
}

function toAgentProcess(row: ProcessRow, cwdCache: Map<number, string | null>): AgentProcess {
  if (!cwdCache.has(row.pid)) {
    cwdCache.set(row.pid, getCwdForPid(row.pid));
  }

  return {
    pid: row.pid,
    ppid: row.ppid,
    cpuUsage: row.cpuUsage,
    memoryBytes: row.memoryBytes,
    cwd: cwdCache.get(row.pid) ?? null,
    command: row.command,
    firstArg: row.firstArg,
  };
}

function isClaudeFirstArg(firstArg: string): boolean {
  const lower = firstArg.toLowerCase();
  return lower === 'claude' || lower.endsWith('/claude');
}

function isCodexFirstArg(firstArg: string): boolean {
  const lower = firstArg.toLowerCase();
  return lower === 'codex' || lower.endsWith('/codex');
}

function isOpenCodeProcess(firstArg: string): boolean {
  return basename(firstArg).toLowerCase() === 'opencode';
}

export function findClaudeProcesses(): AgentProcess[] {
  const rows = parseProcessRows();
  const rowByPid = new Map<number, ProcessRow>();
  const claudePids = new Set<number>();

  for (const row of rows) {
    rowByPid.set(row.pid, row);
    if (isClaudeFirstArg(row.firstArg)) {
      claudePids.add(row.pid);
    }
  }

  const cwdCache = new Map<number, string | null>();
  const result: AgentProcess[] = [];

  for (const row of rows) {
    if (!isClaudeFirstArg(row.firstArg)) {
      continue;
    }

    if (row.command.includes('agent-manager-x')) {
      continue;
    }

    if (claudePids.has(row.ppid)) {
      continue;
    }

    const parent = rowByPid.get(row.ppid);
    if (parent && parent.command.includes('claude-code-acp')) {
      continue;
    }

    result.push(toAgentProcess(row, cwdCache));
  }

  return result;
}

export function findCodexProcesses(): AgentProcess[] {
  const rows = parseProcessRows();
  const cwdCache = new Map<number, string | null>();

  return rows
    .filter((row) => isCodexFirstArg(row.firstArg))
    .map((row) => toAgentProcess(row, cwdCache));
}

export function findOpenCodeProcesses(): AgentProcess[] {
  const rows = parseProcessRows();
  const cwdCache = new Map<number, string | null>();

  return rows
    .filter((row) => isOpenCodeProcess(row.firstArg))
    .map((row) => toAgentProcess(row, cwdCache));
}
