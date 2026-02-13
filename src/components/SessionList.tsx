import { useMemo, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { Session } from '../types/session';
import { SessionListItem } from './SessionListItem';
import {
  type DefaultEditor,
  getCardClickAction,
  getDefaultTerminal,
  getCustomEditorCommand,
  getCustomTerminalCommand,
  getExperimentalVsCodeSessionOpening,
} from './Settings';
import { groupSessionsByProject, type ProjectGroup } from '@/lib/sessionGrouping';
import { truncatePath } from '@/lib/formatters';
import { ProjectHeaderActions } from '@/components/ProjectHeaderActions';
import { useProjectGitDiffStats } from '@/hooks/useProjectGitDiffStats';

type SessionListProps = {
  sessions: Session[];
  defaultEditor: DefaultEditor;
  onRefresh: () => void;
};

export function SessionList({ sessions, defaultEditor, onRefresh }: SessionListProps) {
  const [killingGroups, setKillingGroups] = useState<Set<string>>(new Set());

  const handleKillGroup = async (group: ProjectGroup) => {
    setKillingGroups((prev) => new Set(prev).add(group.projectPath));
    await Promise.all(
      group.sessions.map((session) =>
        invoke('kill_session', { pid: session.pid }).catch((error) =>
          console.error(`Failed to kill session ${session.pid}:`, error)
        )
      )
    );
    onRefresh();
  };

  const handleGroupClick = async (group: ProjectGroup) => {
    const clickAction = getCardClickAction();
    if (clickAction === 'terminal') {
      try {
        const terminal = getDefaultTerminal();
        const terminalCommand = terminal === 'custom' ? getCustomTerminalCommand() : terminal;
        if (!terminalCommand) {
          console.error('No custom terminal command configured');
          return;
        }
        await invoke('open_in_terminal', { path: group.projectPath, terminal: terminalCommand });
      } catch (error) {
        console.error('Failed to open in terminal:', error);
      }
    } else {
      try {
        const editorCommand = defaultEditor === 'custom' ? getCustomEditorCommand() : defaultEditor;
        if (!editorCommand) {
          console.error('No custom editor command configured');
          return;
        }
        await invoke('open_in_editor', {
          path: group.projectPath,
          editor: editorCommand,
          experimentalVsCodeSessionOpening: getExperimentalVsCodeSessionOpening(),
          projectName: group.projectName,
        });
      } catch (error) {
        console.error(`Failed to open in ${defaultEditor}:`, error);
      }
    }
  };

  const projectGroups = useMemo(() => groupSessionsByProject(sessions), [sessions]);
  const projectPaths = useMemo(() => projectGroups.map((group) => group.projectPath), [projectGroups]);
  const gitDiffStatsByPath = useProjectGitDiffStats(projectPaths);

  return (
    <div className='space-y-4'>
      {projectGroups.map((group) => {
        const gitDiffStats = gitDiffStatsByPath[group.projectPath];
        const hasGitDiffStats = !!gitDiffStats && (gitDiffStats.additions > 0 || gitDiffStats.deletions > 0);
        const groupGitBranch = group.sessions.find((session) => session.gitBranch)?.gitBranch;

        return (
          <div
            key={group.projectPath}
            className={`relative rounded-xl border ${group.color} ${killingGroups.has(group.projectPath) ? 'opacity-50' : ''}`}
          >
            <div
              className='group relative w-full px-3 py-2 border-b border-white/5 cursor-pointer hover:opacity-80 transition-opacity'
              onClick={() => handleGroupClick(group)}
            >
              <button
                onClick={(event) => {
                  event.stopPropagation();
                  handleKillGroup(group);
                }}
                className='absolute -top-2 -left-2 w-5 h-5 rounded-full bg-destructive hover:bg-destructive/80 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity z-10 shadow-md cursor-pointer'
                title={`Kill all ${group.sessions.length} session${group.sessions.length > 1 ? 's' : ''}`}
              >
                <svg className='w-3 h-3 text-destructive-foreground' fill='none' stroke='currentColor' viewBox='0 0 24 24'>
                  <path strokeLinecap='round' strokeLinejoin='round' strokeWidth={2} d='M6 18L18 6M6 6l12 12' />
                </svg>
              </button>

              <ProjectHeaderActions projectName={group.projectName} projectPath={group.projectPath} />

              <div className='flex items-start justify-between gap-4 pr-24'>
                <div className='min-w-0'>
                  <h2 className='text-base font-semibold text-foreground truncate'>{group.projectName}</h2>
                  <p className='text-xs text-muted-foreground truncate mt-1'>{truncatePath(group.projectPath)}</p>
                </div>
                <div className='flex items-center gap-3 text-xs text-muted-foreground whitespace-nowrap'>
                  {groupGitBranch && (
                    <div className='flex items-center gap-1'>
                      <svg className='w-3 h-3' fill='none' stroke='currentColor' viewBox='0 0 24 24'>
                        <path
                          strokeLinecap='round'
                          strokeLinejoin='round'
                          strokeWidth={2}
                          d='M6 3v12M18 9a3 3 0 100-6 3 3 0 000 6zM6 21a3 3 0 100-6 3 3 0 000 6zM18 9a9 9 0 01-9 9'
                        />
                      </svg>
                      <span>{groupGitBranch}</span>
                    </div>
                  )}
                  {hasGitDiffStats && (
                    <div className='flex items-center gap-1 text-[11px] font-mono'>
                      <span className='text-emerald-400'>+{gitDiffStats.additions}</span>
                      <span className='text-rose-400'>-{gitDiffStats.deletions}</span>
                    </div>
                  )}
                  <span className='shrink-0 whitespace-nowrap'>
                    {group.sessions.length} {group.sessions.length === 1 ? 'session' : 'sessions'}
                  </span>
                </div>
              </div>
            </div>

            <div className='p-2 space-y-2'>
              {group.sessions.map((session) => (
                <SessionListItem key={session.id} session={session} defaultEditor={defaultEditor} onKill={onRefresh} />
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}
