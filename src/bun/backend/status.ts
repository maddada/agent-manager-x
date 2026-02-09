import type { SessionStatus } from './types';

function extractTextContent(content: unknown): string {
  if (typeof content === 'string') {
    return content;
  }
  if (Array.isArray(content)) {
    for (const item of content) {
      if (item && typeof item === 'object' && 'text' in item) {
        const text = (item as { text?: unknown }).text;
        if (typeof text === 'string') {
          return text;
        }
      }
    }
  }
  return '';
}

export function hasToolUse(content: unknown): boolean {
  if (!Array.isArray(content)) {
    return false;
  }
  return content.some((item) => {
    if (!item || typeof item !== 'object') {
      return false;
    }
    const type = (item as { type?: unknown }).type;
    return type === 'tool_use';
  });
}

export function hasToolResult(content: unknown): boolean {
  if (!Array.isArray(content)) {
    return false;
  }
  return content.some((item) => {
    if (!item || typeof item !== 'object') {
      return false;
    }
    const type = (item as { type?: unknown }).type;
    return type === 'tool_result';
  });
}

export function isInterruptedRequest(content: unknown): boolean {
  const text = extractTextContent(content);
  return text.includes('[Request interrupted by user]');
}

export function isLocalSlashCommand(content: unknown): boolean {
  const text = extractTextContent(content).trim();
  const localCommands = [
    '/clear',
    '/compact',
    '/help',
    '/config',
    '/cost',
    '/doctor',
    '/init',
    '/login',
    '/logout',
    '/memory',
    '/model',
    '/permissions',
    '/pr-comments',
    '/review',
    '/status',
    '/terminal-setup',
    '/vim',
  ];

  return localCommands.some((cmd) => text === cmd || text.startsWith(`${cmd} `));
}

export function statusSortPriority(status: SessionStatus): number {
  switch (status) {
    case 'thinking':
    case 'processing':
      return 0;
    case 'waiting':
      return 1;
    case 'idle':
      return 2;
    case 'stale':
      return 3;
    default:
      return 3;
  }
}

export function determineStatus(
  lastMsgType: string | null,
  lastHasToolUse: boolean,
  lastHasToolResult: boolean,
  lastIsLocalCommand: boolean,
  lastIsInterrupted: boolean,
  fileRecentlyModified: boolean,
  messageIsStale: boolean,
): SessionStatus {
  if (messageIsStale && !fileRecentlyModified) {
    if (lastMsgType === 'assistant' || lastMsgType === 'user') {
      return 'waiting';
    }
    return 'idle';
  }

  if (lastMsgType === 'assistant') {
    if (lastHasToolUse) {
      return fileRecentlyModified ? 'processing' : 'waiting';
    }
    if (fileRecentlyModified) {
      return 'processing';
    }
    return 'waiting';
  }

  if (lastMsgType === 'user') {
    if (lastIsLocalCommand || lastIsInterrupted) {
      return 'waiting';
    }
    if (lastHasToolResult) {
      return fileRecentlyModified ? 'thinking' : 'waiting';
    }
    return fileRecentlyModified ? 'thinking' : 'waiting';
  }

  return fileRecentlyModified ? 'thinking' : 'idle';
}
