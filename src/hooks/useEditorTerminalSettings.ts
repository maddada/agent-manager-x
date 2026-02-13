// Editor and terminal settings hook

import { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import {
  type DefaultEditor,
  type DefaultTerminal,
  getDefaultEditor,
  setDefaultEditor,
  getCustomEditorCommand,
  setCustomEditorCommand,
  getDefaultTerminal,
  setDefaultTerminalSetting,
  getCustomTerminalCommand,
  setCustomTerminalCommand,
  getExperimentalVsCodeSessionOpening,
  setExperimentalVsCodeSessionOpening,
} from '@/lib/settings';

export type UseEditorTerminalSettingsReturn = {
  // Editor state
  defaultEditor: DefaultEditor;
  customEditorCommand: string;
  handleEditorChange: (editor: DefaultEditor) => void;
  handleCustomEditorCommandChange: (command: string) => void;
  experimentalVsCodeSessionOpening: boolean;
  handleExperimentalVsCodeSessionOpeningChange: (enabled: boolean) => void;

  // Terminal state
  defaultTerminal: DefaultTerminal;
  customTerminalCommand: string;
  handleTerminalChange: (terminal: DefaultTerminal) => void;
  handleCustomTerminalCommandChange: (command: string) => void;
};

export function useEditorTerminalSettings(): UseEditorTerminalSettingsReturn {
  const [defaultEditor, setDefaultEditorState] = useState<DefaultEditor>('zed');
  const [customEditorCommand, setCustomEditorCommandState] = useState('');
  const [experimentalVsCodeSessionOpening, setExperimentalVsCodeSessionOpeningState] = useState(false);
  const [defaultTerminal, setDefaultTerminalState] = useState<DefaultTerminal>('terminal');
  const [customTerminalCommand, setCustomTerminalCommandState] = useState('');

  // Load saved settings on mount
  useEffect(() => {
    setDefaultEditorState(getDefaultEditor());
    setCustomEditorCommandState(getCustomEditorCommand());
    setExperimentalVsCodeSessionOpeningState(getExperimentalVsCodeSessionOpening());
    setDefaultTerminalState(getDefaultTerminal());
    setCustomTerminalCommandState(getCustomTerminalCommand());
  }, []);

  const handleEditorChange = (editor: DefaultEditor) => {
    setDefaultEditorState(editor);
    setDefaultEditor(editor);
  };

  const handleCustomEditorCommandChange = (command: string) => {
    setCustomEditorCommandState(command);
    setCustomEditorCommand(command);
  };

  const handleExperimentalVsCodeSessionOpeningChange = (enabled: boolean) => {
    setExperimentalVsCodeSessionOpeningState(enabled);
    setExperimentalVsCodeSessionOpening(enabled);
    invoke('set_mini_viewer_experimental_vscode_session_opening', { enabled }).catch(
      console.error
    );
  };

  const handleTerminalChange = (terminal: DefaultTerminal) => {
    setDefaultTerminalState(terminal);
    setDefaultTerminalSetting(terminal);
  };

  const handleCustomTerminalCommandChange = (command: string) => {
    setCustomTerminalCommandState(command);
    setCustomTerminalCommand(command);
  };

  return {
    defaultEditor,
    customEditorCommand,
    handleEditorChange,
    handleCustomEditorCommandChange,
    experimentalVsCodeSessionOpening,
    handleExperimentalVsCodeSessionOpeningChange,
    defaultTerminal,
    customTerminalCommand,
    handleTerminalChange,
    handleCustomTerminalCommandChange,
  };
}
