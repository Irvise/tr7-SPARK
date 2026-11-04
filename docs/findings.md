# Findings

## Upstream TR7

- Upstream: <https://gitlab.com/jobol/tr7>, version 2.0.19, licence 0BSD.
- Size: `tr7.c` 23,056 lines; `tr7.h` 2,644 lines; 183 exported C functions.
- Architecture: bytecode compiler + explicit-stack VM, tagged values, mark-sweep
  GC, UTF-8 strings, ports, `syntax-rules`, `call/cc`, `dynamic-wind`.
- `call/cc` is implemented by copying the VM stacks into continuation objects.
  There is no `setjmp`/`longjmp`.
- Deliberate upstream gaps: no big integers, no rationals, no complex numbers;
  exactness is fixnum versus double.
- The nine upstream test suites all pass with the C implementation:
  `test-cases`, `test-compile`, `test-dynamic-wind`, `test-import`, `test-ref`,
  `test-syntax`, `test-srfi-1`, `test-srfi-259`, `test-srfi-263`.
- `tr7libs/` contains Scheme-level SRFI implementations that can be reused later
  as conformance tests.
- The C sources use tagged pointers, C preprocessor macros, implicit aliasing,
  and an untyped GC heap. A mechanical translation would not be verifiable.

## Environment

- Alire 2.1.0 is installed.
- System GNAT 16.2.1 is present; Alire can install `gnat_native=16.1.0` and
  `gprbuild=26.0.1`.
- GNATprove 15.1 and 16.1 are available; the default `gnatprove` symlink points
  at 15.1. Proof runs must use the 16.1 binary to match GNAT 16.1.
- Z3, CVC5 and Alt-Ergo are available in the GNATprove 16.1 installation.
- 16 CPU cores, ample disk and memory.

## Design consequences

- SPARK's ownership model cannot represent Scheme's shared mutable object graph
  (two pairs referencing one list, closures sharing an environment, cycles).
  The verified core therefore uses index+generation handles into an
  engine-owned arena. Access types are confined to the C ABI and platform
  boundaries.
- The engine-owner access type still gives explicit ownership at the arena
  level, without per-value ownership.
- A CEK-style evaluator is much smaller than a bytecode compiler and naturally
  supports tail calls, restricted `call/cc`, and `dynamic-wind`.
- The verified `tr7` library is OS-free. The REPL/CLI (`tr7i`) and C ABI
  (`tr7_c`) are the documented trusted boundary.

## What the provers actually discharge (measured, 5 s per check)

All numbers below come from isolated SPARK units run with GNATprove 16.1,
`--level=4 --checks-as-errors`, CVC5/Z3/altergo:

| Obligation | 5 s | 20 s | 60 s |
| --- | --- | --- | --- |
| `X < 2**31 and Y < 2**31 -> X * Y < 2**62` (bounded factors, constant bounds) | proved | - | - |
| `A <= Limit / B -> A * B <= Limit` on `Natural` (31-bit) | proved | - | - |
| `A <= Limit / B -> A * B <= Limit` on `Unsigned_64` (64-bit) | failed | failed | failed |
| `A <= KA and B <= KB -> A * B <= KA * KB` (variable bounds) | failed | failed | - |
| `A / 2**31 <= 2**30`, `A mod 2**31 < 2**31` (divisor is a constant) | proved | - | - |
| Exactness of a split ("wide multiply") fixnum product | failed | - | failed |

Consequences:

- Non-linear reasoning works when the factors are bounded by *constants* and
  when the divisor is a constant. It degrades as soon as 64-bit division or
  variable bounds appear.
- The fixnum range in `Tr7.Config` is therefore chosen so that `*` is one direct
  `Integer_64` multiply plus a range check: `Fixnum_Min = -(2**31)`,
  `Fixnum_Max = 2**31 - 1` gives products of at most `2**62`, and the exactness
  postcondition `Integer_64 (R) = Integer_64 (A) * Integer_64 (B)` proves at 5 s.
- R7RS only demands exact integers across the range usable as indexes of lists,
  vectors, bytevectors and strings and as the result of their `length`
  procedures -- our capacities are 4,096 and below -- and lets an
  implementation report a restriction outside its supported range.  Overflow is
  reported as `Error_Overflow` ("exact integer overflow"), never as a wrong
  answer.

## SPARKlib and big integers

- SPARKlib (AdaCore, <https://github.com/AdaCore/SPARKlib>) solves exactly this
  class of problem with `SPARK.Lemmas.Arithmetic`, a *ghost* generic over an
  integer type and its `Big` (=`Big_Integer`) conversion.  Its key lemma here is
  `Lemma_Mult_Protect` -- the 64-bit division guard above.
- Its body is literally `is null`; the library header states the instances were
  proved "using manual proof in Coq where needed".  We reproduced the lemma in
  three formulations (big-integer postcondition, machine-integer
  postcondition, no-wrap statement) and **none** proved at 5 s with SMT, which
  confirms why they are Coq-proved.
- Adopting it would mean either a source dependency on SPARKlib or copying a
  `null` lemma body, i.e. an unproved assumption.  Both are excluded by the
  project rules (no dependencies, zero unproved checks, no `Annotate`).
- `SPARK.Big_Integers` is available locally but not on the default source path:
  it needs `-I<gnatprove>/include/spark/full`, and conversions for non-`Integer`
  types come from the `Signed_Conversions` / `Unsigned_Conversions` generics.
  It is genuinely useful -- it removes the machine overflow check from a
  postcondition -- and we used it to confirm that the *statement* is not the
  bottleneck: with a `Big_Integer` postcondition the wide multiply still failed
  at 60 s.  Revisit it if a wide fixnum (or `expt`, `gcd`, ...) is ever needed;
  the include path can be added to `tr7.gpr` at that point.

## Ada/SPARK idiom notes from the M0 proof loop

- A single readiness flag beats two: `Engine.Ready` was dropped in favour of
  `E.H.Ready`, so every precondition can be established by the caller without a
  link invariant between the two.
- The step counter moved out of the `Machine` record into `Evaluate`'s local
  state: no callee can mention it, so the loop needs no frame reasoning about a
  4,096-cell record.
- SPARK forbids passing a component of an `in out` parameter together with that
  parameter (`Apply_Procedure (H, M.Result, ..., M, ...)`); copy first.
- A function's implicit result is written `F'Result`, not `Result`, in a
  postcondition, and `Result` is unavailable at all for unconstrained returns
  (`return String`), so contracts on such functions must be expressed elsewhere
  (`Intern` does its own bound checks instead of demanding them from callers).
- `in out` parameters lose every fact not repeated in the `Post`, so every
  heap-mutating helper carries `Pre => H.Ready, Post => H.Ready`; read-only
  helpers keep `H : Heap_Type` and need no post at all.
