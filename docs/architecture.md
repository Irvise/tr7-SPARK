# Architecture

## Crates

- `tr7` -- verified core.  `SPARK_Mode => On`, no OS code, no crate
  dependencies.
- `tr7i` -- REPL and script runner.  Trusted boundary for console and file I/O.
- `tr7_c` -- C ABI subset and generated stubs.  Trusted boundary: its
  package is in SPARK with every signature contracted, and each of its
  subprograms is individually `SPARK_Mode => Off`.

## Values and cells

Scheme values are one of:

- immediate: void, boolean, fixnum, character, nil, unspecified;
- a handle: index plus generation into the engine-owned cell arena.

A `Cell` is a non-variant record with fields for pairs, symbol/string text,
closures, environments and primitives.  Fixed-size cells make allocation and a
later mark-sweep collector easy to reason about.  A stale handle is rejected by
the generation check instead of touching the wrong object.

All capacities live in `Tr7.Config`.  Exhaustion is reported as a Scheme error,
never as memory corruption.

## Evaluator

The evaluator is a CEK machine:

- `Mode_Eval` evaluates `Ctl` in `Env`;
- `Mode_Return` delivers `Result` to the top continuation frame;
- `Mode_Halt` stops.

Continuation frames are records in a bounded stack.  A closure application
replaces the current control and environment without pushing a frame, so tail
calls run in constant stack space.  Applications evaluate the operator first,
then arguments left to right, accumulating a reversed argument list.

Supported forms: `quote`, `if`, `lambda`, `define`, `set!`, `begin`,
`let`, `let*`, `letrec`, `and`, `or`, `cond` (with `=>` and `else`),
`when`, `unless`, `case`, `do`, `quasiquote`, `apply`, `map`, `for-each`,
and procedure application.  `let` and its
relatives are driven by one frame kind (`K_Bind`) that stores the binding just
produced and the environment the remaining initializers run in: parallel `let`
evaluates them in the enclosing environment, `let*`/`letrec` in the new one.
`and`/`or` use `K_And`/`K_Or` and return the value that decided them.  `cond`
walks its clauses one at a time through `Start_Cond` -- a failed test returns
to `K_Cond`, which starts the next clause, so the walk rides the evaluator's
run loop instead of needing a loop of its own; `(=> <expression>)` parks the
test value in `K_Cond_App` while the procedure is evaluated and then calls it
with that value.  `case` evaluates its key first (`K_Case`), then scans each
clause's datum list with `Same_Value` -- `memv`'s relation, and `eq?`'s --
matching immediate values by content and heap values by identity.

`call/cc` is the *restricted* form the plan specifies: an escape
continuation, valid only within the dynamic extent that captured it.  The
continuation cell carries no stack snapshot and no depth -- its own handle
**is** the identity, stamped into the capturing frame's `Sym` -- so an
invocation finds its frame by scanning the stack, and "is this still live"
and "where do I deliver" become one test: a frame found is live (its Sym
matches this very cell, so a stale continuation cannot reach a later
activation), and its index is the unwind target -- everything above it is
discarded when `Top` moves down.  A scan miss is `Error_Continuation`
("continuation expired"), which `tests/bad-callcc.scm` triggers by saving a
continuation past its extent.  The procedure runs through a trampoline
frame (`K_CallCC_Recv`) that both its normal return and an escape land on,
which is why the handler after the call needs no phase of its own.

