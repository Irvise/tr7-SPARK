# TR7-SPARK

A small, dependency-free Ada 2012/SPARK implementation of a core R7RS Scheme
interpreter, with a REPL, a C ABI subset, and a verified core.

## Status

Milestone M0: walking skeleton.  The REPL evaluates literals, `quote`, `if`,
`lambda`, `define`, `set!`, `begin`, applications, and a first set of
primitives.  The core uses handles, a fixed cell arena and a CEK evaluator.

Not yet present: GC, `let` and its relatives, strings beyond literals, vectors,
full numeric tower, `call/cc`, ports beyond strings, the C ABI body, and
`syntax-rules`.

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

See `docs/plan.md`, `docs/findings.md`, `docs/architecture.md` and
`docs/verification.md`.
