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

The script clears `obj/gnatprove`, runs GNATprove sequentially with the 16.1
toolchain, and inspects the summary.  Exit code 0 alone is not trusted.

## Iteration policy

Use a 5 second per-check timeout while bringing up a unit.  Increase it only
for obligations that are known to need more time, and record why.  Prefer
redesigning a contract or data structure over `Assume` or `Suppress`.
