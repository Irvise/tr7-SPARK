# M5 — GC reachability proof: completion report

**Status: M5 complete.  The M5 gate was green at 2,895 checks; it is now
6,138 after the follow-up core-procedure, eval, sequence/number,
`syntax-rules`, comparison/constructor, values-binding, review-fix,
records/SRFI-1, equal?/flonum-conformance, macro-hygiene, numeric-tower and
C-ABI batches, still with
0 unproved, 0 justified, 0 warnings and 58 suites green, each also run under stress GC
(level 4, 5 s, `-j6`, `--checks-as-errors`).**  Last updated: 2026-11-14.

This document records how the reachability/liveness obligation was closed.  It
replaces the earlier M5 handoff, whose state was gate RED; the experiments
from that session are summarised here and the general lessons now live in
`docs/findings.md`.

---

## 1. Goal and result

The obligation was:

> a cell reachable from the machine's roots is marked, and is therefore never
> swept back onto the free list.

Result: after `Collect` returns successfully the marked set is closed
(`Closed_Car`, `Closed_Cdr`, `Closed_Env`), every root is marked, the worklist
is empty, and only live cells are marked.  `Tr7.Reach.Marked_If_Reached` then
proves by path induction over the fuel-bounded `Reachable` predicate that
every cell reachable from a root is marked, and `Tr7.Reach.Sweep` only frees
cells whose mark epoch is not the current cycle's.  All of this is inside
`tr7/src`, `SPARK_Mode => On`, level 4, with no `Assume`, `Annotate` or
`Suppress`.

Latest commit content: worklist drain, read-only closure verification, direct
`Child_Marked`, `Tr7.Reach`, epoch jump, root list.

| accepted gate | checks |
| --- | --- |
| M3 `dynamic-wind` | 2,692 |
| M4 C ABI | 2,692 |
| **M5** | **2,895** |

---

## 2. Final collector architecture

`Tr7.Machine.Collect_Garbage`:

1. Resolves the CEK state and global environment to a `Root_Array` through
   `Tr7.Heap.Live_Cell` (the one definition of "is this handle live") and
   calls `Collect (H, Roots, Count)`.
2. `Collect` jumps the epoch to `max (Mark_Epoch) + 1`, so this cycle starts
   provably clean inside `Collect` itself.
3. The roots are marked and pushed on a bounded worklist.
4. The worklist drains: each popped cell's `Car`, `Cdr` and (for closures and
   environments) `Env` are marked and pushed.  A cell is pushed at most once,
   because a cell is marked on the way in; `Max_Cells` entries suffice and
   `Max_Cells` rounds are enough to drain.
5. A **read-only verification scan** checks closure: for every marked cell,
   its three children are marked.  If any check fails, `Mark_Failed` is set
   and the sweep is skipped.
6. When marking completed, `Tr7.Reach.Sweep` frees every cell whose
   `Mark_Epoch` is not `Epoch`.

Why the verification scan exists: the closure fact is quantified, and
preserving it *inside* the drain forced the prover to reason about an
array-of-record update (`Mark_Epoch`) under a quantifier for every cell.  That
is the structural reason the original drain VCs timed out (z3 at 300 s, cvc5
`unknown (incomplete)`).  Checking closure in a loop that writes nothing makes
preservation immediate, while a failed check can only cost garbage, never
safety.  The runtime cost is one extra linear pass; measurements are in
`docs/findings.md`.

The reachability mathematics lives in `Tr7.Reach`, not `Tr7.Heap`, because
`Reachable`'s definition axiom is a quantifier-instantiation storm for any
unit that mentions it.  Its postconditions never mention `Reachable` -- it is
exponential to evaluate and only appears in loop invariants, which
`tr7/gnat.adc` compiles away at run time while GNATprove still proves them.

---

## 3. What changed in the proof, compared with the RED WIP

