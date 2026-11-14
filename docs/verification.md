# Verification

## Claim

The `tr7` crate is the verified core:

- every unit is `SPARK_Mode => On`;
- GNATprove runs at level 4 with `--checks-as-errors`;
- the accepted state has zero unproved checks, zero justified checks, and no
  `Assume`, `pragma Annotate` or `Suppress` in `tr7/src`;
- contracts document handle validity, arena bounds, free-list accounting,
  environment lookup, list traversal, arithmetic bounds, reader progress and
  writer bounds.

`tr7i` and `tr7_c` are the documented trusted boundary.  They are
`SPARK_Mode => Off` and contain the only OS-facing code.

## What is not claimed

This is not a machine-checked proof of R7RS semantics.  In particular:

- libraries are out of v1 (a re-entrant `call/cc` is implemented);
- `syntax-rules` is a pragmatic subset (non-hygienic, one trailing ellipsis
  group per list level; no nested ellipses);
- C ABI compatibility is function-level, not bit-level tagged-pointer
  compatibility.

## M5 complete

M5 (GC reachability/liveness proof) is complete: after a successful
collection the marked set is closed, every root is marked, and `Tr7.Reach`
proves every cell reachable from a root is marked, so the sweep never frees
live data.  The architecture and the lessons from the failed first attempt are
recorded in [`docs/M5-TASK.md`](M5-TASK.md) and `docs/findings.md`.

## Running the proof

```sh
TIMEOUT=5 ./scripts/prove.sh
```

The script clears `obj/gnatprove`, runs GNATprove 16.1 at level 4 with
`--checks-as-errors` and `-j6`, then fails on *either* a non-zero exit code or
a log containing `medium:`, `high:`, `unproved` or `failed`.  Exit code 0
alone is not trusted.

The proof always runs with `TR7_CHECKS=on` (the script exports it): `-gnatp`
would make GNATprove drop the corresponding obligations instead of proving
them, and a green run without them would be meaningless.

Results, one entry per closed step of the plan:

| step | checks |
| --- | --- |
| M0 (walking skeleton, proof-green core) | 935 |
| M1.1 collector, tail calls | 990 |
| M1.2 binding forms, `cond`, `case` | 1,048 -> 1,079 -> 1,097 |
| M1.3 strings, vectors, bytevectors | 1,197 -> 1,289 -> 1,407 |
| M1.4 list primitives | 1,493 |
| M1.5 integer tower (`abs`/`min`/`max`/division/`expt`) | 1,602 |
| rest arguments and the define shorthand | 1,637 |
| `apply` | 1,654 |
| `map` / `for-each` | 1,695 |
| `quasiquote` converter | 1,826 |
| `do` (completes step 2) | 1,953 |
| flonums (step 5b: reader, writer, arithmetic, `sqrt`) | 2,386 |
| string ports (closes step 4) | 2,546 |
| `/` -- the numeric tower closes | 2,590 |
| `error` -- Scheme's raiser with a text (M3 begins) | 2,620 |
| `values` / `call-with-values` | 2,649 |
| restricted `call/cc` | 2,666 |
| `dynamic-wind` -- M3 complete | 2,692 |
| M4 C ABI (six entry points, 177 generated stubs) | 2,692 |
| M5 collector proof (worklist + read-only closure check) | 2,895 |
| core procedure coverage (type predicates, selectors, conversions, mutation) | 2,982 |
| `eval` + `interaction-environment` | 2,995 |
| sequence conversions, numeric predicates, number/string I/O | 3,125 |
| `syntax-rules` subset (literals, ellipsis, recursive macros) | 3,375 |
| comparisons, string/vector constructors and list utilities | 3,558 |
| `let-values` / `let*-values` (rewritten to `call-with-values`) | 3,600 |
| `import` compatibility (accepted, no library system) | 3,601 |
| review follow-up: arithmetic, cycle bounds, reader/writer, eval forms | 3,963 |
| field-level heap accessors for pairs and environments | 4,008 |
| character names, lone-dot rejection, C ABI pointer validation | 4,014 |
| re-entrant call/cc (heap continuation snapshots) + IEEE special values | 4,079 |
| wind re-entry through continuations | 4,102 |
| relaxed initialization of the GC root scratch array | 4,138 |
| records, SRFI-1 prelude, cross-wind continuations | 4,412 |
| equal?, member/assoc, mixed flonum arithmetic, arena-bounded list walks | **4,578** |

Every row is 0 unproved, 0 justified, 0 warnings, with flow, initialization
and non-aliasing fully proved and a warning-free build.

## Iteration policy

`TIMEOUT=5` (five seconds per check) is the default: fast enough to turn a
whole-unit run around in a couple of minutes and strict enough to expose
obligations that are structurally hard rather than merely slow.  Raise it only
for an obligation already known to need more time, and record the measurement
and the decision (redesign, or document) in `docs/findings.md`.  Prefer
redesigning a contract or data structure over `Assume` or `Suppress`.

There is no raised-timeout obligation in the accepted state: the multiplication
exactness claim became provable at 5 s by choosing a product-safe fixnum range
instead of asking the prover to reason about a wide multiply.

## Gold hardening audit (M5)

At the accepted state (2026-11-14, 4,578 checks):

- every unit under `tr7/src` is `SPARK_Mode => On`; `tr7i` and `tr7_c` are the
  documented `SPARK_Mode => Off` trusted boundary.  The three constant
  functions in `Tr7.IEEE` have `SPARK_Mode => Off` bodies because their
  values come from the Ada runtime's IEEE overflow behaviour; they return
  only +Inf/-Inf/NaN and are recorded as a trusted boundary;
- `grep` finds no `pragma Assume`, `pragma Annotate` or `pragma Suppress`
  under `tr7/src`;
- `gnatprove.out` has an empty *Justified* and *Unproved* column, and every
  unit line reports "0 warnings and 0 pragma Assume statements";
- the checked build (`-gnata -gnatwa`) is warning-free;
- `Reachable` appears only in `Tr7.Reach` (and only in proof-only invariants);
  no pre- or postcondition mentions it, so it is never evaluated at run time.

Summary by obligation category from `gnatprove.out`:

| category | checks | proved |
| --- | --- | --- |
| Initialization | 1,548 | 1,548 |
| Non-Aliasing | 12 | 12 |
| Run-time Checks | 952 | 952 |
| Assertions | 441 | 441 |
| Functional Contracts | 1,481 | 1,481 |
| Termination | 144 | 144 (74 by flow analysis, 70 by the provers) |
| **Total** | **4,578** | **4,578** |

### Contract review

Many public `tr7` operations carry functional contracts (heap operations,
machine and engine entry points, arithmetic helpers, the collector).  Some
selectors and accessors are deliberately Pre-only: `Kind_Of`, `Car_Of`,
`Cdr_Of`, `Lookup` and most constructors constrain safety and readiness, not
their functional result.  Value predicates and the reachability lattice are
total expression functions.  The C ABI subprograms in `tr7_c` keep their
contracts and are documented as trusted bodies.  The collector's postcondition
states the three closedness facts separately and never mentions `Reachable`;
the sweep's liveness goal lives in `Tr7.Reach` loop invariants, which the
policy file compiles away.
