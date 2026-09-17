---
title: What an edit to an unpacked extension needs before the browser uses it
date: 2026-09-17
category: developer-experience
module: chrome-extension
problem_type: developer_experience
component: development_workflow
severity: medium
applies_when:
  - Editing a content script or service worker in an unpacked extension
  - A change to extension code appears to have no effect in the browser
  - Testing an unpacked extension in a headless browser on a scratch profile
  - Reloading an extension from an API instead of the card's reload button
tags:
  - chrome
  - brave
  - chromium
  - unpacked-extension
  - service-worker
  - content-script
  - developer-mode
  - headless-cdp
---

# What an edit to an unpacked extension needs before the browser uses it

## Context

This extension is pages only — a popup — and `AGENTS.md` recorded just that much: the browser reads
the pages from disk each time they open, and the manifest only on reload. That rule does not
generalize. Measured with a probe MV3 extension (a content script, a service worker, and a page),
each surface answers an edit differently, and one of them survives a browser relaunch.

The same run overturned a dead end this repo had recorded: `chrome.runtime.reload()` from the
extension's own page, said to have left a `--load-extension` copy unloaded and still blocked 8s
later "with developer mode on in that profile". Searching the earlier sessions found the session that
recorded it but never how developer mode had been set (session history). Self-reload works when
developer mode is genuinely on, so that profile was not in developer mode — an easy state to be
wrong about, because the pref that turns it on is not the one you would write (see Guidance).

Measured in headless Brave 1.95 (Chromium 153) on scratch profiles, each file edited from `v1` to
`v2` after the extension was loaded. Chrome was not tried; nothing here is Brave-specific as far as
the run showed.

## Guidance

**An edit reaches each surface at a different moment.**

| Surface                   | Picks up an edit when                                       |
| ------------------------- | ----------------------------------------------------------- |
| Extension page and its JS | the page is opened or refreshed — no reload                 |
| Content script            | the extension is loaded again, **and** the tab is refreshed |
| Service worker            | the extension is loaded again — nothing else                |

- **Refreshing the tab does nothing for a content script.** A page the content script matched kept
  running `v1` however often the tab was refreshed, and a brand-new tab on that page ran `v1` too.
- **The service worker is the stubborn one.** It still answered `v1` after being stopped over CDP,
  after idling out for 30s, after the browser was relaunched on the same profile, and after the
  manifest `version` was bumped. Each of those started a fresh worker — a new instance id — running
  the old script. Only reloading the extension, or a new profile, moved it.
- **Reloading is `chrome.developerPrivate.reload(id)`**, the API behind the reload button on the
  extension's card. It moved all three surfaces to `v2`, the content script only in tabs refreshed
  afterwards, since nothing re-injects into tabs that are already open.
- **A reload of an unpacked copy needs developer mode on.** Reloading turns a `--load-extension` copy
  (`Secure Preferences`, `location` 8) into an unpacked one (`location` 4), and that location is
  disabled when developer mode is off: the copy came back `DISABLED` with
  `unsupportedDeveloperExtension` and its pages showed the blocked-page error. Turning developer mode
  on re-enabled it by itself, with no `chrome.management.setEnabled(id, true)`.
- **`chrome.runtime.reload()` from the extension's own page works**, with developer mode on, twice in
  a row (measured from a tab, not from the popup). With developer mode off it lands in the disabled
  state above, which is what "the reload unloaded it" looks like from outside. Removing the page's own
  tab before the call dropped the reload altogether (measured in the earlier session, not re-tried).
- **Developer mode is a MAC-protected pref.** It lives in the profile's `Secure Preferences` under
  `.extensions.ui.developer_mode`; the same key written into `Preferences` before launch was ignored,
  and `chrome.developerPrivate.getProfileConfiguration()` still read `inDeveloperMode: false`. Set it
  with `chrome.developerPrivate.updateProfileConfiguration({ inDeveloperMode: true })` from a
  `chrome://extensions/` tab, and read it back from `getProfileConfiguration()` rather than assuming.
- **A content script can opt out of the reload** by being a loader: register a stub that imports the
  real module through `chrome.runtime.getURL`, which is served from disk like a page. This is how
  crxjs dev builds avoid reloading for content-script edits.

## Why This Matters

"My change did nothing" has three different answers depending on the surface, and only the page one
matches the note this repo already had. The service worker is the trap: relaunching the browser
feels like a clean slate and is not, so a test can pass or fail against code that was replaced
several edits ago, with nothing in the output to say so. In a scratch-profile test run, deleting the
profile — already the rule for `DevToolsActivePort` — is what actually clears it.

The developer-mode gate matters because its failure is silent in the right way to mislead: the reload
resolves without an error, the extension is disabled rather than reloaded, and its pages answer with
the blocked-page error. Read as a reload that unloaded the extension, it cost this repo a documented
dead end and the self-reload option with it.

## When to Apply

- Before concluding that an extension edit had no effect, or that a test run exercised it
- When a headless test relaunches the browser on a profile it already used
- When reloading an extension from `developerPrivate`, or having it reload itself, in any profile
  whose developer mode has not been read back from `getProfileConfiguration()`
- When adding a content script or service worker to an extension that has only had pages

## Examples

A content-script loader, which picks up edits to `real.js` on the next tab refresh with no reload.
`real.js` has to be listed in `web_accessible_resources` for the page's matches:

```js
// registered in manifest.json content_scripts — never edited again
import(chrome.runtime.getURL('real.js'))
```

Reloading from a `chrome://extensions/` tab in a headless profile, developer mode first:

```js
await chrome.developerPrivate.updateProfileConfiguration({ inDeveloperMode: true })
;(await chrome.developerPrivate.getProfileConfiguration()).inDeveloperMode // must read true
await chrome.developerPrivate.reload('<extension id>')
;(await chrome.developerPrivate.getExtensionInfo('<extension id>')).state // ENABLED, not DISABLED
```

Stopping the worker over CDP, which proves the point rather than fixing it — and which needs the
domain enabled first, or it answers `ServiceWorker domain not enabled` and stops nothing:

```js
await send('ServiceWorker.enable', {}, sessionId)
await send('ServiceWorker.stopAllWorkers', {}, sessionId)
// wake it with a message: new instance id, same old script
```

## Related

- [AGENTS.md](../../../AGENTS.md) — "Loading and reloading" for how the browser loads this folder,
  and "Testing without the user's Brave" for the headless recipe the measurements ran on
