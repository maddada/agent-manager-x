import { findClaudeProcesses, findCodexProcesses, findOpenCodeProcesses } from './processDiscovery';
import { getClaudeSessions } from './sessionClaude';
import { getCodexSessions } from './sessionCodex';
import { getOpenCodeSessions } from './sessionOpenCode';
import { statusSortPriority } from './status';
import type { AgentType, Session, SessionsResponse } from './types';

function activityTimestamp(value: string): number {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function agentSortKey(agentType: AgentType): number {
  if (agentType === 'claude') {
    return 0;
  }
  if (agentType === 'codex') {
    return 1;
  }
  return 2;
}

export function getAllSessions(): SessionsResponse {
  const claudeSessions = getClaudeSessions(findClaudeProcesses());
  const codexSessions = getCodexSessions(findCodexProcesses());
  const openCodeSessions = getOpenCodeSessions(findOpenCodeProcesses());

  const allSessions = [...claudeSessions, ...codexSessions, ...openCodeSessions];

  const foreground: Session[] = [];
  const background: Session[] = [];

  for (const session of allSessions) {
    if (session.isBackground) {
      background.push(session);
    } else {
      foreground.push(session);
    }
  }

  foreground.sort((a, b) => {
    const priorityDelta = statusSortPriority(a.status) - statusSortPriority(b.status);
    if (priorityDelta !== 0) {
      return priorityDelta;
    }
    return activityTimestamp(b.lastActivityAt) - activityTimestamp(a.lastActivityAt);
  });

  background.sort((a, b) => {
    const keyDelta = agentSortKey(a.agentType) - agentSortKey(b.agentType);
    if (keyDelta !== 0) {
      return keyDelta;
    }
    return activityTimestamp(b.lastActivityAt) - activityTimestamp(a.lastActivityAt);
  });

  const waitingCount = foreground.filter((session) => session.status === 'waiting').length;

  return {
    sessions: foreground,
    backgroundSessions: background,
    totalCount: foreground.length,
    waitingCount,
  };
}
