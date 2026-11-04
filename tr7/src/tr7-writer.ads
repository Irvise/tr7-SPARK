--  Datum writer.

with Tr7.Heap; use Tr7.Heap;
with Tr7.Runtime; use Tr7.Runtime;
with Tr7.Values; use Tr7.Values;

package Tr7.Writer with
   SPARK_Mode => On
is

   procedure Write_Value
     (H       : Heap_Type;
      V       : Value;
      B       : in out Output_Buffer;
      Ok      : out Boolean;
      Display : Boolean := False)
     with Pre => H.Ready;

end Tr7.Writer;
