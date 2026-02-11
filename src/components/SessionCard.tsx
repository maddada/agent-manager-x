import { useEffect, useRef, useState } from 'react';
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
  const [showPid, setShowPid] = useState(true);
  const footerRef = useRef<HTMLDivElement>(null);
  const statusMetaRef = useRef<HTMLDivElement>(null);
  const metricsRef = useRef<HTMLDivElement>(null);
  const pidMeasureRef = useRef<HTMLSpanElement>(null);

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
  const hasMessage = !!session.lastMessage && session.lastMessage.trim().length > 0;
  const fallbackMessage =
    session.status === 'idle' || session.status === 'stale' ? 'No recent messages' : config.label;

  useEffect(() => {
    const GAP_PX = 8; // gap-2 between metric tokens
    const REQUIRED_SECTION_GAP_PX = 14;
    const RESTORE_SECTION_GAP_PX = 28;

    const updatePidVisibility = () => {
      const footerEl = footerRef.current;
      const statusEl = statusMetaRef.current;
      const metricsEl = metricsRef.current;
      const pidMeasureEl = pidMeasureRef.current;

      if (!footerEl || !statusEl || !metricsEl || !pidMeasureEl) {
        return;
      }

      const footerWidth = footerEl.clientWidth;
      const statusWidth = statusEl.offsetWidth;
      const metricsWidth = metricsEl.scrollWidth;
      const pidWidth = pidMeasureEl.offsetWidth;

      if (showPid) {
        const currentGapPx = footerWidth - statusWidth - metricsWidth;
        if (currentGapPx <= REQUIRED_SECTION_GAP_PX) {
          setShowPid(false);
        }
        return;
      }

      const projectedGapPx = footerWidth - statusWidth - (metricsWidth + pidWidth + GAP_PX);
      if (projectedGapPx >= RESTORE_SECTION_GAP_PX) {
        setShowPid(true);
      }
    };

    updatePidVisibility();

    const footerEl = footerRef.current;
    if (!footerEl) {
      return;
    }

    const resizeObserver = new ResizeObserver(updatePidVisibility);
    resizeObserver.observe(footerEl);

    return () => {
      resizeObserver.disconnect();
    };
  }, [
    showPid,
    session.pid,
    session.cpuUsage,
    session.memoryBytes,
    session.lastActivityAt,
    session.activeSubagentCount,
    config.label,
  ]);

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
              {hasMessage ? (
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
              ) : (
                <div className='text-sm text-foreground/70 line-clamp-3 leading-relaxed'>{fallbackMessage}</div>
              )}
            </div>

            {/* Footer: Status Badge + Time */}
            <div ref={footerRef} className='flex items-center justify-between gap-3 pt-3 mt-3 border-t border-border'>
              <div ref={statusMetaRef} className='flex items-center gap-2 min-w-0'>
                <Badge variant='outline' className={config.badgeClassName}>
                  {config.label}
                </Badge>
                {session.activeSubagentCount > 0 && (
                  <span className='text-xs text-muted-foreground shrink-0'>[+{session.activeSubagentCount}]</span>
                )}
              </div>
              <div ref={metricsRef} className='flex items-center gap-2 text-xs shrink-0 whitespace-nowrap'>
                {showPid && <span className='text-muted-foreground'>PID {session.pid}</span>}
                <span className='text-muted-foreground shrink-0'>{session.cpuUsage.toFixed(0)}%</span>
                <span className='text-muted-foreground shrink-0'>{formatMemory(session.memoryBytes)}</span>
                <span className='text-foreground shrink-0'>{formatTimeAgo(session.lastActivityAt)}</span>
              </div>
              <span
                ref={pidMeasureRef}
                aria-hidden='true'
                className='fixed -left-[9999px] top-0 pointer-events-none opacity-0 text-xs whitespace-nowrap'
              >
                PID {session.pid}
              </span>
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
