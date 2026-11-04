#!/bin/sh
# Prove the verified core.  The core must be SPARK_Mode => On, level 4, with
# zero unproved checks.  Exit code 0 alone is not trusted: the summary is
# inspected for failures and unproved/justified checks.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
gnatprove=${GNATPROVE:-/home/fernando/bin/gnatprove-x86_64-linux-16.1.0-1/bin/gnatprove}
timeout=${TIMEOUT:-5}

cd "$root/tr7"
rm -rf obj/gnatprove
"$gnatprove" -P tr7.gpr \
   --level=4 \
   --checks-as-errors=on \
   --timeout="$timeout" \
   -j1 2>&1 | tee /tmp/tr7-prove.log

if grep -E "(medium:|high:|unproved|failed)" /tmp/tr7-prove.log >/dev/null; then
   echo "prove: FAILED (see /tmp/tr7-prove.log)" >&2
   exit 1
fi

echo "prove: ok (timeout ${timeout}s)"
