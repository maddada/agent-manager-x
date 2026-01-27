// App main content area with session grid, error state, and empty state

import { SessionGrid } from '@/components/SessionGrid';
import { ErrorIcon, EmptyStateIcon } from './icons';
import type { Session } from '@/types/session';
import type { DefaultEditor } from '@/lib/settings';

export type AppMainContentProps = {
  sessions: Session[];
  error: string | null;
  defaultEditor: DefaultEditor;
  onRefresh: () => void;
};

function ErrorState({ error }: { error: string }) {
  return (
    <div className='flex items-center justify-center h-full'>
      <div className='p-6 text-destructive text-sm text-center bg-destructive/10 rounded-xl border border-destructive/20 max-w-md'>
        <ErrorIcon className='w-8 h-8 mx-auto mb-3 opacity-50' />
        {error}
      </div>
    </div>
  );
}

function EmptyState() {
  return (
    <div className='flex flex-col items-center justify-center h-full text-center'>
      <div className='w-20 h-20 mb-6 rounded-2xl bg-muted/50 flex items-center justify-center border border-border'>
        <EmptyStateIcon className='w-10 h-10 text-muted-foreground' />
      </div>
      <h2 className='text-lg font-medium text-foreground mb-2'>No active sessions</h2>
      <p className='text-muted-foreground text-sm max-w-xs'>
        Start a Claude session in your terminal to see it here
      </p>
    </div>
  );
}

export function AppMainContent({ sessions, error, defaultEditor, onRefresh }: AppMainContentProps) {
  return (
    <main className='flex-1 overflow-y-auto p-6'>
      {error ? (
        <ErrorState error={error} />
      ) : sessions.length === 0 ? (
        <EmptyState />
      ) : (
        <SessionGrid sessions={sessions} defaultEditor={defaultEditor} onRefresh={onRefresh} />
      )}
    </main>
  );
}
