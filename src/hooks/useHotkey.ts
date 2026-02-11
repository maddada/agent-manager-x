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

function normalizeShortcut(shortcut: string): string {
  const raw = shortcut.trim();
  if (!raw) {
    return '';
  }

  const parts = raw
    .split('+')
    .map((part) => part.trim())
    .filter((part) => part.length > 0);

  if (parts.length === 0) {
    return '';
  }

  const normalized = parts.map((part) => {
    const lower = part.toLowerCase();
    switch (lower) {
      case 'cmd':
      case 'command':
        return 'Command';
      case 'cmdorctrl':
      case 'commandorcontrol':
        return 'CommandOrControl';
      case 'ctrl':
      case 'control':
        return 'Control';
      case 'alt':
      case 'option':
        return 'Option';
      case 'shift':
        return 'Shift';
      case 'meta':
      case 'super':
      case 'win':
        return 'Super';
      case 'arrowup':
      case 'up':
        return 'Up';
      case 'arrowdown':
      case 'down':
        return 'Down';
      case 'arrowleft':
      case 'left':
        return 'Left';
      case 'arrowright':
      case 'right':
        return 'Right';
      case 'spacebar':
      case 'space':
        return 'Space';
      case 'esc':
      case 'escape':
        return 'Escape';
      case 'return':
      case 'enter':
        return 'Enter';
      default:
        return part.length === 1 ? part.toUpperCase() : part;
    }
  });

  return normalized.join('+');
}

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
    if (savedHotkey === null) {
      setHotkey(DEFAULT_HOTKEY);
      return;
    }

    const normalized = normalizeShortcut(savedHotkey);
    setHotkey(normalized);
    if (normalized !== savedHotkey) {
      localStorage.setItem(STORAGE_KEY, normalized);
    }
  }, []);

  const registerHotkey = useCallback(async (shortcut: string) => {
    try {
      const normalizedShortcut = normalizeShortcut(shortcut);
      if (!normalizedShortcut) {
        throw new Error('Shortcut cannot be empty');
      }
      await invoke('register_shortcut', { shortcut: normalizedShortcut });
      setError(null);
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      return false;
    }
  }, [setError]);

  const handleSave = async () => {
    const pendingRecordedShortcut = normalizeShortcut(recordedKeys.join('+'));
    const normalizedShortcut = normalizeShortcut(hotkey) || pendingRecordedShortcut;
    const success = await registerHotkey(normalizedShortcut);
    if (success) {
      setIsRecording(false);
      setRecordedKeys([]);
      setHotkey(normalizedShortcut);
      localStorage.setItem(STORAGE_KEY, normalizedShortcut);
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    }
  };

  const handleClear = async () => {
    setIsRecording(false);
    setRecordedKeys([]);
    setHotkey('');
    localStorage.setItem(STORAGE_KEY, '');

    try {
      await invoke('unregister_shortcut');
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
    if (savedHotkey === null) {
      const initialHotkey = normalizeShortcut(DEFAULT_HOTKEY) || DEFAULT_HOTKEY;
      localStorage.setItem(STORAGE_KEY, initialHotkey);
      invoke('register_shortcut', { shortcut: initialHotkey }).catch(console.error);
      return;
    }

    const startupHotkey = normalizeShortcut(savedHotkey);
    if (startupHotkey !== savedHotkey) {
      localStorage.setItem(STORAGE_KEY, startupHotkey);
    }

    if (!startupHotkey) {
      return;
    }

    invoke('register_shortcut', { shortcut: startupHotkey }).catch(console.error);
  }, []);
}
