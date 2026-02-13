import { useCallback, useEffect, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import {
  getMiniViewerHotkey,
  setMiniViewerHotkey,
  getMiniViewerSide,
  setMiniViewerSide,
  getMiniViewerShowOnStart,
  setMiniViewerShowOnStart,
  getExperimentalVsCodeSessionOpening,
  MINI_VIEWER_HOTKEY_STORAGE_KEY,
  type MiniViewerSide,
} from '@/lib/settings';

export type UseMiniViewerReturn = {
  miniViewerHotkey: string;
  setMiniViewerHotkeyState: (hotkey: string) => void;
  miniViewerIsRecording: boolean;
  setMiniViewerIsRecording: (recording: boolean) => void;
  miniViewerRecordedKeys: string[];
  setMiniViewerRecordedKeys: (keys: string[]) => void;
  miniViewerSaved: boolean;
  miniViewerSide: MiniViewerSide;
  miniViewerShowOnStart: boolean;
  registerMiniViewerHotkey: (shortcut: string) => Promise<boolean>;
  handleMiniViewerSave: () => Promise<void>;
  handleMiniViewerClear: () => Promise<void>;
  handleMiniViewerSideChange: (side: MiniViewerSide) => Promise<void>;
  handleMiniViewerShowOnStartChange: (enabled: boolean) => void;
};

export function useMiniViewer(
  setError: (error: string | null) => void
): UseMiniViewerReturn {
  const [miniViewerHotkey, setMiniViewerHotkeyState] = useState(getMiniViewerHotkey());
  const [miniViewerIsRecording, setMiniViewerIsRecording] = useState(false);
  const [miniViewerRecordedKeys, setMiniViewerRecordedKeys] = useState<string[]>([]);
  const [miniViewerSaved, setMiniViewerSaved] = useState(false);
  const [miniViewerSide, setMiniViewerSideState] = useState<MiniViewerSide>(getMiniViewerSide());
  const [miniViewerShowOnStart, setMiniViewerShowOnStartState] = useState(getMiniViewerShowOnStart());

  const registerMiniViewerHotkey = useCallback(async (shortcut: string) => {
    try {
      await invoke('register_mini_viewer_shortcut', { shortcut });
      setError(null);
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      return false;
    }
  }, [setError]);

  const handleMiniViewerSave = async () => {
    const success = await registerMiniViewerHotkey(miniViewerHotkey);
    if (success) {
      setMiniViewerHotkey(miniViewerHotkey);
      setMiniViewerSaved(true);
      setTimeout(() => setMiniViewerSaved(false), 2000);
    }
  };

  const handleMiniViewerClear = async () => {
    try {
      await invoke('unregister_mini_viewer_shortcut');
      setMiniViewerHotkeyState('');
      localStorage.removeItem(MINI_VIEWER_HOTKEY_STORAGE_KEY);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const handleMiniViewerSideChange = async (side: MiniViewerSide) => {
    setMiniViewerSideState(side);
    setMiniViewerSide(side);

    try {
      await invoke('set_mini_viewer_side', { side });
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const handleMiniViewerShowOnStartChange = (enabled: boolean) => {
    setMiniViewerShowOnStartState(enabled);
    setMiniViewerShowOnStart(enabled);
  };

  return {
    miniViewerHotkey,
    setMiniViewerHotkeyState,
    miniViewerIsRecording,
    setMiniViewerIsRecording,
    miniViewerRecordedKeys,
    setMiniViewerRecordedKeys,
    miniViewerSaved,
    miniViewerSide,
    miniViewerShowOnStart,
    registerMiniViewerHotkey,
    handleMiniViewerSave,
    handleMiniViewerClear,
    handleMiniViewerSideChange,
    handleMiniViewerShowOnStartChange,
  };
}

export function useMiniViewerInit() {
  useEffect(() => {
    const side = getMiniViewerSide();
    invoke('set_mini_viewer_side', { side }).catch(console.error);
    invoke('set_mini_viewer_experimental_vscode_session_opening', {
      enabled: getExperimentalVsCodeSessionOpening(),
    }).catch(console.error);

    const shortcut = getMiniViewerHotkey();
    if (shortcut) {
      invoke('register_mini_viewer_shortcut', { shortcut }).catch(console.error);
    }

    if (getMiniViewerShowOnStart()) {
      invoke('show_mini_viewer').catch(console.error);
    }
  }, []);
}
