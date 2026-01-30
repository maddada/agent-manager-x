import { Session } from '../types/session';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { formatTimeAgo, formatMemory, statusConfig } from '@/lib/formatters';
import { type DefaultEditor } from './Settings';
import { useSessionCard } from '@/hooks/useSessionCard';
import { AgentStatusIcon, RenameDialog, UrlDialog, SessionCardContextMenu } from './session-card';

export type SessionListItemProps = {
  session: Session;
  defaultEditor: DefaultEditor;
  onKill?: () => void;
};

export function SessionListItem({ session, defaultEditor, onKill }: SessionListItemProps) {
  const {
    isKilling,
    customName,
    customUrl,
    isRenameOpen,
    isUrlOpen,
    renameValue,
    urlValue,
    setIsRenameOpen,
    setIsUrlOpen,
    setRenameValue,
    setUrlValue,
    handleRename,
    handleSaveRename,
    handleResetName,
    handleSetUrl,
    handleSaveUrl,
    handleClearUrl,
    handleOpenUrl,
    handleOpenGitHub,
    handleKillSession,
    handleOpenInEditor,
    handleOpenInTerminal,
    handleCardClick,
  } = useSessionCard({ session, defaultEditor, onKill });

  if (isKilling) {
    return null;
  }

  const config = statusConfig[session.status];
  const hasMessage = !!session.lastMessage && session.lastMessage.trim().length > 0;
  const fallbackMessage =
    session.status === 'idle' || session.status === 'stale' ? 'No recent messages' : config.label;

  const statsLine = `PID ${session.pid} • ${session.cpuUsage.toFixed(0)}% • ${formatMemory(session.memoryBytes)} • ${formatTimeAgo(
    session.lastActivityAt
  )}`;

  return (
    <>
      <SessionCardContextMenu
        onOpenInEditor={() => handleOpenInEditor(defaultEditor)}
        onOpenInTerminal={() => handleOpenInTerminal()}
        onRename={handleRename}
        onSetUrl={handleSetUrl}
        onOpenGitHub={session.githubUrl ? handleOpenGitHub : undefined}
        onKillSession={handleKillSession}
        hasGitHubUrl={!!session.githubUrl}
        hasCustomUrl={!!customUrl}
      >
        <div
          className={`relative group cursor-pointer transition-all duration-200 hover:shadow-md rounded-lg border px-3 py-2 ${config.cardBg} ${config.cardBorder} hover:border-primary/30 ${'cardOpacity' in config ? config.cardOpacity : ''}`}
          onClick={handleCardClick}
        >
          <button
            onClick={(e) => {
              e.stopPropagation();
              handleKillSession();
            }}
            className='absolute -top-2 -left-2 w-5 h-5 rounded-full bg-destructive hover:bg-destructive/80 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity z-10 shadow-md cursor-pointer'
            title='Kill session'
          >
            <svg className='w-3 h-3 text-destructive-foreground' fill='none' stroke='currentColor' viewBox='0 0 24 24'>
              <path strokeLinecap='round' strokeLinejoin='round' strokeWidth={2} d='M6 18L18 6M6 6l12 12' />
            </svg>
          </button>

          <div className='absolute top-2 right-2 z-10 flex items-center gap-1'>
            {customUrl && (
              <div className='opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none group-hover:pointer-events-auto'>
                <Button
                  variant='ghost'
                  size='sm'
                  className='h-6 w-6 p-0 hover:bg-primary/10 bg-background/80 backdrop-blur-sm'
                  onClick={handleOpenUrl}
                  title={customUrl}
                >
                  <svg className='w-4 h-4 text-muted-foreground' fill='none' stroke='currentColor' viewBox='0 0 24 24'>
                    <path
                      strokeLinecap='round'
                      strokeLinejoin='round'
                      strokeWidth={2}
                      d='M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14'
                    />
                  </svg>
                </Button>
              </div>
            )}
            <AgentStatusIcon type={session.agentType} statusColor={config.fillColor} />
          </div>

          <div className='grid gap-1 pr-10'>
            <div className='flex items-center gap-2 text-xs text-muted-foreground overflow-hidden whitespace-nowrap'>
              {customName && (
                <span className='text-foreground font-semibold truncate max-w-[40%]'>{customName}</span>
              )}
              <Badge variant='outline' className={config.badgeClassName}>
                {config.label}
              </Badge>
              {session.activeSubagentCount > 0 && (
                <span className='text-xs text-muted-foreground'>[+{session.activeSubagentCount}]</span>
              )}
            </div>

            {hasMessage ? (
              <TooltipProvider delayDuration={600}>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <div className='text-sm text-foreground line-clamp-1 leading-relaxed'>{session.lastMessage}</div>
                  </TooltipTrigger>
                  <TooltipContent
                    side='bottom'
                    className='max-w-[calc(50vw-20px)] max-h-64 overflow-y-auto whitespace-pre-wrap text-sm leading-relaxed select-none'
                  >
                    {session.lastMessage}
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>
            ) : (
              <div className='text-sm text-foreground/70 min-h-[1.25rem]'>{fallbackMessage}</div>
            )}

            <div className='text-[10px] text-muted-foreground font-mono truncate'>
              {statsLine}
            </div>
          </div>
        </div>
      </SessionCardContextMenu>

      <RenameDialog
        isOpen={isRenameOpen}
        onOpenChange={setIsRenameOpen}
        renameValue={renameValue}
        onRenameValueChange={setRenameValue}
        onSave={handleSaveRename}
        onReset={handleResetName}
        hasCustomName={!!customName}
        originalName={session.projectName}
      />

      <UrlDialog
        isOpen={isUrlOpen}
        onOpenChange={setIsUrlOpen}
        urlValue={urlValue}
        onUrlValueChange={setUrlValue}
        onSave={handleSaveUrl}
        onClear={handleClearUrl}
        hasCustomUrl={!!customUrl}
      />
    </>
  );
}
