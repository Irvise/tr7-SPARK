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
`let`, `let*`, `letrec`, `and`, `or`, `cond`, `when`, `unless`, `case`
(`tests/forms.scm`, `tests/cond.scm`, `tests/case.scm`).

Strings have `string?`, `string-length`, `string-ref`, `substring`,
`string-append`, `string=?`, `#\x` reader escapes and wide-character
write-back (`tests/strings.scm`).

Vectors have `vector`, `vector?`, `vector-length`, `vector-ref`,
`vector-set!` and the `#(...)` reader constructor (`tests/vectors.scm`).

Bytevectors have `bytevector`, `bytevector?`, `bytevector-length`,
`bytevector-u8-ref`, `bytevector-u8-set!` and `#u8(...)` in reader and writer
(`tests/bytevectors.scm`); lists have `length`, `append`, `reverse`,
`list-ref`, `assq` and `memq` (`tests/lists.scm`).

Integer arithmetic has `quotient`, `remainder`, `modulo`, `abs`, `min`, `max`
and `expt` on fixnums, with overflow and zero divisors reported by name
(`tests/numbers.scm`).

Lambdas take rest arguments (`(lambda (a . rest))`) and `define` accepts the
`(define (f x) ...)` shorthand (`tests/defs.scm`).

`apply`, `map` and `for-each` are evaluator forms (`tests/apply.scm`,
`tests/map.scm`).

`quasiquote` with `unquote` and `unquote-splicing` converts its template to
`cons`/`append`/`quote` code and evaluates that (`tests/qq.scm`); `do` runs
its test/body/step loop over three frame kinds with parallel steps
(`tests/do.scm`).

Flonums are IEEE doubles: decimal literals read with a single rounding, the
writer prints the shortest string that reads back to the same value, `+`, `-`,
`*` and the comparisons take mixed operands (inexact wins), `exact->inexact`
converts, and `sqrt` returns the correctly rounded root (`tests/flonums.scm`).

String ports are in: `open-input-string`, `open-output-string`,
`get-output-string`, `read`, `read-char`, `peek-char`, `char-ready?`,
`port?`, `eof-object?`, and the optional port argument on `display`, `write`
and `newline` (`tests/ports.scm`); the OS boundary stays in `tr7i`, which
loads files into strings.

`/` divides exactly when every step is exact and returns the inexact
double otherwise (`(/ 6 3)` is `2`, `(/ 1 2)` is `0.5`) -- v1 has no
rationals (`tests/div.scm`).

`(error message irritant ...)` raises with a text the printer prefers over
the generic code name (`tests/error.scm`).

Not yet present: `call/cc`, real file ports, the C ABI body, and
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

## Benchmark

```sh
./scripts/bench.sh
```

Benchmarks build the whole graph with `TR7_CHECKS=off`: timing a checked build
measures contract checking, not the interpreter (`docs/findings.md`).

See `docs/plan.md`, `docs/findings.md`, `docs/architecture.md` and
`docs/verification.md`.
