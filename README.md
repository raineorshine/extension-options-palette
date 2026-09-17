# extension-options-palette

A Brave extension that opens any extension's options page from the keyboard.

## What it does

| Shortcut                               | Action                                                                       |
| -------------------------------------- | ---------------------------------------------------------------------------- |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>,</kbd> | Open a popup that searches every enabled extension that has an options page. |

Before anything is typed, the list starts with **Manage Extensions** and **Keyboard Shortcuts**, which open brave://extensions/ and brave://extensions/shortcuts. Type to narrow the list, <kbd>↑</kbd>/<kbd>↓</kbd> to move, <kbd>Enter</kbd> to open the selected extension's options page in a new tab beside the current one, <kbd>Esc</kbd> to close. The shortcut can be changed at brave://extensions/shortcuts.

## Install

1. Open brave://extensions and turn on Developer mode.
2. Click **Load unpacked** and choose this folder.

There is no build step: Brave reads the pages from this folder each time the popup opens. A change to `manifest.json` needs the reload button on the extension's card.
