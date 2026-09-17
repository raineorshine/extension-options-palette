#!/bin/sh
# Mutex for the folder Brave loads as an unpacked extension.
#
# Brave stores the absolute path it loaded an unpacked extension from, and that
# path is the main checkout. A worktree can edit its own copy freely, but seeing
# a change in the browser means putting it in that one folder -- and asking the
# user to press the shortcut. Both are single-slot resources, so testing is
# serialized through this lock.
#
# The slot is swapped by detaching the main checkout at the branch's commit.
# That installs a branch exactly -- the files it adds, deletes and renames
# included -- and `git checkout main` puts the folder back. Release restores the
# current `main`, never a snapshot: a snapshot taken at acquire can already be
# behind what shipped while the lock was held, and putting it back would quietly
# un-ship that. Only committed work is installed, and only into a checkout that
# is on `main` and clean, so the user's own uncommitted work in that folder is
# refused rather than overwritten.
#
#   acquire [label] [session]
#                     take the lock and record what to restore; `session` names
#                     the Claude session holding it, so a denied request can say
#                     which chat to go to (falls back to $PALETTE_SESSION)
#   install           detach the main checkout at this worktree's HEAD, saying
#                     so when the swap changes manifest.json and Brave therefore
#                     needs the card's reload button pressed
#   release           put the folder back on `main`, fast-forwarded to
#                     origin/main, and drop the lock
#                     --keep     drop the lock, leave the branch installed
#                     --force    restore even if the folder moved since install
#                     --if-mine  no-op unless this worktree took the lock
#   status            who holds it, since when, whether stale
#   break             force-release a lock left behind by a dead session, and
#                     put back a checkout left detached with no lock at all
set -eu

# $PALETTE_ROOT exists so the whole script can be exercised against a scratch
# repo instead of the folder Brave has actually loaded.
#
# A pipeline reports the exit status of its last command, so a failing
# `git worktree list` would leave ROOT empty and every later `git -C "$ROOT"`
# would silently act on the caller's own worktree instead -- detaching the
# checkout the work is being done in. Hence the emptiness check.
ROOT=${PALETTE_ROOT:-$(git worktree list --porcelain | head -1 | sed 's/^worktree //')}
[ -n "$ROOT" ] || { printf 'could not find the main checkout -- run this from inside the repo, or set PALETTE_ROOT\n' >&2; exit 1; }
LOCK_REL=".claude/extension-test.lock"
LOCK="$ROOT/$LOCK_REL"
STALE_SECONDS=${PALETTE_LOCK_STALE:-1800}
# The one file Brave reads only at load: everything else in the folder is
# re-read from disk when the popup opens.
MANIFEST=manifest.json

SELF=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
NOW=$(date +%s)
# The worktree identifies the lock's owner, but the user's question when a
# request is denied is "which of my chats is that?" -- so record the session
# too. The id is in the environment; the human-readable title is not, so the
# caller passes it.
SESSION_ID=${CLAUDE_CODE_HOST_SESSION_ID:-${CLAUDE_SESSION_ID:-}}

die() { printf '%s\n' "$*" >&2; exit 1; }
# A lock field, or $2 when it was never written. The default is what tells the
# three reads apart: a holder line says so, a restore ref falls back to main,
# and an install that has not happened yet reads as empty.
field() { cat "$LOCK/$1" 2>/dev/null || printf '%s' "${2-(unknown)}"; }
age() {
  held=$(cat "$LOCK/acquired" 2>/dev/null || printf '%s' "$NOW")
  printf '%s' $(( NOW - held ))
}
holder_report() {
  printf 'held by   %s\n' "$(field label)"
  printf 'session   %s\n' "$(field session)"
  if [ -s "$LOCK/session_id" ]; then printf 'session id %s\n' "$(field session_id)"; fi
  printf 'worktree  %s\n' "$(field worktree)"
  printf 'branch    %s\n' "$(field branch)"
  printf 'age       %sm (stale after %sm)\n' "$(( $(age) / 60 ))" "$(( STALE_SECONDS / 60 ))"
}
owned() { [ "$(field worktree)" = "$SELF" ]; }
# STALE_SECONDS=0 means "treat any lock as abandoned" -- the documented override
# for breaking a live lock once the user has confirmed nobody is mid-test.
is_stale() { [ "$(age)" -ge "$STALE_SECONDS" ]; }

