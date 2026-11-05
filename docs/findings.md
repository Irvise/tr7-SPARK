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

## Flonum batch: what the last digit cost

The `%g` formatter and `sqrt` took several rounds; the failures are worth
recording because each looked like a different bug:

- **A double subtraction in the digit loop.**  Counting whole units out of the
  remainder already leaves the remainder in `M`; subtracting the digit again
  went negative (`0.5 - 1.0`), which zeroed every digit after the first.  The
  symptom was systematic (`1.5` printed as `1.0`, `0.125` as `0.01`) and the
  fix was deleting one term.
- **The fraction's zero count was off by one**: `0.5` has its first digit in
  the tenths place, so `Exp = -1` means `-Exp - 1` zeros, not `-Exp`.
- **Newton's fixed point is not the root.**  `g = (g + x/g)/2` settles one ulp
  beside `sqrt(x)` for many inputs -- every tested root was 1-2 ulps from
  libm.  Comparing the neighbours' *squares* cannot fix it: the products
  round to the same ulp as the distances being compared, so the test ties.
  The exact fix was to compare against the **midpoint squared** in integer
  arithmetic: a double's mantissa (53 bits) squared is 106 bits and the
  midpoint's `(2*MG+1)**2` is 108, both inside `Interfaces.Integer_128`, with
  the power-of-two factors aligned by an exponent difference the callers keep
  in `[0, 60]`.  After that, `(sqrt 2)` matches libm bit for bit -- as do
  `3`, `5`, `10`, `7`, `99`, `123456`.
- **The reader's digit-by-digit `/10` drifts.**  Parsing `0.1` as
  `1/10` is one rounding (correct), but `0.31622776601683794` needed seventeen
  divisions and accumulated enough error to accept -- and emit -- the wrong
  string, which made the writer's round-trip check agree with itself rather
  than with the value.  One multiply or divide by an **exact power of ten**
  (every `10**k` up to `10**22` still has all its bits in a double) is a
  single rounding; a table of those23 constants is the whole fix.  Beyond
  `10**22` the shift still steps and rounds per digit -- documented as the
  wide-exponent path.
- GNAT has no `'Decompose` attribute (and no `Long_Elementary_Functions`),
  but `'Fraction` and `'Exponent` -- function-style, `T'Fraction (X)` -- give
  the same split.  Ada also has **no `Character` arithmetic**: `'0' + D` does
  not compile; it is `'Val (Pos ('0') + D)` everywhere.
