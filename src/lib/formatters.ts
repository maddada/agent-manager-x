export function formatTimeAgo(timestamp: string): string {
  const date = new Date(timestamp);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;

  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return `${diffHours}h ago`;

  const diffDays = Math.floor(diffHours / 24);
  return `${diffDays}d ago`;
}

export function truncatePath(path: string): string {
  return path.replace(/^\/Users\/[^/]+/, '~');
}

import type { SessionStatus } from '../types/session';

type StatusStyleConfig = {
  color: string;
  fillColor: string;
  cardBg: string;
  cardBorder: string;
  badgeClassName: string;
  label: string;
  cardOpacity?: string;
};

// Ensure all SessionStatus values plus 'exiting' (UI-only state) are covered
export const statusConfig: Record<SessionStatus | 'exiting', StatusStyleConfig> = {
  thinking: {
    color: 'bg-primary',
    fillColor: 'fill-primary',
    cardBg: 'bg-primary/15',
    cardBorder: 'border-primary/30',
    badgeClassName: 'border-primary/40 text-primary bg-primary/20',
    label: 'Responding...',
  },
  processing: {
    color: 'bg-primary',
    fillColor: 'fill-primary',
    cardBg: 'bg-primary/15',
    cardBorder: 'border-primary/30',
    badgeClassName: 'border-primary/40 text-primary bg-primary/20',
    label: 'Processing..',
  },
  waiting: {
    color: 'bg-primary/50',
    fillColor: 'fill-primary/50',
    cardBg: 'bg-primary/5',
    cardBorder: 'border-primary/15',
    badgeClassName: 'border-primary/20 text-primary/70 bg-primary/10',
    label: 'Waiting for input',
  },
  idle: {
    color: 'bg-gray-400',
    fillColor: 'fill-gray-400',
    cardBg: 'bg-gray-400/10',
    cardBorder: 'border-gray-400/20',
    badgeClassName: 'border-gray-400/30 text-gray-400 bg-gray-400/10',
    label: 'Idle',
    cardOpacity: 'opacity-70',
  },
  stale: {
    color: 'bg-gray-500',
    fillColor: 'fill-gray-500',
    cardBg: 'bg-gray-500/5',
    cardBorder: 'border-gray-500/10',
    badgeClassName: 'border-gray-500/20 text-gray-500 bg-gray-500/5',
    label: 'Stale',
    cardOpacity: 'opacity-50',
  },
  exiting: {
    color: 'bg-destructive',
    fillColor: 'fill-destructive',
    cardBg: 'bg-destructive/5',
    cardBorder: 'border-destructive/20',
    badgeClassName: 'border-destructive/30 text-destructive bg-destructive/10',
    label: 'Exiting...',
    cardOpacity: 'opacity-30',
  },
} as const;
