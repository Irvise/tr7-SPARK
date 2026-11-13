# M5 Task — GC reachability proof: state, findings, resume plan

**Status: M5 in progress; gate RED; work parked on branch `m5-wip`.**
Last updated: 2026-11-13.

This document is the handoff for M5.  It records the goal, exactly what is
committed and what is not, the validated proof architecture, the checks that
still fail and why, every experiment that was tried, and the options for the
next session.  Read this first, then `docs/verification.md`,
`docs/architecture.md` and `docs/findings.md`.

---

## 1. M5 goal

> Mark-sweep GC proof, Gold hardening, contracts, benchmarks, report.

The central proof obligation is **reachability/liveness**:

> a cell that is reachable from the machine's roots is marked, and is
> therefore never swept back onto the free list.

In the vocabulary of the code: after `Collect` succeeds,
`marked = reachable-from-roots`, hence the sweep only frees unreachable cells.

Everything must stay inside the project's definition of *verified*:

- `tr7/src` is `SPARK_Mode => On`, GNATprove **level 4**,
  `--checks-as-errors`, zero unproved checks, zero justified checks, zero
  `Assume` / `pragma Annotate` / `Suppress` in `tr7/src`.
- `tr7i` and `tr7_c` remain the documented trusted boundary
  (`SPARK_Mode => Off`).
- Gate: `./scripts/prove.sh` (timeout 5 s, `-j6`, `TR7_CHECKS=on`).  A raised
  timeout is allowed only for a known-hard check, and the reason must be
  recorded.  Runtime performance numbers are never taken with checks on, and
  assertion policies live in build configuration, never in source.

M0–M4 are complete.  The latest committed milestones are:

| commit | content |
| --- | --- |
| `54dd099` | M4: C ABI — six contracted entry points, 177 generated stubs |
| `abe81a1` | M3: `dynamic-wind` — six phases, one unwind frame, innermost afters first |

Accepted gate at `54dd099`: **2,692 checks proved**, 0 unproved, 0 warnings,
44 test runs green.

---

## 2. What is committed vs. what is in the working tree

### Committed (on `master`)

- M0–M4 as above.  `docs/verification.md` currently ends its table at
  `dynamic-wind` = 2,692 checks; no M5 row yet.
- Tooling used by this work: `scripts/build.sh`, `scripts/test.sh`,
  `scripts/prove.sh`, `scripts/gen_abi.py`, `tests/abi_demo.c`.

### Uncommitted WIP, now on branch `m5-wip`

`git diff --stat` at handoff:

```
 scripts/prove.sh        |   2 +-
 tr7/src/tr7-cells.ads   |   5 +
 tr7/src/tr7-heap.adb    | 248 ++++++++++++++++++++++++--------------------
 tr7/src/tr7-heap.ads    | 146 +++++++++++++++++++++++++-----
 tr7/src/tr7-machine.adb |  94 ++++++++++++++++----
 tr7/tr7.gpr             |   9 +-
 6 files changed, 353 insertions(+), 151 deletions(-)
```

plus new files:

- `tr7/gnat.adc` — `pragma Assertion_Policy (Loop_Invariant => Ignore);`
- `tr7/src/tr7-reach.ads` — `Reachable`, `From_Roots`,
  `Marked_If_Reached`, `Sweep`.
- `tr7/src/tr7-reach.adb` — the lemma body and the sweep loop.

