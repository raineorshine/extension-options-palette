#!/bin/sh
# Exercises extension-test-lock.sh against throwaway repositories, because the
# real slot is the folder the browser has loaded and the user is working in it.
# Every case here is one that has already regressed once, so run this after any
# change to the lock.
#
#   scripts/extension-test-lock-check.sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
LOCK_SH="$SCRIPT_DIR/extension-test-lock.sh"
[ -x "$LOCK_SH" ] || { printf 'not executable: %s\n' "$LOCK_SH" >&2; exit 1; }

cases=0
fail() { printf 'FAIL  %s\n     %s\n' "$CASE" "$*" >&2; exit 1; }
pass() { cases=$((cases + 1)); printf 'ok    %s\n' "$CASE"; }

# A bare origin, a "main checkout" that stands in for the folder the browser
# loads, and a worktree on `feature` whose commit changes pick.js. The
# checkout's .gitignore deliberately does not ignore the lock directory: an
# installed commit predating that rule is the normal case, and the lock must not
# trip its own cleanliness check.
setup() {
  S=$(mktemp -d "${TMPDIR:-/tmp}/lock-check.XXXXXX")
  git init -q --bare "$S/origin.git"
  git clone -q "$S/origin.git" "$S/root" 2>/dev/null
  git -C "$S/root" config user.email check@example.com
  git -C "$S/root" config user.name Check
  printf '{"version":"1.0"}\n' > "$S/root/manifest.json"
  printf 'one\n' > "$S/root/pick.js"
  printf '.claude/worktrees/\n' > "$S/root/.gitignore"
  git -C "$S/root" add -A
  git -C "$S/root" commit -q -m base
  git -C "$S/root" branch -M main
  git -C "$S/root" push -q -u origin main
  git -C "$S/root" worktree add -q "$S/wt" -b feature
  printf 'two\n' > "$S/wt/pick.js"
  git -C "$S/wt" commit -q -am 'edit pick.js'
}
teardown() { rm -rf "$S"; }

# Always from inside a worktree: the script derives the lock's owner from the
# calling checkout, so a run from elsewhere would record the wrong worktree.
lock() { ( cd "$S/wt" && PALETTE_ROOT="$S/root" sh "$LOCK_SH" "$@" ); }
# An assignment written in front of a shell function call stays set in the
# calling shell afterwards under sh, so every override here gets a subshell of
# its own -- otherwise PALETTE_LOCK_STALE=0 would silently govern later cases.
stale0() { ( PALETTE_LOCK_STALE=0; export PALETTE_LOCK_STALE; lock "$@" ); }
lock_in() { dir=$1; shift; ( cd "$dir" && PALETTE_ROOT="$S/root" sh "$LOCK_SH" "$@" ); }
slot_branch() { git -C "$S/root" symbolic-ref --quiet --short HEAD || printf 'detached'; }

CASE='syntax'
sh -n "$LOCK_SH" || fail 'sh -n rejected the script'
pass

CASE='install swaps the branch in and ignores its own lock directory'
setup
lock acquire feature 'Chat A' >/dev/null
git -C "$S/root" status --porcelain --untracked-files=all | grep -q 'extension-test.lock' ||
  fail 'the lock is ignored in this fixture, so the case proves nothing'
lock install >/dev/null || fail 'install refused with only its own lock pending'
[ "$(cat "$S/root/pick.js")" = two ] || fail 'the folder does not hold the branch'
[ "$(slot_branch)" = detached ] || fail 'the folder is not detached'
pass
teardown

CASE='release restores main and brings in what shipped during the lock'
setup
lock acquire feature 'Chat A' >/dev/null
lock install >/dev/null
git -C "$S/wt" push -q origin HEAD:main
lock release >/dev/null || fail 'release refused'
[ "$(slot_branch)" = main ] || fail 'the folder is not back on main'
[ "$(cat "$S/root/pick.js")" = two ] || fail 'the folder did not fast-forward to what shipped'
[ -d "$S/root/.claude/extension-test.lock" ] && fail 'the lock survived release'
pass
teardown

CASE='release works when nothing was ever installed'
setup
lock acquire feature 'Chat A' >/dev/null
lock release >/dev/null || fail 'release refused a lock with no install'
[ -d "$S/root/.claude/extension-test.lock" ] && fail 'the lock survived release'
pass
teardown

