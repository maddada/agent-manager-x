import { runCommand } from './utils/shell';

function getDescendantPids(pid: number): number[] {
  const descendants: number[] = [];
  const result = runCommand(['pgrep', '-P', String(pid)]);
  if (!result.success || !result.stdout) {
    return descendants;
  }

  for (const line of result.stdout.split('\n')) {
    const childPid = Number.parseInt(line.trim(), 10);
    if (Number.isNaN(childPid)) {
      continue;
    }
    descendants.push(...getDescendantPids(childPid));
    descendants.push(childPid);
  }

  return descendants;
}

function isProcessRunning(pid: number): boolean {
  const result = runCommand(['kill', '-0', String(pid)]);
  return result.success;
}

function killPid(pid: number): void {
  runCommand(['kill', '-9', String(pid)]);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

export async function killSessionProcess(pid: number): Promise<void> {
  const descendants = getDescendantPids(pid);

  for (const childPid of descendants) {
    killPid(childPid);
  }

  killPid(pid);
  runCommand(['kill', '-9', `-${pid}`]);

  await sleep(50);

  if (!isProcessRunning(pid)) {
    return;
  }

  const retryDescendants = getDescendantPids(pid);
  for (const childPid of retryDescendants) {
    killPid(childPid);
  }

  killPid(pid);
  await sleep(50);

  if (isProcessRunning(pid)) {
    throw new Error(`Process ${pid} still running after multiple kill attempts`);
  }
}