WIP commit on that branch: `8437932` ("M5 WIP: epoch jump, root list,
drain/sweep split, reachability lemma (gate RED)").  The branch is explicitly
**gate RED**; do not merge it until the failing checks in section 4 are
discharged.

### Runtime state of the WIP: correct

The restructured collector **passes all 44 test runs** (`./scripts/test.sh`)
and builds cleanly.  The new runtime behaviour is:

- Epoch jump at the start of every collection, so each cycle provably starts
  clean inside `Collect` itself.
- Epoch-tagged `Queued` field on each cell, so `On_Stack` is a field read, not
  an existential over the mark stack.
- Roots are resolved by `Collect_Garbage` into a `Root_Array` and handed to
  `Collect`; `Mark_Root` no longer exists.
- Drain (`Collect`) and sweep (`Tr7.Reach.Sweep`) are separate procedures.

So this is a proof problem, not a behaviour problem.

### Phase A of M5: committed-able and green

`tr7/gnat.adc` + the `-gnatec=` switch in `tr7/tr7.gpr` + `-j6` in
`scripts/prove.sh` were validated against the *unmodified* collector: gate
green at 2,692 checks, 0 warnings, 44 tests.  Under
`Loop_Invariant => Ignore` GNATprove still generates and discharges every
loop-invariant obligation; the run-time cost is zero (invariants and
`Loop_Entry` copies compile away; pre/post/type predicates remain checked
under `-gnata`).  This mechanism is sound and should be merged independently
of the restructure if desired.

---

## 3. Validated proof architecture

This architecture was **proved first in a standalone sandbox** (63 checks,
level 4, 5 s timeout, 3.9 s wall clock) before being ported to `tr7`.  The
sandbox directory has since been lost; the exact same reachability maths,
lemma and sweep live in `tr7/src/tr7-reach.*` on `m5-wip`, where the lemma and
sweep checks **do** prove.  Reconstruct a sandbox from that unit (see
section 8) rather than re-deriving the design.

The design rules that made it work:

1. **Loop invariants are proof-only.**
   `tr7/gnat.adc` (wired with `-gnatec=` and
   `Project'Project_Dir & "gnat.adc"` in the `"on"` profile of
   `tr7/tr7.gpr`) sets `Assertion_Policy (Loop_Invariant => Ignore)`.
   GNATprove still proves them; the binary does not evaluate them.  This is
   what allows reachability predicates in invariants at all: evaluating
   `Reachable` costs more than the collection itself.
   *Note:* assertion kinds are comma-separated and `Loop_Entry` is **not** a
   valid policy kind.

2. **Fuel-bounded recursive predicates with `Subprogram_Variant`.**
   `Reachable (H, From, To, Fuel)` is an expression function with
   `Subprogram_Variant => (Decreases => Fuel)`.  Fuel is `Max_Cells`.

3. **Path induction in a recursive lemma.**
   `Marked_If_Reached` has a postcondition that says: if the worklist is
   empty, the marked set is closed, `From` is marked and `Reachable (From,
   To)`, then `To` is marked.  Its recursive call receives that very contract
   as the induction hypothesis — the only induction the provers ever perform.
   The antecedent also needs `(for all J => not On_Stack (H, J))`.

4. **Unit split.**
   Reachability mathematics is in `Tr7.Reach`, separate from `Tr7.Heap`,
   because `Reachable`'s definition axiom seeds a quantifier-instantiation
   storm in *every* VC of any unit that mentions it (measured at ~1,000,000
   instantiations on goals that never touch reachability).  Units that do not
   do reachability must not `with` it.

5. **Procedure/loop split.**
   The drain (`Collect`) has a cheap postcondition; the reachability goal
   lives in the sweep's loop invariants.  **A postcondition may never contain
   `Reachable`**: it would be evaluated at run time (pre/post are checked under
   `-gnata`) and is exponential.

6. **One invariant atom per top-level conjunct.**
   GNATprove slices a loop invariant into one VC per top-level conjunct; only
   the slice containing a lemma call imports the lemma's postcondition axiom.
   Conjoining several quantified facts into one invariant makes the prover
   chase all of them at once.

7. **`H'Loop_Entry` anchoring.**
   The sweep's reachability invariants speak of the loop-entry heap (the
   post-drain heap), so `Free` is the only thing changing in the statement.
   Re-evaluating `Reachable` on the modified heap would require congruence
   under an array update, which needs an induction no single step can do.

8. **`Failed`-on-incomplete.**
   A `for` loop that runs to completion does not imply its exit condition.
   After the drain loop, `if Mark_Top /= 0 then Mark_Failed := True;` — a
   non-empty stack means the rounds ran out, so the caller skips the sweep.
   The next epoch jump retires whatever was marked.

9. **Epoch jump at collection start.**
   `Epoch := max (Mark_Epoch) + 1`, computed by a `while` loop with an
   explicit index so the post-loop fact is derivable.  This makes "this cycle
   starts clean" provable *inside* `Collect`, with no cross-call reasoning.
   The old end-of-collection epoch advance was removed.  `Collect_Stopped`
   guards the `Unsigned_64` wrap case by refusing to sweep ever again.

