---
name: test
description: "Put this branch into the browser the user actually uses, under the live-slot lock, and hand back something to try. Use when a change is ready for the user to see — the popup and the shortcut can only be exercised by hand."
---

# Test (put this branch in front of the user)

The user has one browser with this extension loaded, from the main checkout. Only they can open the
popup or press the shortcut — the headless harness in [AGENTS.md](../../../AGENTS.md) reaches
neither. So **editing is parallel and testing is serial**: every session works in its own worktree,
and one at a time owns the folder the browser loads, through the mutex in
[scripts/extension-test-lock.sh](../../../scripts/extension-test-lock.sh).

## Install as soon as it is ready; do not wait to be told

If the slot is free, take it, install, and hand back with the thing to try. A finished change that
sits in a worktree is invisible to the user, and asking permission to show it spends a turn to learn
nothing. Only a slot someone else holds defers the install.

## Procedure

### 1. Look before you take it

```sh
./scripts/extension-test-lock.sh status
```

Run it from the worktree, with an explicit `cd` if the shell has drifted — the script derives the
owner from the calling checkout, so a lock taken from the wrong directory is recorded against the
wrong worktree.

If another session holds it, say which one, set `🚙 ` on the title, and stop. Do not break a live
lock; see **Stale locks**.

### 2. Commit, then acquire

The slot takes committed work only — `install` checks out the branch's `HEAD` in the main checkout,
so anything uncommitted stays invisible. Commit first; `ship` squashes later, so a `Try the new
row height` commit costs nothing.

Set `🔓 ` on the session title before acquiring and `🔒 ` once the lock is held (see AGENTS.md >
Session titles), and pass this session's own title so a denied session can name the chat that has
the browser:

```sh
./scripts/extension-test-lock.sh acquire "<branch>" "<this session's title>"
```

### 3. Install

```sh
./scripts/extension-test-lock.sh install
```

It refuses when the main checkout is dirty or off `main`, which protects work that is not yours. If
it refuses, release the slot rather than sit on it holding nothing.

### 4. Hand back with something to try

Say what to open and what should happen — the exact keys, the row to look at, what it did before.
"Press ⌘⇧, and type `opt`; Manage Extensions should be gone from the filtered list" beats "please
test the popup". If the branch changed `manifest.json`, `install` says so: the card's reload button
is the one click the swap cannot do for them.

Then leave the turn to them, keeping `🔒 `: the lock says the browser is running unshipped code, and
that is still true while they look.

### 5. Iterate without releasing

Fix, commit, `install` again. The lock stays yours between rounds, and a second `acquire` from this
worktree changes nothing.

### 6. Release

```sh
./scripts/extension-test-lock.sh release
```

The folder goes back to `main` and fast-forwards to `origin/main`, so anything that shipped while
you held the slot arrives with it. Then set `📦 ` (tested, not shipped) or hand off to `ship`, which
releases on its own.

`release --keep` drops the lock but leaves the branch installed, for when the user wants to keep
using it. Say that the browser is on unshipped code until someone puts it back.

## Hazards

- **Do not commit from the main checkout while a lock is held** — it has someone else's branch
  checked out, detached. `status` is the answer, not `git log`.
- **A worktree's own copy of the lock directory means nothing.** A new worktree can arrive with a
  copy of `.claude/` from the main checkout. The script only reads the lock under the main checkout.
- **An old branch carries an old copy of this script**, and releases the way its own copy says.
  Rebase the worktree on `main` when the two disagree.

## Stale locks

`status` marks a lock stale after 30 minutes. That is a hint, not a verdict — a user can be away
from a live test for an hour. Ask before breaking one, then:

```sh
PALETTE_LOCK_STALE=0 ./scripts/extension-test-lock.sh break
```

`break` restores the folder first, so recovery is well defined. It is also what puts back a checkout
that `release --keep` left detached.
