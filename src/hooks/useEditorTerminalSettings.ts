// Editor and terminal settings hook

import { useState, useEffect } from 'react';
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
} from '@/lib/settings';

export type UseEditorTerminalSettingsReturn = {
  // Editor state
  defaultEditor: DefaultEditor;
  customEditorCommand: string;
  handleEditorChange: (editor: DefaultEditor) => void;
  handleCustomEditorCommandChange: (command: string) => void;

  // Terminal state
  defaultTerminal: DefaultTerminal;
  customTerminalCommand: string;
  handleTerminalChange: (terminal: DefaultTerminal) => void;
  handleCustomTerminalCommandChange: (command: string) => void;
};

export function useEditorTerminalSettings(): UseEditorTerminalSettingsReturn {
  const [defaultEditor, setDefaultEditorState] = useState<DefaultEditor>('zed');
  const [customEditorCommand, setCustomEditorCommandState] = useState('');
  const [defaultTerminal, setDefaultTerminalState] = useState<DefaultTerminal>('terminal');
  const [customTerminalCommand, setCustomTerminalCommandState] = useState('');

  // Load saved settings on mount
  useEffect(() => {
    setDefaultEditorState(getDefaultEditor());
    setCustomEditorCommandState(getCustomEditorCommand());
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
    defaultTerminal,
    customTerminalCommand,
    handleTerminalChange,
    handleCustomTerminalCommandChange,
  };
}
