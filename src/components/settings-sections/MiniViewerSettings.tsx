import { Button } from '@/components/ui/button';
import { HotkeySettings } from './HotkeySettings';
import type { MiniViewerSide } from '@/lib/settings';

export type MiniViewerSettingsProps = {
  hotkey: string;
  setHotkey: (hotkey: string) => void;
  isRecording: boolean;
  setIsRecording: (recording: boolean) => void;
  recordedKeys: string[];
  setRecordedKeys: (keys: string[]) => void;
  onSave: () => void;
  onClear: () => void;
  side: MiniViewerSide;
  onSideChange: (side: MiniViewerSide) => void;
  showOnStart: boolean;
  onShowOnStartChange: (enabled: boolean) => void;
};

export function MiniViewerSettings({
  hotkey,
  setHotkey,
  isRecording,
  setIsRecording,
  recordedKeys,
  setRecordedKeys,
  onSave,
  onClear,
  side,
  onSideChange,
  showOnStart,
  onShowOnStartChange,
}: MiniViewerSettingsProps) {
  return (
    <div className='space-y-3'>
      <HotkeySettings
        title='Mini Viewer Hotkey'
        helperText='Toggle the native floating mini viewer from anywhere'
        emptyText='Click to set mini viewer hotkey'
        hotkey={hotkey}
        setHotkey={setHotkey}
        isRecording={isRecording}
        setIsRecording={setIsRecording}
        recordedKeys={recordedKeys}
        setRecordedKeys={setRecordedKeys}
        onSave={onSave}
        onClear={onClear}
      />

      <div className='space-y-2'>
        <div className='text-sm font-medium text-foreground'>Mini Viewer Side</div>
        <div className='grid grid-cols-2 gap-2'>
          <Button
            variant={side === 'left' ? 'default' : 'outline'}
            size='sm'
            className='h-9'
            onClick={() => onSideChange('left')}
          >
            Left
          </Button>
          <Button
            variant={side === 'right' ? 'default' : 'outline'}
            size='sm'
            className='h-9'
            onClick={() => onSideChange('right')}
          >
            Right
          </Button>
        </div>
      </div>

      <div className='space-y-2'>
        <div className='text-sm font-medium text-foreground'>Show Mini Viewer On Start</div>
        <div className='grid grid-cols-2 gap-2'>
          <Button
            variant={showOnStart ? 'default' : 'outline'}
            size='sm'
            className='h-9'
            onClick={() => onShowOnStartChange(true)}
          >
            Yes
          </Button>
          <Button
            variant={!showOnStart ? 'default' : 'outline'}
            size='sm'
            className='h-9'
            onClick={() => onShowOnStartChange(false)}
          >
            No
          </Button>
        </div>
      </div>
    </div>
  );
}
