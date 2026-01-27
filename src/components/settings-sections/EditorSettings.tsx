// Editor settings component

import { Button } from '@/components/ui/button';
import { type DefaultEditor, EDITOR_OPTIONS } from '@/lib/settings';

export type EditorSettingsProps = {
  defaultEditor: DefaultEditor;
  customEditorCommand: string;
  onEditorChange: (editor: DefaultEditor) => void;
  onCustomEditorCommandChange: (command: string) => void;
};

export function EditorSettings({
  defaultEditor,
  customEditorCommand,
  onEditorChange,
  onCustomEditorCommandChange,
}: EditorSettingsProps) {
  return (
    <div className='space-y-3'>
      <div className='text-sm font-medium text-foreground'>Default Editor</div>
      <div className='grid grid-cols-4 gap-2'>
        {EDITOR_OPTIONS.map((opt) => (
          <Button
            key={opt.value}
            variant={defaultEditor === opt.value ? 'default' : 'outline'}
            size='sm'
            className='text-xs px-2'
            onClick={() => onEditorChange(opt.value)}
          >
            {opt.label}
          </Button>
        ))}
      </div>
      {defaultEditor === 'custom' && (
        <input
          type='text'
          value={customEditorCommand}
          onChange={(e) => onCustomEditorCommandChange(e.target.value)}
          placeholder='e.g., vim, emacs, atom'
          className='w-full h-9 px-3 text-sm rounded-md border border-border bg-muted/50 text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring'
        />
      )}
    </div>
  );
}
