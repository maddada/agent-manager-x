// Settings dialog component

import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { useSettings, useHotkeyInit } from '@/hooks/useSettings';
import {
  ThemeSelector,
  BackgroundSettings,
  ClickActionSettings,
  EditorSettings,
  TerminalSettings,
  HotkeySettings,
  NotificationSettings,
} from '@/components/settings-sections';

// Re-export types and functions for backward compatibility
export {
  type DefaultEditor,
  type DefaultTerminal,
  type CardClickAction,
  type ThemeName,
  getDefaultEditor,
  setDefaultEditor,
  getCustomEditorCommand,
  setCustomEditorCommand,
  getCardClickAction,
  setCardClickAction,
  getTheme,
  setTheme,
  getBackgroundImage,
  setBackgroundImage,
  applyTheme,
  applyBackgroundImage,
  getOverlayOpacity,
  setOverlayOpacity,
  getOverlayColor,
  setOverlayColor,
  applyOverlay,
  getDefaultTerminal,
  setDefaultTerminalSetting,
  getCustomTerminalCommand,
  setCustomTerminalCommand,
} from '@/lib/settings';

export { useHotkeyInit };

export type SettingsProps = {
  isOpen: boolean;
  onClose: () => void;
};

export function Settings({ isOpen, onClose }: SettingsProps) {
  const settings = useSettings();

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className='sm:max-w-[420px] gap-6'>
        <DialogHeader>
          <DialogTitle>Settings</DialogTitle>
        </DialogHeader>

        <div className='space-y-6'>
          <ThemeSelector theme={settings.theme} onThemeChange={settings.handleThemeChange} />

          <BackgroundSettings
            backgroundImage={settings.backgroundImage}
            onBackgroundImageChange={settings.handleBackgroundImageChange}
            overlayOpacity={settings.overlayOpacity}
            onOverlayOpacityChange={settings.handleOverlayOpacityChange}
            overlayColor={settings.overlayColor}
            onOverlayColorChange={settings.handleOverlayColorChange}
            setOverlayColorState={settings.setOverlayColorState}
          />

          <ClickActionSettings
            clickAction={settings.clickAction}
            onClickActionChange={settings.handleClickActionChange}
          />

          <EditorSettings
            defaultEditor={settings.defaultEditor}
            customEditorCommand={settings.customEditorCommand}
            onEditorChange={settings.handleEditorChange}
            onCustomEditorCommandChange={settings.handleCustomEditorCommandChange}
          />

          <TerminalSettings
            defaultTerminal={settings.defaultTerminal}
            customTerminalCommand={settings.customTerminalCommand}
            onTerminalChange={settings.handleTerminalChange}
            onCustomTerminalCommandChange={settings.handleCustomTerminalCommandChange}
          />

          <HotkeySettings
            hotkey={settings.hotkey}
            setHotkey={settings.setHotkey}
            isRecording={settings.isRecording}
            setIsRecording={settings.setIsRecording}
            recordedKeys={settings.recordedKeys}
            setRecordedKeys={settings.setRecordedKeys}
            onSave={settings.handleSave}
            onClear={settings.handleClear}
          />

          <NotificationSettings
            notificationInstalled={settings.notificationInstalled}
            notificationLoading={settings.notificationLoading}
            bellMode={settings.bellMode}
            bellModeLoading={settings.bellModeLoading}
            onInstall={settings.handleInstallNotifications}
            onUninstall={settings.handleUninstallNotifications}
            onBellModeToggle={settings.handleBellModeToggle}
          />

          {settings.error && (
            <div className='p-3 rounded-lg bg-destructive/10 border border-destructive/20 text-destructive text-sm'>
              {settings.error}
            </div>
          )}

          {settings.saved && (
            <div className='p-3 rounded-lg bg-emerald-400/10 border border-emerald-400/20 text-emerald-400 text-sm'>
              Hotkey saved
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
