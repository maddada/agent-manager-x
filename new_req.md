  - Right-clicking a session card or icon in the mini viewer should open the main Agent Manager X window. ✅
  - The mini viewer should only show sessions that were active in the last 10 minutes. ✅
  - That “recent sessions only” behavior should be controlled by a setting and default to enabled. ✅
  - All mini viewer tooltip/popover behavior should be removed. ✅
  - The mini viewer should have a configurable hover delay before expanding, defaulting to 1000 ms.
  - Instead, expansion should only happen after hovering a session icon for the configured timeout.
  - Only the icon’s original hotspot should keep the mini viewer expanded; hovering the card body itself should let it fade out.
  - The collapsed hover/click area should match the icon exactly, not a larger invisible box.
  - Hovering an icon should immediately increase the icon opacity so it feels highlighted.
  - Unhovered icons should stay visually fixed in place and not shift when another card expands.
  - The card show/hide animation should match the original pre-change animation exactly, with the text fading in together with the card instead of
    appearing later.
  - On the right side of the screen, the expanded mini viewer should behave like the left side implementation, but with the icons staying anchored on
    the right where they are in the collapsed state.

  Summary: Listed the user-facing mini viewer requirements we implemented or explicitly changed during this chat, including features that were later
  reverted.