# The branch the main checkout has out, or nothing at all when it is detached --
# which is either a branch installed right now or the leftover of a `--keep`.
slot_branch() { git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || :; }
slot_head() { git -C "$ROOT" rev-parse HEAD; }
short() { git -C "$ROOT" rev-parse --short "$1"; }

# Everything the main checkout has pending, except the lock directory itself.
# The lock lives inside that checkout and must never fail install's own
# cleanliness check: its ignore rule is only present on commits that already
# carry it, so an older commit installed in the slot would leave the lock
# showing as untracked.
pending() {
  git -C "$ROOT" status --porcelain --untracked-files=all -- . ":(exclude)$LOCK_REL"
}

# Brave reads manifest.json only when the extension is loaded, so any swap that
# changes it needs the card's reload button pressed -- on the way out as much as
# on the way in. $1 is the commit the folder was on before the swap.
manifest_note() {
  git -C "$ROOT" diff --quiet "$1" HEAD -- "$MANIFEST" 2>/dev/null ||
    printf '%s changed -- press the reload button on the extension'"'"'s card at chrome://extensions\n' "$MANIFEST"
}

# Put the folder back on $1 and advance it to whatever has shipped since. The
# fetch is what makes a commit pushed to origin/main while the lock was held
# present in the folder afterwards; both it and the fast-forward are notes
# rather than failures, since the restore itself has already succeeded and a
# lagging local `main` is the ship's problem, not the lock's.
# Returns non-zero instead of exiting, so `break` can still clear a lock whose
# folder it could not put back.
restore_slot() {
  ref=$1
  if [ -n "$(pending)" ]; then
    printf 'The main checkout has uncommitted changes:\n' >&2
    pending >&2
    printf '\nRestoring would carry them onto %s or fail outright, so this refuses.\n' "$ref" >&2
    printf 'Commit or discard them there, or drop the lock with `%s release --keep`.\n' "$0" >&2
    return 1
  fi
  # A commit made in the slot itself is reachable only from its detached HEAD, so
  # checking the folder back out would leave it unreferenced with nothing said.
  # `git branch --contains` prints the detached HEAD itself as an entry, so it
  # never reads as empty here; for-each-ref lists only real refs.
  if [ -z "$(slot_branch)" ] &&
    [ -z "$(git -C "$ROOT" for-each-ref --contains HEAD --count=1 refs/heads refs/remotes refs/tags 2>/dev/null)" ]; then
    printf 'The main checkout has a commit no branch contains: %s\n' "$(short HEAD)" >&2
    printf 'Restoring would leave it unreachable. Keep it first:\n' >&2
    printf '  git -C %s branch <name> %s\n' "$ROOT" "$(short HEAD)" >&2
    return 1
  fi
  git -C "$ROOT" checkout --quiet "$ref"
  if git -C "$ROOT" remote | grep -qx origin; then
    git -C "$ROOT" fetch --quiet origin 2>/dev/null ||
      printf 'note: could not fetch origin; %s may be behind what has shipped\n' "$ref" >&2
  fi
  if git -C "$ROOT" rev-parse --verify --quiet "refs/remotes/origin/$ref" >/dev/null; then
    git -C "$ROOT" merge --ff-only --quiet "origin/$ref" 2>/dev/null ||
      printf 'note: %s could not fast-forward to origin/%s; the folder is on the local %s\n' "$ref" "$ref" "$ref" >&2
  fi
}

