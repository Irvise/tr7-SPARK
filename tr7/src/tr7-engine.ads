--  Interpreter engine.
--
--  The engine owns the heap, the global environment and the output buffer.  It
--  contains no OS code: files and consoles live in the tr7i boundary.

with Tr7.Heap; use Tr7.Heap;
with Tr7.Machine;
with Tr7.Runtime; use Tr7.Runtime;
with Tr7.Values; use Tr7.Values;

package Tr7.Engine with
   SPARK_Mode => On
is

   type Engine is limited record
      H      : Heap_Type;
      Global : Handle := Null_Handle;
      Output : Output_Buffer;
      M      : Tr7.Machine.Machine;
      Ready  : Boolean := False;
   end record;

   procedure Initialize
     (E  : out Engine;
      Ok : out Boolean)
     with Post => (if Ok then E.Ready);

   procedure Evaluate
     (E      : in out Engine;
      Source : String;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => E.Ready
         and then Source'First = 1;

   procedure Print_Value
     (E       : in out Engine;
      V       : Value;
      Display : Boolean;
      Ok      : out Boolean)
     with Pre => E.Ready;

   procedure Reset_Output (E : in out Engine)
     with Pre => E.Ready;

   function Output_Text (E : Engine) return String
     with Pre => E.Ready;

end Tr7.Engine;
