import { type MouseEvent, useEffect, useMemo, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { getProjectCommand, setProjectCommand, type ProjectCommandAction } from '@/lib/projectCommands';
import { getCustomTerminalCommand, getDefaultTerminal } from '@/lib/settings';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';

type ProjectHeaderActionsProps = {
  projectName: string;
  projectPath: string;
};

type ActionMeta = {
  action: ProjectCommandAction;
  label: string;
};

const ACTIONS: ActionMeta[] = [
  { action: 'run', label: 'Run' },
  { action: 'build', label: 'Build' },
];

export function ProjectHeaderActions({ projectName, projectPath }: ProjectHeaderActionsProps) {
  const [runCommand, setRunCommand] = useState(() => getProjectCommand(projectPath, 'run'));
  const [buildCommand, setBuildCommand] = useState(() => getProjectCommand(projectPath, 'build'));
  const [dialogOpen, setDialogOpen] = useState(false);
  const [activeAction, setActiveAction] = useState<ProjectCommandAction>('run');
  const [commandValue, setCommandValue] = useState('');
  const [runAfterSave, setRunAfterSave] = useState(false);

  useEffect(() => {
    setRunCommand(getProjectCommand(projectPath, 'run'));
    setBuildCommand(getProjectCommand(projectPath, 'build'));
  }, [projectPath]);

  const commands = useMemo(
    () => ({
      run: runCommand,
      build: buildCommand,
    }),
    [runCommand, buildCommand]
  );

  const setCommandInState = (action: ProjectCommandAction, nextCommand: string) => {
    if (action === 'run') {
      setRunCommand(nextCommand);
      return;
    }
    setBuildCommand(nextCommand);
  };

  const openCommandDialog = (action: ProjectCommandAction, shouldRunAfterSave: boolean) => {
    setActiveAction(action);
    setCommandValue(commands[action]);
    setRunAfterSave(shouldRunAfterSave);
    setDialogOpen(true);
  };

  const executeProjectCommand = async (action: ProjectCommandAction, command: string) => {
    try {
      const terminal = getDefaultTerminal();
      const customTerminalCommand = getCustomTerminalCommand();
      const terminalCommand = terminal === 'custom' ? customTerminalCommand || 'terminal' : terminal;

      await invoke('run_project_command', { path: projectPath, command, terminal: terminalCommand });
    } catch (error) {
      console.error(`Failed to execute ${action} command for ${projectPath}:`, error);
      window.alert(`Failed to execute ${action} command.\n\n${String(error)}`);
    }
  };

  const handleRunAction = async (event: MouseEvent, action: ProjectCommandAction) => {
    event.preventDefault();
    event.stopPropagation();

    const command = commands[action];
    if (!command) {
      openCommandDialog(action, true);
      return;
    }

    await executeProjectCommand(action, command);
  };

  const handleEditAction = (event: MouseEvent, action: ProjectCommandAction) => {
    event.preventDefault();
    event.stopPropagation();
    openCommandDialog(action, false);
  };

  const handleSaveDialog = async () => {
    const normalized = commandValue.trim();
    setProjectCommand(projectPath, activeAction, normalized);
    setCommandInState(activeAction, normalized);
    setDialogOpen(false);

    if (runAfterSave && normalized) {
      await executeProjectCommand(activeAction, normalized);
    }
  };

  return (
    <>
      <div
        className='absolute top-2 right-2 z-50 flex items-center gap-1 opacity-0 transition-opacity group-hover:opacity-100 pointer-events-auto'
      >
        {ACTIONS.map(({ action, label }) => (
          <button
            key={action}
            type='button'
            onMouseDown={(event) => {
              event.preventDefault();
              event.stopPropagation();
            }}
            onClick={(event) => {
              void handleRunAction(event, action);
            }}
            onContextMenu={(event) => {
              handleEditAction(event, action);
            }}
            className='h-6 rounded-md border border-border/70 bg-background/80 px-2 text-[11px] font-medium text-foreground backdrop-blur-sm hover:bg-primary/10 cursor-pointer'
            style={{ cursor: 'pointer' }}
            title={commands[action] ? `${label} (${commands[action]})` : `Set ${action} command`}
          >
            {label}
          </button>
        ))}
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent onClick={(event) => event.stopPropagation()}>
          <DialogHeader>
            <DialogTitle>{activeAction === 'run' ? 'Run command' : 'Build command'}</DialogTitle>
          </DialogHeader>

          <div className='py-4'>
            <Input
              value={commandValue}
              onChange={(event) => setCommandValue(event.target.value)}
              placeholder={activeAction === 'run' ? 'e.g., pnpm dev' : 'e.g., pnpm build'}
              onKeyDown={(event) => {
                if (event.key === 'Enter') {
                  void handleSaveDialog();
                }
              }}
              autoFocus
            />
            <p className='mt-2 text-xs text-muted-foreground'>
              {runAfterSave
                ? `Set and run ${activeAction} command for ${projectName}.`
                : `Edit ${activeAction} command for ${projectName}.`}
            </p>
          </div>

          <DialogFooter className='flex gap-2'>
            <Button variant='outline' onClick={() => setDialogOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void handleSaveDialog()}>{runAfterSave ? 'Save and Run' : 'Save'}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