cmd=${1:-status}
case "$cmd" in

  acquire)
    # `mkdir` on the lock itself is the atomic test-and-set, so its parent has
    # to exist first -- a checkout that has never had a .claude/ directory
    # would otherwise fail here and read as a lock held by nobody.
    mkdir -p "$(dirname "$LOCK")"
    if mkdir "$LOCK" 2>/dev/null; then
      # A detached checkout with no lock has no branch to go back to, and
      # recording `HEAD` as the ref to restore would make release a no-op that
      # strands whatever is installed. `break` is what puts that state back.
      restore_ref=$(slot_branch)
      if [ -z "$restore_ref" ]; then
        rm -rf "$LOCK"
        die "the main checkout is detached at $(short HEAD) with no lock held -- run \`$0 break\` to put it back on main first"
      fi
      printf '%s\n' "$SELF" > "$LOCK/worktree"
      printf '%s\n' "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '(detached)')" > "$LOCK/branch"
      printf '%s\n' "${2:-$(basename "$SELF")}" > "$LOCK/label"
      printf '%s\n' "${3:-${PALETTE_SESSION:-(unnamed session)}}" > "$LOCK/session"
      printf '%s\n' "$SESSION_ID" > "$LOCK/session_id"
      printf '%s\n' "$NOW" > "$LOCK/acquired"
      printf '%s\n' "$restore_ref" > "$LOCK/restore"
      printf 'acquired -- the extension folder is yours; `install` puts this branch in it\n'
    elif owned; then
      # Re-acquiring must change nothing: rewriting `acquired` would hide the
      # age of a lock this worktree has been sitting on, and rewriting
      # `restore` would record whatever is installed as the thing to go back to.
      printf 'already held by this worktree (restore ref and acquire time preserved)\n'
    else
      printf 'LOCKED -- the session "%s" is testing.\n' "$(field session)" >&2
      holder_report >&2
      is_stale && printf '\nLock is stale; `break` it after confirming with the user.\n' >&2
      exit 1
    fi
    ;;

  install)
    [ -d "$LOCK" ] || die 'no lock held -- run `acquire` first'
    owned || { printf 'lock held by another session:\n' >&2; holder_report >&2; exit 1; }
    sha=$(git -C "$SELF" rev-parse HEAD)
    restore_ref=$(field restore main)

    # Only two states are installable: the folder on the ref this lock will
    # restore, or already detached at what this same lock installed -- the
    # normal fix-and-retest loop. Anything else is someone else's checkout.
    here=$(slot_head)
    installed=$(field installed '')
    slot=$(slot_branch)
    if [ -n "$slot" ]; then
      [ "$slot" = "$restore_ref" ] ||
        die "the main checkout is on $slot, not $restore_ref -- put it back before installing"
    elif [ "$here" != "$installed" ]; then
      die "the main checkout is detached at $(short "$here") and this lock did not put it there -- run \`$0 break\` first"
    fi
    if [ -n "$(pending)" ]; then
      printf 'The main checkout has uncommitted changes, and installing would checkout over them:\n' >&2
      pending >&2
      printf '\nOnly committed work is installed. Commit or discard those changes first.\n' >&2
      exit 1
    fi

    # Compare manifest.json across the swap before it happens: Brave reads the
    # pages from disk each time they open, but the manifest only on reload.
    git -C "$ROOT" checkout --quiet --detach "$sha"
    printf '%s\n' "$sha" > "$LOCK/installed"
    printf 'installed %s (%s) in %s\n' "$(git -C "$SELF" rev-parse --abbrev-ref HEAD)" "$(short "$sha")" "$ROOT"
    manifest_note "$here"
    ;;

  release)
    mode=${2:-}
    # `ship` releases only a lock this session took. A branch that was never
    # tested holds no lock, and another session's lock is theirs to restore --
    # neither is worth a message, so both exit quietly.
    if [ "$mode" = "--if-mine" ]; then
      { [ -d "$LOCK" ] && owned; } || exit 0
      mode=
    fi
    [ -d "$LOCK" ] || { printf 'no lock held\n'; exit 0; }
    owned || { printf 'lock held by another session; refusing to release:\n' >&2; holder_report >&2; exit 1; }
    restore_ref=$(field restore main)

    if [ "$mode" = "--keep" ]; then
      rm -rf "$LOCK"
      printf 'lock dropped; the branch is left installed in %s\n' "$ROOT"
      printf 'run `%s break` there when you want the folder back on %s\n' "$0" "$restore_ref"
      exit 0
    fi

    # What the folder should be at right now: the commit this lock installed, or
    # the ref it took the lock on if nothing was installed. Anything else means
    # the checkout moved underneath us, and restoring blind would throw away a
    # swap this lock knows nothing about.
    installed=$(field installed '')
    [ -n "$installed" ] || installed=$(git -C "$ROOT" rev-parse "$restore_ref")
    here=$(slot_head)
    if [ "$mode" != "--force" ] && [ "$here" != "$installed" ]; then
      printf 'The main checkout is at %s, not the %s this lock installed.\n' "$(short "$here")" "$(short "$installed")" >&2
      printf 'Restoring would discard whatever put it there.\n\n' >&2
      printf '  leave it where it is:  %s release --keep\n' "$0" >&2
      printf '  restore anyway:        %s release --force\n' "$0" >&2
      exit 1
    fi

    restore_slot "$restore_ref" || exit 1
    manifest_note "$here"
    rm -rf "$LOCK"
    printf 'released -- %s is back on %s at %s\n' "$ROOT" "$restore_ref" "$(short HEAD)"
    ;;

  status)
    if [ ! -d "$LOCK" ]; then
      printf 'unlocked\n'
      # The state `release --keep` leaves behind: a branch still installed with
      # nobody holding the folder. Name it, because nothing else will.
      if [ -z "$(slot_branch)" ]; then
        printf 'but %s is detached at %s with no lock held -- `break` puts it back\n' "$ROOT" "$(short HEAD)"
      fi
      exit 0
    fi
    owned && printf 'LOCKED by this worktree\n' || printf 'LOCKED by another session\n'
    holder_report
    if [ -s "$LOCK/installed" ]; then
      printf 'installed %s\n' "$(short "$(field installed '')")"
    else
      printf 'installed (nothing yet)\n'
    fi
    is_stale && printf 'STALE -- presumed abandoned\n'
    exit 0
    ;;

  break)
    if [ ! -d "$LOCK" ]; then
      [ -z "$(slot_branch)" ] || { printf 'no lock held\n'; exit 0; }
      # No lock, but the folder is still detached -- `release --keep`, or a
      # session that died between install and release. Same restore.
      here=$(slot_head)
      restore_slot main || exit 1
      manifest_note "$here"
      printf 'no lock held; %s put back on main at %s\n' "$ROOT" "$(short HEAD)"
      exit 0
    fi
    if ! is_stale; then
      printf 'Lock is only %sm old and may still be in use:\n' "$(( $(age) / 60 ))" >&2
      holder_report >&2
      printf 'Confirm with the user, then re-run with PALETTE_LOCK_STALE=0.\n' >&2
      exit 1
    fi
    restore_ref=$(field restore main)
    if [ -z "$(slot_branch)" ]; then
      here=$(slot_head)
      if restore_slot "$restore_ref"; then
        manifest_note "$here"
        printf 'restored the abandoned checkout to %s at %s\n' "$restore_ref" "$(short HEAD)"
      else
        # The lock still goes, or an abandoned lock over a folder nobody can
        # clean up would be a dead end for every other session too.
        printf 'note: the folder is left as it is; the lock is cleared anyway\n' >&2
      fi
    fi
    rm -rf "$LOCK"
    printf 'lock broken\n'
    ;;

  *) die "unknown command: $cmd (acquire|install|release|status|break)" ;;
esac
