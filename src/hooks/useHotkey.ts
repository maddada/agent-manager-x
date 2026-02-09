// Hotkey settings hook

import { useState, useEffect, useCallback } from 'react';
import { invoke } from '@/platform/native';
import { STORAGE_KEY, DEFAULT_HOTKEY } from '@/lib/settings';

export type UseHotkeyReturn = {
  hotkey: string;
  setHotkey: (hotkey: string) => void;
  isRecording: boolean;
  setIsRecording: (recording: boolean) => void;
  recordedKeys: string[];
  setRecordedKeys: (keys: string[]) => void;
  saved: boolean;
  registerHotkey: (shortcut: string) => Promise<boolean>;
  handleSave: () => Promise<void>;
  handleClear: () => Promise<void>;
};

export function useHotkey(
  setError: (error: string | null) => void
): UseHotkeyReturn {
  const [hotkey, setHotkey] = useState(DEFAULT_HOTKEY);
  const [isRecording, setIsRecording] = useState(false);
  const [recordedKeys, setRecordedKeys] = useState<string[]>([]);
  const [saved, setSaved] = useState(false);

  // Load saved hotkey on mount
  useEffect(() => {
    const savedHotkey = localStorage.getItem(STORAGE_KEY);
    if (savedHotkey) {
      setHotkey(savedHotkey);
    }
  }, []);

  const registerHotkey = useCallback(async (shortcut: string) => {
    try {
      await invoke('register_shortcut', { shortcut });
      setError(null);
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      return false;
    }
  }, [setError]);

  const handleSave = async () => {
    const success = await registerHotkey(hotkey);
    if (success) {
      localStorage.setItem(STORAGE_KEY, hotkey);
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    }
  };

  const handleClear = async () => {
    try {
      await invoke('unregister_shortcut');
      setHotkey('');
      localStorage.removeItem(STORAGE_KEY);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  return {
    hotkey,
    setHotkey,
    isRecording,
    setIsRecording,
    recordedKeys,
    setRecordedKeys,
    saved,
    registerHotkey,
    handleSave,
    handleClear,
  };
}

// Hook to initialize hotkey on app load
export function useHotkeyInit() {
  useEffect(() => {
    const savedHotkey = localStorage.getItem(STORAGE_KEY);
    if (savedHotkey) {
      invoke('register_shortcut', { shortcut: savedHotkey }).catch(console.error);
    }
  }, []);
}
