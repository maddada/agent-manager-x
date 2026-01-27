// App header component with title, badges, and action buttons

import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { SettingsIcon, RefreshIcon, BellIcon, VoiceIcon } from './icons';
import type { AgentType } from '@/types/session';

export type AppHeaderProps = {
  totalCount: number;
  waitingCount: number;
  agentCounts: Record<AgentType, number>;
  isLoading: boolean;
  getInactiveCount: () => number;
  getStaleCount: () => number;
  killInactiveSessions: () => void;
  killStaleSessions: () => void;
  killSessionsByType: (agentType: AgentType) => void;
  onSettingsClick: () => void;
  onRefresh: () => void;
  notificationInstalled: boolean | null;
  bellMode: boolean;
  bellModeLoading: boolean;
  onBellModeToggle: () => void;
};

const AGENT_TYPES: AgentType[] = ['claude', 'codex', 'opencode'];

export function AppHeader({
  totalCount,
  waitingCount,
  agentCounts,
  isLoading,
  getInactiveCount,
  getStaleCount,
  killInactiveSessions,
  killStaleSessions,
  killSessionsByType,
  onSettingsClick,
  onRefresh,
  notificationInstalled,
  bellMode,
  bellModeLoading,
  onBellModeToggle,
}: AppHeaderProps) {
  const inactiveCount = getInactiveCount();
  const staleCount = getStaleCount();
  const hasAgentSessions = AGENT_TYPES.some((t) => agentCounts[t] > 0);
  const showSeparator = (inactiveCount > 0 || staleCount > 0) && hasAgentSessions;

  return (
    <header
      data-tauri-drag-region
      className='h-14 flex items-center justify-between px-6 border-b border-border bg-card/50 backdrop-blur-sm'
    >
      <div data-tauri-drag-region className='flex items-center gap-4 pl-16'>
        <h1 data-tauri-drag-region className='text-lg font-semibold text-foreground'>
          Agent Manager X
        </h1>
        {totalCount > 0 && (
          <div data-tauri-drag-region className='flex items-center gap-2'>
            <Badge data-tauri-drag-region variant='secondary' className='font-medium pointer-events-none'>
              {totalCount} active
            </Badge>
            {waitingCount > 0 && (
              <Badge
                data-tauri-drag-region
                className='bg-status-waiting/20 text-status-waiting border-status-waiting/30 font-medium pointer-events-none'
              >
                {waitingCount} waiting
              </Badge>
            )}
          </div>
        )}
      </div>
      <div className='flex items-center gap-1'>
        {/* Idle sessions button (5+ min) */}
        {inactiveCount > 0 && (
          <Button
            variant='ghost'
            size='sm'
            className='h-7 px-2 text-xs gap-1'
            onClick={killInactiveSessions}
            title='End sessions idle for 5+ minutes'
          >
            <span>Idle</span>
            <Badge variant='secondary' className='h-4 px-1 text-[10px] font-medium'>
              {inactiveCount}
            </Badge>
          </Button>
        )}

        {/* Stale sessions button (10+ min) */}
        {staleCount > 0 && (
          <Button
            variant='ghost'
            size='sm'
            className='h-7 px-2 text-xs gap-1'
            onClick={killStaleSessions}
            title='End sessions stale for 10+ minutes'
          >
            <span>Stale</span>
            <Badge variant='secondary' className='h-4 px-1 text-[10px] font-medium'>
              {staleCount}
            </Badge>
          </Button>
        )}

        {/* Separator between idle/stale and agent buttons */}
        {showSeparator && <div className='w-px h-5 bg-border mx-1' />}

        {/* End All buttons for each agent type - only show if count > 0 */}
        {AGENT_TYPES.map(
          (agentType) =>
            agentCounts[agentType] > 0 && (
              <Button
                key={agentType}
                variant='ghost'
                size='sm'
                className='h-7 px-2 text-xs gap-1'
                onClick={() => killSessionsByType(agentType)}
                title={`End all ${agentType} sessions`}
              >
                <span className='capitalize'>{agentType}</span>
                <Badge variant='secondary' className='h-4 px-1 text-[10px] font-medium'>
                  {agentCounts[agentType]}
                </Badge>
              </Button>
            )
        )}

        {notificationInstalled && (
          <>
            <div className='w-px h-5 bg-border mx-1' />
            <Button
              variant='ghost'
              size='icon-sm'
              onClick={onBellModeToggle}
              disabled={bellModeLoading}
              title={bellMode ? 'Bell mode (click for voice)' : 'Voice mode (click for bell)'}
            >
              {bellMode ? <BellIcon /> : <VoiceIcon />}
            </Button>
          </>
        )}

        <div className='w-px h-5 bg-border mx-1' />

        <Button variant='ghost' size='icon-sm' onClick={onSettingsClick} title='Settings'>
          <SettingsIcon />
        </Button>
        <Button variant='ghost' size='icon-sm' onClick={onRefresh} disabled={isLoading} title='Refresh'>
          <RefreshIcon isLoading={isLoading} />
        </Button>
      </div>
    </header>
  );
}
