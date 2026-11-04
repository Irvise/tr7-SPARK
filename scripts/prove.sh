#!/bin/sh
# Prove the verified core.  The core must be SPARK_Mode => On, level 4, with
# zero unproved checks.  The exit code of gnatprove alone is not trusted: the
# log is scanned as well, and either one failing is a failed run.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
gnatprove=${GNATPROVE:-/home/fernando/bin/gnatprove-x86_64-linux-16.1.0-1/bin/gnatprove}
timeout=${TIMEOUT:-5}
log=/tmp/tr7-prove.log

#  -gnatp (TR7_CHECKS=off) makes GNATprove skip the corresponding obligations,
#  so a proof run must always be in the checked configuration.
export TR7_CHECKS=on

cd "$root/tr7"
rm -rf obj/gnatprove

status=0
"$gnatprove" -P tr7.gpr \
   --level=4 \
   --checks-as-errors=on \
   --timeout="$timeout" \
   -j4 > "$log" 2>&1 || status=$?
cat "$log"

if [ "$status" -ne 0 ]; then
   echo "prove: FAILED (gnatprove exit $status, see $log)" >&2
   exit 1
fi

if grep -E "(medium:|high:|unproved|failed)" "$log" >/dev/null; then
   echo "prove: FAILED (see $log)" >&2
   exit 1
fi

echo "prove: ok (timeout ${timeout}s)"
