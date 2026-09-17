# AGENTS.md

Chrome extension in plain HTML, CSS and JS with no build step. Cmd+Shift+, opens a popup that searches
every enabled extension with an options page, and Enter opens the chosen one's options page in a new
tab beside the current one. Before anything is typed, the list starts with Manage Extensions and
Keyboard Shortcuts, which open chrome://extensions/ and chrome://extensions/shortcuts, above an
Extensions heading. The browser loads this folder directly (Load unpacked).

- `manifest.json` — the `management` permission for the extension list, the popup
  (`action.default_popup`), and the shortcut (`commands._execute_action.suggested_key`).
- `pick.html`, `pick.css`, `pick.js` — the popup.
- `gear.svg`, `keyboard.svg` — the icons beside Manage Extensions and Keyboard Shortcuts. `pick.css`
  uses them as masks over the text color, so only their shape counts, not their stroke color.
- `docs/solutions/` — documented solutions to past problems (bugs, best practices, workflow
  patterns), organized by category with YAML frontmatter (`module`, `tags`, `problem_type`).

## Why the shortcut is in the extension

**A Brave-only shortcut that opens an extension's own UI belongs in the extension.** Brave lists the
shortcut and lets it be changed at brave://extensions/shortcuts, and `_execute_action` opens the
extension's popup under the toolbar. This started as a Karabiner rule running
`open -a 'Brave Browser' 'chrome-extension://<id>/pick.html'`, which can only open a tab, adds a shell
spawn, and whose first version never loaded because Karabiner rejected a key in it. Karabiner stays
the answer for a shortcut that must work from other apps: Chrome documents extension commands as
global only on Ctrl+Shift+[0-9] (not tried).

## Loading and reloading

