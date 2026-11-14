# TR7-SPARK plan

## Current status

M0–M5 are complete and the v1 scope below is implemented: the verified core,
REPL and script runner, the C ABI (102 of 183 `tr7.h` symbols implemented,
with a differential harness against upstream C TR7), the conformance suites,
and the mark-sweep reachability proof.  The gate is green at 6,138 checks
(level 4, 5 s per check, `--checks-as-errors`), with no unproved, justified
or assumed checks and 58 green suites (each also run under stress GC).

Design decisions taken along the way are recorded in `docs/findings.md`; the
ones that shape the code most are the product-safe fixnum range
(`-(2**31) .. 2**31 - 1`), the single engine readiness flag (`E.H.Ready`),
mark epochs instead of mark bits, and the collector split into worklist drain
plus read-only closure verification (`docs/M5-TASK.md`).

Work explicitly left outside v1 is listed under "Not in v1" below (notably
`syntax-rules`, libraries/`import`, `load` and real file ports; `eval`
and re-entrant `call/cc` are now available.

## Goal

A small, dependency-free Ada 2012/SPARK implementation of a core R7RS-small
Scheme interpreter, with a C ABI subset and a REPL.

"Fully verified" for this project means:

- the `tr7` library is `SPARK_Mode => On` throughout and proves at GNATprove
  level 4 with `--checks-as-errors`;
- zero unproved checks, zero justified checks, zero `Assume`, zero
  `pragma Annotate`, zero `Suppress` in `tr7`;
- functional contracts cover handle validity, arena bounds, free-list
  integrity, mark/sweep safety, CEK state invariants, continuation bounds,
  environment lookup, arithmetic, string/vector/bytevector bounds, reader
  progress and writer bounds;
- OS I/O, C pointers, clocks and process control are isolated in `tr7_c` and
  `tr7i`, which are the documented trusted boundary;
- Scheme behaviour is validated by a focused conformance suite, stress-GC runs
  and (optionally) differential testing against upstream C TR7.

It does not claim a machine-checked proof of the full R7RS semantics.

## v1 scope

In v1:

- datums: booleans, fixnums, flonums, chars, strings, symbols, pairs, vectors,
  bytevectors, procedures, string ports, EOF, unspecified;
- forms: `quote`, `if`, `lambda`, `define`, `set!`, `begin`, `let`, `let*`,
  `letrec`, `cond`, `case`, `and`, `or`, `when`, `unless`, `do`, `quasiquote`;
- procedures: arithmetic/comparison, pairs/lists, strings/chars,
  vectors/bytevectors, predicates, `apply`, `map`, `for-each`,
  `display`/`write`/`newline`, `read`, `error`, `values`/`call-with-values`,
  re-entrant `call/cc`, `dynamic-wind`, string ports;
- memory: engine-owned fixed-size cell arena, index+generation handles,
  simple mark-sweep GC;
- C ABI: core subset implemented, all other `tr7.h` symbols present as stubs;
- REPL and script runner.

Not in v1: a complete R7RS mark/rename hygiene algorithm (`syntax-rules` is
hygienic for template-introduced binders, with documented ellipsis limits), a
real library system (`import` is accepted as a compatibility declaration and
loads the SRFI-1 prelude), `load`, the full SRFI catalogue (SRFI-1 and SRFI-9
records are implemented), full Unicode tables, unbounded-precision bignums
(the numeric tower caps them at 256 decimal digits), the full TR7
debug/trace/extension API, and bit-level tagged-pointer ABI compatibility.

## Crates

```
TR7-SPARK/
  tr7/        verified core, SPARK_Mode On, no OS code
  tr7_c/      C ABI subset + generated stubs, SPARK_Mode Off
  tr7i/       REPL/CLI, SPARK_Mode Off
  tests/      core .scm/.expected suite, C demo, stress-GC runs
  scripts/    build.sh, prove.sh, test.sh
  docs/       architecture.md, verification.md
  Makefile
```

Commands:

```sh
alr toolchain --select --disable-assistant gnat_native=16.1.0 gprbuild=26.0.1
alr init --lib tr7
alr init --lib tr7_c
alr init --bin tr7i
(cd tr7_c && alr with tr7 --use=../tr7)
(cd tr7i && alr with tr7 --use=../tr7)
```

`tr7` has no crate dependencies. `gnatprove` is a development tool only and is
not declared as a crate dependency, so `alr build` requires only GNAT and GPR.

## Core design

- CEK machine: `Control`, `Environment` and `Continuation` are handles; one
  `Step` function plus a run loop. Tail calls are natural.
- Fixed-size cells: pairs, closures, environment frames, continuation frames,
  symbol chunks, string chunks, vector chunks, bytevector chunks, procedures.
- Handles are index + generation. A stale handle is an error, not memory
  corruption. The engine owns the cell array.
- Mark-sweep GC: the CEK state and global environment are the complete root
  set at a safe point; symbols are interned by scanning, ports carry text
  inline, and there is no separate constants table.
- `call/cc`: heap snapshot of the CEK frames; re-entrant/multi-shot.
- Environments: association-list frames with a parent handle.
- Ports: string ports in `tr7`; `tr7i` loads files into strings and prints
  output. The verified core never touches the OS.
- Numbers: fixnum in `-(2**31) .. 2**31 - 1` plus double, chosen so that
  products fit in `Integer_64` and their exactness proves at the 5 s timeout
  (R7RS only requires the index range; see `docs/findings.md`). Pure Ada
  `sqrt` and `expt`; pure Ada `%g`-style formatting. No `libm` dependency.
- Reader/writer: bounded buffers, clear error positions, depth/visited limits.
- Primitives dispatch through an enum + `case`, avoiding `'Access` tables.

## C ABI

- `tr7_c` exposes the core subset with original names/signatures where
  possible: engine lifecycle, eval string/file, define/ref, apply/call, value
  constructors, predicates, accessors, error status.
- All remaining `tr7.h` symbols are generated as stubs that return
  `TR7_VOID`/false/null/0 and never crash.
- `tr7_t` is an opaque tagged 64-bit handle at the boundary; the Ada core uses
  its own `Value`/`Handle` types.
- Function-level compatibility is guaranteed. Bit-level compatibility with
  TR7's tagged pointers and representation macros is not.

## Verification

- `tr7`: `SPARK_Mode => On`, level 4, `--checks-as-errors`, zero
  unproved/justified checks, zero `Assume`/`Annotate`/`Suppress`.
- GC safety and reachability/liveness (`marked = reachable`) are both proved:
  the marked set is closed after draining, and `Tr7.Reach`'s path-induction
  lemma carries it to every cell reachable from a root.  Stress-GC mode
  collects on a fixed cadence.
- `scripts/prove.sh` clears `obj/gnatprove`, runs with `--timeout=5 -j6` and
  greps the summary for `medium:`/`high:`/`unproved`/`failed`; exit code 0
  alone is not trusted.  Never overlap two runs on the same `obj` directory.

## Milestones

| Phase | Effort | Deliverable |
|---|---|---|
| M0 | 1-2 days | Three crates, toolchain, pins, build/prove scripts, walking skeleton (`(+ 1 2)`) |
| M1 | 1-2 weeks | Values, arena, symbols, numbers, pairs, strings, vectors, bytevectors; GC skeleton |
| M2 | 2-3 weeks | Reader/writer, full CEK machine, core special forms, tail calls |
| M3 | 2 weeks | Core primitives, errors, restricted `call/cc`, `dynamic-wind`, `values` -- **complete**: `error`, `values`/`call-with-values`, restricted `call/cc` and `dynamic-wind` are in (`tests/error.scm`, `tests/values.scm`, `tests/callcc.scm`, `tests/wind.scm`) |
| M4 | 2 weeks | String ports, REPL, C ABI subset + generated stubs, core test suite -- **complete**: string ports (`tests/ports.scm`), the REPL, the C ABI (102 of 183 symbols implemented, the rest generated stubs, `tests/abi_demo.c`) and 44 test runs |
| M5 | 2-3 weeks | Mark-sweep GC proof, Gold hardening, contracts, benchmarks, report -- **complete**: `Tr7.Reach` proves reachable cells are marked and the sweep never frees them, the collector is split into epoch jump / worklist drain / read-only verification / sweep, and the gate is green with zero unproved checks |

Size: about 15k lines of Ada in `tr7/src`, plus the REPL, C ABI, generated
stubs and tests.

## Proof practices adopted from the Ironclad campaign

- Prefer structural subtypes and representation aspects over re-proved
  invariants.
- Avoid nonlinear arithmetic in contracts.
- Measure proof time cold; clear `obj/gnatprove` before per-unit runs.
- One GNATprove run at a time per object directory (`-j6` inside it is fine);
  a syntax error in any unit poisons all runs.
- Never hide real checks with `Suppress`; remove unproved obligations by design.
- Keep `SPARK_Mode Off` bodies scoped and documented.
- Never pass a record and one of its own fields to the same subprogram.
- Fully initialize `out` parameters.
- Prefer expression functions when preconditions mention them.

## M1 breakdown (record)

Concrete order, each step keeping the proof and the suites green.

1. **GC skeleton** -- **done in code, in proof**: explicit roots (CEK state plus
   global environment), mark phase over the arena, sweep into the free list,
   and a `--stress-gc` mode collecting on a fixed cadence so the suites
   exercise the collector continuously.  The suite asserts that garbage was
   reclaimed (`free-cells`), and the same file runs both normally and under
   stress.  Root contract: `Ready` survives collection, the mark stack stays
   bounded, no cell is freed while marking is incomplete.  The proof run for
   this step is the gate for committing it.

   The GC suite also exposed (and now regression-tests) two M0 defects: tail
   calls were leaking a pass-through frame per call, and `-gnata` was evaluating
   quantified loop invariants at run time (8.4 ms per collection instead of
   5 us).  Both are fixed; see `docs/findings.md`.
2. **Derived binding forms** -- rest arguments (`(lambda (a . rest))`) and
   the `(define (f x) ...)` shorthand are in: parameter shape is validated and
   counted once at closure creation (`Param_Fixed_Length`), rest-ness is
   re-derived at call time, and `Bind_Params` binds the tail list -- after the
   rest case, so `(f)` still works for `(f . xs)`.  Note for the record:
   recursive rest-argument functions need `apply` (step 4b), because
   `(f (cdr xs))` passes the tail as *one* argument; the suites use proper
   lists where recursion is wanted.  The rest of the step: `let`, `let*`,
   `letrec`, `and`, `or` are in
   (`tests/forms.scm`: parallel binding swaps, sequential rebinding, mutual
   `letrec` recursion, short-circuit side effects), so are `cond` (with `=>`
   and `else`, `tests/cond.scm`), `when`, `unless`, `case`
   (`tests/case.scm`, sharing `Same_Value` with `eq?`), `quasiquote` -- as a
   converter to `cons`/`append`/`quote` code rather than a frame kind
   (`tests/qq.scm`, `tests/bad-qq.scm`) -- and finally `do`
   (`tests/do.scm`, `tests/bad-do.scm`), which completes this step: three
   frame kinds (test, body, steps), initializers through the marked `K_Bind`,
   and parallel steps that rebind only the variables that have one.
3. **Strings and vectors** -- strings are in (`string?`, `string-length`,
   `string-ref`, `substring`, `string-append`, `string=?`, the reader's
   `#\x` escapes, wide-character write-back), and so are vectors:
   `vector`, `vector?`, `vector-length`, `vector-ref`, `vector-set!` and the
   `#(...)` reader constructor (`tests/vectors.scm`, `tests/vindex.scm`, and a
   vector kept alive across the gc suite's churn), and bytevectors:
   `bytevector`, `bytevector?`, `bytevector-length`, `bytevector-u8-ref`,
   `bytevector-u8-set!` and `#u8(...)` in both reader and writer -- same cell
   as a string, so byte access is O(1) (`tests/bytevectors.scm`,
   `tests/bvindex.scm`, `tests/brange.scm`).
4. **More primitives** -- `length`, `append`, `reverse`, `list-ref`, `assq`
   and `memq` are in (`tests/lists.scm`); `string?`/`vector?`/`bytevector?`
   arrived with step 3; `apply` is in as an evaluator form (`tests/apply.scm`)
   -- it reuses the operator/argument frames, carrying the "spread the last
   argument" marker in the frame's unused Sym, and validates the spread with
   `Length` so a non-list tail is a type error.  `map` and `for-each` are
   evaluator forms for the same reason -- they call a closure per element over
   a variadic list of lists (`tests/map.scm`): K_Operator/K_Argument evaluate
   the operands, K_Map carries one round, and `Map_Next` owns "finished, or
   push and call" so the entry and the continuation cannot drift.  Step 4 is
   complete: string ports are in (`tests/ports.scm`, `tests/bad-ports.scm`)
   -- text inline in the port cell, a local-buffer bridge for writes, the
   `Kind_EOF` datum for `read` at the end of text -- with the OS boundary
   where the plan put it, in `tr7i`, which loads files into strings.
5. **Numeric tower step 1** -- the integer half is in: `abs`, `min`, `max`,
   `quotient`, `remainder`, `modulo` and `expt` (`tests/numbers.scm`,
   `tests/numovf.scm`), each overflow or zero-divisor path guarded and named,
   and so is step 5b: flonums (`tests/flonums.scm`) -- decimals read with a
   single rounding, `%g`-style output that round-trips through the reader,
   `exact->inexact`, `sqrt` (exact for perfect squares, and otherwise the
   correctly rounded double via `Integer_128` midpoint arithmetic), and
   inexact paths through `+`, `-`, `*` and the comparison chain.  Later
   batches extended `abs`, `min`, `max`, `expt`, `quotient`, `remainder` and
   `modulo` to mixed flonums and replaced the early no-rationals rule with
   the numeric tower: exact rationals, bignums and complex numbers
   (`tests/tower.scm`).  `/` (`tests/div.scm`) is exact when it divides
   evenly and otherwise produces a normalized exact rational, so `(/ 6 3)`
   is `2` and `(/ 1 2)` is `1/2`, with a single flonum making the whole
   chain inexact and the float division guarded into the branches the
   provers discharge (a divisor of at least one, or both operands inside a
   fixed window whose ratio fits the range), reporting an overflow rather
   than an infinity.

Each step ends with: build, four suites, `scripts/prove.sh`, commit.
