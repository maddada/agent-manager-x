// Hotkey settings component

import { useEffect } from 'react';
import { Button } from '@/components/ui/button';

export type HotkeySettingsProps = {
  title?: string;
  helperText?: string;
  emptyText?: string;
  hotkey: string;
  setHotkey: (hotkey: string) => void;
  isRecording: boolean;
  setIsRecording: (recording: boolean) => void;
  recordedKeys: string[];
  setRecordedKeys: (keys: string[]) => void;
  onSave: () => void;
  onClear: () => void;
};

export function HotkeySettings({
  title = 'Global Hotkey',
  helperText = 'Click and press your desired key combination',
  emptyText = 'Click to set hotkey',
  hotkey,
  setHotkey,
  isRecording,
  setIsRecording,
  recordedKeys,
  setRecordedKeys,
  onSave,
  onClear,
}: HotkeySettingsProps) {
  // Handle key recording
  useEffect(() => {
    if (!isRecording) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      e.preventDefault();
      e.stopPropagation();

      const keys: string[] = [];

      if (e.metaKey) keys.push('Command');
      if (e.ctrlKey) keys.push('Control');
      if (e.altKey) keys.push('Option');
      if (e.shiftKey) keys.push('Shift');

      // Add the actual key if it's not a modifier
      const key = e.key;
      if (!['Meta', 'Control', 'Alt', 'Shift'].includes(key)) {
        // Convert key to proper format
        let formattedKey = key;
        if (key === ' ') formattedKey = 'Space';
        else if (key.length === 1) formattedKey = key.toUpperCase();
        else if (key.startsWith('Arrow')) formattedKey = key;
        else if (key.startsWith('F') && key.length <= 3) formattedKey = key; // F1-F12

        keys.push(formattedKey);
      }

      setRecordedKeys(keys);
    };

    const handleKeyUp = (e: KeyboardEvent) => {
      e.preventDefault();

      if (recordedKeys.length > 0 && !['Meta', 'Control', 'Alt', 'Shift'].includes(e.key)) {
        // We have a complete shortcut
        const shortcut = recordedKeys.join('+');
        setHotkey(shortcut);
        setIsRecording(false);
        setRecordedKeys([]);
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
    };
  }, [isRecording, recordedKeys, setHotkey, setIsRecording, setRecordedKeys]);

  return (
    <div className='space-y-3'>
      <div className='text-sm font-medium text-foreground'>{title}</div>
      <div className='flex gap-2'>
        <div
          className={`flex-1 flex items-center justify-center h-11 rounded-lg border cursor-pointer transition-colors ${
            isRecording
              ? 'border-foreground/50 bg-foreground/5'
              : 'border-border bg-muted/50 hover:border-muted-foreground/50'
          }`}
          onClick={() => setIsRecording(true)}
        >
          <span className='text-sm text-foreground'>
            {isRecording
              ? recordedKeys.length > 0
                ? recordedKeys.join(' + ')
                : 'Press keys...'
              : hotkey || emptyText}
          </span>
        </div>
        <Button variant='ghost' size='sm' className='h-11' onClick={onClear}>
          Clear
        </Button>
        <Button size='sm' className='h-11' onClick={onSave}>
          Save
        </Button>
      </div>
      <p className='text-xs text-muted-foreground'>{helperText}</p>
    </div>
  );
}
