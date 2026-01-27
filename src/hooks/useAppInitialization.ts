// App initialization hook for theme, background, and overlay settings

import { useEffect } from 'react';
import {
  getTheme,
  getBackgroundImage,
  getOverlayColor,
  getOverlayOpacity,
  applyTheme,
  applyBackgroundImage,
  applyOverlay,
} from '@/lib/settings';

/**
 * Hook to initialize app appearance settings on mount.
 * Applies saved theme, background image, and overlay settings.
 */
export function useAppInitialization(): void {
  useEffect(() => {
    applyTheme(getTheme());
    applyBackgroundImage(getBackgroundImage());
    applyOverlay(getOverlayColor(), getOverlayOpacity());
  }, []);
}
