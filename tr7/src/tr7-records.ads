--  define-record-type / SRFI-9 records.
--
--  A record is an ordinary vector whose slot 0 is the record-type name
--  symbol (a quoted datum).  The form is rewritten into a begin of
--  definitions for the constructor, predicate, accessors and optional
--  modifiers, so no new cell kind or evaluator frame is needed.

with Tr7.Heap; use Tr7.Heap;
with Tr7.Values; use Tr7.Values;

package Tr7.Records with
   SPARK_Mode => On
is

   procedure Build
     (H      : in out Heap_Type;
      Form   : Value;
      Result : out Value;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready;

end Tr7.Records;
