---
name: ship
description: "Land this branch on origin/main as one commit and bring the local main the browser reads along with it. Use only when the user asks for the change to be shipped, landed, or pushed — never because a change looks finished."
---

# Ship (land this branch on main)

Solo workflow for this extension. Squash the branch to one commit, push it to `origin/main`, and
fast-forward the local `main` — which is the folder the browser has loaded, so the fast-forward is
what actually puts the change in front of the user. No pull request.

**Shipping is asked for, never inferred.** A change that is finished and tried is a change *ready*
to ship — say so and stop. Only the user asking to ship, land, merge or push it starts this
procedure, or a skill they invoked whose own procedure ends in one.

## Procedure

### 1. Prefix the title, then release the slot

Set `🚀 ` on the session title (AGENTS.md > Session titles), replacing whatever stage it was at, then:

```sh
./scripts/extension-test-lock.sh release --if-mine
```

Do both before the work, not after: the sidebar should say what the session is doing while it does
it, and a slot this session still holds would otherwise block its own fast-forward in step 4.
`--if-mine` is silent when there is no lock, or when the lock is another session's.

### 2. Commit what is not committed

Generate the message from the diff. Imperative, sentence case (`Add …`, `Fix …`, `Open …`, `Replace
…`), matching the history; no `type:` prefix. Extended body lines use real newlines inside the
quoted string, never escaped `\n`.

### 3. Rebase on origin/main

```sh
git fetch origin && git rebase origin/main
```

Resolve conflicts, `git add` the files, `git rebase --continue`. Where both sides only added lines,
keep both.

### 4. Squash and push

```sh
git reset --soft "$(git merge-base HEAD origin/main)" && git commit -m "subject" -m "body"
git push origin HEAD:main
```

One commit per change — `main` is the shipping branch and every commit on it should stand alone.

**If the push is rejected as non-fast-forward**, another session landed first. Go back to step 3,
rebase, re-squash from the new merge base, and push again. `origin/main` only ever advances by
fast-forward, so the loser rebases and retries; nothing is lost and no merge commits appear.

### 5. Fast-forward the local main — this is what the user sees

Only when that checkout is on a branch — the `symbolic-ref` test is the guard, not a formality:

```sh
MAIN=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
git -C "$MAIN" symbolic-ref --quiet HEAD >/dev/null &&
  git -C "$MAIN" merge --ff-only origin/main
```

**A detached checkout means another session has its branch in the slot, and `merge --ff-only` would
fast-forward that detached HEAD without a word** — swapping the files under a branch someone is
mid-test on. Skipping costs nothing: the ship already happened at step 4, only the local ref lags,
and whoever holds the slot brings it forward when they release. A dirty checkout needs no guard here;
git refuses that merge loudly on its own.

Say so in the report when it lags: the user cannot see that the change is on GitHub but not yet in
their browser, and that is the one consequence of this step they would otherwise discover by
wondering why nothing changed.

### 6. Correct the title if it did not land

The push in step 4 is what counts as shipped. If it succeeded, `🚀 ` is already right. If it failed
or the ship was abandoned, put the title back to what is true now — `📦 ` for a branch that is done
and tried. Do not report this step.

### 7. Clean up, when the user says so

Once the branch is on `origin/main`, the worktree and branch can go. Only on their word:

```sh
MAIN=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
BRANCH=$(git branch --show-current)
git -C "$MAIN" worktree remove <this-worktree-path> && git -C "$MAIN" branch -d "$BRANCH"
```

There is no learnings step here. AGENTS.md > Working agreements already runs `ce-compound` at the
completion checkpoint, so a learning worth keeping is captured before the ship, not after it.
