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
