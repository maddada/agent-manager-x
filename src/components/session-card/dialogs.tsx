import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';

export type RenameDialogProps = {
  isOpen: boolean;
  onOpenChange: (open: boolean) => void;
  renameValue: string;
  onRenameValueChange: (value: string) => void;
  onSave: () => void;
  onReset: () => void;
  hasCustomName: boolean;
  originalName: string;
};

export const RenameDialog = ({
  isOpen,
  onOpenChange,
  renameValue,
  onRenameValueChange,
  onSave,
  onReset,
  hasCustomName,
  originalName,
}: RenameDialogProps) => (
  <Dialog open={isOpen} onOpenChange={onOpenChange}>
    <DialogContent onClick={(e) => e.stopPropagation()}>
      <DialogHeader>
        <DialogTitle>Rename Session</DialogTitle>
      </DialogHeader>
      <div className='py-4'>
        <Input
          value={renameValue}
          onChange={(e) => onRenameValueChange(e.target.value)}
          placeholder='Enter custom name'
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              onSave();
            }
          }}
          autoFocus
        />
        <p className='text-xs text-muted-foreground mt-2'>Original: {originalName}</p>
      </div>
      <DialogFooter className='flex gap-2'>
        {hasCustomName && (
          <Button variant='outline' onClick={onReset}>
            Reset to Original
          </Button>
        )}
        <Button variant='outline' onClick={() => onOpenChange(false)}>
          Cancel
        </Button>
        <Button onClick={onSave}>Save</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
);

export type UrlDialogProps = {
  isOpen: boolean;
  onOpenChange: (open: boolean) => void;
  urlValue: string;
  onUrlValueChange: (value: string) => void;
  onSave: () => void;
  onClear: () => void;
  hasCustomUrl: boolean;
};

export const UrlDialog = ({
  isOpen,
  onOpenChange,
  urlValue,
  onUrlValueChange,
  onSave,
  onClear,
  hasCustomUrl,
}: UrlDialogProps) => (
  <Dialog open={isOpen} onOpenChange={onOpenChange}>
    <DialogContent onClick={(e) => e.stopPropagation()}>
      <DialogHeader>
        <DialogTitle>Set Development URL</DialogTitle>
      </DialogHeader>
      <div className='py-4'>
        <Input
          value={urlValue}
          onChange={(e) => onUrlValueChange(e.target.value)}
          placeholder='e.g., localhost:3000'
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              onSave();
            }
          }}
          autoFocus
        />
        <p className='text-xs text-muted-foreground mt-2'>Quick access URL for this project (e.g., dev server)</p>
      </div>
      <DialogFooter className='flex gap-2'>
        {hasCustomUrl && (
          <Button variant='outline' onClick={onClear}>
            Clear URL
          </Button>
        )}
        <Button variant='outline' onClick={() => onOpenChange(false)}>
          Cancel
        </Button>
        <Button onClick={onSave}>Save</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
);