`dynamic-wind before thunk after` is a procedure whose three expressions are
evaluated once, left to right -- R7RS leaves operand order unspecified
(4.1.3), so this is a choice, not a requirement -- then `before` is called,
then `thunk` under a wind frame, then `after` whenever control leaves the
extent, and the form returns the *thunk's* value ("returning the result(s)
of this call").  Six frame kinds carry the six phases (three expression
evaluations, three procedure calls), and the wind frame (`K_Wind`) is what
an escape's scan looks for: it holds the after *procedure*, already
evaluated when the form ran.  On an escape the crossed wind frames are
scanned outwards and their afters consed, so the list runs innermost first
as R7RS requires (the inner call's after before the outer's); the stack is
then truncated to the captured frame and the unwind frame (`K_Unwind`) is
pushed directly on top of it -- so arriving (list exhausted, value in
`Func`) needs no index arithmetic: popping the unwind frame lands exactly
on the target.  Because `call/cc` here is the restricted escape form, a
completed extent's capture frame is gone, so a wind is never *re-entered*
and `before` never re-runs; and because R7RS leaves the effect of entering
or exiting a `before` or `after` extent through a captured continuation
unspecified, an escape firing from inside an `after` during an unwind may
abandon the afters still queued -- which is what v1 does, recorded rather
than papered over (`tests/wind.scm`).

`call-with-values` runs in three phases with a frame kind each: evaluate
the consumer and hold it (`K_Values`), evaluate the producer
(`K_Values_App`), call the producer with no arguments (`K_Values_Recv`),
then spread its values onto the consumer.  Spreading is the whole trick: a
`values` wrapper cell carries its values as a list in `Car` -- the
kind-agnostic marking covers it -- anything else is the single value and
becomes a one-element list.  The primitive keeps R7RS's shape: no values is
a wrapper, one value is that value itself (so it binds and passes like any
other), several become the wrapper.  A wrapper that leaks into a
single-value context (a `define`, say) is a v1 deviation, recorded rather
than checked at every binding site.

`do` runs on three frame kinds, one per phase: `K_Do` receives the test's
value, `K_Do_Body` the body's (discarded), and `K_Do_Step` each step's.
Initializers are bound by the existing `K_Bind`, marked with `Alt = #t` so that
when the last one is stored the frame starts the loop instead of a body.  Each
iteration rebuilds nothing: the frame carries the steps as `(var . step)` pairs
(only bindings that have a step), the test clause, the body and the
environment; steps are all evaluated before `Do_Restart` rebinds anything --
which is what makes them parallel -- and variables without a step are simply
never rebound, so `set!` is the way to change them.

Every sequence-like form (`begin`, a lambda body, `let` bodies, the operands of
`and`/`or`) is in tail position when only one form remains, so no frame is
pushed for it -- the last value goes straight to the parent frame.

## Environments

An environment is a cell containing an association list of
`(symbol . value)` entries and a parent handle.  Lookup walks frames and entries
with explicit depth bounds.  This is deliberately simple; compile-time frame
offsets can replace it later without changing the evaluator interface.

One traversal serves all three operations: `Find_In_Frame` returns the *binding
cell* rather than its value, so `Lookup` reads it while `Define` and `Set`
update it through `Set_Cdr` -- nobody walks a frame twice, and no caller
receives an `out` parameter it would have to ignore.

## Reader and writer