- `Child_Marked` is stated directly on cell fields instead of through
  `Live_Cell`'s postcondition (same logic: not a handle, out of range, free,
  stale generation, or `Mark_Epoch = Epoch`).  This removed the repeated
  `Live_Cell` instantiation from every quantified VC.
- `Mark_Child` resolves `To_Handle (V).Index` itself, so the marked index and
  the predicate's index are the same expression.
- The drain's invariants say nothing about closure; closure is checked after
  the drain by the read-only scan.
- Closure is split into `Closed_Car` / `Closed_Cdr` / `Closed_Env`, one
  top-level conjunct per child, in both the invariants and `Collect`'s
  postcondition (GNATprove slices one VC per top-level conjunct).
- The per-cell `Queued` epoch tag and `On_Stack` predicate were removed.
  Marking pushes a cell exactly once because marking happens on push, so
  `Is_Marked` alone prevents duplicate work.
- `Sweep`'s precondition and `Marked_If_Reached`'s antecedent no longer carry
  "no cell is on the stack"; the worklist is internal to `Collect`.
- The collector copies only `Car`/`Cdr`/`Env` per visit, never the whole
  `Cell` (whose 256-byte text buffer made `memmove` the hot spot).

The earlier scan-based fixed-point algorithm (forward and backward passes
until no mark changes) also proved, but one round per list link made the
stress suite run for minutes.  It was discarded in favour of the worklist.

---

## 4. Residual risks and known limits

- The verification scan is a runtime check, not a proof that the drain is
  complete.  If it ever failed, the cycle would be abandoned and no cell
  freed; the suite, including `--stress-gc`, exercises the success path.
- `Mark_Failed` is a safe failure mode throughout: a full worklist, exhausted
  rounds, or a failed verification scan leaves garbage in place and never
  frees live data.  After 2**64 cycles `Collect_Stopped` latches for the same
  reason.
- The M5 gate does not raise any timeout: every check proves at 5 s.
- Benchmarks are always run with `TR7_CHECKS=off`; never time a checked build.

---

## 5. Verification and test commands

```sh
./scripts/build.sh        # checked build (TR7_CHECKS=on by default)
./scripts/test.sh         # 58 suites, normal + stress; prints ms per suite
./scripts/prove.sh        # full gate, 5 s, -j6
TIMEOUT=20 ./scripts/prove.sh   # only for a recorded hard check
./scripts/bench.sh        # checks off, removes objects afterwards
```

Fast iteration on the collector:

```sh
cd tr7
/home/fernando/bin/gnatprove-x86_64-linux-16.1.0-1/bin/gnatprove \
  -P tr7.gpr --level=4 --timeout=5 -j6 --limit-name=Collect
```

**Stale-object trap:** after changing `gnat.adc` or compiler switches, remove
`tr7/obj`, `tr7i/obj` and `tr7_c/obj`.  Never overlap two GNATprove runs on
the same object directory.

---

## 6. File map

| file | role |
| --- | --- |
| `tr7/gnat.adc` | `Loop_Invariant => Ignore` policy (proof-only invariants) |
| `tr7/tr7.gpr` | passes `-gnatec=…/gnat.adc` in the checked profile |
| `scripts/prove.sh` | gate; `-j6`; `TIMEOUT` override |
| `scripts/test.sh` | focused suites, per-suite timing, stress-GC run |
| `tr7/src/tr7-cells.ads` | cells; `Mark_Epoch` epoch marks |
| `tr7/src/tr7-heap.ads` | `Root_Array`, `Live_Cell`, `Is_Marked`, `Child_Marked`, `Closed_*`/`Closure`, worklist, `Collect` contract |
| `tr7/src/tr7-heap.adb` | epoch jump, root list, worklist drain, verification scan |
| `tr7/src/tr7-reach.ads` / `.adb` | `Reachable`, `From_Roots`, `Marked_If_Reached`, `Sweep` |
| `tr7/src/tr7-machine.adb` | `Collect_Garbage` root list; calls `Collect` then `Reach.Sweep` |