10. **`Queued : Unsigned_64` cell field.**
    The epoch at which a cell was pushed (`0` = not queued).  `On_Stack`
    becomes `J /= 0 and then H.Cells (J).Queued = H.Epoch` — a field read
    instead of an existential over the mark stack.  Epoch stamping makes
    abandoned-cycle tags expire at the next jump, so no clearing pass is
    needed.

11. **`Cell_Array` is indexed by `Valid_Cell_Index` (1 .. Max).**
    Cell 0 is the nil marker and has no array slot.  `Is_Marked` must be
    total (`J /= 0 and then …`), and loops that walk the arena start at 1.

12. **Roots as a list.**
    `Machine.Collect_Garbage` resolves every root value via `Live_Cell`
    (fetch logic in one place), appends to `Root_Array`, and calls
    `Collect (H, Roots, Count)`, which marks them after the epoch jump.
    `Mark_Root` was deleted.

13. **`pragma Inline` / nested `Root_Child` over a contract.**
    A contract for `Root_Child` would need an unaffordable array-frame clause
    to keep the other drain invariants provable.  Nested is better: GNATprove
    inlines local subprograms for proof, so the closure invariant sees the
    mark-and-push directly.

14. **Sparklib idiom in `tr7_c`.**
    Package `SPARK_Mode => On`, each subprogram `Off` with an inline
    `trusted: …` why-comment and complete Pre/Post contracts.  Under
    `-gnata` those contracts are runtime-checked and exercised by
    `tests/abi_demo.c`.

---

## 4. The failing checks (gate RED)

Command: `./scripts/prove.sh` (5 s, `-j6`).  All failures are
**"provers reached time limit"**, not refutations.  The remaining checks are
believed **true** (hand-verified); the provers cannot discharge them within
the tested budgets.

| # | location | check |
| --- | --- | --- |
| 1 | `tr7/src/tr7-heap.adb:609` | drain invariant `H.Mark_Failed or else Drained_Car (H)` not preserved |
| 2 | `tr7/src/tr7-heap.adb:610` | same for `Drained_Cdr` |
| 3 | `tr7/src/tr7-heap.adb:611` | same for `Drained_Env` |
| 4 | `tr7/src/tr7-heap.adb:586` / `624` | queue-tag fact `Queued /= 0 → Queued = Mark_Epoch` fails in first iteration (drain and roots loops) |
| 5 | `tr7/src/tr7-heap.ads` (`Collect` post) | `Closure` cascade of 1–3 |

Everything else (≈2,600 checks) passes; 0 warnings.

### Why it is stuck

`Drained_*` says: *a marked cell that is no longer on the worklist has all of
its children marked.*  Preservation has to reason about an array of records
being updated field by field (`Mark_Epoch`, `Queued`) while a quantified
predicate (`Child_Marked`, via `Live_Cell`) is re-evaluated for every cell.
The suspected root cause is **congruence of `Live_Cell` / child predicates
under array-of-record field updates inside a quantified preservation proof**;
the SMT file is ~257 KB with 76–77 top-level assertions and a single
`check-sat`.

Solver data on the hard VC
(`tr7-heap.adb_609_33_loop_invariant_preserv_1.smt2`):

- z3 at 300 s: **timeout**;
- cvc5 at 300 s with `--rlimit=0`: **`unknown (:reason-unknown incomplete)`**
  in under 1 s;
- single-prover runs (altergo, cvc5, z3) each fail this check;
- SMT-level bisection removing any single top-level axiom still times out;
- removing the *other* drain invariants (queue-tag, stack-marked,
  `marked → ¬Free`) does not help.

Conclusion: this is a **prover capability gap, not a budget problem**.  More
time will not fix it; the VC must be made structurally simpler.

(Interrupted while measuring: the hardest VC was being profiled with
`(set-option :smt.qi.profile true)`.  `k!513` dominates instantiations;
identify its source in the SMT file before doing anything else — that is the
first useful datum for the next session.)

---

## 5. Every experiment tried and its outcome

