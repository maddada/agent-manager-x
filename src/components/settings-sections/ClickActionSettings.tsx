// Click action settings component

import { Button } from '@/components/ui/button';
import { type CardClickAction } from '@/lib/settings';

export type ClickActionSettingsProps = {
  clickAction: CardClickAction;
  onClickActionChange: (action: CardClickAction) => void;
};

export function ClickActionSettings({ clickAction, onClickActionChange }: ClickActionSettingsProps) {
  return (
    <div className='space-y-3'>
      <div className='text-sm font-medium text-foreground'>Left click on card to open with</div>
      <div className='flex gap-2'>
        {(['editor', 'terminal'] as const).map((action) => (
          <Button
            key={action}
            variant={clickAction === action ? 'default' : 'outline'}
            size='sm'
            className='flex-1 capitalize'
            onClick={() => onClickActionChange(action)}
          >
            {action === 'editor' ? 'Editor' : 'Terminal'}
          </Button>
        ))}
      </div>
    </div>
  );
}
