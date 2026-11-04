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
      K_Argument,
      --  let / let* / letrec: bind the value that was just evaluated, then
      --  start the next initializer or the body.
      K_Bind,
      --  and / or: stop as soon as the value decides the answer.
      K_And,
      K_Or,
      --  cond: the test of the current clause has been evaluated, so the rest
      --  of that clause and the remaining clauses decide what happens next.
      K_Cond,
      --  cond with =>: the procedure to call has been evaluated and the value
      --  of the test is waiting in Alt.
      K_Cond_App,
      --  when / unless: run the body only if the test agrees with the form.
      K_When,
      K_Unless,
      --  case: the key has been evaluated and the clauses are waiting.
      K_Case,
      --  map / for-each: waiting for the procedure called on the current
      --  heads; the accumulated results ride in Expr and the map/for-each
      --  choice in Alt.
      K_Map,
      --  do: the test of the current iteration has been evaluated.
      K_Do,
      --  do: the body of the current iteration has run; the steps follow.
      K_Do_Body,
      --  do: one step expression has been evaluated and its value is waiting
      --  to be collected before the next step starts.
      K_Do_Step);

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

   --  Collect the heap, rooting the machine state and the global environment.
   --
   --  This is only correct at a safe point -- between steps, where the CEK
   --  state plus Env are the whole of the live data -- which is where the
   --  evaluator and the engine call it.  When marking cannot complete the
   --  cycle is abandoned and the heap is left exactly as it was, so the only
   --  effect of a failed collection is that less garbage is reclaimed.
   procedure Collect_Garbage
     (H   : in out Heap_Type;
      Env : Handle;
      M   : Machine)
     with
       Pre  => H.Ready,
       Post => H.Ready
         and then H.Mark_Top = 0
         and then H.Free_Count >= H.Free_Count'Old;

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
