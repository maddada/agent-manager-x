// Voice notification settings component

import { Button } from '@/components/ui/button';

export type NotificationSettingsProps = {
  notificationInstalled: boolean | null;
  notificationLoading: boolean;
  bellMode: boolean;
  bellModeLoading: boolean;
  onInstall: () => void;
  onUninstall: () => void;
  onBellModeToggle: () => void;
};

export function NotificationSettings({
  notificationInstalled,
  notificationLoading,
  bellMode,
  bellModeLoading,
  onInstall,
  onUninstall,
  onBellModeToggle,
}: NotificationSettingsProps) {
  return (
    <div className='space-y-3'>
      <div className='text-sm font-medium text-foreground'>Voice Notifications</div>
      <p className='text-xs text-muted-foreground'>
        Claude will speak a summary when tasks complete (macOS only)
      </p>
      <Button
        variant={notificationInstalled ? 'destructive' : 'default'}
        size='sm'
        className='w-full'
        onClick={notificationInstalled ? onUninstall : onInstall}
        disabled={notificationLoading || notificationInstalled === null}
      >
        {notificationLoading ? 'Working...' : notificationInstalled ? 'Uninstall' : 'Install'}
      </Button>
      {notificationInstalled && (
        <div className='flex items-center justify-between pt-2'>
          <div>
            <div className='text-sm text-foreground'>Bell Mode</div>
            <p className='text-xs text-muted-foreground'>Play a sound instead of speaking</p>
          </div>
          <Button
            variant={bellMode ? 'default' : 'outline'}
            size='sm'
            onClick={onBellModeToggle}
            disabled={bellModeLoading}
          >
            {bellModeLoading ? '...' : bellMode ? 'On' : 'Off'}
          </Button>
        </div>
      )}
    </div>
  );
}
