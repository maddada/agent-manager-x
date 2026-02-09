import { spawn, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';

export interface CommandResult {
  success: boolean;
  exitCode: number;
  stdout: string;
  stderr: string;
}

function decode(data: Buffer | string | null | undefined): string {
  if (!data) {
    return '';
  }
  return String(data).trim();
}

export function runCommand(
  cmd: string[],
  options?: {
    cwd?: string;
    env?: Record<string, string>;
    stdin?: string;
  },
): CommandResult {
  try {
    const proc = spawnSync(cmd[0], cmd.slice(1), {
      cwd: options?.cwd,
      env: options?.env,
      input: options?.stdin,
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    return {
      success: proc.status === 0,
      exitCode: proc.status ?? 1,
      stdout: decode(proc.stdout),
      stderr: decode(proc.stderr),
    };
  } catch (error) {
    return {
      success: false,
      exitCode: 1,
      stdout: '',
      stderr: error instanceof Error ? error.message : String(error),
    };
  }
}

export function spawnDetached(
  cmd: string[],
  options?: {
    cwd?: string;
    env?: Record<string, string>;
  },
): void {
  const child = spawn(cmd[0], cmd.slice(1), {
    cwd: options?.cwd,
    env: options?.env,
    stdio: 'ignore',
    detached: true,
  });
  child.unref();
}

export function commandExists(name: string): boolean {
  const pathValue = process.env.PATH ?? '';
  const paths = pathValue.split(':').filter(Boolean);
  for (const base of paths) {
    const candidate = `${base}/${name}`;
    if (existsSync(candidate)) {
      return true;
    }
  }
  return false;
}

export function escapeAppleScriptString(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

export function shellEscapeSingleQuotes(value: string): string {
  return value.replace(/'/g, "'\\''");
}
