--  A small Scheme prelude for the SRFI procedures that are naturally
--  higher-order.  It is evaluated once when the engine is initialized, so
--  the definitions live in the global environment like the primitives.
--  Keeping them in Scheme means the evaluator, not a primitive table, calls
--  user procedures; the source is fixed and covered by the suites.

package Tr7.Prelude with
   SPARK_Mode => On
is

   function Source return String
     with Post => Source'Result'First = 1
       and then Source'Result'Length <= 10_000
       and then Source'Result'Last <= Natural'Last - 2;

end Tr7.Prelude;
