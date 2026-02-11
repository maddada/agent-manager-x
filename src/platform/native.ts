// Keep command names aligned with the existing frontend invoke surface.
export type NativeCommand =
  | 'get_all_sessions'
  | 'focus_session'
  | 'update_tray_title'
  | 'register_shortcut'
  | 'unregister_shortcut'
  | 'kill_session'
  | 'open_in_editor'
  | 'open_in_terminal'
  | 'write_debug_log'
  | 'check_notification_system'
  | 'install_notification_system'
  | 'uninstall_notification_system'
  | 'check_bell_mode'
  | 'set_bell_mode';

type RpcRequestMap = Record<string, (params?: unknown) => Promise<unknown>>;
type ElectroviewLike = { rpc?: { request: RpcRequestMap } };

let cachedPromise: Promise<ElectroviewLike> | null = null;

async function getElectroview(): Promise<ElectroviewLike> {
  if (cachedPromise) {
    return cachedPromise;
  }

  cachedPromise = (async () => {
    const runtimeReady =
      typeof window !== 'undefined'
      && typeof (window as { __electrobunWebviewId?: unknown }).__electrobunWebviewId === 'number';
    if (!runtimeReady) {
      throw new Error('Electrobun runtime is not available');
    }

    const module = await import('electrobun/view');
    const ctor = (module.default as { Electroview?: unknown } | undefined)?.Electroview;
    if (
      typeof ctor !== 'function'
      || typeof (ctor as { defineRPC?: unknown }).defineRPC !== 'function'
    ) {
      throw new Error('Electrobun runtime is not available');
    }

    const electroviewCtor = ctor as unknown as {
      new (args: { rpc: unknown }): ElectroviewLike;
      defineRPC: (config: {
        handlers: {
          requests: Record<string, unknown>;
          messages: Record<string, unknown>;
        };
      }) => unknown;
    };

    const rpc = electroviewCtor.defineRPC({
      handlers: {
        requests: {},
        messages: {},
      },
    });

    return new electroviewCtor({ rpc });
  })();

  return cachedPromise;
}

export async function invoke<T>(command: NativeCommand, args?: Record<string, unknown>): Promise<T> {
  const view = await getElectroview();
  const requestFn = view.rpc?.request[command];
  if (typeof requestFn !== 'function') {
    throw new Error(`Native command not available: ${command}`);
  }

  if (args === undefined) {
    return (await requestFn()) as T;
  }
  return (await requestFn(args)) as T;
}

export async function openUrl(url: string): Promise<void> {
  const view = await getElectroview();
  const requestFn = view.rpc?.request.open_url;
  if (typeof requestFn !== 'function') {
    throw new Error('Native command not available: open_url');
  }
  const ok = (await requestFn({ url })) as boolean;
  if (!ok) {
    throw new Error(`Failed to open URL: ${url}`);
  }
}
