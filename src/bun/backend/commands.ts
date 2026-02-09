import { focusSession as focusTerminalSession } from './focusTerminal';
import { killSessionProcess } from './killSession';
import {
  checkBellMode,
  checkNotificationSystem,
  installNotificationSystem,
  setBellMode,
  uninstallNotificationSystem,
  writeDebugLog,
} from './notifications';
import { openInEditor, openInTerminal } from './openers';
import { getAllSessions } from './sessions';

type WindowController = {
  isMinimized(): boolean;
  minimize(): void;
  unminimize(): void;
  focus(): void;
};

type TrayController = {
  setTitle(title: string): void;
};

type GlobalShortcutApi = {
  register(accelerator: string, callback: () => void): boolean;
  unregister(accelerator: string): boolean;
};

type UtilsApi = {
  openExternal(url: string): boolean;
};

let mainWindow: WindowController | null = null;
let tray: TrayController | null = null;
let currentShortcut: string | null = null;
let globalShortcutApi: GlobalShortcutApi | null = null;
let utilsApi: UtilsApi | null = null;
const appBootTimeMs = Date.now();

function toggleMainWindow(): void {
  if (!mainWindow) {
    return;
  }

  // Guard against spurious shortcut callbacks fired during initial registration.
  // Keep startup deterministic: first shortcut events should surface the app, not hide it.
  if (Date.now() - appBootTimeMs < 2_000) {
    if (mainWindow.isMinimized()) {
      mainWindow.unminimize();
    }
    mainWindow.focus();
    return;
  }

  if (mainWindow.isMinimized()) {
    mainWindow.unminimize();
    mainWindow.focus();
  } else {
    mainWindow.minimize();
  }
}

export function bindMainWindow(window: WindowController): void {
  mainWindow = window;
}

export function bindTray(nextTray: TrayController): void {
  tray = nextTray;
}

export function bindNativeApis(api: {
  GlobalShortcut: GlobalShortcutApi;
  Utils: UtilsApi;
}): void {
  globalShortcutApi = api.GlobalShortcut;
  utilsApi = api.Utils;
}

function parseNumber(value: unknown, field: string): number {
  if (typeof value !== 'number' || Number.isNaN(value)) {
    throw new Error(`Missing or invalid ${field}`);
  }
  return value;
}

function parseString(value: unknown, field: string): string {
  if (typeof value !== 'string') {
    throw new Error(`Missing or invalid ${field}`);
  }
  return value;
}

export const commandHandlers = {
  get_all_sessions: () => getAllSessions(),

  focus_session: (params: { pid?: unknown; projectPath?: unknown; project_path?: unknown } = {}) => {
    const pid = parseNumber(params.pid, 'pid');
    const projectPath = parseString(params.projectPath ?? params.project_path, 'project_path');
    focusTerminalSession(pid, projectPath);
    return null;
  },

  update_tray_title: (params: { total?: unknown; waiting?: unknown } = {}) => {
    const total = parseNumber(params.total, 'total');
    const waiting = parseNumber(params.waiting, 'waiting');

    const title = waiting > 0
      ? `${total} (${waiting} idle)`
      : total > 0
        ? `${total}`
        : '';

    tray?.setTitle(title);
    return null;
  },

  register_shortcut: (params: { shortcut?: unknown } = {}) => {
    if (!globalShortcutApi) {
      throw new Error('Global shortcut API is not initialized');
    }

    const shortcut = parseString(params.shortcut, 'shortcut');

    if (currentShortcut) {
      globalShortcutApi.unregister(currentShortcut);
      currentShortcut = null;
    }

    const ok = globalShortcutApi.register(shortcut, () => {
      toggleMainWindow();
    });

    if (!ok) {
      throw new Error('Failed to register shortcut');
    }

    currentShortcut = shortcut;
    return null;
  },

  unregister_shortcut: () => {
    if (!globalShortcutApi) {
      throw new Error('Global shortcut API is not initialized');
    }

    if (currentShortcut) {
      const ok = globalShortcutApi.unregister(currentShortcut);
      currentShortcut = null;
      if (!ok) {
        throw new Error('Failed to unregister shortcut');
      }
    }
    return null;
  },

  kill_session: async (params: { pid?: unknown } = {}) => {
    const pid = parseNumber(params.pid, 'pid');
    await killSessionProcess(pid);
    return null;
  },

  open_in_editor: (params: { path?: unknown; editor?: unknown } = {}) => {
    const path = parseString(params.path, 'path');
    const editor = parseString(params.editor, 'editor');
    openInEditor(path, editor);
    return null;
  },

  open_in_terminal: (params: { path?: unknown; terminal?: unknown } = {}) => {
    const path = parseString(params.path, 'path');
    const terminal = parseString(params.terminal, 'terminal');
    openInTerminal(path, terminal);
    return null;
  },

  write_debug_log: (params: { content?: unknown } = {}) => {
    const content = parseString(params.content, 'content');
    return writeDebugLog(content);
  },

  check_notification_system: () => checkNotificationSystem(),

  install_notification_system: () => {
    installNotificationSystem();
    return null;
  },

  uninstall_notification_system: () => {
    uninstallNotificationSystem();
    return null;
  },

  check_bell_mode: () => checkBellMode(),

  set_bell_mode: (params: { enabled?: unknown } = {}) => {
    if (typeof params.enabled !== 'boolean') {
      throw new Error('Missing or invalid enabled');
    }
    setBellMode(params.enabled);
    return null;
  },

  open_url: (params: { url?: unknown } = {}) => {
    if (!utilsApi) {
      throw new Error('Utils API is not initialized');
    }

    const url = parseString(params.url, 'url');
    return utilsApi.openExternal(url);
  },
} as const;
