import type { Session } from '@/types/session';

export type ProjectGroup = {
  projectPath: string;
  projectName: string;
  sessions: Session[];
  color: string;
};

const PROJECT_GROUP_COLOR = 'bg-white/5 border-white/10';

export function groupSessionsByProject(sessions: Session[]): ProjectGroup[] {
  const groups = new Map<string, Session[]>();

  for (const session of sessions) {
    const existing = groups.get(session.projectPath);
    if (existing) {
      existing.push(session);
    } else {
      groups.set(session.projectPath, [session]);
    }
  }

  const result: ProjectGroup[] = [];
  for (const [projectPath, projectSessions] of groups) {
    result.push({
      projectPath,
      projectName: projectSessions[0].projectName,
      sessions: projectSessions,
      color: PROJECT_GROUP_COLOR,
    });
  }

  result.sort((a, b) => a.projectPath.localeCompare(b.projectPath));

  return result;
}