- **The manifest's `key` pins the id** (`mncnjnpmhmdjonlledbijmjdfdenkkbi`); without one, Brave
  derives the id from the load path, and Brave keeps the shortcut assignment under the id. The id is
  the first 32 hex digits of the SHA-256 of the DER public key, each mapped 0-f to a-p. Generate one
  with `openssl genrsa`, then `openssl rsa -pubout -outform DER`, then `openssl base64 -A` for the
  manifest (the `base64` on PATH here is GNU's, which has no `-i`). An unpacked extension never needs
  the private key.
- **Brave reads the pages from disk each time they open, and the manifest only on reload** — the
  reload button on the extension's card. Adding the `commands` entry to an already-loaded copy and
  reloading was enough for Brave to assign the suggested Cmd+Shift+,.
- **Brave stores the absolute path it loaded an unpacked extension from**, so a copy loaded from a
  git worktree breaks when the worktree is removed. Load this folder, not a worktree.
- **Loading and reloading are the user's click, every time.** Computer use grants browsers read-only.
  Claude in Chrome's `navigate` turns `brave://extensions` and `chrome://extensions` into
  `https://brave//extensions`. Neither reaches the Load unpacked folder picker, and
  `open -a 'Brave Browser' 'brave://extensions'` is ignored (nothing in the session log).

## Opening the browser's own pages

- **`chrome.tabs.create` from an extension page opens `brave://` and `chrome://` URLs alike in Brave:**
  both `brave://extensions/shortcuts` and `chrome://extensions/shortcuts` landed on
  `chrome://extensions/shortcuts`. Navigating an existing tab to another extension's page is a
  different matter (Dead ends).
- **Chrome has no `brave://`, so Manage Extensions and Keyboard Shortcuts use `chrome://`.** In Chrome
  for Testing 152, `chrome.tabs.create` with `brave://extensions/shortcuts` resolved without an error
  and left the new tab on `about:blank` with nothing in its history. `chrome://extensions/shortcuts`
  opened the shortcuts view in both browsers, and `chrome://extensions/` the Extensions page.

## Brave's own records

All JSON under `~/Library/Application Support/BraveSoftware/Brave-Browser/Default/`, readable with
`jq` and no permission.

- **Installed extensions: `Secure Preferences`, `.extensions.settings`**, keyed by id — not
  `Preferences`. Unpacked entries (`location` 4) cache no manifest, only an absolute `path`, so name
  and options page come from `<path>/manifest.json`. Store installs (`location` 1) have `path`
  relative to `Extensions/`, `location` 5 is Brave's bundled components, and entries with no `path`
  are not loaded. There is no `state`: a disabled extension has a non-empty `disable_reasons`.
- **Brave's own shortcuts: `Preferences`, `.brave.accelerators`**, as Chromium accelerator strings
  (`Command+Comma`, `Command+Shift+KeyR`). This is how to check a chord is free in Brave; a System
  Events walk of Brave's menu-bar key equivalents ran past 60s without finishing.
- **Extension shortcuts: `Preferences`, `.extensions.commands`**, keyed like
  `mac:Command+Shift+Comma`, each naming the extension id and command. The entry appearing is the
  check that Brave actually assigned a suggested key.
- **`Sessions/Session_*` logs every navigation's URL** in plain text, so `strings` confirms a URL
  opened in the user's Brave without asking for anything. It cannot tell a page that loaded from one
  that was blocked: the blocked page keeps the URL.

## Dead ends

- **Building the list from those files.** A shell prototype worked, but it reverse-engineers a format
  that has already moved (settings to `Secure Preferences`, `state` to `disable_reasons`) and needs
  every unpacked manifest read from disk. With the `management` permission,
  `chrome.management.getAll()` returns `name`, `enabled` and `optionsUrl` directly.
- **Navigating a tab to another extension's page from an extension page.** `chrome.tabs.update` landed
  on "This page has been blocked by Brave" (ERR_BLOCKED_BY_CLIENT), and setting `location.href`
  landed on `chrome-extension://invalid/`. `chrome.tabs.create` loads the page. Presumably Brave counts
  the first two as navigations the extension started, which another extension's pages refuse unless
  it lists them as web accessible.
- **Opening a page from outside Brave.** `open -a 'Brave Browser' 'chrome-extension://<id>/…'` is
  accepted (the session log recorded it), unlike a `brave://` URL. It works; the Karabiner rule built
  on it was replaced by the extension's own shortcut, not abandoned for failing.

## Testing without the user's Brave

A second, headless Brave on a scratch profile runs the real extension and leaves the user's browser
and session alone:

```sh
"/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" --headless=new --user-data-dir="$SCRATCH/profile" --remote-debugging-port=0 --no-first-run --disable-features=DisableLoadExtensionCommandLineSwitch --load-extension="$SCRATCH/target,$SCRATCH/extension"
```

- **Brave 1.95 honored `--load-extension`** with that feature disabled (not tried without it), and the
  manifest `key` gave the pinned id.
- **Let `--remote-debugging-port=0` pick the port, and read it from `DevToolsActivePort`.** Sessions
  in other worktrees run their own headless browsers at the same time, and a fixed port fails two
  ways. The second browser cannot listen on it, and a CDP script connecting to it drives the other
  session's browser: its copy of the extension has the same pinned id, so a test passes or fails
  against the wrong code with no error. Chromium writes the port as the first line of
  `$SCRATCH/profile/DevToolsActivePort` once DevTools is listening; Brave 1.95 and Chrome for
  Testing 152 both did, and CDP from node 24 connected on that port.
- **A reused profile keeps the last run's `DevToolsActivePort`** until the new browser overwrites
  it, so a script waiting for the file reads the old port at once. Delete the profile (or the file)
  before relaunching.
- **Drive it over CDP from node 24, which has a global `WebSocket`.** `Target.createTarget` a
  `chrome-extension://` page, `Target.attachToTarget` with `flatten: true`, then `Runtime.evaluate`
  with `awaitPromise`: extension APIs work there (`chrome.commands.getAll()` showed `⇧⌘,` assigned),
  and `Input.insertText` and `Input.dispatchKeyEvent` drive the page's own key handlers. Send
  `rawKeyDown` alone for a key that closes the page, or the `keyUp` fails with "Session with given id
  not found".
- **Load a second unpacked extension with an options page as the target** of anything that opens
  another extension's page.
- **Chrome for Testing checks Chrome's behavior**, since Chrome is not installed: Puppeteer's cache has
  builds under `~/.cache/puppeteer/chrome/mac_arm-<version>/chrome-mac-arm64/`. 152 took the same
  flags and gave the same pinned id. Both browsers ran with `--use-mock-keychain` as well (not tried
  without it).
- **It does not test the shortcut or the popup.** CDP key events go to the page rather than to Brave's
  accelerators (not tried), and headless has no toolbar for a popup. Test those in the user's Brave
  after a reload, with the `extensions.commands` check above first.
- **Stop it by its profile path**, `pkill -f -- "--user-data-dir=$SCRATCH/profile"`, which cannot match
  the user's Brave.

## Workflow

Work happens on a branch in a worktree. The main checkout is the folder the browser has loaded, so
`main` is what the user is running.

- **Putting a branch in front of the user** goes through the `test` skill, which holds the live-slot
  lock in [scripts/extension-test-lock.sh](scripts/extension-test-lock.sh) while the browser runs
  that branch.
- **Landing a change** goes through the `ship` skill: squash, push to `origin/main`, fast-forward the
  local `main`. No pull request.
- **Shipping is asked for, never inferred.** A change that is finished and tried is *ready* to ship;
  only the user asking starts it.
- The skills live in `.github/skills/`, and `.claude/skills` is a symlink to that directory — a diff
  naming `.github/skills/…` after an edit through `.claude/skills/…` is the same file.

## Session titles

The sidebar shows a status dot and a branch glyph, and neither can be set from here. A **single
leading emoji on the title** is the only lever, and it is spent on what the app cannot know: where
the work stands — so the sidebar answers "which session has my browser" without opening any of them.

| Prefix | Means                                                             |
| ------ | ----------------------------------------------------------------- |
| `⏳ `  | working — brainstorming, planning or building                     |
| `🔓 `  | waiting for the live slot, or releasing it                        |
| `🔒 `  | holding the live slot: the browser is running this branch         |
| `📦 `  | committed and tried, shippable without redoing anything           |
| `🚀 `  | shipping to `main`, or shipped                                    |
| `🚙 `  | parked: the work is sound and waiting on the user                 |
| `🪦 `  | dead end — kept for the findings, not to resume                   |

**Never mention a prefix in the response** — not what it was set to, not that it was already right,
not that it was left alone. It is sidebar state; say nothing about it unless asked.

These are stages, not flags: exactly one at a time, and setting a new one replaces whatever was
there. Every title carries one, and the first goes onto the harness-given title as part of the first
response. Set a prefix when the stage *starts*, not when it succeeds, and correct it if the stage
falls over — a title that only becomes true at the end is blank for the whole stretch the sidebar is
there to describe. `test` and `ship` set `🔓 `, `🔒 ` and `🚀 ` themselves; the rest go on by hand,
and nothing reconciles a title against reality. Handing back is itself a stage: a response that
closes on something for the user to do is a park, and `🚙 ` goes on before that response, since the
idle dot cannot tell "waiting on you" from "given up on".

**Ask which session this is before renaming one.** The session-info tool with `"self"` is the only
answer, and it changes under a fork: a forked session carries the whole transcript, the id it read
earlier in that transcript, and a different id of its own, so a rename that reuses the remembered one
retitles the session it forked _from_ — often the one holding the lock, whose title is the one the
sidebar most needs to be true.

## Working agreements

- **The README and `docs/` say Chrome, not Brave.** Brave is named only where the behavior is
  Brave-specific and does not hold in Chrome — Brave's own JSON records, its blocking of
  extension-initiated navigation, the headless test browser. AGENTS.md keeps naming Brave, since
  it describes the browser this extension is actually loaded and tested in.
- After a solved, verified problem, automatically invoke the `ce-compound` skill with
  `mode:non-interactive` at the completion checkpoint only when the work produced durable project
  reasoning that is not readily recoverable from the final code, tests, types, comments, or existing
  documentation, and losing it would plausibly cause recurrence, material risk, or substantial
  rediscovery. Apply this counterfactual: if the learning document disappeared, would a future
  engineer reading the final implementation still be likely to repeat the mistake or redo
  substantial investigation? If not, do not invoke it. Completion, effort, and diff size alone are
  not enough. Capture at the checkpoint so a qualifying learning can ship in the PR that produced
  it, and only where the repository treats captured learnings as tracked, committed knowledge.
