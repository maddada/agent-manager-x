import { useMemo, useState } from 'react';
import Masonry from 'react-masonry-css';
import { invoke } from '@tauri-apps/api/core';
import { Session } from '../types/session';
import { SessionCard } from './SessionCard';
import { type DefaultEditor, getCardClickAction, getDefaultTerminal, getCustomEditorCommand, getCustomTerminalCommand } from './Settings';

type SessionGridProps = {
  sessions: Session[];
  defaultEditor: DefaultEditor;
  onRefresh: () => void;
};

// Color for project groups (consistent style for all groups)
const PROJECT_GROUP_COLOR = 'bg-white/5 border-white/10';

type ProjectGroup = {
  projectPath: string;
  projectName: string;
  sessions: Session[];
  color: string;
};

const masonryBreakpoints = {
  default: 3,
  1024: 3,
  768: 2,
  640: 1,
};

export function SessionGrid({ sessions, defaultEditor, onRefresh }: SessionGridProps) {
  const [killingGroups, setKillingGroups] = useState<Set<string>>(new Set());

  const handleKillGroup = async (group: ProjectGroup) => {
    setKillingGroups((prev) => new Set(prev).add(group.projectPath));
    // Kill all sessions in parallel for speed
    await Promise.all(
      group.sessions.map((session) =>
        invoke('kill_session', { pid: session.pid }).catch((error) =>
          console.error(`Failed to kill session ${session.pid}:`, error)
        )
      )
    );
    // Immediately refresh to update UI
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
        await invoke('open_in_editor', { path: group.projectPath, editor: editorCommand });
      } catch (error) {
        console.error(`Failed to open in ${defaultEditor}:`, error);
      }
    }
  };

  // Group sessions by project path
  const projectGroups = useMemo(() => {
    const groups = new Map<string, Session[]>();

    for (const session of sessions) {
      const existing = groups.get(session.projectPath);
      if (existing) {
        existing.push(session);
      } else {
        groups.set(session.projectPath, [session]);
      }
    }

    // Convert to array and add color
    const result: ProjectGroup[] = [];
    for (const [projectPath, projectSessions] of groups) {
      result.push({
        projectPath,
        projectName: projectSessions[0].projectName,
        sessions: projectSessions,
        color: PROJECT_GROUP_COLOR,
      });
    }

    // Sort by project path for stable ordering (alphabetical)
    result.sort((a, b) => a.projectPath.localeCompare(b.projectPath));

    return result;
  }, [sessions]);

  return (
    <Masonry breakpointCols={masonryBreakpoints} className='flex -ml-4 w-auto' columnClassName='pl-4 bg-clip-padding'>
      {projectGroups.map((group) => (
        <div
          key={group.projectPath}
          className={`group/project relative mb-4 rounded-xl border p-3 space-y-3 transition-opacity duration-200 ${group.color} ${killingGroups.has(group.projectPath) ? 'opacity-50' : ''}`}
        >
          {/* Kill group button - top left corner outside, hidden when hovering over a session card */}
          <button
            onClick={() => handleKillGroup(group)}
            className='absolute -top-2 -left-2 w-5 h-5 rounded-full bg-destructive hover:bg-destructive/80 flex items-center justify-center opacity-0 group-hover/project:opacity-100 group-has-[.group:hover]/project:opacity-0 transition-opacity z-10 shadow-md cursor-pointer'
            title={`Kill all ${group.sessions.length} session${group.sessions.length > 1 ? 's' : ''}`}
          >
            <svg className='w-3 h-3 text-destructive-foreground' fill='none' stroke='currentColor' viewBox='0 0 24 24'>
              <path strokeLinecap='round' strokeLinejoin='round' strokeWidth={2} d='M6 18L18 6M6 6l12 12' />
            </svg>
          </button>

          {/* Project header - always show, clickable */}
          <div
            className='w-full px-1 pb-2 border-b border-white/5 cursor-pointer hover:opacity-80 transition-opacity'
            onClick={() => handleGroupClick(group)}
          >
            <h2 className='text-lg font-semibold text-foreground truncate'>{group.projectName}</h2>
            <p className='text-sm text-muted-foreground truncate mt-1.5'>
              {group.projectPath.replace(/^\/Users\/[^/]+/, '~')}
            </p>
            <div className='flex items-center gap-3 mt-1 text-sm text-muted-foreground'>
              {group.sessions[0].gitBranch && (
                <div className='flex items-center gap-1'>
                  <svg className='w-3 h-3' fill='none' stroke='currentColor' viewBox='0 0 24 24'>
                    <path
                      strokeLinecap='round'
                      strokeLinejoin='round'
                      strokeWidth={2}
                      d='M6 3v12M18 9a3 3 0 100-6 3 3 0 000 6zM6 21a3 3 0 100-6 3 3 0 000 6zM18 9a9 9 0 01-9 9'
                    />
                  </svg>
                  <span>{group.sessions[0].gitBranch}</span>
                </div>
              )}
              <span>
                {group.sessions.length} {group.sessions.length === 1 ? 'session' : 'sessions'}
              </span>
            </div>
          </div>

          {/* Session cards */}
          <div className='space-y-4'>
            {group.sessions.map((session) => (
              <SessionCard key={session.id} session={session} defaultEditor={defaultEditor} onKill={onRefresh} />
            ))}
          </div>
        </div>
      ))}
    </Masonry>
  );
}
