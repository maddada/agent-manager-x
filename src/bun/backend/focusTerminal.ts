import { escapeAppleScriptString, runCommand } from './utils/shell';

function executeAppleScript(script: string): void {
  const result = runCommand(['osascript', '-e', script]);
  if (!result.success) {
    const message = result.stderr || 'AppleScript execution failed';
    throw new Error(message);
  }

  if (result.stdout.trim() === 'not found') {
    throw new Error('Tab not found');
  }
}

function getTtyForPid(pid: number): string {
  const result = runCommand(['ps', '-p', String(pid), '-o', 'tty=']);
  if (!result.success) {
    throw new Error('Failed to get TTY for process');
  }

  const tty = result.stdout.trim();
  if (!tty || tty === '??') {
    throw new Error('Process has no TTY');
  }

  return tty;
}

function focusITermByTty(tty: string): void {
  const script = `
    tell application "System Events"
      if not (exists process "iTerm2") then
        error "iTerm2 not running"
      end if
    end tell

    tell application "iTerm2"
      activate
      repeat with w in windows
        repeat with t in tabs of w
          repeat with s in sessions of t
            if tty of s contains "${escapeAppleScriptString(tty)}" then
              select s
              select t
              set index of w to 1
              return "found"
            end if
          end repeat
        end repeat
      end repeat
    end tell
    return "not found"
  `;

  executeAppleScript(script);
}

function focusTerminalAppByTty(tty: string): void {
  const checkScript = `
    tell application "System Events"
      return exists process "Terminal"
    end tell
  `;

  const check = runCommand(['osascript', '-e', checkScript]);
  if (!check.success || check.stdout.trim() !== 'true') {
    throw new Error('Terminal is not running');
  }

  const script = `
    tell application "Terminal"
      activate
      repeat with w in windows
        repeat with t in tabs of w
          try
            if tty of t contains "${escapeAppleScriptString(tty)}" then
              set selected of t to true
              set index of w to 1
              return "found"
            end if
          end try
        end repeat
      end repeat
    end tell
    return "not found"
  `;

  executeAppleScript(script);
}

function focusAnyTerminalWithTmux(): void {
  const script = `
    tell application "System Events"
      if exists process "iTerm2" then
        tell application "iTerm2" to activate
        return "found"
      else if exists process "Terminal" then
        tell application "Terminal" to activate
        return "found"
      end if
    end tell
    return "not found"
  `;

  executeAppleScript(script);
}

function focusTmuxClientTerminal(): void {
  const result = runCommand(['tmux', 'display-message', '-p', '#{client_tty}']);
  if (!result.success) {
    focusAnyTerminalWithTmux();
    return;
  }

  const clientTty = result.stdout.trim();
  if (!clientTty) {
    focusAnyTerminalWithTmux();
    return;
  }

  const ttyName = clientTty.split('/').pop() ?? clientTty;

  try {
    focusITermByTty(ttyName);
    return;
  } catch {
    // Try Terminal.app.
  }

  try {
    focusTerminalAppByTty(ttyName);
    return;
  } catch {
    // Fall through to generic activation.
  }

  focusAnyTerminalWithTmux();
}

function focusTmuxPaneByTty(tty: string): void {
  const result = runCommand([
    'tmux',
    'list-panes',
    '-a',
    '-F',
    '#{pane_tty} #{session_name}:#{window_index}.#{pane_index}',
  ]);

  if (!result.success) {
    throw new Error('tmux not running or no sessions');
  }

  for (const line of result.stdout.split('\n')) {
    const parts = line.trim().split(/\s+/);
    if (parts.length < 2) {
      continue;
    }

    const paneTty = parts[0] ?? '';
    const target = parts[1] ?? '';

    if (!target) {
      continue;
    }

    if (paneTty.includes(tty) || paneTty.endsWith(tty)) {
      runCommand(['tmux', 'select-window', '-t', target]);
      runCommand(['tmux', 'select-pane', '-t', target]);
      focusTmuxClientTerminal();
      return;
    }
  }

  throw new Error('Pane not found in tmux');
}

function focusTerminalForPid(pid: number): void {
  const tty = getTtyForPid(pid);

  try {
    focusTmuxPaneByTty(tty);
    return;
  } catch {
    // Try iTerm directly.
  }

  try {
    focusITermByTty(tty);
    return;
  } catch {
    // Fall back to Terminal.app.
  }

  focusTerminalAppByTty(tty);
}

function focusTerminalByPath(projectPath: string): void {
  const searchTerm = projectPath.split('/').filter(Boolean).pop() ?? projectPath;
  const escapedSearchTerm = escapeAppleScriptString(searchTerm);

  const script = `
    tell application "System Events"
      if exists process "iTerm2" then
        tell application "iTerm2"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if name of s contains "${escapedSearchTerm}" then
                  select s
                  select t
                  set index of w to 1
                  return "found"
                end if
              end repeat
            end repeat
          end repeat
        end tell
      end if
    end tell
    return "not found"
  `;

  executeAppleScript(script);
}

export function focusSession(pid: number, projectPath: string): void {
  try {
    focusTerminalForPid(pid);
  } catch {
    focusTerminalByPath(projectPath);
  }
}