- **The float-in-loop rule, found by bisection**: a float multiplication or
  addition *inside a loop* times out on its overflow check even at 90
  seconds, while the identical operation straight-line proves in seconds and
  looped *divisions* prove fine.  The cause is not the operation but
  GNATprove's **invariant generation** over floating point, which does not
  converge: the check waits on a generated invariant that never arrives.
  The fix is to give **every** loop that touches floats a complete explicit
  invariant set -- sign *and* magnitude, including nested loops (the unit
  counter inside the digit loop needed its own `M <= 10 - D` before the
  outer loop's bound could close).  Reproduced in a five-procedure sandbox
  before touching the real code: same loops, same checks, minutes apart in
  outcome.  Consequence for style: no float loop in this codebase ships
  without two explicit invariants.
- **A bound must be re-establishable to be useful in a loop precondition**:
  `Step_Toward`'s precondition could not simply say `X <= 1e160`, because
  the up-step *increases* its argument and no fixed bound survives it.  The
  shape that works: a precondition over the full range, a postcondition over
  the full range (both trivially maintained), and dead fallback branches
  inside so the postcondition needs no reasoning about near-range sums --
  unreachable for the actual candidates, which stay under 2e160.
- **What GNATprove can and cannot prove about floating-point bounds** --
  this decided the whole shape of the code.  It *cannot* prove a product or
  quotient bounded from a reciprocal guard (`|A| <= Last/|B| => |A*B| <=
  Last`, `G >= X/Last => X/G <= Last`): each timed out at 90 seconds, so it
  is a capability gap, not a budget one.  What it *does* discharge quickly is
  **constant-bound branches**: one operand below one, or both below a fixed
  threshold whose product/sum is provably inside the range.  The float paths
  in `+`, `-` and `*` are therefore written as those branches with an
  `Error_Overflow` otherwise -- no false rejections for small operands, and
  the rejected band (two operands both above ~9e307 adding, or both above
  ~1.3e154 multiplying) is recorded as a v1 limit.
- **Newton's method had to go**, not because of the iteration but because
  `X / G` carries a division bound no prover here could discharge (G's
  lower bound would have to survive a halving loop, which no static
  invariant can express).  The replacement builds the candidate on the
  *integer* side: `X = M2 * 2**(2*K)`, `floor(sqrt(M2 * 2**72))` in
  `Integer_128` (a 63-bit root of a value below 2**126), rounded to 53 bits
  and scaled by guarded doublings -- then the exact `Sq_Le`/`Mid_Le`
  comparisons finish the job.  Two algebra errors were caught by the test
  table on the way: the power is `E - 53`, not `E` (the mantissa already
  absorbed 53 bits), and the rounding shift leaves `sqrt(M2) * 2**26`, so
  the scale is `K - 26`, not `K - 36` -- each was visible as a value off by
  exactly a power of two.
- **GNATprove does not model the floating-point manipulation attributes at
  all**: `'Fraction`, `'Exponent`, `'Scaling` and `'Adjacent` were each
  rejected as *"non-static attribute ... is not yet supported"* -- a hard
  analysis error, not an unprovable check, so no contract shape can hide
  them.  The fix was to spell out what they do in arithmetic the prover
  sees: a `Decompose` of exact halving/doubling loops (with a clamp after
  them so the `[0.5, 1)` postcondition needs no floating-point loop
  invariant), the mantissa as fifty-three doublings plus a conversion whose
  bound comes from a dead guard, the ulp as a scaled one, and the neighbour
  as `X +/- ulp`.  Power-of-two scaling is exact, so the results are the
  attributes' results -- only the spelling changed.

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
  helpers take `H : Heap_Type` and carry no post -- a post that merely repeats
  the precondition of an `in` parameter earns a "postcondition does not check
  the outcome" warning, and GNATprove separately suggests `could be IN` for
  every `in out` parameter the body never writes.
- GNAT warns about an `out` parameter the caller never reads, and silencing it
  with `pragma Unreferenced` earns a second warning.  The way out is to change
  the shape of the interface so that every caller uses it (see the environment
  note in `docs/architecture.md`).
- GNATprove rejects a conditional expression *inside* an aggregate
  (`cannot untangle node N_IF_EXPRESSION`): build the record first, then
  assign the conditional field.
- A function is implicitly `Always_Terminates` in SPARK, a procedure is not,
  so a cursor walk inside a function needs a `Loop_Variant` -- a bounded
  counter with `Decreases => Bound - Steps` is the shape that proved here --
  while the identical walk in a procedure needs neither.
- For mutually recursive procedures, `Subprogram_Variant => (Decreases => Fuel)`
  on both forward declarations proves the cycle terminates.  A `Fuel` parameter
  works without dragging the callee's precondition along when the fuel check is
  an entry guard (`if Fuel = 0 then ... return`) rather than a precondition:
  the guard establishes `Fuel >= 1`, which makes `Fuel - 1` range-safe and
  strictly decreasing at every call site, while the callee's precondition stays
  free of fuel entirely (a precondition `Fuel > 0` would not be re-established
  by `Fuel - 1` -- the off-by-one traps that shape every time).
- Flow demands an `out` parameter be initialized on *every* return path, early
  returns included -- `Build_Call2` failed its first proof on exactly that
  once it started being called.  The mirror-image complaint is "unused
  assignment" when every path overwrites the initial value before any read
  (`Data_Code`'s `Ok := False`, `QQ_Spine`'s `Status := No_Error`, both dead
  because a callee's `out` always wrote first).  Both were fixed by moving or
  deleting the assignment, never by annotating anything.
- The same family has a third shape: *"X is set by Y but not used after the
  call"*, which fires when one call site needs only some of a helper's `out`
  parameters.  The fix that keeps every caller honest is to split the helper
  by what callers actually read (`Do_Binding` for var+init, `Do_Step_Of` for
  var+step) rather than to introduce dummy reads or annotations.  Related: an
  `in out` parameter the callee writes but the caller never reads again draws
  the same complaint about the *caller's* variable -- taking it `in` and
  copying to a local inside the callee (`F2 := F; F2.Kind := ...; Push (F2)`)
  moves the write to where it is genuinely used.
- Loop invariants that the construct already implies -- `for I in 0 .. N`
  giving `I <= N`, `while Mag > 0` giving `Mag >= 0`, a counter nothing
  decrements -- draw `condition is always True` warnings: delete them.

## Performance: measure with the checks off

Rule adopted after this episode: **benchmark a checks-off build, never the
checked one**, and keep runtime-check policy in the build flags rather than in
the source.

GNAT evaluates `pragma Loop_Invariant` at run time under `-gnata`.  A
quantified invariant -- `for all J in Valid_Cell_Index => ...` inside a
`for I in Valid_Cell_Index` loop -- is then O(n^2): 4,096 x 4,096 element
tests.  Measured on the real `Collect_Garbage` (612 calls, idle heap):

| build | per collection |
| --- | --- |
| `TR7_CHECKS=on` (`-gnata`, the default: tests and proofs) | 8,990 us |
| `TR7_CHECKS=off` (`-gnatp`, benchmarks) | 2.3 us |

Both profiles compile the same sources.  The scenario lives in `tr7.gpr`
(a `case` on `TR7_CHECKS` inside `package Compiler`), so nothing in
`tr7/src` selects a policy; `scripts/bench.sh` exports `TR7_CHECKS=off` for
the whole project graph.

How the number was mis-read at first, so it is not repeated:

- benchmarking a client project that `with`s the library rebuilds the library
  too -- if `TR7_CHECKS` is not exported for *that* invocation, the library is
  quietly rebuilt with `-gnata` and the benchmark measures assertions again;
- a standalone micro-benchmark whose result is dead can be optimised away and
  report an instant time for the wrong reason.

Numbers from `scripts/bench.sh` (checks off for the whole graph):

| workload | time |
| --- | --- |
| 612 collections of an idle heap | 2.3 us each |
| `tests/gc.scm` (3,000-element list, 6,000 tail calls) | 0.11 s |
| the same under `--stress-gc` (~11,000 collections) | 2.3 s |
| 500 datums of `(display 1)(newline)` | 0.005 s |

A third way to mis-measure, worth recording: switching `TR7_CHECKS` does not
change any source, so a plain `./scripts/build.sh` after the switch rebuilds
nothing and the "unchecked" binary is still the checked one.  `bench.sh` is
immune because it removes the object directories first; a hand-rolled
comparison is not.

The checked profile keeps quantified loop invariants live on purpose -- they
are what proves the sweep leaves no stale mark -- and pays for it: the stress
suite takes 2.3 s there as well, dominated by ~0.2 ms collections (marking a
3,000-cell live set).  That is acceptable for a test build; anything timed goes
through `scripts/bench.sh`.

### The regression the suites caught, and what fixed it

Symptom: after the derived forms landed, `tests/gc.scm` went from 0.11 s to
3.0 s and `--stress-gc` on the same file stopped finishing at all (180 s),
in **both** the checked and unchecked builds of the time.

Diagnosis, in order:

1. `perf record` + `perf report`: **99.48 % of all samples inside
   `Tr7.Heap.Collect`**, and `perf annotate` showed the hot instructions as a
   loop guarded by `cmp $0x1000` (4,096) nested inside itself -- the quantified
   `for all J in Valid_Cell_Index` invariant of the sweep, evaluated at run
   time, 4,096 x 4,096 per collection.
2. Counting collections (`free-cells` temporarily returning the count):
   `sum` over a 3,000-element list triggered **174 collections**.  That is
   correct behaviour -- a 3,000-cell live set leaves ~1,050 free cells, so the
   512-cell low-water mark is crossed every ~17 calls -- but at ~8 ms each it
   was 1.4 s of the 1.42 s runtime.

Fix: **mark epochs**.  A cell is marked when `Mark_Epoch = Heap.Epoch`, and
`Epoch` advances after every sweep, retiring the cycle's marks in one
assignment.  The clearing pass and both quantified invariants disappeared, so
the sweep is a single linear pass with scalar invariants only:

| workload | before | after |
| --- | --- | --- |
| `tests/gc.scm` | 3.0 s | 0.15 s |
| `--stress-gc tests/gc.scm` | > 60 s | 3.8 s |
| `sum` over 3,000 cells | 1.41 s | 0.10 s |
| samples in `Collect` (perf) | 99.5 % | 9.5 % |

Two structural lessons: a quantified invariant is a *run-time* cost under
`-gnata`, so it must not sit in a loop that runs per cell; and a design that
needs an O(n^2) proof invariant usually wants a different design (epochs make
"no stale marks" a scalar postcondition instead).

The same profile names what is left: after the fix the stress run spends
52 % in `memmove` and 25 % in `Mark_Root`/`Fetch` -- the 330-byte cell copied
by value out of the arena on every visit.  That cost is bounded by the arena
size (~1.4 ms per collection at 4,096 cells), so it cannot run away, but the
next GC optimisation is to stop copying: read the fields needed for marking in
place instead of `Fetch`-ing a whole `Cell`.

Tooling: `perf` (record/report/annotate) was the right instrument and is what
the numbers above come from; `valgrind --tool=callgrind` is the fallback when
instruction-level attribution of a microsecond-scale function is needed.

`free-cells` is a small non-standard extension primitive: it lets the GC suite
assert that garbage was actually reclaimed, not merely that nothing crashed.
