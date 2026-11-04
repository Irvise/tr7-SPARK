# TR7-SPARK

A small, dependency-free Ada 2012/SPARK implementation of a core R7RS Scheme
interpreter, with a REPL, a C ABI subset, and a verified core.

## Status

Milestone M0: walking skeleton.  The REPL evaluates literals, `quote`, `if`,
`lambda`, `define`, `set!`, `begin`, applications, and a first set of
primitives.  The core uses handles, a fixed cell arena and a CEK evaluator.

Exact integers are fixnums in `-(2**31) .. 2**31 - 1`; out-of-range arithmetic
reports `exact integer overflow` instead of wrapping.  The range satisfies
R7RS's index-range requirement and keeps every arithmetic proof obligation
inside what the SMT provers discharge in five seconds (`docs/findings.md`).

Mark-sweep GC runs at safe points (between evaluator steps), rooting the CEK
state plus the global environment.  Tail calls push no frame, so recursion
keeps a constant-size root set and constant stack space.  `tr7i --stress-gc`
collects on a fixed cadence; the `gc` suite runs both ways and asserts that
garbage was actually reclaimed.  `free-cells` is a small extension primitive
used by that suite.

Supported special forms: `quote`, `if`, `lambda`, `define`, `set!`, `begin`,
`let`, `let*`, `letrec`, `and`, `or` (see `tests/forms.scm`).

Not yet present: `cond`/`case`/`when`/`unless`/`do`, strings beyond literals,
vectors, full numeric tower, `call/cc`, ports beyond strings, the C ABI body,
and `syntax-rules`.

## Build

```sh
alr toolchain --select --disable-assistant gnat_native=16.1.0 gprbuild=26.0.1
./scripts/build.sh
./scripts/test.sh
```

## Run

```sh
tr7i/bin/tr7i            # REPL
tr7i/bin/tr7i file.scm   # script
```

## Verify

```sh
TIMEOUT=5 ./scripts/prove.sh
```

## Benchmark

```sh
./scripts/bench.sh
```

Benchmarks build the whole graph with `TR7_CHECKS=off`: timing a checked build
measures contract checking, not the interpreter (`docs/findings.md`).

See `docs/plan.md`, `docs/findings.md`, `docs/architecture.md` and
`docs/verification.md`.
