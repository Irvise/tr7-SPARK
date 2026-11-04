--  Primitive procedures.
--
--  Dispatch is an enumeration plus a case statement, not a table of access to
--  subprogram values, which keeps the verified core simple.

with Tr7.Heap; use Tr7.Heap;
with Tr7.Ids; use Tr7.Ids;
with Tr7.Runtime; use Tr7.Runtime;
with Tr7.Values; use Tr7.Values;

package Tr7.Primitives with
   SPARK_Mode => On
is

   function Name_Of (P : Primitive_Id) return String;

   procedure Call
     (H      : in out Heap_Type;
      P      : Primitive_Id;
      Args   : Value;
      Result : out Value;
      B      : in out Output_Buffer;
      Ok     : out Boolean)
     with Pre => H.Ready;

end Tr7.Primitives;
