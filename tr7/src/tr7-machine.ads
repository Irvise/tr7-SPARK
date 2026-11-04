--  CEK-style evaluator.
--
--  The machine state is (mode, control, environment, continuation stack).  A
--  closure application does not push a frame, so tail calls consume constant
--  stack.  Continuation frames are plain records in a bounded array.

with Tr7.Config; use Tr7.Config;
with Tr7.Heap; use Tr7.Heap;
with Tr7.Runtime; use Tr7.Runtime;
with Tr7.Values; use Tr7.Values;

package Tr7.Machine with
   SPARK_Mode => On
is

   type Mode_Kind is (Mode_Eval, Mode_Return, Mode_Halt);

   type Frame_Kind is
     (K_If,
      K_Begin,
      K_Define,
      K_Set,
      K_Operator,
      K_Argument);

   type Frame is record
      Kind : Frame_Kind := K_If;
      Expr : Value := Nil_Value;
      Alt  : Value := Nil_Value;
      Func : Value := Nil_Value;
      Args : Value := Nil_Value;
      Env  : Handle := Null_Handle;
      Sym  : Value := Nil_Value;
   end record;

   type Frame_Array is array (1 .. Max_Stack) of Frame;

   type Machine is record
      Mode   : Mode_Kind := Mode_Halt;
      Ctl    : Value := Nil_Value;
      Env    : Handle := Null_Handle;
      Stack  : Frame_Array := (others => (others => <>));
      Top    : Natural range 0 .. Max_Stack := 0;
      Result : Value := Nil_Value;
      Error  : Error_Code := No_Error;
   end record;

   procedure Evaluate
     (H      : in out Heap_Type;
      Env    : Handle;
      Expr   : Value;
      M      : in out Machine;
      B      : in out Output_Buffer)
     with
       Pre  => H.Ready,
       Post => H.Ready;

end Tr7.Machine;