CASE='installing again while detached at this lock own commit is the retest loop'
setup
lock acquire feature 'Chat A' >/dev/null
lock install >/dev/null
printf 'three\n' > "$S/wt/pick.js"
git -C "$S/wt" commit -q -am 'edit pick.js again'
lock install >/dev/null || fail 'the second install refused'
[ "$(cat "$S/root/pick.js")" = three ] || fail 'the folder did not follow the branch'
pass
teardown

CASE='install refuses over uncommitted work in the folder'
setup
printf 'the user was editing this\n' > "$S/root/pick.js"
lock acquire feature 'Chat A' >/dev/null
out=$(lock install 2>&1) && fail 'install proceeded over uncommitted work'
printf '%s' "$out" | grep -q 'pick.js' || fail "the refusal did not name the file: $out"
grep -q 'the user was editing this' "$S/root/pick.js" || fail 'install touched the uncommitted file'
pass
teardown

CASE='a second worktree is refused and told which session holds it'
setup
lock acquire feature 'Chat A: the holder' >/dev/null
git -C "$S/root" worktree add -q "$S/wt2" -b other
out=$(lock_in "$S/wt2" acquire other 'Chat B' 2>&1) && fail 'the second worktree took the lock'
printf '%s' "$out" | grep -q 'Chat A: the holder' || fail "the refusal did not name the holder: $out"
pass
teardown

CASE='release --if-mine releases this worktree own lock whatever the session id is'
setup
CLAUDE_CODE_HOST_SESSION_ID=first lock acquire feature 'Chat A' >/dev/null
CLAUDE_CODE_HOST_SESSION_ID=second lock release --if-mine >/dev/null
[ -d "$S/root/.claude/extension-test.lock" ] && fail 'a fork of the holding session left the lock held'
pass
teardown

CASE='release --if-mine leaves another worktree lock alone'
setup
lock acquire feature 'Chat A' >/dev/null
git -C "$S/root" worktree add -q "$S/wt2" -b other
lock_in "$S/wt2" release --if-mine >/dev/null
[ -d "$S/root/.claude/extension-test.lock" ] || fail 'another worktree released a lock that was not its own'
pass
teardown

CASE='release says so when the swap changes the manifest'
setup
printf '{"version":"2.0"}\n' > "$S/wt/manifest.json"
git -C "$S/wt" commit -q -am 'bump the manifest'
lock acquire feature 'Chat A' >/dev/null
lock install 2>&1 | grep -q 'reload button' || fail 'install did not ask for a reload'
lock release 2>&1 | grep -q 'reload button' || fail 'release did not ask for a reload'
pass
teardown

CASE='release refuses to orphan a commit made in the folder'
setup
lock acquire feature 'Chat A' >/dev/null
lock install >/dev/null
printf 'edited in the slot\n' > "$S/root/pick.js"
git -C "$S/root" commit -q -am 'a commit made in the folder itself'
out=$(lock release --force 2>&1) && fail 'release discarded a commit no branch contains'
printf '%s' "$out" | grep -q 'no branch contains' || fail "the refusal did not explain itself: $out"
pass
teardown

CASE='break clears an abandoned lock even when it cannot put the folder back'
setup
lock acquire feature 'Chat A' >/dev/null
lock install >/dev/null
printf 'left dirty by a dead session\n' > "$S/root/pick.js"
stale0 break >/dev/null 2>&1 || fail 'break failed on a dirty folder'
[ -d "$S/root/.claude/extension-test.lock" ] && fail 'break left the lock in place'
grep -q 'left dirty by a dead session' "$S/root/pick.js" || fail 'break discarded the uncommitted work'
pass
teardown

CASE='status marks a stale lock and break refuses a live one'
setup
lock acquire feature 'Chat A' >/dev/null
stale0 status | grep -q 'STALE' || fail 'status did not mark it stale'
lock break >/dev/null 2>&1 && fail 'break took a live lock'
stale0 break >/dev/null || fail 'break failed with the override'
[ -d "$S/root/.claude/extension-test.lock" ] && fail 'break left the lock in place'
pass
teardown

CASE='status names a folder left detached with no lock'
setup
lock acquire feature 'Chat A' >/dev/null
lock install >/dev/null
lock release --keep >/dev/null
lock status | grep -q 'detached' || fail 'status did not name the abandoned folder'
lock break >/dev/null || fail 'break did not put the folder back'
[ "$(slot_branch)" = main ] || fail 'the folder is not back on main'
pass
teardown

printf '\n%s cases passed\n' "$cases"
