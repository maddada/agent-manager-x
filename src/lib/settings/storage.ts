// Settings storage functions - localStorage getters/setters

import {
  type DefaultEditor,
  type DefaultTerminal,
  type CardClickAction,
  type DisplayMode,
  type MiniViewerSide,
  type ThemeName,
  STORAGE_KEY,
  MINI_VIEWER_HOTKEY_STORAGE_KEY,
  MINI_VIEWER_SIDE_STORAGE_KEY,
  MINI_VIEWER_SHOW_ON_START_STORAGE_KEY,
  EDITOR_STORAGE_KEY,
  CUSTOM_EDITOR_COMMAND_KEY,
  TERMINAL_STORAGE_KEY,
  CUSTOM_TERMINAL_COMMAND_KEY,
  CLICK_ACTION_STORAGE_KEY,
  DISPLAY_MODE_STORAGE_KEY,
  EXPERIMENTAL_VS_CODE_SESSION_OPENING_STORAGE_KEY,
  THEME_STORAGE_KEY,
  BACKGROUND_IMAGE_STORAGE_KEY,
  OVERLAY_OPACITY_STORAGE_KEY,
  OVERLAY_COLOR_STORAGE_KEY,
  DEFAULT_HOTKEY,
  DEFAULT_MINI_VIEWER_HOTKEY,
  DEFAULT_MINI_VIEWER_SIDE,
  DEFAULT_MINI_VIEWER_SHOW_ON_START,
  DEFAULT_EDITOR,
  DEFAULT_DISPLAY_MODE,
  DEFAULT_EXPERIMENTAL_VS_CODE_SESSION_OPENING,
  DEFAULT_OVERLAY_OPACITY,
  DEFAULT_OVERLAY_COLOR,
  DEFAULT_BACKGROUND_IMAGE,
  DEFAULT_THEME,
  EDITOR_OPTIONS,
  TERMINAL_OPTIONS,
  THEME_OPTIONS,
} from './types';
import { applyTheme, applyBackgroundImage, applyOverlay } from './theme';

// Hotkey storage
export function getHotkey(): string {
  return localStorage.getItem(STORAGE_KEY) || DEFAULT_HOTKEY;
}

export function setHotkey(hotkey: string) {
  localStorage.setItem(STORAGE_KEY, hotkey);
}

export function getMiniViewerHotkey(): string {
  return localStorage.getItem(MINI_VIEWER_HOTKEY_STORAGE_KEY) || DEFAULT_MINI_VIEWER_HOTKEY;
}

export function setMiniViewerHotkey(hotkey: string) {
  localStorage.setItem(MINI_VIEWER_HOTKEY_STORAGE_KEY, hotkey);
}

export function getMiniViewerSide(): MiniViewerSide {
  const saved = localStorage.getItem(MINI_VIEWER_SIDE_STORAGE_KEY);
  if (saved === 'left' || saved === 'right') {
    return saved;
  }
  return DEFAULT_MINI_VIEWER_SIDE;
}

export function setMiniViewerSide(side: MiniViewerSide) {
  localStorage.setItem(MINI_VIEWER_SIDE_STORAGE_KEY, side);
}

export function getMiniViewerShowOnStart(): boolean {
  const saved = localStorage.getItem(MINI_VIEWER_SHOW_ON_START_STORAGE_KEY);
  if (saved === null) {
    return DEFAULT_MINI_VIEWER_SHOW_ON_START;
  }
  return saved === 'true';
}

export function setMiniViewerShowOnStart(enabled: boolean) {
  localStorage.setItem(MINI_VIEWER_SHOW_ON_START_STORAGE_KEY, String(enabled));
}

// Editor storage
export function getDefaultEditor(): DefaultEditor {
  const saved = localStorage.getItem(EDITOR_STORAGE_KEY);
  if (EDITOR_OPTIONS.some((opt) => opt.value === saved)) {
    return saved as DefaultEditor;
  }
  return DEFAULT_EDITOR;
}

export function setDefaultEditor(editor: DefaultEditor) {
  localStorage.setItem(EDITOR_STORAGE_KEY, editor);
}

export function getCustomEditorCommand(): string {
  return localStorage.getItem(CUSTOM_EDITOR_COMMAND_KEY) || '';
}