| experiment | outcome |
| --- | --- |
| Policy file + `-gnatec` + `-j6` on the old collector | **green**: 2,692 checks, 0 warnings, 44 tests |
| Standalone reachability sandbox | **green**: 63 checks, level 4, 5 s, 3.9 s |
| Port the sandbox design to `tr7` | runtime correct (44 tests), gate red on drain |
| `Live_Cell` `Pre => H.Ready` | removed; `Live_Cell` is a pure array read. Was causing "precondition might fail" in the math functions |
| `Live_Cell` `Inline => True` | no change to the hard VC |
| `Root_Child` lifted to package level with an O(1) contract | **worse**: broke two previously passing invariants (contract cannot give array-frame facts affordably) |
| `Child_Marked` single-atom child predicate | kept; removed doubled `Live_Cell` terms, but the drain still fails |
| `Drained` split into `Drained_Car/Cdr/Env` (one invariant each) | kept; fewer case splits, still fails |
| `Queued` epoch tag (On_Stack as field read) | kept; removed the existential over the mark stack. Changed the VC but did not make it provable |
| Add `¬On_Stack` conjunct to the lemma antecedent | kept; fixed the lemma's own post (which then proved) |
| Replace the drain `for` with guarded/`while` reasoning | not completed; still an option (see 6.3) |
| Remove queue-tag invariant from drain (bisection 1) | no change: still 3 preservation failures |
| Remove stack-marked + marked-nonfree invariants (bisection 2) | no change: still 3 preservation failures |
| Give `Drained_*` a longer budget: 30 s / 60 s / 120 s | still fails; 120 s produced no proof |
| z3 directly at 300 s on the saved VC | timeout |
| cvc5 with `--rlimit=0` on the saved VC | `unknown`, `incomplete`, < 1 s |
| SMT-level axiom removal (one at a time) | every variant still times out |
| `--prover=altergo` / `cvc5` / `z3` / all three, 60 s | all fail this check (and altergo fails unrelated checks) |
| `-O0 -g` rebuild for gdb | clarified the cell-0 indexing bug; **must revert** (currently reverted to `-O3`) |
| Minimal sandbox reconstruction (this session) | not green: `marked → non-free` preservation and `Roots_Marked` post remained; discarded (see section 8) |

Two bugs found and fixed along the way:

- The epoch-jump loop started at cell 0, but `Cell_Array` starts at
  `Valid_Cell_Index` = 1 → `CONSTRAINT_ERROR` at `tr7-heap.adb:552`.  Fixed by
  starting at 1 and making `Is_Marked` total.
- `Roots` was not fully initialized → "might not be initialized" flow errors.
  Fixed with `Roots : Root_Array := (others => Valid_Cell_Index'First)`.

---

## 6. Options for the next session (in order of preference)

### 6.1 Make the child relation a field read (most promising)

`Child_Marked` goes through `Live_Cell`, which validates index, generation and
kind.  Inside a quantified preservation proof this expands to several
conjuncts per cell per update.  Try making the drain's closure invariant speak
of **cell indices already resolved**, not values:

- Add a per-cell `Rooted : Boolean` (or reuse `Queued`-style epoch tag)
  maintained by the drain: when a cell's children are rooted, set
  `C.Rooted := True` on the popped cell.
- The drain invariant becomes a *scalar* statement about `Rooted` plus a
  bridge: `Rooted (J) → Child_Marked` for the three child fields.
- Prove the bridge once per child, outside the drain loop, where no array
  update is interleaved.

This trades one quantified predicate for a code-maintained flag and a much
smaller bridge obligation.

### 6.2 Definitional post-equation for `Live_Cell`

Give `Live_Cell` a postcondition of the form
`Result = (if <condition> then Hd.Index else 0)` (a definitional equation, not
a conjunction of consequences).  Congruence under array updates would then be
derivable by rewriting instead of by case analysis.  Beware: a postcondition
on every call site may itself be expensive; restrict it to the drain's
hypotheses.

### 6.3 State children through `To_Handle (V).Index` and mark-independent
liveness

Instead of `Live_Cell (H, V)`, split the child fact into:

- `Is_Handle (V)` and `To_Handle (V).Index in Valid_Cell_Index`;
- generation equality, which never mentions `Mark_Epoch` or `Queued`;
- `Kind /= Cell_Free`, which the drain never changes.

