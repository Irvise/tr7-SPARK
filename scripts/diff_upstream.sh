#!/bin/sh
# Differential test against upstream C TR7, the project's independent
# oracle.  Compiles tests/abi_differential.c twice -- once against a
# library built from the upstream checkout's tr7.c, once against this
# library -- and diffs the two reports.  Values are compared through each
# library's own accessors, so no bit-level compatibility is required.
#
#   scripts/diff_upstream.sh [path-to-upstream-checkout]
#
# The oracle is located by the argument, $TR7_UPSTREAM, or the default
# checkout.  When no oracle is present the script reports "skipped" and
# exits 0: it is not a required gate without one.  When an oracle is
# present a report mismatch fails the run.  The upstream checkout itself
# is never modified; the library is compiled into a scratch directory.
#
# Known divergences are excluded from the program, not normalized here:
# see the comment header of tests/abi_differential.c and
# docs/architecture.md ("Differential status").
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
up=${1:-${TR7_UPSTREAM:-/home/fernando/Build/tr7}}

if [ ! -f "$up/tr7.c" ] || [ ! -f "$up/tr7.h" ]; then
   echo "diff: skipped (no upstream TR7 at $up; set TR7_UPSTREAM or pass a path)"
   exit 0
fi

work=$(mktemp -d /tmp/opencode/tr7diff.XXXXXX)
trap 'rm -rf "$work"' EXIT

#  The upstream side: a native library from source, never touching the
#  checkout, plus the path to its Scheme libraries for the environment
#  preamble of the differential program.
cc -c -o "$work/libtr7.o" -std=c11 -D_POSIX_C_SOURCE=200809L \
   -I"$up" "$up/tr7.c" 2> "$work/cc-up.log" || {
   echo "diff: FAILED (upstream tr7.c did not compile)"; cat "$work/cc-up.log"; exit 1; }
cc -std=c11 -I"$up" -DTR7_UPSTREAM_LIBS="\"$up/tr7libs\"" \
   "$root/tests/abi_differential.c" "$work/libtr7.o" -lm \
   -o "$work/diff-up" 2> "$work/cc-up2.log" || {
   echo "diff: FAILED (upstream side did not compile)"; cat "$work/cc-up2.log"; exit 1; }

#  Our side: same program, same recipe as the abi demo (the linker
#  constructor from gnatbind -a runs adainit before main).
if [ ! -f "$root/tr7_c/lib/libTr7_C.a" ] || [ ! -f "$root/tr7/lib/libTr7.a" ]; then
   "$root/scripts/build.sh" > /dev/null
fi
(cd "$root/tr7_c" && alr exec -- sh -c '
   set -eu
   gnatbind -n -a tr7_c -Ilib -I../tr7/lib
   gcc -c b~tr7_c.adb
   install_dir=$(gcc -print-search-dirs | sed -n "s/^install: //p")
   adalib="${install_dir%/}/adalib"
   echo "$adalib" > /tmp/opencode/tr7-diff-adalib
') || { echo "diff: FAILED (bind failed)"; exit 1; }
adalib=$(cat /tmp/opencode/tr7-diff-adalib)
cc -std=c11 -I"$root/tr7_c/include" "$root/tests/abi_differential.c" \
   "$root/tr7_c/b~tr7_c.o" "$root/tr7_c/lib/libTr7_C.a" \
   "$root/tr7/lib/libTr7.a" -L"$adalib" -lgnat -lm \
   -o "$work/diff-ada" 2> "$work/cc-ada.log" || {
   echo "diff: FAILED (this library's side did not compile)"; cat "$work/cc-ada.log"; exit 1; }

#  Upstream prints trapped errors on stderr, this library on stdout; the
#  diff compares stdout with error lines filtered from both.
"$work/diff-up" > "$work/up.out" 2>/dev/null || true
"$work/diff-ada" > "$work/ada.out" 2>/dev/null || true
grep -v '^error:' "$work/up.out" > "$work/up.norm"
grep -v '^error:' "$work/ada.out" > "$work/ada.norm"

if diff -u "$work/up.norm" "$work/ada.norm"; then
   n=$(grep -c ': ' "$work/ada.norm" || true)
   echo "diff: ok ($n cases agree with upstream)"
else
   echo "diff: FAILED (reports differ; see the diff above)" >&2
   exit 1
fi
