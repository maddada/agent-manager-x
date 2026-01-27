// Theme selector component

import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { CheckIcon, ChevronDownIcon, SunIcon, MoonIcon } from 'lucide-react';
import { type ThemeName, THEME_OPTIONS, DARK_THEMES, LIGHT_THEMES } from '@/lib/settings';

export type ThemeSelectorProps = {
  theme: ThemeName;
  onThemeChange: (theme: ThemeName) => void;
};

export function ThemeSelector({ theme, onThemeChange }: ThemeSelectorProps) {
  return (
    <div className='space-y-3'>
      <div className='text-sm font-medium text-foreground'>Theme</div>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant='outline' className='w-full justify-between'>
            <span className='flex items-center gap-2'>
              {THEME_OPTIONS.find((t) => t.value === theme)?.mode === 'light' ? (
                <SunIcon className='h-4 w-4' />
              ) : (
                <MoonIcon className='h-4 w-4' />
              )}
              {THEME_OPTIONS.find((t) => t.value === theme)?.label || 'Select theme'}
            </span>
            <ChevronDownIcon className='h-4 w-4 opacity-50' />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent
          className='w-[var(--radix-dropdown-menu-trigger-width)] max-h-80 overflow-y-auto'
          align='start'
        >
          <DropdownMenuLabel className='flex items-center gap-2'>
            <MoonIcon className='h-3.5 w-3.5' />
            Dark Themes
          </DropdownMenuLabel>
          <DropdownMenuGroup>
            {DARK_THEMES.map((opt) => (
              <DropdownMenuItem
                key={opt.value}
                onSelect={(e) => {
                  e.preventDefault();
                  onThemeChange(opt.value);
                }}
                className='flex items-center justify-between cursor-pointer'
              >
                <div className='flex flex-col'>
                  <span>{opt.label}</span>
                  <span className='text-xs text-muted-foreground'>{opt.description}</span>
                </div>
                {theme === opt.value && <CheckIcon className='h-4 w-4' />}
              </DropdownMenuItem>
            ))}
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <DropdownMenuLabel className='flex items-center gap-2'>
            <SunIcon className='h-3.5 w-3.5' />
            Light Themes
          </DropdownMenuLabel>
          <DropdownMenuGroup>
            {LIGHT_THEMES.map((opt) => (
              <DropdownMenuItem
                key={opt.value}
                onSelect={(e) => {
                  e.preventDefault();
                  onThemeChange(opt.value);
                }}
                className='flex items-center justify-between cursor-pointer'
              >
                <div className='flex flex-col'>
                  <span>{opt.label}</span>
                  <span className='text-xs text-muted-foreground'>{opt.description}</span>
                </div>
                {theme === opt.value && <CheckIcon className='h-4 w-4' />}
              </DropdownMenuItem>
            ))}
          </DropdownMenuGroup>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}
