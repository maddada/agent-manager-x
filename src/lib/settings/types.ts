// Settings types and constants

export type DefaultEditor = 'zed' | 'code' | 'cursor' | 'sublime' | 'neovim' | 'webstorm' | 'idea' | 'custom';
export type DefaultTerminal = 'ghostty' | 'iterm' | 'kitty' | 'terminal' | 'warp' | 'alacritty' | 'hyper' | 'custom';
export type CardClickAction = 'editor' | 'terminal';
export type DisplayMode = 'masonry' | 'list';
export type ThemeName =
  | 'default'
  | 'catppuccin'
  | 'rosepine'
  | 'nord'
  | 'dracula'
  | 'gruvbox'
  | 'tokyonight'
  | 'onedark'
  | 'solarized'
  | 'monokai'
  | 'kanagawa'
  | 'everforest'
  | 'ayu'
  | 'ayu-blue'
  | 'ayu-indigo'
  | 'material'
  | 'synthwave'
  | 'github-dark'
  | 'nightowl'
  | 'github-light'
  | 'solarized-light'
  | 'catppuccin-latte';

export type ThemeOption = {
  value: ThemeName;
  label: string;
  description: string;
  mode: 'dark' | 'light';
};

// Storage keys
export const STORAGE_KEY = 'agent-manager-x-hotkey';
export const EDITOR_STORAGE_KEY = 'agent-manager-x-default-editor';
export const CUSTOM_EDITOR_COMMAND_KEY = 'agent-manager-x-custom-editor-command';
export const TERMINAL_STORAGE_KEY = 'agent-manager-x-default-terminal';
export const CUSTOM_TERMINAL_COMMAND_KEY = 'agent-manager-x-custom-terminal-command';
export const CLICK_ACTION_STORAGE_KEY = 'agent-manager-x-click-action';
export const DISPLAY_MODE_STORAGE_KEY = 'agent-manager-x-display-mode';
export const THEME_STORAGE_KEY = 'agent-manager-x-theme';
export const BACKGROUND_IMAGE_STORAGE_KEY = 'agent-manager-x-background-image';
export const OVERLAY_OPACITY_STORAGE_KEY = 'agent-manager-x-overlay-opacity';
export const OVERLAY_COLOR_STORAGE_KEY = 'agent-manager-x-overlay-color';

// Default values
export const DEFAULT_HOTKEY = 'Command+Control+Shift+Space';
export const DEFAULT_OVERLAY_OPACITY = 88;
export const DEFAULT_OVERLAY_COLOR = '#000000';
export const DEFAULT_BACKGROUND_IMAGE = 'https://images.pexels.com/photos/28428592/pexels-photo-28428592.jpeg';
export const DEFAULT_THEME: ThemeName = 'ayu';
export const DEFAULT_EDITOR: DefaultEditor = 'code';
export const DEFAULT_DISPLAY_MODE: DisplayMode = 'masonry';

// Theme options
export const DARK_THEMES: ThemeOption[] = [
  { value: 'default', label: 'Default', description: 'Minimal monochrome', mode: 'dark' },
  { value: 'catppuccin', label: 'Catppuccin Mocha', description: 'Soothing pastels', mode: 'dark' },
  { value: 'rosepine', label: 'Rosé Pine', description: 'Elegant muted tones', mode: 'dark' },
  { value: 'nord', label: 'Nord', description: 'Arctic bluish', mode: 'dark' },
  { value: 'dracula', label: 'Dracula', description: 'Classic purple', mode: 'dark' },
  { value: 'gruvbox', label: 'Gruvbox', description: 'Retro warm tones', mode: 'dark' },
  { value: 'tokyonight', label: 'Tokyo Night', description: 'Modern night vibes', mode: 'dark' },
  { value: 'onedark', label: 'One Dark', description: 'Atom classic', mode: 'dark' },
  { value: 'solarized', label: 'Solarized Dark', description: 'Contrast optimized', mode: 'dark' },
  { value: 'monokai', label: 'Monokai', description: 'Sublime classic', mode: 'dark' },
  { value: 'kanagawa', label: 'Kanagawa', description: 'Japanese aesthetic', mode: 'dark' },
  { value: 'everforest', label: 'Everforest', description: 'Nature inspired', mode: 'dark' },
  { value: 'ayu', label: 'Ayu Dark', description: 'Modern minimal', mode: 'dark' },
  { value: 'ayu-blue', label: 'Ayu Blue', description: 'Ayu with blue accents', mode: 'dark' },
  { value: 'ayu-indigo', label: 'Ayu Indigo', description: 'Ayu with deep blue', mode: 'dark' },
  { value: 'material', label: 'Material', description: 'Google design', mode: 'dark' },
  { value: 'synthwave', label: "Synthwave '84", description: 'Retro neon', mode: 'dark' },
  { value: 'github-dark', label: 'GitHub Dark', description: 'Dimmed classic', mode: 'dark' },
  { value: 'nightowl', label: 'Night Owl', description: 'Deep blue night', mode: 'dark' },
];

export const LIGHT_THEMES: ThemeOption[] = [
  { value: 'github-light', label: 'GitHub Light', description: 'Clean & minimal', mode: 'light' },
  { value: 'solarized-light', label: 'Solarized Light', description: 'Warm contrast', mode: 'light' },
  { value: 'catppuccin-latte', label: 'Catppuccin Latte', description: 'Soft pastels', mode: 'light' },
];

export const THEME_OPTIONS: ThemeOption[] = [...DARK_THEMES, ...LIGHT_THEMES];

// Editor and terminal options
export const EDITOR_OPTIONS: { value: DefaultEditor; label: string }[] = [
  { value: 'code', label: 'VS Code' },
  { value: 'cursor', label: 'Cursor' },
  { value: 'zed', label: 'Zed' },
  { value: 'sublime', label: 'Sublime' },
  { value: 'neovim', label: 'Neovim' },
  { value: 'webstorm', label: 'WebStorm' },
  { value: 'idea', label: 'IntelliJ' },
  { value: 'custom', label: 'Custom' },
];

export const TERMINAL_OPTIONS: { value: DefaultTerminal; label: string }[] = [
  { value: 'ghostty', label: 'Ghostty' },
  { value: 'iterm', label: 'iTerm2' },
  { value: 'kitty', label: 'Kitty' },
  { value: 'terminal', label: 'Terminal' },
  { value: 'warp', label: 'Warp' },
  { value: 'alacritty', label: 'Alacritty' },
  { value: 'hyper', label: 'Hyper' },
  { value: 'custom', label: 'Custom' },
];
