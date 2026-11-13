--  Runtime-wide definitions shared by the evaluator and primitives.

package Tr7.Runtime with
   SPARK_Mode => On
is

   type Error_Code is
     (No_Error,
      Error_Unbound,
      Error_Not_A_Procedure,
      Error_Wrong_Arity,
      Error_Type,
      Error_Heap_Full,
      Error_Parse,
      Error_Division_By_Zero,
      Error_Not_Implemented,
      Error_Step_Limit,
      Error_Malformed,
      Error_EOF,
      Error_Overflow,
      Error_Output_Full,
      Error_Index,
      Error_Range,
      --  Scheme's own (error ...), whose text lives in Heap.Error_Msg.
      Error_User,
      --  A continuation invoked outside the dynamic extent it captured.
      Error_Continuation,
      --  The environment chain is deeper than Max_Env_Depth.
      Error_Env_Depth);

   Max_Output : constant := 4_096;

   type Output_Array is array (1 .. Max_Output) of Character;

   type Output_Buffer is record
      Data : Output_Array := (others => ' ');
      Len  : Natural range 0 .. Max_Output := 0;
   end record;

   procedure Put_Char
     (B  : in out Output_Buffer;
      C  : Character;
      Ok : out Boolean)
     with
       Post => (if Ok then B.Len = B.Len'Old + 1 else B.Len = B.Len'Old);

   procedure Put_String
     (B  : in out Output_Buffer;
      S  : String;
      Ok : out Boolean)
     with
       Pre  => S'First >= 1 and then S'Last < Natural'Last,
       Post => (if Ok then B.Len = B.Len'Old + S'Length else B.Len = B.Len'Old);

   procedure Reset_Output (B : out Output_Buffer);

   function Error_Name (E : Error_Code) return String;

end Tr7.Runtime;
