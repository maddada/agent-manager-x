export type ProjectCommandAction = 'run' | 'build';

type ProjectCommandRecord = Partial<Record<ProjectCommandAction, string>>;
type ProjectCommandsStore = Record<string, ProjectCommandRecord>;

const PROJECT_COMMANDS_STORAGE_KEY = 'agent-manager-x-project-commands';

function readProjectCommandsStore(): ProjectCommandsStore {
  try {
    const rawValue = localStorage.getItem(PROJECT_COMMANDS_STORAGE_KEY);
    if (!rawValue) {
      return {};
    }

    const parsed = JSON.parse(rawValue);
    if (parsed && typeof parsed === 'object') {
      return parsed as ProjectCommandsStore;
    }
  } catch {
    // Ignore malformed storage and fall back to empty object
  }

  return {};
}

function writeProjectCommandsStore(store: ProjectCommandsStore) {
  localStorage.setItem(PROJECT_COMMANDS_STORAGE_KEY, JSON.stringify(store));
}

export function getProjectCommand(projectPath: string, action: ProjectCommandAction): string {
  const store = readProjectCommandsStore();
  return (store[projectPath]?.[action] || '').trim();
}

export function setProjectCommand(projectPath: string, action: ProjectCommandAction, command: string) {
  const store = readProjectCommandsStore();
  const normalized = command.trim();

  if (normalized) {
    store[projectPath] = {
      ...store[projectPath],
      [action]: normalized,
    };
  } else if (store[projectPath]) {
    delete store[projectPath][action];
    if (Object.keys(store[projectPath]).length === 0) {
      delete store[projectPath];
    }
  }

  writeProjectCommandsStore(store);
}
