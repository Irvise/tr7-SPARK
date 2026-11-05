#!/bin/sh
# Run the focused conformance smoke suites.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

#  Tests are meant to trip contracts, so they run against a checked build even
#  if TR7_CHECKS=off was left in the environment by a benchmark run.
export TR7_CHECKS=on

status=0
for suite in smoke primitives errors arity gc forms malformed cond bad-cond case bad-case strings index vectors vindex bytevectors bvindex brange lists numbers numovf defs defbad apply map qq bad-qq do bad-do flonums ports bad-ports div error bad-error; do
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

exit "$status"
