#!/bin/sh
# Run the focused conformance smoke suites.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

#  Tests are meant to trip contracts, so they run against a checked build even
#  if TR7_CHECKS=off was left in the environment by a benchmark run.
export TR7_CHECKS=on

status=0
#  Milliseconds for a start stamp taken with `stamp`.
stamp() { date +%s%N; }
elapsed_ms() { echo $(( ($2 - $1) / 1000000 )); }

suites="smoke primitives core records srfi1 macro bad-macro bad-eval bad-dot bad-cycle bad-map errors arity gc forms malformed cond bad-cond case bad-case strings index vectors vindex bytevectors bvindex brange lists numbers numovf defs defbad apply map qq bad-qq do bad-do flonums ports bad-ports div error bad-error values bad-values callcc callcc-multi wind wind-reentry wind-cross bad-wind"

for suite in $suites; do
   t0=$(stamp)
   if ! timeout 30 "$root/tr7i/bin/tr7i" "$root/tests/$suite.scm" > "/tmp/tr7-$suite.out"; then
      t1=$(stamp)
      echo "test: $suite FAILED (timeout or crash, $(elapsed_ms "$t0" "$t1") ms)" >&2
      status=1
      continue
   fi
   t1=$(stamp)
   if diff -u "$root/tests/$suite.expected" "/tmp/tr7-$suite.out"; then
      echo "test: $suite ok ($(elapsed_ms "$t0" "$t1") ms)"
   else
      echo "test: $suite FAILED ($(elapsed_ms "$t0" "$t1") ms)" >&2
      status=1
   fi
done

#  Every suite again with a collection on a fixed cadence: any unrooted live
#  object shows up here as a stale handle or a wrong answer.  (The gc suite
#  has its own, heavier stress run below.)
for suite in $suites; do
   case "$suite" in
      gc) continue ;;
   esac
   t0=$(stamp)
   if ! timeout 30 "$root/tr7i/bin/tr7i" --stress-gc "$root/tests/$suite.scm" > "/tmp/tr7-$suite-stress.out"; then
      t1=$(stamp)
      echo "test: $suite (stress) FAILED (timeout or crash, $(elapsed_ms "$t0" "$t1") ms)" >&2
      status=1
      continue
   fi
   t1=$(stamp)
   if diff -u "$root/tests/$suite.expected" "/tmp/tr7-$suite-stress.out"; then
      echo "test: $suite (stress) ok ($(elapsed_ms "$t0" "$t1") ms)"
   else
      echo "test: $suite (stress) FAILED ($(elapsed_ms "$t0" "$t1") ms)" >&2
      status=1
   fi
done

#  The allocation-heavy gc suite with a collection on a fixed cadence.  If this takes more than
#  a few seconds, something in the collector or an invariant has regressed.
t0=$(stamp)
if ! timeout 60 "$root/tr7i/bin/tr7i" --stress-gc "$root/tests/gc.scm" > /tmp/tr7-gc-stress.out; then
   t1=$(stamp)
   echo "test: gc (stress) FAILED (timeout or crash, $(elapsed_ms "$t0" "$t1") ms)" >&2
   exit 1
fi
t1=$(stamp)
if diff -u "$root/tests/gc.expected" /tmp/tr7-gc-stress.out; then
   echo "test: gc (stress) ok ($(elapsed_ms "$t0" "$t1") ms)"
else
   echo "test: gc (stress) FAILED ($(elapsed_ms "$t0" "$t1") ms)" >&2
   status=1
fi

#  A source line longer than the old 4 KiB line buffer must not be split.
python3 - <<'PY_LONG'
open("/tmp/tr7-longline.scm", "w").write(";" + "x" * 5000 + "\n(display 1)(newline)\n")
open("/tmp/tr7-crlf.scm", "w").write("(display 2)(newline)\r\n")
PY_LONG
if [ "$("$root/tr7i/bin/tr7i" /tmp/tr7-longline.scm)" = "1" ]    && [ "$("$root/tr7i/bin/tr7i" /tmp/tr7-crlf.scm)" = "2" ]; then
   echo "test: long source line + CRLF ok"
else
   echo "test: long source line + CRLF FAILED" >&2
   status=1
fi

#  C ABI: the generated stubs must match the header exactly.
if python3 "$root/scripts/gen_abi.py" --check; then
   echo "test: abi (stubs current) ok"
else
   echo "test: abi (stubs current) FAILED" >&2
   status=1
fi

#  C ABI: bind the Ada runtime for a foreign main, link a real C program
#  against the libraries, run it, and compare its report.  The linker
#  constructor from gnatbind -a runs adainit before main, which is what
#  makes the secondary stack (and every String the core returns) usable.
if (
   cd "$root/tr7_c"
   alr exec -- sh -c '
      set -eu
      gnatbind -n -a tr7_c -Ilib -I../tr7/lib
      gcc -c b~tr7_c.adb
      install_dir=$(gcc -print-search-dirs | sed -n "s/^install: //p")
      adalib="${install_dir%/}/adalib"
      cc -std=c11 -Wall -Wextra -I include ../tests/abi_demo.c b~tr7_c.o \
         lib/libTr7_C.a ../tr7/lib/libTr7.a -L"$adalib" -lgnat -lm \
         -o /tmp/tr7-abi-demo
   '
) && /tmp/tr7-abi-demo > /tmp/tr7-abi.out 2> /tmp/tr7-abi.err \
   && diff -u "$root/tests/abi.expected" /tmp/tr7-abi.out \
   && python3 "$root/scripts/gen_abi.py" --check-lib "$root/tr7_c/lib/libTr7_C.a"
then
   echo "test: abi (C demo) ok"
else
   echo "test: abi (C demo) FAILED" >&2
   cat /tmp/tr7-abi.err >&2 || true
   status=1
fi

#  C ABI: differential test against upstream C TR7, the independent oracle.
#  The script skips itself (exit 0) when no upstream checkout is available,
#  so the gate stays green without an oracle; with one present, a report
#  mismatch fails the run.
if python3 -c 'import sys' 2>/dev/null && sh "$root/scripts/diff_upstream.sh" > /tmp/tr7-diff.log 2>&1; then
   tail -1 /tmp/tr7-diff.log
else
   echo "test: abi (differential) FAILED" >&2
   cat /tmp/tr7-diff.log >&2
   status=1
fi

exit "$status"
