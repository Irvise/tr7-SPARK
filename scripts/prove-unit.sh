#!/bin/sh
# Prove a single unit quickly while iterating, e.g.
#   ./scripts/prove-unit.sh tr7-heap.adb
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
gnatprove=${GNATPROVE:-/home/fernando/bin/gnatprove-x86_64-linux-16.1.0-1/bin/gnatprove}
timeout=${TIMEOUT:-5}
unit=${1:?usage: prove-unit.sh UNIT.adb}

cd "$root/tr7"
"$gnatprove" -P tr7.gpr -u "$unit" \
   --level=4 \
   --checks-as-errors=on \
   --timeout="$timeout" \
   -j1
