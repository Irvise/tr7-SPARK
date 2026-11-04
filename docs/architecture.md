# Architecture

## Crates

- `tr7` -- verified core.  `SPARK_Mode => On`, no OS code, no crate
  dependencies.
- `tr7i` -- REPL and script runner.  Trusted boundary for console and file I/O.
- `tr7_c` -- C ABI subset.  Trusted boundary, added after the core stabilises.

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
`when`, `unless`, `case`, and procedure application.  `let` and its
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
  pairs, quote, booleans, characters, strings with escapes, fixnums and symbols.
  Symbols are interned by scanning existing symbol cells.
- Writer: bounded recursive printer with a depth limit, proper-list notation and
  dotted tails.

## Boundary

`tr7` only sees strings and output buffers.  `tr7i` reads files and lines,
calls the engine and prints the resulting buffer.  The C ABI layer will convert
between `tr7_t` and core handles at the boundary.

## Strings

A string is one cell: a `Max_Text` (256) byte buffer plus its length, so every
string operation is bounded arithmetic on that buffer -- `string-length`,
`string-ref` (0-based, R7RS half-open ranges in `substring`), `string=?`, and
`string-append`, which fails with `Error_Overflow` when the result would not
fit.  Strings are bytes: this is the documented v1 limit, not a Unicode claim.

The reader accepts `#\x41` as a hexadecimal scalar value (a lone `#\x` stays
the character `x`), and the writer prints characters beyond the byte range as
`#\x1234`, so a wide character survives a write/read round trip.

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

## Errors

Primitives report `Error_Code`, not a bare boolean: `Call` returns
`No_Error`, `Error_Type`, `Error_Wrong_Arity`, `Error_Overflow`,
`Error_Heap_Full` or `Error_Output_Full`.  The evaluator turns the code into a
Scheme error at the application point, and `tr7i` prints
`error: <name>` while keeping everything the program printed before the error.
Every path through `Call` that does not report success reports a type error, so
a missing assignment can only produce an error, never silence.

## Garbage collection

The arena is collected by a mark-sweep collector that only ever runs at a
**safe point**: the top of the evaluator loop, between steps, plus (for the
next datum) in the engine's read loop.  At those points the CEK state -- control,
result, current environment and every continuation frame -- plus the global
environment are a *complete* root set, and no step-local object is alive.

- `Tr7.Machine.Collect_Garbage` roots that state with `Tr7.Heap.Mark_Root` and
  then calls `Tr7.Heap.Collect`.
- `Collect` drains a bounded mark stack (each cell is pushed at most once, so
  `Max_Cells` entries suffice), then sweeps every cell whose mark *epoch* is
  not the current cycle's back onto the free list, in place, without touching
  their generation -- the generation check on the next allocation is what
  rejects stale handles.
- Marks are epochs, not bits: a cell is marked when `Mark_Epoch = Epoch`, and
  `Epoch` advances after every sweep, retiring the whole cycle's marks in one
  assignment.  That removes both the clearing pass over the arena and, with it,
  the quantified loop invariant that `-gnata` evaluates at run time (4,096 x
  4,096 tests per collection -- `docs/findings.md`).  After 2**64 cycles
  `Collect_Stopped` latches and the collector stops freeing altogether rather
  than ever sweeping against a stale epoch.
- If marking cannot complete (a full mark stack), the cycle is abandoned: every
  mark is dropped and *no* cell is freed.  A failed collection therefore only
  leaves garbage in place; it can never free a live object.  `Collect` has no
  success flag because the heap is left exactly as it was.
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