Then a field update to `Mark_Epoch`/`Queued` cannot disturb the child
liveness facts; only the `Is_Marked` half changes, and that is a single field
read.

### 6.4 Split the drain into drain + verification loop

Do the actual marking in a first loop with trivial invariants, then run a
second loop that only *checks* the closure property and has no writes except
none at all.  The verification loop's invariant is then preserved vacuously,
and the postcondition is assembled from the check loop's exit fact.  This
mirrors the drain/sweep split that already worked.

### 6.5 Change the worklist structure

If none of the above converges, replace the array-based mark stack with:

- a linked worklist stored in the cells themselves (an intrusive `Next`
  field), or
- a scan-based fixpoint (repeatedly walk the arena; mark any cell whose
  parent is marked) with an explicit round counter.

Both remove the existential/array-frame reasoning that is poisoning the VC,
at the cost of a runtime change and a bigger rewrite of `Collect`.

### 6.6 Last resort, only if documented

Raise the timeout for this specific check **with a recorded measurement** and
keep the gate honest.  But at 300 s z3 still times out and cvc5 says
`incomplete`, so this will not work as-is; it only becomes an option after a
restructure makes the check slow-but-provable.

**Do not** use `Assume`, `pragma Annotate` or `Suppress`; they violate the
project's verification definition.

---

## 7. Resume commands

```sh
# get the WIP back
git checkout m5-wip

# build / test (fast)
./scripts/build.sh
./scripts/test.sh                      # 44 runs, must stay green

# full gate (5 s per check, -j6)
./scripts/prove.sh

# budget experiment
TIMEOUT=120 ./scripts/prove.sh

# fast iteration on just Collect (~70-80 s)
cd tr7
/home/fernando/bin/gnatprove-x86_64-linux-16.1.0-1/bin/gnatprove \
  -P tr7.gpr --level=4 --timeout=5 -j6 --limit-name=Collect

# save VCs for direct solver runs
gnatprove -P tr7.gpr --level=4 --timeout=5 -j6 --limit-name=Collect \
  --debug-save-vcs
# VCs land in tr7/obj/release/gnatprove/*.smt2
```

Tool locations:

- GNATprove:
  `/home/fernando/bin/gnatprove-x86_64-linux-16.1.0-1/bin/gnatprove`
- provers:
  `/home/fernando/bin/gnatprove-x86_64-linux-16.1.0-1/libexec/spark/bin/`
  (`z3`, `cvc5`, `altergo`)

**Stale-object trap:** after changing `gnat.adc` or compiler switches, always
`rm -rf tr7/obj tr7i/obj tr7_c/obj`.  A stale `tr7-runtime.o` kept pre-policy
invariant checks in the binary once.

**Never overlap two GNATprove runs on the same `obj` directory.**

---

## 8. The lost sandbox and the surviving reference

The original sandbox (`/tmp/opencode/reachprobe`: `Reach_Types`, `Reach_Facts`,
`Reach_Math`, `Reach_Collect`, `Reach_Sweep`) was lost between sessions.  It
had proved 63 checks at level 4 / 5 s in 3.9 s.

**Reconstruction attempt (this handoff session):** a fresh minimal version was
written (plain cell indices, boolean-free epoch marks, the drain/sweep split,
`Loop_Entry`-anchored sweep, `Failed`-on-incomplete) and iterated.  It did
**not** reproduce a green run: two checks remained —

- drain invariant `Is_Marked (J) → Kind /= Cell_Free` not preserved
  (`marked` cells can be free cells in the reconstructed heap because there is
  no `Live_Cell` liveness precondition), and
- post `Roots_Marked` (`Mark_Epoch = Epoch`) at the drain exit.

The attempt was discarded rather than committed unproven.  This is a useful
negative datum: the difficulty is **intrinsic to the closure invariant's
interaction with array updates**, not merely the tr7 handle/generation
indirection, so simply deleting `Live_Cell` will not fix the real drain.

What survives and is the real reference:

- `tr7/src/tr7-reach.ads` / `.adb` on `m5-wip` — `Reachable`, `From_Roots`,
  `Marked_If_Reached` and `Sweep` are the validated design, and *their* checks
  prove in the tr7 build (only the drain in `tr7-heap` fails).
