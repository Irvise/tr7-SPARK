#!/bin/sh
# Benchmarks.  Runtime checks are switched off for the *whole* project graph,
# so the numbers describe the algorithm rather than contract checking: with
# -gnata GNAT evaluates quantified loop invariants on every iteration, which is
# O(n^2) over the 4,096-cell arena (see docs/findings.md).
#
# The script leaves every object directory behind it removed: benchmarks build
# with TR7_CHECKS=off, tests and proofs must not inherit those objects.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export TR7_CHECKS=off

#  gprbuild only runs inside an Alire workspace, so the bench project is built
#  from the tr7 crate with an absolute path.
cd "$root/tr7"
rm -rf obj lib
alr exec -- gprbuild -P tr7.gpr -j"${JOBS:-4}"
alr exec -- gprbuild -P "$root/bench/bench.gpr" -f -j"${JOBS:-4}"

echo "=== collection cost (612 collections of an idle heap) ==="
"$root/bench/obj/bench_collect"

cd "$root/tr7i"
rm -rf obj bin
alr exec -- gprbuild -P tr7i.gpr -j"${JOBS:-4}"

echo "=== workload: GC suite (tail calls, 3,000-element list, 6,000 tail calls) ==="
time "$root/tr7i/bin/tr7i" "$root/tests/gc.scm"
echo "=== workload: same, collector every 9th safe point ==="
time "$root/tr7i/bin/tr7i" --stress-gc "$root/tests/gc.scm"
echo "=== workload: 500 datums of (display 1)(newline) ==="
awk 'BEGIN { for (i = 0; i < 500; i++) print "(display 1)(newline)" }' > /tmp/tr7-bench.scm
time "$root/tr7i/bin/tr7i" /tmp/tr7-bench.scm > /dev/null

#  Leave the tree in the checked configuration.
cd "$root/tr7"
rm -rf obj lib
cd "$root/tr7i"
rm -rf obj bin
cd "$root/bench"
rm -rf obj
echo "bench: done (objects removed; rebuild with ./scripts/build.sh)"
