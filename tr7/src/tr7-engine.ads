--  Interpreter engine.
--
--  The engine owns the heap, the global environment and the output buffer.  It
--  contains no OS code: files and consoles live in the tr7i boundary.
--
--  Readiness is a single fact: the heap is ready.  Keeping one flag instead of
--  a separate boolean plus a heap flag means every precondition can be
--  established by the caller without an extra link invariant.

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
   end record;

   procedure Initialize
     (E  : out Engine;
      Ok : out Boolean)
     with Post => E.H.Ready;

   procedure Evaluate
     (E      : in out Engine;
      Source : String;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => E.H.Ready
         and then Source'First = 1
         and then Source'Last <= Natural'Last - 2,
       Post => E.H.Ready;

   procedure Print_Value
     (E       : in out Engine;
      V       : Value;
      Display : Boolean;
      Ok      : out Boolean)
     with
       Pre  => E.H.Ready,
       Post => E.H.Ready;

   procedure Set_Stress_GC (E : in out Engine; Enabled : Boolean)
     with
       Pre  => E.H.Ready,
       Post => E.H.Ready and then E.H.Stress_GC = Enabled;

   procedure Reset_Output (E : in out Engine)
     with Pre => E.H.Ready;

   function Output_Text (E : Engine) return String
     with Pre => E.H.Ready;

   --  The text of a raised (error ...), or the empty string when the
   --  failure carried none and only its Error_Code name applies.
   function Error_Message (E : Engine) return String
     with Pre => E.H.Ready;

end Tr7.Engine;
