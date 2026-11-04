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

Supported forms in M0: `quote`, `if`, `lambda`, `define`, `set!`, `begin`, and
procedure application.

## Environments

An environment is a cell containing an association list of
`(symbol . value)` entries and a parent handle.  Lookup walks frames and entries
with explicit depth bounds.  This is deliberately simple; compile-time frame
offsets can replace it later without changing the evaluator interface.

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
