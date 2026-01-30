// App header component with title, badges, and action buttons

import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { SettingsIcon, RefreshIcon, BellIcon, VoiceIcon } from './icons';
import type { AgentType, Session } from '@/types/session';

export type AppHeaderProps = {
  totalCount: number;
  waitingCount: number;
  agentCounts: Record<AgentType, number>;
  backgroundSessions: Session[];
  isLoading: boolean;
  getInactiveCount: () => number;
  getStaleCount: () => number;
  killInactiveSessions: () => void;
  killStaleSessions: () => void;
  killSessionsByType: (agentType: AgentType) => void;
  killBackgroundSession: (pid: number) => void;
  killAllBackgroundSessions: () => void;
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
  backgroundSessions,
  isLoading,
  getInactiveCount,
  getStaleCount,
  killInactiveSessions,
  killStaleSessions,
  killSessionsByType,
  killBackgroundSession,
  killAllBackgroundSessions,
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
  const backgroundCount = backgroundSessions.length;

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
        {backgroundCount > 0 && (
          <TooltipProvider delayDuration={500}>
            <Tooltip>
              <DropdownMenu>
                <TooltipTrigger asChild>
                  <DropdownMenuTrigger asChild>
                    <Button variant='ghost' size='sm' className='h-7 text-xs gap-1' title='Background processes'>
                      <span>BG</span>
                      <Badge variant='secondary' className='h-4 px-1 text-[10px] font-medium'>
                        {backgroundCount}
                      </Badge>
                    </Button>
                  </DropdownMenuTrigger>
                </TooltipTrigger>
                <DropdownMenuContent align='end' className='w-72 p-3'>
                  <DropdownMenuLabel className='text-xs uppercase tracking-wide text-muted-foreground'>
                    Background Processes
                  </DropdownMenuLabel>
                  <div className='text-xs text-muted-foreground mt-1 leading-relaxed'>
                    Background processes by the agents without messages or working directory.
                  </div>
                  <div className='text-xs text-muted-foreground mt-2 leading-relaxed'>
                    Ex. Codex needs these for other sessions to work.
                  </div>
                  <DropdownMenuSeparator className='my-3' />
                  <div className='space-y-2 max-h-48 overflow-y-auto pr-1'>
                    {backgroundSessions.map((session) => (
                      <div
                        key={session.id}
                        className='flex items-center justify-between rounded-md border border-border/60 bg-background/60 px-2 py-1.5 text-xs'
                      >
                        <div className='flex flex-col'>
                          <span className='capitalize text-foreground'>{session.agentType}</span>
                          <span className='text-muted-foreground'>pid {session.pid}</span>
                        </div>
                        <button
                          onClick={(e) => {
                            e.preventDefault();
                            e.stopPropagation();
                            killBackgroundSession(session.pid);
                          }}
                          className='inline-flex h-6 w-6 items-center justify-center rounded-full text-muted-foreground hover:text-destructive hover:bg-destructive/10 transition-colors'
                          title='Close background process'
                        >
                          <svg className='h-3.5 w-3.5' fill='none' stroke='currentColor' viewBox='0 0 24 24'>
                            <path
                              strokeLinecap='round'
                              strokeLinejoin='round'
                              strokeWidth={2}
                              d='M6 18L18 6M6 6l12 12'
                            />
                          </svg>
                        </button>
                      </div>
                    ))}
                  </div>
                  <DropdownMenuSeparator className='my-3' />
                  <Button
                    variant='outline'
                    size='sm'
                    className='w-full text-xs'
                    onClick={(e) => {
                      e.preventDefault();
                      e.stopPropagation();
                      killAllBackgroundSessions();
                    }}
                  >
                    Close All
                  </Button>
                </DropdownMenuContent>
              </DropdownMenu>
              <TooltipContent side='bottom' className='max-w-xs text-xs leading-relaxed'>
                Background processes by the agents without messages or working directory.
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        )}

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
              title={bellMode ? 'Using Bell mode (click for voice)' : 'Using Voice mode (click for bell)'}
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
