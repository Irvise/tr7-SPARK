#!/bin/sh
# Run the focused conformance smoke suites.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

#  Tests are meant to trip contracts, so they run against a checked build even
#  if TR7_CHECKS=off was left in the environment by a benchmark run.
export TR7_CHECKS=on

status=0
for suite in smoke primitives errors arity gc forms malformed cond bad-cond case bad-case strings index vectors vindex bytevectors bvindex brange lists numbers numovf defs defbad apply map qq bad-qq do bad-do flonums ports bad-ports div error bad-error values bad-values callcc bad-callcc wind bad-wind; do
   "$root/tr7i/bin/tr7i" "$root/tests/$suite.scm" > "/tmp/tr7-$suite.out"
   if diff -u "$root/tests/$suite.expected" "/tmp/tr7-$suite.out"; then
      echo "test: $suite ok"
   else
      echo "test: $suite FAILED" >&2
      status=1
   fi
done

#  Same suite with a collection at every safe point: any unrooted live object
#  shows up here as a stale handle or a wrong answer.
"$root/tr7i/bin/tr7i" --stress-gc "$root/tests/gc.scm" > /tmp/tr7-gc-stress.out
if diff -u "$root/tests/gc.expected" /tmp/tr7-gc-stress.out; then
   echo "test: gc (stress) ok"
else
   echo "test: gc (stress) FAILED" >&2
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

exit "$status"
