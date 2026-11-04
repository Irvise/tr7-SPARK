#!/bin/sh
# Run the focused conformance smoke suites.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

status=0
for suite in smoke primitives errors arity; do
   "$root/tr7i/bin/tr7i" "$root/tests/$suite.scm" > "/tmp/tr7-$suite.out"
   if diff -u "$root/tests/$suite.expected" "/tmp/tr7-$suite.out"; then
      echo "test: $suite ok"
   else
      echo "test: $suite FAILED" >&2
      status=1
   fi
done

exit "$status"
