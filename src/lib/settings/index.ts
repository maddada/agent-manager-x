// Settings module barrel export

// Types and constants
export {
  type DefaultEditor,
  type DefaultTerminal,
  type CardClickAction,
  type DisplayMode,
  type ThemeName,
  type ThemeOption,
  STORAGE_KEY,
  EDITOR_STORAGE_KEY,
  CUSTOM_EDITOR_COMMAND_KEY,
  TERMINAL_STORAGE_KEY,
  CUSTOM_TERMINAL_COMMAND_KEY,
  CLICK_ACTION_STORAGE_KEY,
  DISPLAY_MODE_STORAGE_KEY,
  THEME_STORAGE_KEY,
  BACKGROUND_IMAGE_STORAGE_KEY,
  OVERLAY_OPACITY_STORAGE_KEY,
  OVERLAY_COLOR_STORAGE_KEY,
  DEFAULT_HOTKEY,
  DEFAULT_OVERLAY_OPACITY,
  DEFAULT_OVERLAY_COLOR,
  DEFAULT_BACKGROUND_IMAGE,
  DEFAULT_THEME,
  DEFAULT_EDITOR,
  DEFAULT_DISPLAY_MODE,
  DARK_THEMES,
  LIGHT_THEMES,
  THEME_OPTIONS,
  EDITOR_OPTIONS,
  TERMINAL_OPTIONS,
} from './types';

// Storage functions
export {
  getDefaultEditor,
  setDefaultEditor,
  getCustomEditorCommand,
  setCustomEditorCommand,
  getDefaultTerminal,
  setDefaultTerminalSetting,
  getCustomTerminalCommand,
  setCustomTerminalCommand,
  getCardClickAction,
  setCardClickAction,
  getDisplayMode,
  setDisplayMode,
  getTheme,
  setTheme,
  getBackgroundImage,
  setBackgroundImage,
  getOverlayOpacity,
  setOverlayOpacity,
  getOverlayColor,
  setOverlayColor,
} from './storage';

// Theme functions
export { applyTheme, applyBackgroundImage, applyOverlay } from './theme';