export function setCustomEditorCommand(command: string) {
  localStorage.setItem(CUSTOM_EDITOR_COMMAND_KEY, command);
}

// Terminal storage
export function getDefaultTerminal(): DefaultTerminal {
  const saved = localStorage.getItem(TERMINAL_STORAGE_KEY);
  if (TERMINAL_OPTIONS.some((opt) => opt.value === saved)) {
    return saved as DefaultTerminal;
  }
  return 'terminal';
}

export function setDefaultTerminalSetting(terminal: DefaultTerminal) {
  localStorage.setItem(TERMINAL_STORAGE_KEY, terminal);
}

export function getCustomTerminalCommand(): string {
  return localStorage.getItem(CUSTOM_TERMINAL_COMMAND_KEY) || '';
}

export function setCustomTerminalCommand(command: string) {
  localStorage.setItem(CUSTOM_TERMINAL_COMMAND_KEY, command);
}

// Click action storage
export function getCardClickAction(): CardClickAction {
  const saved = localStorage.getItem(CLICK_ACTION_STORAGE_KEY);
  if (saved === 'editor' || saved === 'terminal') {
    return saved;
  }
  return 'editor';
}

export function setCardClickAction(action: CardClickAction) {
  localStorage.setItem(CLICK_ACTION_STORAGE_KEY, action);
}

export function getExperimentalVsCodeSessionOpening(): boolean {
  const saved = localStorage.getItem(EXPERIMENTAL_VS_CODE_SESSION_OPENING_STORAGE_KEY);
  if (saved === null) {
    return DEFAULT_EXPERIMENTAL_VS_CODE_SESSION_OPENING;
  }
  return saved === 'true';
}

export function setExperimentalVsCodeSessionOpening(enabled: boolean) {
  localStorage.setItem(EXPERIMENTAL_VS_CODE_SESSION_OPENING_STORAGE_KEY, String(enabled));
}

// Display mode storage
export function getDisplayMode(): DisplayMode {
  const saved = localStorage.getItem(DISPLAY_MODE_STORAGE_KEY);
  if (saved === 'list' || saved === 'masonry') {
    return saved;
  }
  return DEFAULT_DISPLAY_MODE;
}

export function setDisplayMode(mode: DisplayMode) {
  localStorage.setItem(DISPLAY_MODE_STORAGE_KEY, mode);
}

// Theme storage
export function getTheme(): ThemeName {
  const saved = localStorage.getItem(THEME_STORAGE_KEY);
  if (THEME_OPTIONS.some((opt) => opt.value === saved)) {
    return saved as ThemeName;
  }
  return DEFAULT_THEME;
}

export function setTheme(theme: ThemeName) {
  localStorage.setItem(THEME_STORAGE_KEY, theme);
  applyTheme(theme);
}

// Background image storage
export function getBackgroundImage(): string {
  return localStorage.getItem(BACKGROUND_IMAGE_STORAGE_KEY) ?? DEFAULT_BACKGROUND_IMAGE;
}

export function setBackgroundImage(url: string) {
  localStorage.setItem(BACKGROUND_IMAGE_STORAGE_KEY, url);
  applyBackgroundImage(url);
}

// Overlay storage
export function getOverlayOpacity(): number {
  const saved = localStorage.getItem(OVERLAY_OPACITY_STORAGE_KEY);
  if (saved) {
    const num = parseInt(saved, 10);
    if (!isNaN(num) && num >= 0 && num <= 100) {
      return num;
    }
  }
  return DEFAULT_OVERLAY_OPACITY;
}

export function setOverlayOpacity(opacity: number) {
  localStorage.setItem(OVERLAY_OPACITY_STORAGE_KEY, String(opacity));
  applyOverlay(getOverlayColor(), opacity);
}

export function getOverlayColor(): string {
  return localStorage.getItem(OVERLAY_COLOR_STORAGE_KEY) || DEFAULT_OVERLAY_COLOR;
}

export function setOverlayColor(color: string) {
  localStorage.setItem(OVERLAY_COLOR_STORAGE_KEY, color);
  applyOverlay(color, getOverlayOpacity());
}
