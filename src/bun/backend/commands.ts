import { spawnSync } from 'node:child_process';
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
  show(): void;
  close(): void;
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
let mainWindowFactory: (() => WindowController) | null = null;
let tray: TrayController | null = null;
let currentShortcut: string | null = null;
let globalShortcutApi: GlobalShortcutApi | null = null;
let utilsApi: UtilsApi | null = null;
const appBootTimeMs = Date.now();
const APP_PROCESS_ID = process.pid;
const APP_PARENT_PROCESS_ID = process.ppid;
const APP_BUNDLE_ID = (
  typeof process.env.ELECTROBUN_APP_IDENTIFIER === 'string'
    ? process.env.ELECTROBUN_APP_IDENTIFIER.trim()
    : ''
) || 'sh.madda.agentmanagerx';

function runAppleScript(script: string) {
  return spawnSync('osascript', ['-e', script], { encoding: 'utf8' });
}

function runAppleScriptBoolean(script: string): boolean {
  const result = runAppleScript(script);
  return result.status === 0 && String(result.stdout).trim().toLowerCase() === 'true';
}

function runAppleScriptText(script: string): string | null {
  const result = runAppleScript(script);
  if (result.status !== 0) {
    return null;
  }
  return String(result.stdout).trim();
}

function setCurrentAppVisible(visible: boolean): boolean {
  if (process.platform !== 'darwin') {
    return false;
  }

  const byBundleIdScript = `tell application id "${APP_BUNDLE_ID}" to set visible to ${visible ? 'true' : 'false'}`;
  if (runAppleScript(byBundleIdScript).status === 0) {
    return true;
  }

  const pidCandidates = [APP_PROCESS_ID, APP_PARENT_PROCESS_ID].filter((pid) => Number.isInteger(pid) && pid > 1);
  for (const pid of pidCandidates) {
    const byPidScript = `tell application "System Events"
if exists (first application process whose unix id is ${pid}) then
  set visible of first application process whose unix id is ${pid} to ${visible ? 'true' : 'false'}
  return true
end if
return false
end tell`;
    if (runAppleScriptBoolean(byPidScript)) {
      return true;
    }
  }

  return false;
}

function activateCurrentApp(): void {
  if (process.platform !== 'darwin') {
    return;
  }

  const activateByBundleIdScript = `tell application id "${APP_BUNDLE_ID}" to activate`;
  runAppleScript(activateByBundleIdScript);
}

function isCurrentAppFrontmost(): boolean {
  if (process.platform !== 'darwin') {
    return false;
  }

  const frontmostPidText = runAppleScriptText('tell application "System Events" to get unix id of first application process whose frontmost is true');
  const frontmostPid = frontmostPidText ? Number.parseInt(frontmostPidText, 10) : Number.NaN;
  if (!Number.isNaN(frontmostPid) && (frontmostPid === APP_PROCESS_ID || frontmostPid === APP_PARENT_PROCESS_ID)) {
    return true;
  }

  const byBundleScript = `tell application "System Events"
if not (exists (first application process whose frontmost is true)) then
  return false
end if
return (bundle identifier of first application process whose frontmost is true) is "${APP_BUNDLE_ID}"
end tell`;
  return runAppleScriptBoolean(byBundleScript);
}

function showMainWindow(): void {
  if (process.platform === 'darwin') {
    setCurrentAppVisible(true);
    activateCurrentApp();
  }

  // Guard against spurious shortcut callbacks fired during initial registration.
  // Keep startup deterministic: first shortcut events should surface the app.
  if (Date.now() - appBootTimeMs < 2_000) {
    if (!mainWindow && mainWindowFactory) {
      mainWindow = mainWindowFactory();
    }
    if (!mainWindow) {
      return;
    }
    if (mainWindow.isMinimized()) {
      mainWindow.unminimize();
    }
    mainWindow.show();
    mainWindow.focus();
    return;
  }

  if (!mainWindow && mainWindowFactory) {
    mainWindow = mainWindowFactory();
  }

  if (!mainWindow) {
    return;
  }

  if (mainWindow.isMinimized()) {
    mainWindow.unminimize();
  }

  mainWindow.show();
  mainWindow.focus();
}

function hideMainWindow(): void {
  if (process.platform === 'darwin') {
    if (setCurrentAppVisible(false)) {
      return;
    }
  }

  if (!mainWindow) {
    return;
  }

  if (!mainWindow.isMinimized()) {
    mainWindow.minimize();
  }
}

function hasMacUiScriptingAccess(): boolean {
  if (process.platform !== 'darwin') {
    return true;
  }

  const requiresAccessibilityScript = 'tell application "System Events" to tell process "Finder" to count UI elements';
  const result = runAppleScript(requiresAccessibilityScript);
  return result.status === 0;
}

function toggleMainWindowFromHotkey(): void {
  if (process.platform === 'darwin' && isCurrentAppFrontmost()) {
    hideMainWindow();
    return;
  }

  showMainWindow();
}

function requestMacGlobalHotkeyPermissions(): void {
  if (process.platform !== 'darwin') {
    return;
  }

  // Accessibility permission is required for reliable global keyboard capture.
  spawnSync('open', ['x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'], { stdio: 'ignore' });
}

export function bindMainWindow(window: WindowController): void {
  mainWindow = window;
}

export function clearMainWindow(): void {
  mainWindow = null;
}

export function bindMainWindowFactory(factory: () => WindowController): void {
  mainWindowFactory = factory;
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

function normalizeShortcut(shortcut: string): string {
  return shortcut
    .split('+')
    .map((part) => part.trim())
    .filter((part) => part.length > 0)
    .join('+');
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
      : `${total}`;

    tray?.setTitle(title);
    return null;
  },

  toggle_main_window: () => {
    toggleMainWindowFromHotkey();
    return null;
  },

  hide_app: () => {
    hideMainWindow();
    return null;
  },

  check_accessibility_permission: () => {
    return hasMacUiScriptingAccess();
  },

  open_accessibility_settings: () => {
    requestMacGlobalHotkeyPermissions();
    return null;
  },

  register_shortcut: (params: { shortcut?: unknown; promptPermissions?: unknown } = {}) => {
    if (!globalShortcutApi) {
      throw new Error('Global shortcut API is not initialized');
    }

    const shortcut = normalizeShortcut(parseString(params.shortcut, 'shortcut'));
    if (!shortcut) {
      throw new Error('Missing or invalid shortcut');
    }

    const promptPermissions = params.promptPermissions === true;
    if (!hasMacUiScriptingAccess()) {
      if (promptPermissions) {
        requestMacGlobalHotkeyPermissions();
      }
      throw new Error('Global hotkey needs macOS Accessibility permission. Enable Agent Manager X in Privacy & Security > Accessibility, then save again.');
    }

    if (currentShortcut) {
      globalShortcutApi.unregister(currentShortcut);
      currentShortcut = null;
    }

    const ok = globalShortcutApi.register(shortcut, () => {
      toggleMainWindowFromHotkey();
    });

    if (!ok) {
      throw new Error('Failed to register shortcut (it may already be in use)');
    }

    currentShortcut = shortcut;
    return null;
  },

  unregister_shortcut: () => {
    if (!globalShortcutApi) {
      throw new Error('Global shortcut API is not initialized');
    }

    if (currentShortcut) {
      globalShortcutApi.unregister(currentShortcut);
      currentShortcut = null;
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
