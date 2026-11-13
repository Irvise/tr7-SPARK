--  syntax-rules transformers.
--
--  A pragmatic R7RS subset: literals, pattern variables, `_`, and one
--  trailing ellipsis group per list level.  Expansion is non-hygienic:
--  identifiers introduced by a template are ordinary interned symbols.  The
--  common macro shapes -- (name body ...), (name x y ...), nested lists with
--  a trailing ellipsis -- work; nested ellipses and ellipses followed by a
--  dotted tail are rejected (the rule simply does not match).
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
