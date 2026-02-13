import { invoke } from '@tauri-apps/api/core';
import { useEffect, useMemo, useState } from 'react';

type GitDiffStats = {
  additions: number;
  deletions: number;
};

const REFRESH_INTERVAL_MS = 10000;

export function useProjectGitDiffStats(projectPaths: string[]) {
  const [statsByPath, setStatsByPath] = useState<Record<string, GitDiffStats>>({});

  const uniquePaths = useMemo(() => Array.from(new Set(projectPaths)).sort(), [projectPaths]);
  const pathsKey = JSON.stringify(uniquePaths);

  useEffect(() => {
    let isDisposed = false;
    const paths = JSON.parse(pathsKey) as string[];

    if (paths.length === 0) {
      setStatsByPath({});
      return;
    }

    const fetchStats = async () => {
      const statsEntries = await Promise.all(
        paths.map(async (projectPath) => {
          try {
            const stats = await invoke<GitDiffStats>('get_project_git_diff_stats', { projectPath });
            return [projectPath, stats] as const;
          } catch (error) {
            console.error(`Failed to fetch git diff stats for ${projectPath}:`, error);
            return [projectPath, { additions: 0, deletions: 0 }] as const;
          }
        })
      );

      if (isDisposed) {
        return;
      }

      setStatsByPath(Object.fromEntries(statsEntries));
    };

    fetchStats();
    const intervalId = window.setInterval(fetchStats, REFRESH_INTERVAL_MS);

    return () => {
      isDisposed = true;
      window.clearInterval(intervalId);
    };
  }, [pathsKey]);

  return statsByPath;
}
