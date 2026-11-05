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

- mark-sweep reachability/liveness is a later proof goal;
- full re-entrant `call/cc`, `syntax-rules`, libraries and `eval` are out of v1;
- C ABI compatibility is function-level, not bit-level tagged-pointer
  compatibility.

## Running the proof

```sh
TIMEOUT=5 ./scripts/prove.sh
```

The script clears `obj/gnatprove`, runs GNATprove 16.1 at level 4 with
`--checks-as-errors` and `-j4`, then fails on *either* a non-zero exit code or
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
| restricted `call/cc` | **2,666** |

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
