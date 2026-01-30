export type SessionStatus = 'waiting' | 'processing' | 'thinking' | 'idle' | 'stale';

export type AgentType = 'claude' | 'codex' | 'opencode';

export interface Session {
  id: string;
  agentType: AgentType;
  projectName: string;
  projectPath: string;
  gitBranch: string | null;
  githubUrl: string | null;
  status: SessionStatus;
  lastMessage: string | null;
  lastMessageRole: 'user' | 'assistant' | null;
  lastActivityAt: string;
  pid: number;
  cpuUsage: number;
  memoryBytes: number;
  activeSubagentCount: number;
  isBackground: boolean;
}

export interface SessionsResponse {
  sessions: Session[];
  backgroundSessions: Session[];
  totalCount: number;
  waitingCount: number;
}
