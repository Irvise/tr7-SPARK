# TR7-SPARK

A small, dependency-free Ada 2012/SPARK implementation of a core R7RS Scheme
interpreter, with a REPL, a C ABI subset, and a verified core.

## Status

Milestones M0–M5 are complete.  The REPL evaluates the core R7RS forms
(literals, `quote`, `if`, `lambda`, `define`, `set!`, `begin`, applications,
the derived binding and conditional forms, `do`, `quasiquote`, `map`,
`for-each`, `apply`, `values`, re-entrant `call/cc` and `dynamic-wind`), a
broad primitive set, and a C ABI subset.  The core uses handles, a fixed cell
arena and a CEK evaluator, and its mark-sweep collector is proved at SPARK
level 4: every cell reachable from a root is marked and never swept.

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

Supported special forms: `quote`, `if`, `lambda`, `define`, `define-syntax`,
`syntax-rules`, `set!`, `begin`, `let`, `let*`, `letrec`, `and`, `or`,
`cond`, `when`, `unless`, `case` (`tests/forms.scm`, `tests/cond.scm`,
`tests/case.scm`, `tests/macro.scm`).

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

Core procedure coverage includes the type predicates `boolean?`, `symbol?`,
`char?`, `number?` and `procedure?`; pair mutation with `set-car!`/`set-cdr!`;
the selectors `caar`/`cadr`/`cdar`/`cddr`; `symbol->string` /
`string->symbol`; and `char->integer` / `integer->char` (`tests/core.scm`).

`eval` is available with `(interaction-environment)` as the top-level
environment specifier (`tests/core.scm`); `load` is still outside v1.

Sequence and number utilities include `list->vector`, `vector->list`,
`list->string`, `string->list`, `string-copy`, `number->string`,
`string->number`, `exact?`, `inexact?`, `zero?`, `positive?`, `negative?`,
`odd?`, `even?`, `memv` and `assv`; and the comparison, constructor and
list utilities `char=?`/`char<?`/`char>?`/`char<=?`/`char>=?`,
`string<?`/`string>?`/`string<=?`/`string>=?`, `make-string`, `string-set!`,
`make-vector`, `vector-fill!`, `list-tail`, `list-copy`, `last-pair`,
`eqv?`, `boolean=?` and `symbol=?` (`tests/core.scm`).

`values` and `call-with-values` are in (`tests/values.scm`): several
values ride a wrapper cell that the evaluator spreads onto the consumer,
one value stays itself, none becomes the empty wrapper.  `let-values` and
`let*-values` are rewritten into nested `call-with-values` forms
(`tests/core.scm`).

`call/cc` is re-entrant (`tests/callcc.scm`, `tests/callcc-multi.scm`): a
continuation is a persistent heap snapshot of the frames, so it can be
invoked more than once, and call/cc in tail position adds no frame.  Escaping
across `dynamic-wind` runs the crossed `after` procedures innermost first;
re-entering a wind does not re-run its `before` yet.

`dynamic-wind` is in (`tests/wind.scm`): `before`, `thunk` and `after`
are called around the extent, the form returns the thunk's value, and an
escape runs the crossed `after`s innermost first.

The C ABI (`tr7_c`) is in: the six entry points a C host needs to run
source text, zero-returning stubs for the other 177 `tr7.h` symbols
generated by `scripts/gen_abi.py`, and `tests/abi_demo.c` -- bound,
linked and run by `test.sh` as `abi (C demo)`.  Every signature carries
Pre/Post contracts that `-gnata` checks at run time; the bodies are the
trusted boundary.

`syntax-rules` macros are in (`tests/macro.scm`): literals, pattern
variables, `_`, one trailing ellipsis group per list level, multiple rules
and recursive macros.  Expansion is non-hygienic, so an introduced binding can
capture a caller's identifier; nested ellipses and an ellipsis followed by a
dotted tail are not supported.

`(import ...)` is accepted as a compatibility declaration: there is no
library system, but the core bindings are already in the initial environment,
so R7RS scripts that open with `(import (scheme base))` run.

`+inf.0`, `-inf.0` and `+nan.0` are both written and read (`tests/core.scm`);
the constants come from the standard Ada elementary-function library in the
small trusted `Tr7.IEEE` boundary.  Known limits: re-entering a
`dynamic-wind` extent through a continuation restores its frames but does not
re-run `before`.  Not yet present: real file ports, `load`, a real library
system and full hygienic `syntax-rules`.

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
