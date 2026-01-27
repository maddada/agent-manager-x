// Appearance settings hook (theme, background, overlay)

import { useState, useEffect } from 'react';
import {
  type ThemeName,
  type CardClickAction,
  DEFAULT_OVERLAY_OPACITY,
  DEFAULT_OVERLAY_COLOR,
  getTheme,
  setTheme,
  getBackgroundImage,
  setBackgroundImage,
  getOverlayOpacity,
  setOverlayOpacity,
  getOverlayColor,
  setOverlayColor,
  getCardClickAction,
  setCardClickAction,
} from '@/lib/settings';

export type UseAppearanceSettingsReturn = {
  // Theme state
  theme: ThemeName;
  handleThemeChange: (theme: ThemeName) => void;

  // Background state
  backgroundImage: string;
  handleBackgroundImageChange: (url: string) => void;

  // Overlay state
  overlayOpacity: number;
  handleOverlayOpacityChange: (opacity: number) => void;
  overlayColor: string;
  handleOverlayColorChange: (color: string) => void;
  setOverlayColorState: (color: string) => void;

  // Click action state
  clickAction: CardClickAction;
  handleClickActionChange: (action: CardClickAction) => void;
};

export function useAppearanceSettings(): UseAppearanceSettingsReturn {
  const [theme, setThemeState] = useState<ThemeName>('default');
  const [backgroundImage, setBackgroundImageState] = useState('');
  const [overlayOpacity, setOverlayOpacityState] = useState(DEFAULT_OVERLAY_OPACITY);
  const [overlayColor, setOverlayColorState] = useState(DEFAULT_OVERLAY_COLOR);
  const [clickAction, setClickActionState] = useState<CardClickAction>('editor');

  // Load saved settings on mount
  useEffect(() => {
    setThemeState(getTheme());
    setBackgroundImageState(getBackgroundImage());
    setOverlayOpacityState(getOverlayOpacity());
    setOverlayColorState(getOverlayColor());
    setClickActionState(getCardClickAction());
  }, []);

  const handleThemeChange = (newTheme: ThemeName) => {
    setThemeState(newTheme);
    setTheme(newTheme);
  };

  const handleBackgroundImageChange = (url: string) => {
    setBackgroundImageState(url);
    setBackgroundImage(url);
  };

  const handleOverlayOpacityChange = (opacity: number) => {
    setOverlayOpacityState(opacity);
    setOverlayOpacity(opacity);
  };

  const handleOverlayColorChange = (color: string) => {
    setOverlayColorState(color);
    setOverlayColor(color);
  };

  const handleClickActionChange = (action: CardClickAction) => {
    setClickActionState(action);
    setCardClickAction(action);
  };

  return {
    theme,
    handleThemeChange,
    backgroundImage,
    handleBackgroundImageChange,
    overlayOpacity,
    handleOverlayOpacityChange,
    overlayColor,
    handleOverlayColorChange,
    setOverlayColorState,
    clickAction,
    handleClickActionChange,
  };
}
