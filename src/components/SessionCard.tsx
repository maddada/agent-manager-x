import { Session } from '../types/session';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { formatTimeAgo, formatMemory, statusConfig } from '@/lib/formatters';
import { type DefaultEditor } from './Settings';
import { useSessionCard } from '@/hooks/useSessionCard';
import { AgentStatusIcon, RenameDialog, UrlDialog, SessionCardContextMenu } from './session-card';

export type SessionCardProps = {
  session: Session;
  defaultEditor: DefaultEditor;
  onKill?: () => void;
};

export function SessionCard({ session, defaultEditor, onKill }: SessionCardProps) {
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

  // Instantly hide card when killing - provides immediate feedback
  if (isKilling) {
    return null;
  }

  const config = statusConfig[session.status];

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
        <Card
          className={`relative group cursor-pointer transition-all duration-200 hover:shadow-lg py-0 gap-0 h-full flex flex-col ${config.cardBg} ${config.cardBorder} hover:border-primary/30 ${'cardOpacity' in config ? config.cardOpacity : ''}`}
          onClick={handleCardClick}
        >
          {/* Kill session button - top left corner outside */}
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

          {/* Agent icon - top right corner outside */}
          <div className='absolute top-1 right-1 z-10'>
            <AgentStatusIcon type={session.agentType} statusColor={config.fillColor} />
          </div>

          {/* URL button - visible on hover when URL is set */}
          {customUrl && (
            <div className='absolute top-1 right-6 z-10 opacity-0 group-hover:opacity-100 transition-opacity'>
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

          {/* Custom Name - floating on top edge */}
          {customName && (
            <div className='absolute -top-3 left-1/2 -translate-x-1/2 z-10 max-w-[75%]'>
              <div className='bg-background border border-border rounded-full px-3 py-0.5 shadow-sm'>
                <span className='font-semibold text-xs text-foreground truncate block'>{customName}</span>
              </div>
            </div>
          )}

          <CardContent className='p-4 flex flex-col flex-1'>
            {/* Message Preview */}
            <div className='flex-1'>
              {session.lastMessage && (
                <TooltipProvider delayDuration={600}>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <div className='text-sm text-foreground line-clamp-3 leading-relaxed'>{session.lastMessage}</div>
                    </TooltipTrigger>
                    <TooltipContent
                      side='bottom'
                      className='max-w-[calc(33vw-20px)] max-h-64 overflow-y-auto whitespace-pre-wrap text-sm leading-relaxed select-none'
                    >
                      {session.lastMessage}
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              )}
            </div>

            {/* Process stats */}
            <div className='flex items-center gap-3 pt-2 mt-2 border-t border-border/50 text-[10px] text-muted-foreground font-mono'>
              <span>PID {session.pid}</span>
              <span>CPU {session.cpuUsage.toFixed(0)}%</span>
              <span>MEM {formatMemory(session.memoryBytes)}</span>
            </div>

            {/* Footer: Status Badge + Time */}
            <div className='flex items-center justify-between pt-2 mt-1 border-t border-border'>
              <div className='flex items-center gap-2'>
                <Badge variant='outline' className={config.badgeClassName}>
                  {config.label}
                </Badge>
                {session.activeSubagentCount > 0 && (
                  <span className='text-xs text-muted-foreground'>[+{session.activeSubagentCount}]</span>
                )}
              </div>
              <span className='text-xs text-foreground'>{formatTimeAgo(session.lastActivityAt)}</span>
            </div>
          </CardContent>
        </Card>
      </SessionCardContextMenu>

      {/* Rename Dialog */}
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

      {/* URL Dialog */}
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
