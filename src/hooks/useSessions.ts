import { useState, useEffect, useCallback, useRef } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { Session, SessionsResponse, AgentType } from '../types/session';
import { mergeWithStableOrder } from '../lib/sessionOrdering';

const POLL_INTERVAL = 2000; // 2 seconds

export type AgentCounts = Record<AgentType, number>;

export function useSessions() {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [waitingCount, setWaitingCount] = useState(0);
  const [agentCounts, setAgentCounts] = useState<AgentCounts>({ claude: 0, codex: 0, opencode: 0 });
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const sessionsRef = useRef<Session[]>([]);

  const updateTrayTitle = useCallback(async (total: number, waiting: number) => {
    try {
      await invoke('update_tray_title', { total, waiting });
    } catch (err) {
      console.error('Failed to update tray title:', err);
    }
  }, []);

  const fetchSessions = useCallback(async () => {
    try {
      const response = await invoke<SessionsResponse>('get_all_sessions');
      // Merge with stable ordering to prevent unnecessary reordering
      const stableSessions = mergeWithStableOrder(sessionsRef.current, response.sessions);
      sessionsRef.current = stableSessions;
      setSessions([...stableSessions]);
      setTotalCount(response.totalCount);
      setWaitingCount(response.waitingCount);

      // Compute counts by agent type
      const counts: AgentCounts = { claude: 0, codex: 0, opencode: 0 };
      for (const session of stableSessions) {
        counts[session.agentType]++;
      }
      setAgentCounts(counts);

      setError(null);

      // Update tray icon title with counts
      await updateTrayTitle(response.totalCount, response.waitingCount);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch sessions');
    } finally {
      setIsLoading(false);
    }
  }, [updateTrayTitle]);

  const focusSession = useCallback(async (session: Session) => {
    try {
      await invoke('focus_session', {
        pid: session.pid,
        projectPath: session.projectPath,
      });
    } catch (err) {
      console.error('Failed to focus session:', err);
    }
  }, []);

  const killSessionsByType = useCallback(async (agentType: AgentType) => {
    const sessionsToKill = sessionsRef.current.filter(s => s.agentType === agentType);
    // Kill all sessions in parallel for speed - don't await, fire and forget
    sessionsToKill.forEach(session =>
      invoke('kill_session', { pid: session.pid }).catch(err =>
        console.error(`Failed to kill session ${session.pid}:`, err)
      )
    );
    // Refresh to update the UI (don't await - let polling handle eventual consistency)
    fetchSessions();
  }, [fetchSessions]);

  // Kill inactive sessions (idle 5+ min)
  const killInactiveSessions = useCallback(async () => {
    const inactiveSessions = sessionsRef.current.filter(s => s.status === 'idle');
    // Kill all inactive sessions in parallel - fire and forget for speed
    inactiveSessions.forEach(session =>
      invoke('kill_session', { pid: session.pid }).catch(err =>
        console.error(`Failed to kill session ${session.pid}:`, err)
      )
    );
    // Refresh to update the UI
    fetchSessions();
  }, [fetchSessions]);

  // Kill stale sessions (10+ min)
  const killStaleSessions = useCallback(async () => {
    const staleSessions = sessionsRef.current.filter(s => s.status === 'stale');
    // Kill all stale sessions in parallel - fire and forget for speed
    staleSessions.forEach(session =>
      invoke('kill_session', { pid: session.pid }).catch(err =>
        console.error(`Failed to kill session ${session.pid}:`, err)
      )
    );
    // Refresh to update the UI
    fetchSessions();
  }, [fetchSessions]);

  const getInactiveCount = useCallback(() => {
    return sessionsRef.current.filter(s => s.status === 'idle').length;
  }, []);

  const getStaleCount = useCallback(() => {
    return sessionsRef.current.filter(s => s.status === 'stale').length;
  }, []);

  // Initial fetch
  useEffect(() => {
    fetchSessions();
  }, [fetchSessions]);

  // Polling
  useEffect(() => {
    const interval = setInterval(fetchSessions, POLL_INTERVAL);
    return () => clearInterval(interval);
  }, [fetchSessions]);

  return {
    sessions,
    totalCount,
    waitingCount,
    agentCounts,
    isLoading,
    error,
    refresh: fetchSessions,
    focusSession,
    killSessionsByType,
    killInactiveSessions,
    killStaleSessions,
    getInactiveCount,
    getStaleCount,
  };
}
