// Background and overlay settings component

import { HexColorPicker } from 'react-colorful';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { getOverlayColor } from '@/lib/settings';

export type BackgroundSettingsProps = {
  backgroundImage: string;
  onBackgroundImageChange: (url: string) => void;
  overlayOpacity: number;
  onOverlayOpacityChange: (opacity: number) => void;
  overlayColor: string;
  onOverlayColorChange: (color: string) => void;
  setOverlayColorState: (color: string) => void;
};

export function BackgroundSettings({
  backgroundImage,
  onBackgroundImageChange,
  overlayOpacity,
  onOverlayOpacityChange,
  overlayColor,
  onOverlayColorChange,
  setOverlayColorState,
}: BackgroundSettingsProps) {
  return (
    <>
      {/* Background Image */}
      <div className='space-y-3'>
        <div className='text-sm font-medium text-foreground'>Background Image</div>
        <input
          type='text'
          value={backgroundImage}
          onChange={(e) => onBackgroundImageChange(e.target.value)}
          placeholder='https://example.com/image.jpg'
          className='w-full h-9 px-3 text-sm rounded-md border border-border bg-muted/50 text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring'
        />
        <p className='text-xs text-muted-foreground'>
          Browse images on{' '}
          <a
            href='https://www.pexels.com/search/dark%20abstract/'
            target='_blank'
            rel='noopener noreferrer'
            className='text-primary hover:underline'
          >
            Pexels
          </a>
        </p>
      </div>

      {/* Overlay Settings - only show when background image is set */}
      {backgroundImage && (
        <div className='space-y-3'>
          <div className='flex justify-between items-center'>
            <div className='text-sm font-medium text-foreground'>Overlay</div>
            <span className='text-xs text-muted-foreground'>{overlayOpacity}%</span>
          </div>
          <div className='flex items-center gap-3'>
            <Popover>
              <PopoverTrigger asChild>
                <button
                  className='w-9 h-9 rounded-md border border-border shrink-0 cursor-pointer hover:ring-2 hover:ring-ring'
                  style={{ backgroundColor: overlayColor }}
                  title='Pick overlay color'
                />
              </PopoverTrigger>
              <PopoverContent className='w-auto p-3 space-y-3' align='start'>
                <HexColorPicker color={overlayColor} onChange={onOverlayColorChange} />
                <input
                  type='text'
                  value={overlayColor}
                  onChange={(e) => {
                    const val = e.target.value;
                    if (/^#[0-9A-Fa-f]{6}$/.test(val)) {
                      onOverlayColorChange(val);
                    } else {
                      setOverlayColorState(val);
                    }
                  }}
                  onBlur={() => {
                    if (!/^#[0-9A-Fa-f]{6}$/.test(overlayColor)) {
                      setOverlayColorState(getOverlayColor());
                    }
                  }}
                  className='w-full h-8 px-2 text-sm rounded-md border border-border bg-muted/50 text-foreground font-mono text-center'
                  placeholder='#000000'
                />
              </PopoverContent>
            </Popover>
            <input
              type='range'
              min='0'
              max='100'
              value={overlayOpacity}
              onChange={(e) => onOverlayOpacityChange(parseInt(e.target.value, 10))}
              className='flex-1 h-2 bg-muted rounded-lg appearance-none cursor-pointer accent-primary'
            />
          </div>
        </div>
      )}
    </>
  );
}
