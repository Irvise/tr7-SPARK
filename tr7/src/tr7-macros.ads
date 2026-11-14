--  syntax-rules transformers.
--
--  Pattern matching supports literals, pattern variables, `_`, and nested
--  ellipses, with one trailing repetition group per list level.  Repetitions
--  are stored as trees: a variable under d ellipses maps to a value at depth
--  d, represented by an internal Cell_Values node whose Car is the next
--  level's list.  A path of ellipsis indices lets a template descend the
--  tree, so (a b ...) ... and deeper nestings expand correctly.
--
--  Instantiation is hygienic for binders introduced by the template
--  (lambda, let, let*, letrec, letrec*, named let, do and internal define):
--  each binder is a fresh %h... symbol, and a lexical rename environment
--  follows its scoped occurrences.  Pattern variables, literals and free
--  references are left alone; quote contents are data (pattern variables
--  inside them still substitute).  Not supported: an ellipsis followed by a
--  dotted tail, a second repetition group at the same list level, and
--  per-iteration names for binders that are themselves under an ellipsis.
--
--  This unit is separate from the evaluator so the recursive matcher and
--  instantiator can be proved in isolation, with a fuel measure instead of
--  cross-unit heap reasoning.

with Tr7.Heap; use Tr7.Heap;
with Tr7.Values; use Tr7.Values;

package Tr7.Macros with
   SPARK_Mode => On
is

   --  Turn the value of a (syntax-rules (literal ...) (pattern template) ...)
   --  form into a macro cell.
   procedure Build
     (H      : in out Heap_Type;
      Spec   : Value;
      Result : out Value;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready and then (if Ok then Is_Handle (Result));

   --  Expand one use of Macro.  Form is the whole (name argument ...) form;
   --  the macro name itself is not matched (patterns are matched on their
   --  tails, as R7RS specifies).
   procedure Expand
     (H      : in out Heap_Type;
      Macro  : Handle;
      Form   : Value;
      Result : out Value;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready;

end Tr7.Macros;
