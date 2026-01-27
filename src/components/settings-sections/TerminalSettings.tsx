// Terminal settings component

import { Button } from '@/components/ui/button';
import { type DefaultTerminal, TERMINAL_OPTIONS } from '@/lib/settings';

export type TerminalSettingsProps = {
  defaultTerminal: DefaultTerminal;
  customTerminalCommand: string;
  onTerminalChange: (terminal: DefaultTerminal) => void;
  onCustomTerminalCommandChange: (command: string) => void;
};

export function TerminalSettings({
  defaultTerminal,
  customTerminalCommand,
  onTerminalChange,
  onCustomTerminalCommandChange,
}: TerminalSettingsProps) {
  return (
    <div className='space-y-3'>
      <div className='text-sm font-medium text-foreground'>Default Terminal</div>
      <div className='grid grid-cols-4 gap-2'>
        {TERMINAL_OPTIONS.map((opt) => (
          <Button
            key={opt.value}
            variant={defaultTerminal === opt.value ? 'default' : 'outline'}
            size='sm'
            className='text-xs px-2'
            onClick={() => onTerminalChange(opt.value)}
          >
            {opt.label}
          </Button>
        ))}
      </div>
      {defaultTerminal === 'custom' && (
        <input
          type='text'
          value={customTerminalCommand}
          onChange={(e) => onCustomTerminalCommandChange(e.target.value)}
          placeholder='e.g., xterm, konsole, tilix'
          className='w-full h-9 px-3 text-sm rounded-md border border-border bg-muted/50 text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring'
        />
      )}
    </div>
  );
}
