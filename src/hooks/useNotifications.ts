// Voice notification settings hook

import { useState, useEffect } from 'react';
import { invoke } from '@/platform/native';

export type UseNotificationsReturn = {
  notificationInstalled: boolean | null;
  notificationLoading: boolean;
  bellMode: boolean;
  bellModeLoading: boolean;
  handleInstallNotifications: () => Promise<void>;
  handleUninstallNotifications: () => Promise<void>;
  handleBellModeToggle: () => Promise<void>;
};

export function useNotifications(
  setError: (error: string | null) => void
): UseNotificationsReturn {
  const [notificationInstalled, setNotificationInstalled] = useState<boolean | null>(null);
  const [notificationLoading, setNotificationLoading] = useState(false);
  const [bellMode, setBellMode] = useState<boolean>(false);
  const [bellModeLoading, setBellModeLoading] = useState(false);

  // Check voice notification status on mount
  useEffect(() => {
    invoke<boolean>('check_notification_system')
      .then((installed) => {
        setNotificationInstalled(installed);
        if (installed) {
          invoke<boolean>('check_bell_mode')
            .then(setBellMode)
            .catch(() => setBellMode(false));
        }
      })
      .catch(() => setNotificationInstalled(false));
  }, []);

  const handleInstallNotifications = async () => {
    setNotificationLoading(true);
    try {
      await invoke('install_notification_system');
      setNotificationInstalled(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
    setNotificationLoading(false);
  };

  const handleUninstallNotifications = async () => {
    setNotificationLoading(true);
    try {
      await invoke('uninstall_notification_system');
      setNotificationInstalled(false);
      setBellMode(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
    setNotificationLoading(false);
  };

  const handleBellModeToggle = async () => {
    setBellModeLoading(true);
    try {
      const newValue = !bellMode;
      await invoke('set_bell_mode', { enabled: newValue });
      setBellMode(newValue);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
    setBellModeLoading(false);
  };

  return {
    notificationInstalled,
    notificationLoading,
    bellMode,
    bellModeLoading,
    handleInstallNotifications,
    handleUninstallNotifications,
    handleBellModeToggle,
  };
}
