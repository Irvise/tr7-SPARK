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
      K_Do_Step,
      --  call-with-values: the consumer expression has been evaluated; its
      --  value arrives next while the producer expression waits in Expr.
      K_Values,
      --  call-with-values: the consumer's value waits in Func while the
      --  producer expression is evaluated.
      K_Values_App,
      --  call-with-values: the producer closure is being called with no
      --  arguments; its values arrive next, to be spread onto the consumer
      --  waiting in Func.
      K_Values_Recv,
      --  call/cc: the procedure expression is being evaluated; its value
      --  arrives next, to be given the continuation held in Expr's result.
      K_CallCC,
      --  eval: the environment expression has been evaluated and its value
      --  waits in the popped frame's place; the expression to evaluate is in
      --  Expr and the environment to use is the result.
      K_Eval,
      --  eval: the environment value has been checked; the expression
      --  argument is being evaluated in the caller's environment and its
      --  value will be evaluated in the environment held in this frame.
      K_Eval_Expr,
      --  dynamic-wind: the `before` expression is being evaluated; its
      --  value (the before procedure) arrives next and rides in Func while
      --  the thunk expression is evaluated.  Expr holds the thunk
      --  expression, Alt the after expression.
      K_DW_Before,
      --  dynamic-wind: the thunk expression is being evaluated; on return
      --  the after expression moves to Expr for its turn, the thunk
      --  procedure rides in Alt, and before's still waits in Func.
      K_DW_Thunk,
      --  dynamic-wind: the after expression is being evaluated; on return
      --  all three procedures are in hand and `before` is called.
      K_DW_After,
      --  dynamic-wind: `before` has been called; on return `thunk` is
      --  called, with Expr still holding the after procedure for later.
      K_DW_Call,
      --  dynamic-wind: the thunk is running with this frame on the stack,
      --  which is exactly what an escape's scan looks for; Expr holds the
      --  after procedure to call when the thunk returns.
      K_Wind,
      --  dynamic-wind: the after procedure has been called; Func holds the
      --  thunk's value, which is the form's value.
      K_Wind_After,
      --  escape: the after procedures crossed by the unwind, innermost
      --  first, in Args; Func is the value to deliver.  The frame sits
      --  directly on the captured frame, so when the list runs out,
      --  popping it lands exactly on the target.
      K_Unwind);

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
