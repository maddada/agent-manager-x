import { appendFileSync } from 'node:fs';
import { BrowserView, BrowserWindow, GlobalShortcut, Tray, Utils } from 'electrobun/bun';
import {
  bindMainWindow,
  bindMainWindowFactory,
  bindNativeApis,
  bindTray,
  clearMainWindow,
  commandHandlers,
} from './backend/commands';

type RequestDef<F> = F extends (...args: infer A) => infer R
  ? {
      params: A extends [] ? undefined : A[0];
      response: Awaited<R>;
    }
  : never;

type BackendRequests = {
  [K in keyof typeof commandHandlers]: RequestDef<(typeof commandHandlers)[K]>;
};

type BackendRPCSchema = {
  bun: {
    requests: BackendRequests;
    messages: Record<never, never>;
  };
  webview: {
    requests: Record<never, never>;
    messages: Record<never, never>;
  };
};

const MAIN_TITLE = 'Agent Manager X';
const STARTUP_LOG_PATH = '/tmp/agent-manager-x-electrobun.log';

function formatError(error: unknown): string {
  if (error instanceof Error) {
    return error.stack ?? error.message;
  }
  return String(error);
}

function logStartup(message: string): void {
  try {
    appendFileSync(STARTUP_LOG_PATH, `${new Date().toISOString()} ${message}\n`, 'utf8');
  } catch {
    // Ignore filesystem logging errors so startup flow is never blocked.
  }
}

process.on('uncaughtException', (error) => {
  logStartup(`[uncaughtException] ${formatError(error)}`);
});

process.on('unhandledRejection', (reason) => {
  logStartup(`[unhandledRejection] ${formatError(reason)}`);
});

function getMainViewUrl(): string {
  const devUrl = process.env.ELECTROBUN_DEV_URL;
  if (typeof devUrl === 'string' && devUrl.trim().length > 0) {
    return devUrl.trim();
  }
  return 'views://mainview/index.html';
}

function createMainTray(getOrCreateMainWindow: () => BrowserWindow): Tray {
  const appTray = new Tray({ title: '0' });
  appTray.setMenu([
    { type: 'normal', label: 'Show Window', action: 'show' },
    { type: 'separator' },
    { type: 'normal', label: 'Quit', action: 'quit' },
  ]);

  appTray.on('tray-clicked', (event: unknown) => {
    const payload = (event as { data?: { action?: string } }).data;
    const action = payload?.action ?? '';

    if (action === 'quit') {
      Utils.quit();
      return;
    }

    if (action === '' || action === 'show') {
      const mainWindow = getOrCreateMainWindow();
      if (mainWindow.isMinimized()) {
        mainWindow.unminimize();
      }
      mainWindow.show();
      mainWindow.focus();
    }
  });

  return appTray;
}

const rpc = BrowserView.defineRPC<BackendRPCSchema>({
  maxRequestTime: 30_000,
  handlers: {
    requests: commandHandlers as never,
    messages: {},
  },
});

try {
  const url = getMainViewUrl();
  logStartup(`[startup] creating main window with url=${url}`);
  console.log(`[amx] creating main window with url=${url}`);

  let mainWindow: BrowserWindow | null = null;

  const getOrCreateMainWindow = (): BrowserWindow => {
    if (mainWindow) {
      return mainWindow;
    }

    mainWindow = new BrowserWindow({
      title: MAIN_TITLE,
      url,
      frame: {
        width: 1100,
        height: 700,
        x: 160,
        y: 120,
      },
      rpc,
    });

    mainWindow.on('close', () => {
      clearMainWindow();
      mainWindow = null;
    });

    bindMainWindow(mainWindow);
    logStartup('[startup] main window created');
    console.log('[amx] main window created');
    return mainWindow;
  };

  bindNativeApis({ GlobalShortcut, Utils });
  bindMainWindowFactory(getOrCreateMainWindow);
  bindTray(createMainTray(getOrCreateMainWindow));
  commandHandlers.update_tray_title({ total: 0, waiting: 0 });

  const window = getOrCreateMainWindow();

  if (window.isMinimized()) {
    window.unminimize();
  }
  window.show();
  window.focus();
} catch (error) {
  const message = formatError(error);
  logStartup(`[startup] fatal: ${message}`);
  throw error;
}
