import { useState, useEffect, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { openUrl } from '@tauri-apps/plugin-opener';
import { Session } from '../types/session';
import {
  type DefaultEditor,
  getDefaultTerminal,
  getCardClickAction,
  getCustomEditorCommand,
  getCustomTerminalCommand,
} from '../components/Settings';
import { getCustomNames, setCustomName, getCustomUrls, setCustomUrl } from '../components/session-card/utils';

export type UseSessionCardOptions = {
  session: Session;
  defaultEditor: DefaultEditor;
  onKill?: () => void;
};

export function useSessionCard({ session, defaultEditor, onKill }: UseSessionCardOptions) {
  const [isKilling, setIsKilling] = useState(false);
  const [customName, setCustomNameState] = useState<string>('');
  const [customUrl, setCustomUrlState] = useState<string>('');
  const [isRenameOpen, setIsRenameOpen] = useState(false);
  const [isUrlOpen, setIsUrlOpen] = useState(false);
  const [renameValue, setRenameValue] = useState('');
  const [urlValue, setUrlValue] = useState('');

  // Load custom data on mount
  useEffect(() => {
    const names = getCustomNames();
    const urls = getCustomUrls();
    setCustomNameState(names[session.id] || '');
    setCustomUrlState(urls[session.id] || '');
  }, [session.id]);

  const handleRename = () => {
    setRenameValue(customName || session.projectName);
    setIsRenameOpen(true);
  };

  const handleSaveRename = () => {
    const newName = renameValue.trim();
    if (newName === session.projectName) {
      setCustomName(session.id, '');
      setCustomNameState('');
    } else {
      setCustomName(session.id, newName);
      setCustomNameState(newName);
    }
    setIsRenameOpen(false);
  };

  const handleResetName = () => {
    setCustomName(session.id, '');
    setCustomNameState('');
    setIsRenameOpen(false);
  };

  const handleSetUrl = () => {
    setUrlValue(customUrl);
    setIsUrlOpen(true);
  };

  const handleSaveUrl = () => {
    const newUrl = urlValue.trim();
    setCustomUrl(session.id, newUrl);
    setCustomUrlState(newUrl);
    setIsUrlOpen(false);
  };

  const handleClearUrl = () => {
    setCustomUrl(session.id, '');
    setCustomUrlState('');
    setIsUrlOpen(false);
  };

  const handleOpenUrl = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (customUrl) {
      // Add protocol if missing
      let url = customUrl;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://' + url;
      }
      await openUrl(url);
    }
  };

  const handleOpenGitHub = useCallback(async () => {
    if (session.githubUrl) {
      await openUrl(session.githubUrl);
    }
  }, [session.githubUrl]);

  // CRITICAL: useCallback with session.pid dependency ensures we always kill the correct process
  // Without this, the closure would capture a stale PID if the session list reorders
  const handleKillSession = useCallback(async () => {
    setIsKilling(true);
    try {
      await invoke('kill_session', { pid: session.pid });
      // Immediately refresh to update UI
      onKill?.();
    } catch (error) {
      console.error('Failed to kill session:', error);
      setIsKilling(false);
    }
  }, [session.pid, onKill]);

  const handleOpenInEditor = useCallback(async (editor: DefaultEditor, e?: React.MouseEvent) => {
    e?.stopPropagation();
    try {
      const editorCommand = editor === 'custom' ? getCustomEditorCommand() : editor;
      if (!editorCommand) {
        console.error('No custom editor command configured');
        return;
      }
      await invoke('open_in_editor', { path: session.projectPath, editor: editorCommand });
    } catch (error) {
      console.error(`Failed to open in ${editor}:`, error);
    }
  }, [session.projectPath]);

  const handleOpenInTerminal = useCallback(async (e?: React.MouseEvent) => {
    e?.stopPropagation();
    try {
      const terminal = getDefaultTerminal();
      const terminalCommand = terminal === 'custom' ? getCustomTerminalCommand() : terminal;
      if (!terminalCommand) {
        console.error('No custom terminal command configured');
        return;
      }
      await invoke('open_in_terminal', { path: session.projectPath, terminal: terminalCommand });
    } catch (error) {
      console.error('Failed to open in terminal:', error);
    }
  }, [session.projectPath]);

  const handleCardClick = useCallback(async () => {
    const clickAction = getCardClickAction();
    if (clickAction === 'terminal') {
      await handleOpenInTerminal();
    } else {
      await handleOpenInEditor(defaultEditor);
    }
  }, [handleOpenInTerminal, handleOpenInEditor, defaultEditor]);

  return {
    // State
    isKilling,
    customName,
    customUrl,
    isRenameOpen,
    isUrlOpen,
    renameValue,
    urlValue,
    // Setters
    setIsRenameOpen,
    setIsUrlOpen,
    setRenameValue,
    setUrlValue,
    // Handlers
    handleRename,
    handleSaveRename,
    handleResetName,
    handleSetUrl,
    handleSaveUrl,
    handleClearUrl,
    handleOpenUrl,
    handleOpenGitHub,
    handleKillSession,
    handleOpenInEditor,
    handleOpenInTerminal,
    handleCardClick,
  };
}
