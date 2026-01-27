// Settings state management hook - composes smaller settings hooks

import { useState } from 'react';
import { useHotkey, useHotkeyInit, type UseHotkeyReturn } from './useHotkey';
import { useNotifications, type UseNotificationsReturn } from './useNotifications';
import { useAppearanceSettings, type UseAppearanceSettingsReturn } from './useAppearanceSettings';
import { useEditorTerminalSettings, type UseEditorTerminalSettingsReturn } from './useEditorTerminalSettings';

export type UseSettingsReturn = UseHotkeyReturn &
  UseNotificationsReturn &
  UseAppearanceSettingsReturn &
  UseEditorTerminalSettingsReturn & {
    error: string | null;
    setError: (error: string | null) => void;
  };

export function useSettings(): UseSettingsReturn {
  const [error, setError] = useState<string | null>(null);

  const hotkey = useHotkey(setError);
  const notifications = useNotifications(setError);
  const appearance = useAppearanceSettings();
  const editorTerminal = useEditorTerminalSettings();

  return {
    // Error state
    error,
    setError,

    // Hotkey state
    ...hotkey,

    // Notification state
    ...notifications,

    // Appearance state
    ...appearance,

    // Editor/Terminal state
    ...editorTerminal,
  };
}

// Re-export for convenience
export { useHotkeyInit };