- Reader: bounded recursive descent over a string.  Supports lists, dotted
  pairs, the `'` `` ` `` `,` `,@` shorthands (all built the same way: intern a
  keyword, read one datum, make `(keyword datum)`), booleans, characters,
  strings with escapes, fixnums and symbols.  Symbols are interned by scanning
  existing symbol cells -- `Intern` lives in `Tr7.Heap`, because that is where
  symbols live and the reader, the engine and the quasiquote converter all
  need it.
- Writer: bounded recursive printer with a depth limit, proper-list notation and
  dotted tails.

## Quasiquote

`(quasiquote t)` converts the template into *code* at evaluation time and the
evaluator runs that code: `cons` for structure, `(quote v)` for data, the
unquoted expression itself where a value is wanted, `append` for `,@`, and
`(list 'quasiquote ...)` to rebuild a nested quasiquote as data.  No new frame
kind is needed -- the conversion is one synchronous step, then the generated
code is evaluated in place, so quasiquote is a tail position -- and quoting a
backtick form still behaves like data, because the reader always emits
`(quasiquote ...)` as a datum.

Two mechanics are worth the detail:

- **Nesting.** `Nesting` counts active quasiquotes: an `unquote` at nesting 1
  is an expression, deeper ones are data (`(list 'unquote ...)`), and a
  `(quasiquote ...)` in a template raises the count for its interior.  The
  bound `QQ_Limit` and the `Fuel` budget per call are both far above what a
  reader-produced template can reach (its depth is capped at
  `Max_Reader_Depth`), so the guards that enforce them are safety nets: they
  turn the impossible case into a clean error instead of a stack overflow.
- **The spine walk is a left fold over the reversed list**, which is a right
  fold over the original: elements are collected into a reversed list
  iteratively, the tail is converted once, and then each element conses its
  code in front of what follows -- which is also exactly what makes an `,@`
  element `append` the code built for the rest.  Recursion therefore only ever
  descends into sub-templates (bounded by reader depth), never along a list.

One consequence follows from the data model rather than from choice: the tail
of `` `(a . ,x) `` reads as the list `(unquote x)`, which is *the same datum*
as `(a unquote x)` -- lists are their elements -- so a structural converter
necessarily treats them alike.  `(unquote)` with no argument is rejected as
malformed, which is what R7RS says about an unquote that is not exactly one
operand (`tests/qq.scm`, `tests/bad-qq.scm`).

## Macros

`define-syntax` builds a `Cell_Macro` transformer from a `syntax-rules` form:
the cell's `Car` holds the literals list and its `Cdr` the rules, each a
`(pattern . template)` pair.  A `define-syntax` is installed like any other
definition; when the evaluator reaches an application whose head symbol is
bound to a macro, `Tr7.Macros.Expand` matches the rule patterns against the
form's tail and instantiates the winning template before evaluation continues.
The expansion is evaluated in place, so a macro use is a tail position and a
macro may expand to another macro use.

The matcher and instantiator live in `Tr7.Macros`, separately from both the
evaluator and the heap, because they are recursive over user data and are
proved with a fuel measure (`Subprogram_Variant`) rather than cross-unit heap
reasoning.  Bindings are two association lists -- scalar pattern variables and
ellipsis variables whose values are lists -- so a template ellipsis can
iterate the repeated variables in lockstep.

This is a pragmatic R7RS subset, and the limits are deliberate:

- literals, pattern variables, `_`, multiple rules and recursive macros work;
- **one trailing ellipsis group per list level** is supported.  An ellipsis
  followed by more pattern elements or a dotted tail does not match, and
  nested ellipses are rejected by the matcher;
- expansion is **non-hygienic**: an identifier introduced by a template is an
  ordinary interned symbol.  Macros that introduce their own binders (the
  usual `swap!` shape) work only when those names do not collide with the
  caller's; full hygiene is future work.

The macro cell is an ordinary heap object with no new marking rule: its
literals and rules are reachable through `Car`/`Cdr`, which the collector
already follows.

## Ports

A port is a value over one of two cell kinds -- `Cell_Input_Port` and
`Cell_Output_Port` -- whose text lives **inline in the port itself** (the
same `Max_Text` buffer strings use), with `Arity` doubling as the read
position or the written length.  Carrying the text inline means a port holds
no handle, so the collector needs no extra root for one, and it caps every
port at `Max_Text` bytes: a *string* port, which is what v1 specifies.

The procedures are `open-input-string`, `open-output-string`,
`get-output-string`, `read`, `read-char`, `peek-char`, `char-ready?`,
`port?` and `eof-object?`; `display`, `write` and `newline` take the
optional port argument R7RS gives them and otherwise write to the engine's
buffer, which is what the REPL prints.  `read` returns the `#<eof>` object
(the `Kind_EOF` datum) at the end of its text.

Two shapes recur and are worth naming:

- **the local-buffer bridge**: writing a value into a port runs the writer
  against a local `Output_Buffer` seeded from the port and copies the result
  back in one assignment, because SPARK forbids handing a slice of the heap
  to a procedure that also takes the heap -- and because it makes a full
  buffer atomic (the port is untouched).
- **`read` copies its text to a local buffer** for the same aliasing reason,
  reads one datum at the port's position, and writes the position back
  through `Heap.Set_Port_Pos`.

The OS boundary stays where the plan puts it: `tr7i` loads a file into a
string and prints the engine's output buffer; the verified core never opens
a file.

## Boundary

`tr7` only sees strings and output buffers.  `tr7i` reads files and lines,
calls the engine and prints the resulting buffer.  `tr7_c` is where C
pointers live.

Its package is in SPARK and every signature carries Pre/Post contracts --
pointer alignment, the 0/1 load contract, "the config now holds the
defaults" -- while each subprogram is individually `SPARK_Mode => Off`,
because the bodies use raw addresses, unchecked conversions and C stdio
and are therefore trusted rather than proven (the sparklib idiom).  The
contracts are not documentation-only: the crate builds with `-gnata`, so
they are checked at run time, and `tests/abi_demo.c` exercises every one
of them.

The implemented subset is what a C host needs to run source text:
`tr7_get_id`, `tr7_get_version`, `tr7_config_init_default`,
`tr7_engine_create`, `tr7_engine_destroy`, `tr7_load_string`.  Everything
else the header declares -- 183 symbols in all, six of them here -- is a
zero-returning stub generated by `scripts/gen_abi.py` from
`tr7_c/include/tr7.h`, so a C program links against this library exactly
as against upstream's.  The test re-runs the generator (`--check`) and
`nm`-checks the built archive (`--check-lib`), so neither the header nor
the subset can drift without the gate noticing.

Deviations from upstream, all deliberate: the engine keeps its arena in
Ada's heap, so the custom allocators in `tr7_config_t` are validated as
upstream validates them but never called; `tr7_t` values are not exposed
at all (v1 has no tagged-pointer ABI); output and error text go to this
process's C stdout, where tr7i writes them too.

Linking is the one piece of Ada a C host must know: `gnatbind -n -a`
generates a binder whose `adainit` is a linker constructor, so elaboration
-- the secondary stack among it -- runs before `main`.  Without it the
first call that returns a `String` dies inside `ss_mark`, which is the
signature of missing elaboration rather than of a bad pointer.

## Strings

A string is one cell: a `Max_Text` (256) byte buffer plus its length, so every
string operation is bounded arithmetic on that buffer -- `string-length`,
`string-ref` (0-based, R7RS half-open ranges in `substring`), `string=?`, and
`string-append`, which fails with `Error_Overflow` when the result would not
fit.  Strings are bytes: this is the documented v1 limit, not a Unicode claim.

The reader accepts `#\x41` as a hexadecimal scalar value (a lone `#\x` stays
the character `x`), and the writer prints characters beyond the byte range as
`#\x1234`, so a wide character survives a write/read round trip.

## Vectors

A vector is one cell: `Arity` holds the length and `Car` a proper list of the
elements, so `vector-ref`/`vector-set!` walk to index *i* (O(i), bounded by the
length) while `vector-length` is a field read.  The reader turns `#(...)` into
`(vector ...)` -- the same wrap `'x -> (quote x)` uses -- which is why vector
elements are *expressions*: `#((1 2) 3)` tries to apply `1`, exactly as
`(vector (1 2) 3)` does.

Because a vector stores values in `Car`, the collector's drain marks `Car` and
`Cdr` for **every** cell kind rather than enumerating them: allocation resets
those fields to nil for kinds that do not use them, so nothing is retained
wrongly, and a future cell kind cannot be silently unrooted.  `tests/gc.scm`
keeps a vector alive across three thousand allocations to prove it.

## Bytevectors

A bytevector is the string cell with a different kind: the same `Max_Text`
byte buffer, `Name_Len` as the length, and no value fields at all -- so
`bytevector-u8-ref` and `bytevector-u8-set!` are field accesses (O(1), unlike
a vector's walk), stores go through `Heap.Set_Byte`, and an out-of-bounds
index is `Error_Index` while a value outside 0..255 is `Error_Range`.  The
reader wraps `#u8(1 2 3)` into `(bytevector 1 2 3)` exactly as it does
`#(...)`, and the writer prints `#u8(...)`.

## Numbers

Exact integers are fixnums in `-(2**31) .. 2**31 - 1` (see `Tr7.Config`).  The
range covers everything R7RS requires -- indexes of lists, vectors, bytevectors
and strings, and the results of their `length` procedures -- and it is chosen so
that a product always fits in `Integer_64`.  Multiplication is therefore a
direct multiply plus a range check, with the exactness of the result stated as
a postcondition.  Out-of-range results are reported as `Error_Overflow`, never
silently wrapped or truncated.  A wider fixnum would require a wide multiply
whose exactness the SMT provers cannot discharge; `docs/findings.md` records
the measurements and the route back (big-integer contracts).

`/` has the no-rationals rule: exact when every step divides evenly, the
inexact double otherwise (`(/ 6 3)` is `2`, `(/ 1 2)` is `0.5`), one
flonum anywhere making the chain inexact.  Its float division branches the
way the provers can discharge -- a divisor of at least one, or both
operands inside a fixed window whose ratio fits the range -- and reports an
overflow rather than producing an infinity.

Exact division follows Scheme through Ada: `quotient` is Ada's `/`
(truncation toward zero), `remainder` is `rem` (dividend's sign) and `modulo`
is `mod` (divisor's sign) -- all three share one guard for a zero divisor and
for the single product `Fixnum_Min / -1` that no fixnum holds.  `abs` rejects
`Fixnum_Min` for the same reason, and `expt` is fixnum-only: powers of 0, 1
and -1 are answered without a loop, any exponent above 63 overflows (a base of
at least 2 cannot stay in a fixnum longer), and a negative power of anything
else is `not implemented` because v1 has no rationals.

## Flonums

A flonum is an IEEE double in the value record -- immediate like a fixnum, no
cell, invisible to the collector.  The reader parses decimals with at most one
rounding (a single multiply or divide by an exact power of ten, which exists up
to `10**22`), the writer prints the shortest string that reads back to the same
value (increasing precision until `Parse_Float` agrees, with `%g`'s choice
between fixed and scientific notation), and `exact->inexact` converts a fixnum
to the nearest double.

Arithmetic and comparison switch paths when any operand is inexact: one
inexact operand makes the whole operation inexact (R7RS), every operand still
has to be a number, and a NaN makes every comparison false for free.

`sqrt` is exact when the argument is exact and the root is (R7RS) -- an
integer binary search settles that without touching a float -- and otherwise
Newton's method seeded from the value's own binary exponent, followed by two
*exact* comparisons: `Sq_Le` and `Mid_Le` compare squares and the midpoint's
square on `Interfaces.Integer_128` (a double's mantissa squared needs at most
109 bits, which fits), so the floor and the rounding decision are exact where
a floating-point product would tie.  That is what makes `(sqrt 2)` come out
`1.4142135623730951`, the same double libm returns.

## Errors

Primitives report `Error_Code`, not a bare boolean: `Call` returns
`No_Error`, `Error_Type`, `Error_Wrong_Arity`, `Error_Overflow`,
`Error_Heap_Full` or `Error_Output_Full`.  The evaluator turns the code into a
Scheme error at the application point, and `tr7i` prints
`error: <name>` while keeping everything the program printed before the error.
Every path through `Call` that does not report success reports a type error, so
a missing assignment can only produce an error, never silence.

`(error message irritant ...)` is Scheme's own raiser and the one code with a
text: the primitive assembles the message with its irritants displayed after
it, parks the string in `Heap.Error_Msg` -- a primitive sees the heap, not the
machine, which is why the slot lives there -- and returns `Error_User`.  The
slot is cleared at the start of every evaluation, marked defensively by the
collector (copied to a local first: a component of H cannot travel with H),
and `tr7i` prefers it over the generic code name, so a program prints
`error: boom 1 2` while everything it printed beforehand still appears.

## Garbage collection

The arena is collected by a mark-sweep collector that only ever runs at a
**safe point**: the top of the evaluator loop, between steps, plus (for the
next datum) in the engine's read loop.  At those points the CEK state -- control,
result, current environment and every continuation frame -- plus the global
environment are a *complete* root set, and no step-local object is alive.

- `Tr7.Machine.Collect_Garbage` resolves that state to a list of live cells
  (`Tr7.Heap.Live_Cell`, the one place that decides whether a handle is still
  live) and calls `Tr7.Heap.Collect` with the list.  There is no separate
  `Mark_Root` entry point.
- `Collect` first *jumps the epoch* past every mark in the arena, so each
  cycle provably starts clean inside `Collect` itself; no call site has to
  reason about what a previous collection left behind.  It then marks the
  root list and drains a bounded worklist (a cell is pushed at most once, so
  `Max_Cells` entries suffice).
- The drain's invariants deliberately say nothing about closure.  Closure --
  "every marked cell has its `Car`, `Cdr` and (for closures/environments)
  `Env` marked" -- is checked afterwards by a **read-only verification
  scan**.  Because the scan writes nothing, its quantified invariants are
  preserved trivially, and a failure only sets `Mark_Failed` (the cycle is
  abandoned, so garbage is left in place but nothing live is ever freed).
  This split is what keeps the collector linear and the proof small: putting
  the quantified closure fact inside the drain forced the prover to reason
  about array-of-record updates under a quantifier (see `docs/findings.md`).
- The sweep lives in `Tr7.Reach`, which proves the M5 liveness goal: the
  worklist drained and the marked set is closed, so a fuel-bounded
  `Reachable` predicate plus a path-induction lemma show every cell reachable
  from a root is marked, and the sweep only frees cells whose mark epoch is
  not the current one.
- Marks are epochs, not bits: a cell is marked when `Mark_Epoch = Epoch`, and
  `Epoch` advances at the start of every collection, retiring the whole
  cycle's marks in one assignment.  That removes both the clearing pass over
  the arena and the quantified loop invariant that `-gnata` would evaluate at
  run time (4,096 x 4,096 tests per collection -- `docs/findings.md`).  After
  2**64 cycles `Collect_Stopped` latches and the collector stops freeing
  altogether rather than ever sweeping against a stale epoch.
- If marking cannot complete (a full worklist, exhausted rounds, or a failed
  verification scan), the cycle is abandoned: every mark is dropped and *no*
  cell is freed.  A failed collection therefore only leaves garbage in place;
  it can never free a live object.
- Trigger: `H.Free_Count <= GC_Low_Water` (512 cells) at a safe point, or a
  fixed cadence under `--stress-gc` (`GC_Stress_Every`, 8).
- The reader never allocates while a collection can run, so reader temporaries
  are never at risk; a datum that alone exceeds the free space is reported as
  `heap exhausted`.

Tail calls matter to the collector as much as to the stack: the last form of a
lambda body and the last form of a `begin` are in tail position and push **no**
frame, so recursion keeps a constant-size root set (and constant stack space).

## Runtime checks are a build property

No source file selects an assertion policy.  `tr7.gpr` picks the switches from
the `TR7_CHECKS` scenario, and every project in the graph inherits it:

- `TR7_CHECKS=on` (default): `-gnata`, so preconditions, postconditions,
  overflow and index checks are live while the suites run.  This is what tests
  and proofs use, and what `prove.sh` and `test.sh` force.
- `TR7_CHECKS=off`: `-gnatp`, no contract evaluation at run time.  Benchmarks
  only -- quantified loop invariants cost O(n^2) under `-gnata`
  (`docs/findings.md`), so timing a checked build measures the checker.

GNATprove checks loop invariants and contracts in both cases; a `-gnatp` build
would make it *skip* obligations, which is why `prove.sh` pins the scenario.
