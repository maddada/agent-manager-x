// Theme application functions

import { type ThemeName, THEME_OPTIONS } from './types';

export function applyTheme(theme: ThemeName) {
  const root = document.documentElement;
  // Remove all theme classes
  THEME_OPTIONS.forEach((opt) => {
    if (opt.value !== 'default') {
      root.classList.remove(`theme-${opt.value}`);
    }
  });
  // Add the new theme class (if not default)
  if (theme !== 'default') {
    root.classList.add(`theme-${theme}`);
  }
}

export function applyBackgroundImage(url: string) {
  if (url) {
    document.body.style.setProperty('--background-image', `url(${url})`);
    document.body.classList.add('has-background-image');
  } else {
    document.body.style.setProperty('--background-image', 'none');
    document.body.classList.remove('has-background-image');
  }
}

export function applyOverlay(color: string, opacity: number) {
  // Convert hex to rgba
  const r = parseInt(color.slice(1, 3), 16);
  const g = parseInt(color.slice(3, 5), 16);
  const b = parseInt(color.slice(5, 7), 16);
  const alpha = opacity / 100;
  const rgbaValue = `rgba(${r}, ${g}, ${b}, ${alpha})`;
  document.documentElement.style.setProperty('--background-overlay', rgbaValue);
}
