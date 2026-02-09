import { spawnDetached, runCommand, shellEscapeSingleQuotes } from './utils/shell';

export function enrichedPath(): string {
  const fromShell = runCommand(['/bin/zsh', '-l', '-c', 'echo $PATH']);
  if (fromShell.success && fromShell.stdout.trim().length > 0) {
    return fromShell.stdout.trim();
  }

  const base = process.env.PATH ?? '';
  const home = process.env.HOME ?? '';

  const parts = [
    '/usr/local/bin',
    '/opt/homebrew/bin',
    '/opt/homebrew/sbin',
  ];

  if (home) {
    parts.push(`${home}/.local/bin`);
  }

  if (base) {
    parts.push(base);
  }

  return parts.join(':');
}

function spawnWithPath(cmd: string[], cwd?: string): void {
  spawnDetached(cmd, {
    cwd,
    env: {
      ...process.env,
      PATH: enrichedPath(),
    },
  });
}

export function openInEditor(path: string, editor: string): void {
  const mapped = (() => {
    switch (editor) {
      case 'zed':
      case 'code':
      case 'cursor':
        return editor;
      case 'sublime':
        return 'subl';
      case 'neovim':
        return 'nvim';
      case 'webstorm':
        return 'webstorm';
      case 'idea':
        return 'idea';
      default:
        return editor;
    }
  })();

  try {
    spawnWithPath([mapped, path]);
  } catch (error) {
    throw new Error(`Failed to open ${path} in ${editor}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

export function openInTerminal(path: string, terminal: string): void {
  const escapedPath = shellEscapeSingleQuotes(path);

  try {
    switch (terminal) {
      case 'ghostty':
        spawnDetached(['open', '-a', 'Ghostty', path]);
        return;
      case 'iterm': {
        const script = `tell application "iTerm"
          activate
          create window with default profile
          tell current session of current window
            write text "cd '${escapedPath}'"
          end tell
        end tell`;
        spawnDetached(['osascript', '-e', script]);
        return;
      }
      case 'kitty':
        spawnWithPath(['kitty', '--directory', path]);
        return;
      case 'terminal': {
        const script = `tell application "Terminal"
          activate
          do script "cd '${escapedPath}'"
        end tell`;
        spawnDetached(['osascript', '-e', script]);
        return;
      }
      case 'warp':
        spawnDetached(['open', '-a', 'Warp', path]);
        return;
      case 'alacritty':
        spawnWithPath(['alacritty', '--working-directory', path]);
        return;
      case 'hyper':
        spawnDetached(['open', '-a', 'Hyper', path]);
        return;
      default:
        try {
          spawnDetached(['open', '-a', terminal, path]);
        } catch {
          spawnWithPath([terminal, path]);
        }
    }
  } catch (error) {
    throw new Error(`Failed to open ${terminal}: ${error instanceof Error ? error.message : String(error)}`);
  }
}