- The architecture rules in section 3 of this document.

If a sandbox is wanted again, rebuild it from that unit (drop the `Tr7.`
prefixes, replace handles/values with plain indices **and keep a liveness
predicate** so `marked → non-free` is available), then gate it with
`gnatprove -P reach.gpr --level=4 --timeout=5 -j6` before porting.

---

## 9. After the drain proof: remaining M5 work

Once the gate is green:

1. **Gold hardening audit** — confirm zero `Assume`/`Annotate`/`Suppress`,
   no justified checks, no warnings, all units `SPARK_Mode => On`; check
   `gnatprove.out` for "justified" and for `Assume`.
2. **Contracts review** — every public subprogram has a meaningful Pre/Post;
   `Tr7.Reach`'s postconditions never mention `Reachable` (run-time cost).
3. **Benchmarks** — `scripts/bench.sh` with checks off (never with
   `TR7_CHECKS=on`), record GC and interpreter numbers in
   `docs/verification.md` / `docs/findings.md`.
4. **Final report** — update `docs/verification.md` (add the M5 row and the
   final check count), `docs/architecture.md` (collector split, `Tr7.Reach`,
   epoch jump, root list), `docs/plan.md` (mark M5 complete), `README.md`, and
   `docs/findings.md` (M5 lessons: policy file, unit split, single-atom
   invariants, `Loop_Entry` anchoring, `Failed`-on-incomplete, the prover
   capability gap).
5. **Merge** `m5-wip` to `master` only when `./scripts/prove.sh` is green and
   `./scripts/test.sh` is 44/44.

---

## 10. File map for M5

| file | role |
| --- | --- |
| `tr7/gnat.adc` | `Loop_Invariant => Ignore` policy |
| `tr7/tr7.gpr` | passes `-gnatec=…/gnat.adc` in the checked profile |
| `scripts/prove.sh` | gate; `-j6`; `TIMEOUT` override |
| `tr7/src/tr7-cells.ads` | `Queued` epoch tag; `Cell_Array` indexed by `Valid_Cell_Index` |
| `tr7/src/tr7-heap.ads` | `Root_Array`/`Root_Count`/`Max_Roots`, `Live_Cell`, `Is_Marked`, `On_Stack`, `Child_Marked`, `Closure`, `Drained_Car/Cdr/Env`, `Collect` contract |
| `tr7/src/tr7-heap.adb` | `Live_Cell`, `Fetch` refactor, reworked `Collect` (epoch jump, roots loop, drain, `Root_Child`, failed-on-incomplete) |
| `tr7/src/tr7-reach.ads` / `.adb` | `Reachable`, `From_Roots`, `Marked_If_Reached`, `Sweep` |
| `tr7/src/tr7-machine.adb` | `Collect_Garbage` root list + `In_Roots` invariants + conditional `Reach.Sweep` |
| `tr7/src/tr7-machine.ads` | `Collect_Garbage` contract (`H.Ready` post) |

---

## 11. Traps already paid for (do not re-learn)

- Constraints are illegal on formals — use named subtypes.
- Postconditions use `F'Result`, never bare `Result`.
- `Mark_Stack` is indexed by `Valid_Cell_Index`; quantify with
  `Valid_Cell_Index (K)` and convert loop variables.
- Mixing `and then` / `or else` needs parentheses.
- `Interfaces` visibility is needed wherever `Unsigned_64` operators appear;
  spec vs body placement matters.
- Assertion policy kinds are comma-separated; `Loop_Entry` is not a policy
  kind.
- `Cell_Array` has no slot for cell 0; make predicates total.
- A `for` loop's normal completion does not imply its exit condition.
- Tests: one error per file; expectations cross-checked against an
  independent oracle (Guile `--no-auto-compile`, upstream C TR7 at
  `/home/fernando/Build/tr7`; R7RS PDF
  `/home/fernando/Build/tr7/r7rs.pdf`).
- In `Call`, `Args` *is* the argument list (take `car`); `Output_Array` needs
  a local `Text_Buffer` bridge; GC runs only at the safe point between steps.
