with Tr7.Cells; use Tr7.Cells;
with Tr7.Env; use Tr7.Env;
with Tr7.Pairs; use Tr7.Pairs;
with Tr7.Primitives; use Tr7.Primitives;

package body Tr7.Machine with
   SPARK_Mode => On
is


   function Is_Symbol_Named
     (H    : Heap_Type;
      V    : Value;
      Name : String) return Boolean
     with
       Pre => H.Ready and then Name'First >= 1
   is
      C     : Cell;
      Valid : Boolean;
   begin
      if not Is_Handle (V) then
         return False;
      end if;
      Fetch (H, To_Handle (V), C, Valid);
      return Valid
        and then C.Kind = Cell_Symbol
        and then C.Name_Len = Name'Length
        and then C.Name (1 .. C.Name_Len) = Name;
   end Is_Symbol_Named;

   procedure Push
     (M  : in out Machine;
      F  : Frame;
      Ok : out Boolean)
     with
       Post => (if Ok then M.Top = M.Top'Old + 1 else M.Top = M.Top'Old)
   is
   begin
      if M.Top = Max_Stack then
         Ok := False;
         return;
      end if;
      M.Top := M.Top + 1;
      M.Stack (M.Top) := F;
      Ok := True;
   end Push;

   procedure Pop
     (M  : in out Machine;
      F  : out Frame;
      Ok : out Boolean)
     with
       Post => (if Ok then M.Top = M.Top'Old - 1 else M.Top = M.Top'Old)
   is
   begin
      F := (Kind => K_If, others => <>);
      if M.Top = 0 then
         Ok := False;
         return;
      end if;
      F := M.Stack (M.Top);
      M.Top := M.Top - 1;
      Ok := True;
   end Pop;

   procedure Fail (M : in out Machine; E : Error_Code) is
   begin
      M.Error := E;
      M.Mode := Mode_Halt;
   end Fail;

   procedure Bind_Params
     (H      : in out Heap_Type;
      Params : Value;
      Args   : Value;
      Env    : Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      P : Value := Params;
      A : Value := Args;
      Sym : Value;
      Val : Value;
      Next : Value;
      Good : Boolean;
   begin
      Ok := False;
      loop
         pragma Loop_Invariant (H.Ready);
         if Is_Nil (P) then
            Ok := Is_Nil (A);
            return;
         end if;
         if Is_Nil (A) then
            return;
         end if;

         Car_Of (H, P, Sym, Good);
         if not Good or else not Is_Handle (Sym) then
            return;
         end if;
         Car_Of (H, A, Val, Good);
         if not Good then
            return;
         end if;
         Tr7.Env.Define (H, Env, Sym, Val, Good);
         if not Good then
            return;
         end if;
         Cdr_Of (H, P, Next, Good);
         if not Good then
            return;
         end if;
         P := Next;
         Cdr_Of (H, A, Next, Good);
         if not Good then
            return;
         end if;
         A := Next;
      end loop;
   end Bind_Params;

   procedure Apply_Procedure
     (H    : in out Heap_Type;
      Func : Value;
      Args : Value;
      M    : in out Machine;
      B    : in out Output_Buffer)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      C     : Cell;
      Valid : Boolean;
      Good  : Boolean;
      Res   : Value;
      Arity : Natural;
      New_Env : Handle;
      Prim_Status : Error_Code;
      Lambda_Body : Value;
      First : Value;
      Rest  : Value;
      F     : Frame;
   begin
      if not Is_Handle (Func) then
         Fail (M, Error_Not_A_Procedure);
         return;
      end if;

      Fetch (H, To_Handle (Func), C, Valid);
      if not Valid then
         Fail (M, Error_Not_A_Procedure);
         return;
      end if;

      case C.Kind is
         when Cell_Primitive =>
            Call (H, C.Prim, Args, Res, B, Prim_Status);
            if Prim_Status /= No_Error then
               Fail (M, Prim_Status);
               return;
            end if;
            M.Result := Res;
            M.Mode := Mode_Return;

         when Cell_Closure =>
            Length (H, Args, Arity, Good);
            if not Good or else Arity /= C.Arity then
               Fail (M, Error_Wrong_Arity);
               return;
            end if;

            Tr7.Env.New_Environment (H, C.Env, New_Env, Good);
            if not Good then
               Fail (M, Error_Heap_Full);
               return;
            end if;

            Bind_Params (H, C.Car, Args, New_Env, Good);
            if not Good then
               Fail (M, Error_Wrong_Arity);
               return;
            end if;

            Lambda_Body := C.Cdr;
            if Is_Nil (Lambda_Body) then
               M.Result := Unspecified_Value;
               M.Env := New_Env;
               M.Mode := Mode_Return;
               return;
            end if;

            Car_Of (H, Lambda_Body, First, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            Cdr_Of (H, Lambda_Body, Rest, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;

            if Is_Nil (Rest) then
               --  Single-form body: the form is in tail position, so no frame
               --  is pushed and recursion runs in constant stack space.  The
               --  value it produces is delivered straight to the caller's
               --  frame, which is exactly what the pass-through frame did.
               M.Ctl := First;
               M.Env := New_Env;
               M.Mode := Mode_Eval;
               return;
            end if;

            F := (Kind => K_Begin,
                  Expr => Rest,
                  Env  => New_Env,
                  others => <>);
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;

            M.Ctl := First;
            M.Env := New_Env;
            M.Mode := Mode_Eval;

         when others =>
            Fail (M, Error_Not_A_Procedure);
      end case;
   end Apply_Procedure;

   procedure Eval_Symbol
     (H : Heap_Type;
      M : in out Machine)
     --  H is read-only here, so there is nothing to restore and no post is
     --  needed: the caller keeps every fact it had about the heap.
     with Pre => H.Ready
   is
      Val : Value;
      Ok  : Boolean;
   begin
      Tr7.Env.Lookup (H, M.Env, M.Ctl, Val, Ok);
      if not Ok then
         Fail (M, Error_Unbound);
         return;
      end if;
      M.Result := Val;
      M.Mode := Mode_Return;
   end Eval_Symbol;

   --  Enter the first form of a body in Env.  A sequence frame is pushed only
   --  when further forms follow: the last form is in tail position, so its
   --  value must reach the parent frame without an extra hop (and without an
   --  extra frame on the stack).
   procedure Start_Body
     (H    : Heap_Type;
      M    : in out Machine;
      Forms : Value;
      Env  : Handle)
     with Pre => H.Ready
   is
      First : Value;
      Rest  : Value;
      F     : Frame;
      Good  : Boolean;
   begin
      if Is_Nil (Forms) then
         M.Result := Unspecified_Value;
         M.Mode := Mode_Return;
         return;
      end if;

      Car_Of (H, Forms, First, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Cdr_Of (H, Forms, Rest, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      if not Is_Nil (Rest) then
         F := (Kind => K_Begin,
               Expr => Rest,
               Env  => Env,
               others => <>);
         Push (M, F, Good);
         if not Good then
            Fail (M, Error_Step_Limit);
            return;
         end if;
      end if;

      M.Ctl := First;
      M.Env := Env;
      M.Mode := Mode_Eval;
   end Start_Body;

   --  Split (<variable> <expression>) into its two parts, rejecting the forms
   --  R7RS does not allow: no initializer, or extra expressions.
   procedure Split_Binding
     (H    : Heap_Type;
      B    : Value;
      Var  : out Value;
      Init : out Value;
      Ok   : out Boolean)
     with Pre => H.Ready
   is
      Tail : Value;
      More : Value;
      Good : Boolean;
   begin
      Init := Nil_Value;
      Ok   := False;

      Car_Of (H, B, Var, Good);
      if not Good or else not Is_Handle (Var) then
         return;
      end if;
      Cdr_Of (H, B, Tail, Good);
      if not Good or else Is_Nil (Tail) then
         return;
      end if;
      Car_Of (H, Tail, Init, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Tail, More, Good);
      if not Good or else not Is_Nil (More) then
         return;
      end if;
      Ok := True;
   end Split_Binding;

   --  let, let* and letrec differ only in where the initializers run: all in
   --  the enclosing environment (parallel bindings), or in the new environment
   --  as each binding is added.  letrec needs no special case: its initializers
   --  also run in the new environment, and R7RS requires referencing a binding
   --  before its initializer has run to be an error -- which is exactly the
   --  unbound-variable error a missing binding gives here.
   type Let_Style is (Let_Parallel, Let_Sequential);

   procedure Start_Let
     (H     : in out Heap_Type;
      M     : in out Machine;
      Style : Let_Style)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Bindings : Value;
      Forms    : Value;
      New_Env  : Handle;
      Eval_Env : Handle;
      First_B  : Value;
      Rest_B   : Value;
      Var      : Value;
      Init     : Value;
      F        : Frame;
      Good     : Boolean;
   begin
      --  The keyword is the head of M.Ctl: cadr holds the bindings, cddr the
      --  body.
      Cadr_Of (H, M.Ctl, Bindings, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Cddr_Of (H, M.Ctl, Forms, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      Tr7.Env.New_Environment (H, M.Env, New_Env, Good);
      if not Good then
         Fail (M, Error_Heap_Full);
         return;
      end if;

      if Is_Nil (Bindings) then
         Start_Body (H, M, Forms, New_Env);
         return;
      end if;

      Car_Of (H, Bindings, First_B, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Cdr_Of (H, Bindings, Rest_B, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Split_Binding (H, First_B, Var, Init, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      --  Parallel bindings evaluate every initializer where the let form
      --  appears; sequential ones evaluate it in the environment built so far.
      if Style = Let_Parallel then
         Eval_Env := M.Env;
      else
         Eval_Env := New_Env;
      end if;

      F := (Kind => K_Bind,
            Sym  => Var,
            Args => Rest_B,
            Func => From_Handle (New_Env),
            Expr => Forms,
            Env  => Eval_Env,
            others => <>);
      Push (M, F, Good);
      if not Good then
         Fail (M, Error_Step_Limit);
         return;
      end if;

      M.Ctl := Init;
      M.Env := Eval_Env;
      M.Mode := Mode_Eval;
   end Start_Let;

   --  Enter the next cond clause.  Advancing after a failed test comes back
   --  here, so the clause walk happens one step at a time and needs no loop of
   --  its own: the evaluator's run loop is the driver.
   procedure Start_Cond
     (H       : Heap_Type;
      M       : in out Machine;
      Clauses : Value)
     with Pre => H.Ready
   is
      --  SPARK forbids passing a component of M together with M itself, so the
      --  environment the clause forms run in is snapshotted on entry.  Both
      --  callers have already put the right environment in M.Env.
      Clause_Env : constant Handle := M.Env;
      Clause : Value;
      Rest   : Value;
      Test   : Value;
      Forms  : Value;
      F      : Frame;
      Good   : Boolean;
   begin
      if Is_Nil (Clauses) then
         M.Result := Unspecified_Value;
         M.Mode := Mode_Return;
         return;
      end if;

      Car_Of (H, Clauses, Clause, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Cdr_Of (H, Clauses, Rest, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Car_Of (H, Clause, Test, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      if Is_Symbol_Named (H, Test, "else") then
         --  else has no test: it runs its body, and R7RS requires it to be the
         --  last clause.
         if not Is_Nil (Rest) then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Clause, Forms, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Start_Body (H, M, Forms, Clause_Env);
         return;
      end if;

      F := (Kind => K_Cond,
            Args => Clause,
            Expr => Rest,
            Env  => Clause_Env,
            others => <>);
      Push (M, F, Good);
      if not Good then
         Fail (M, Error_Step_Limit);
         return;
      end if;

      M.Ctl := Test;
      M.Mode := Mode_Eval;
   end Start_Cond;

   --  case: the key has already been evaluated, so its clauses can be scanned
   --  against the value directly.  A datum list is matched with Same_Value --
   --  memv's relation, and `eq?`'s -- and the clause walk, like cond's, rides
   --  the evaluator's run loop rather than calling itself.
   procedure Start_Case
     (H       : Heap_Type;
      M       : in out Machine;
      Clauses : Value;
      Key     : Value;
      Env     : Handle)
     with Pre => H.Ready
   is
      Pending : Value := Clauses;
      Clause  : Value;
      Rest    : Value;
      Datums  : Value;
      Forms   : Value;
      Cur     : Value;
      Next    : Value;
      Datum   : Value;
      Match   : Boolean;
      Good    : Boolean;
   begin
      loop
         if Is_Nil (Pending) then
            M.Result := Unspecified_Value;
            M.Mode := Mode_Return;
            return;
         end if;

         Car_Of (H, Pending, Clause, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Pending, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Car_Of (H, Clause, Datums, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Clause, Forms, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;

         if Is_Symbol_Named (H, Datums, "else") then
            if not Is_Nil (Rest) then
               Fail (M, Error_Malformed);
               return;
            end if;
            Start_Body (H, M, Forms, Env);
            return;
         end if;

         Cur := Datums;
         Match := False;
         while not Is_Nil (Cur) loop
            Car_Of (H, Cur, Datum, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            if Same_Value (Datum, Key) then
               Match := True;
               exit;
            end if;
            Cdr_Of (H, Cur, Next, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            Cur := Next;
         end loop;

         if Match then
            if Is_Nil (Forms) then
               --  R7RS: a clause with no result expressions yields an
               --  unspecified value.
               M.Result := Unspecified_Value;
               M.Mode := Mode_Return;
               return;
            end if;
            Start_Body (H, M, Forms, Env);
            return;
         end if;

         Pending := Rest;
      end loop;
   end Start_Case;

   procedure Eval_Pair
     (H : in out Heap_Type;
      M : in out Machine)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Head : Value;
      Rest : Value;
      Good : Boolean;
      F    : Frame;
      Params : Value;
      Forms  : Value;
      Arity  : Natural;
      Hd     : Handle;
      Then_V : Value;
      Else_V : Value;
      Tail   : Value;
      Tail2  : Value;
      Test   : Value;
      Name   : Value;
      Expr_V : Value;
      Tmp    : Value;
   begin
      Car_Of (H, M.Ctl, Head, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      if Is_Symbol_Named (H, Head, "quote") then
         Cadr_Of (H, M.Ctl, M.Result, Good);
         if not Good then
            Fail (M, Error_Malformed);
         else
            M.Mode := Mode_Return;
         end if;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "if") then
         Cadr_Of (H, M.Ctl, Test, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cddr_Of (H, M.Ctl, Tail, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Car_Of (H, Tail, Then_V, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Tail, Tail2, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         if Is_Nil (Tail2) then
            Else_V := Unspecified_Value;
         else
            Car_Of (H, Tail2, Else_V, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
         end if;

         F := (Kind => K_If,
               Expr => Then_V,
               Alt  => Else_V,
               Env  => M.Env,
               others => <>);
         Push (M, F, Good);
         if not Good then
            Fail (M, Error_Step_Limit);
            return;
         end if;
         M.Ctl := Test;
         M.Mode := Mode_Eval;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "lambda") then
         Cadr_Of (H, M.Ctl, Params, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cddr_Of (H, M.Ctl, Forms, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Length (H, Params, Arity, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         New_Closure (H, Params, Forms, M.Env, Arity, Hd, Good);
         if not Good then
            Fail (M, Error_Heap_Full);
            return;
         end if;
         M.Result := From_Handle (Hd);
         M.Mode := Mode_Return;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "define") then
         Cadr_Of (H, M.Ctl, Name, Good);
         if not Good or else not Is_Handle (Name) then
            Fail (M, Error_Malformed);
            return;
         end if;
         Caddr_Of (H, M.Ctl, Expr_V, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         F := (Kind => K_Define,
               Sym  => Name,
               Env  => M.Env,
               others => <>);
         Push (M, F, Good);
         if not Good then
            Fail (M, Error_Step_Limit);
            return;
         end if;
         M.Ctl := Expr_V;
         M.Mode := Mode_Eval;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "set!") then
         Cadr_Of (H, M.Ctl, Name, Good);
         if not Good or else not Is_Handle (Name) then
            Fail (M, Error_Malformed);
            return;
         end if;
         Caddr_Of (H, M.Ctl, Expr_V, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         F := (Kind => K_Set,
               Sym  => Name,
               Env  => M.Env,
               others => <>);
         Push (M, F, Good);
         if not Good then
            Fail (M, Error_Step_Limit);
            return;
         end if;
         M.Ctl := Expr_V;
         M.Mode := Mode_Eval;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "begin") then
         Cdr_Of (H, M.Ctl, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         if Is_Nil (Rest) then
            M.Result := Unspecified_Value;
            M.Mode := Mode_Return;
            return;
         end if;
         Car_Of (H, Rest, Tmp, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Rest, Tail2, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         if not Is_Nil (Tail2) then
            F := (Kind => K_Begin,
                  Expr => Tail2,
                  Env  => M.Env,
                  others => <>);
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
         end if;
         M.Ctl := Tmp;
         M.Mode := Mode_Eval;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "and")
        or else Is_Symbol_Named (H, Head, "or")
      then
         --  (and) is #t, (or) is #f; otherwise the operands are evaluated
         --  left to right and the first deciding value is the answer.
         Cdr_Of (H, M.Ctl, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         if Is_Nil (Rest) then
            if Is_Symbol_Named (H, Head, "and") then
               M.Result := True_Value;
            else
               M.Result := False_Value;
            end if;
            M.Mode := Mode_Return;
            return;
         end if;

         Car_Of (H, Rest, Tmp, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Rest, Tail2, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;

         if not Is_Nil (Tail2) then
            if Is_Symbol_Named (H, Head, "and") then
               F := (Kind => K_And, Expr => Tail2, Env => M.Env, others => <>);
            else
               F := (Kind => K_Or, Expr => Tail2, Env => M.Env, others => <>);
            end if;
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
         end if;

         M.Ctl := Tmp;
         M.Mode := Mode_Eval;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "let") then
         Start_Let (H, M, Let_Parallel);
         return;
      elsif Is_Symbol_Named (H, Head, "let*") then
         Start_Let (H, M, Let_Sequential);
         return;
      elsif Is_Symbol_Named (H, Head, "letrec") then
         Start_Let (H, M, Let_Sequential);
         return;
      elsif Is_Symbol_Named (H, Head, "case") then
         Cadr_Of (H, M.Ctl, Test, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cddr_Of (H, M.Ctl, Tail2, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;

         F := (Kind => K_Case, Expr => Tail2, Env => M.Env, others => <>);
         Push (M, F, Good);
         if not Good then
            Fail (M, Error_Step_Limit);
            return;
         end if;

         M.Ctl := Test;
         M.Mode := Mode_Eval;
         return;
      elsif Is_Symbol_Named (H, Head, "cond") then
         Cdr_Of (H, M.Ctl, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Start_Cond (H, M, Rest);
         return;
      elsif Is_Symbol_Named (H, Head, "when")
        or else Is_Symbol_Named (H, Head, "unless")
      then
         Cadr_Of (H, M.Ctl, Test, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cddr_Of (H, M.Ctl, Tail2, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;

         if Is_Symbol_Named (H, Head, "when") then
            F := (Kind => K_When, Expr => Tail2, Env => M.Env, others => <>);
         else
            F := (Kind => K_Unless, Expr => Tail2, Env => M.Env, others => <>);
         end if;
         Push (M, F, Good);
         if not Good then
            Fail (M, Error_Step_Limit);
            return;
         end if;

         M.Ctl := Test;
         M.Mode := Mode_Eval;
         return;
      end if;

      --  Ordinary application: evaluate the operator first.
      Cdr_Of (H, M.Ctl, Rest, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      F := (Kind => K_Operator,
            Expr => Rest,
            Env  => M.Env,
            others => <>);
      Push (M, F, Good);
      if not Good then
         Fail (M, Error_Step_Limit);
         return;
      end if;
      M.Ctl := Head;
      M.Mode := Mode_Eval;
   end Eval_Pair;

   procedure Eval_Step
     (H : in out Heap_Type;
      M : in out Machine)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      C     : Cell;
      Valid : Boolean;
   begin
      if Is_Fixnum (M.Ctl)
        or else Is_Boolean (M.Ctl)
        or else Is_Character (M.Ctl)
        or else Is_Void (M.Ctl)
        or else Is_Nil (M.Ctl)
        or else M.Ctl.Kind = Kind_Unspecified
      then
         M.Result := M.Ctl;
         M.Mode := Mode_Return;
         return;
      end if;

      if not Is_Handle (M.Ctl) then
         Fail (M, Error_Type);
         return;
      end if;

      Fetch (H, To_Handle (M.Ctl), C, Valid);
      if not Valid then
         Fail (M, Error_Type);
         return;
      end if;

      case C.Kind is
         when Cell_Symbol =>
            Eval_Symbol (H, M);

         when Cell_Pair =>
            Eval_Pair (H, M);

         when Cell_String | Cell_Vector | Cell_Bytevector | Cell_Closure
            | Cell_Primitive | Cell_Environment | Cell_Continuation =>
            M.Result := M.Ctl;
            M.Mode := Mode_Return;

         when Cell_Free =>
            Fail (M, Error_Type);
      end case;
   end Eval_Step;

   procedure Return_Step
     (H : in out Heap_Type;
      M : in out Machine;
      B : in out Output_Buffer)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      F    : Frame;
      Good : Boolean;
      New_Args : Value;
      Proper   : Value;
      First    : Value;
      Rest     : Value;
      Var      : Value;
      Init     : Value;
   begin
      if M.Top = 0 then
         M.Mode := Mode_Halt;
         return;
      end if;

      Pop (M, F, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      case F.Kind is
         when K_If =>
            if Is_True (M.Result) then
               M.Ctl := F.Expr;
            else
               M.Ctl := F.Alt;
            end if;
            M.Env := F.Env;
            M.Mode := Mode_Eval;

         when K_Begin =>
            if Is_Nil (F.Expr) then
               --  Last form: pass the value through to the parent frame.
               M.Mode := Mode_Return;
            else
               Car_Of (H, F.Expr, First, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               Cdr_Of (H, F.Expr, Rest, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               if Is_Nil (Rest) then
                  --  Last form: tail position, so the pass-through frame is
                  --  skipped and the value goes straight to the parent frame.
                  M.Ctl := First;
                  M.Env := F.Env;
                  M.Mode := Mode_Eval;
               else
                  F.Expr := Rest;
                  Push (M, F, Good);
                  if not Good then
                     Fail (M, Error_Step_Limit);
                     return;
                  end if;
                  M.Ctl := First;
                  M.Env := F.Env;
                  M.Mode := Mode_Eval;
               end if;
            end if;

         when K_Define =>
            Tr7.Env.Define (H, F.Env, F.Sym, M.Result, Good);
            if not Good then
               Fail (M, Error_Type);
               return;
            end if;
            M.Result := Unspecified_Value;
            M.Mode := Mode_Return;

         when K_Set =>
            Tr7.Env.Set (H, F.Env, F.Sym, M.Result, Good);
            if not Good then
               Fail (M, Error_Unbound);
               return;
            end if;
            M.Result := Unspecified_Value;
            M.Mode := Mode_Return;

         when K_Operator =>
            if Is_Nil (F.Expr) then
               --  Copy the operator out of M: SPARK forbids passing a
               --  component of M together with M itself.
               First := M.Result;
               Apply_Procedure (H, First, Nil_Value, M, B);
            else
               Car_Of (H, F.Expr, First, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               Cdr_Of (H, F.Expr, Rest, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               F.Kind := K_Argument;
               F.Func := M.Result;
               F.Expr := Rest;
               F.Args := Nil_Value;
               Push (M, F, Good);
               if not Good then
                  Fail (M, Error_Step_Limit);
                  return;
               end if;
               M.Ctl := First;
               M.Env := F.Env;
               M.Mode := Mode_Eval;
            end if;

         when K_Bind =>
            --  The initializer has been evaluated: store it, then run the
            --  next initializer or the body.
            if not Is_Handle (F.Func) then
               Fail (M, Error_Malformed);
               return;
            end if;
            Tr7.Env.Define (H, To_Handle (F.Func), F.Sym, M.Result, Good);
            if not Good then
               Fail (M, Error_Heap_Full);
               return;
            end if;

            if Is_Nil (F.Args) then
               Start_Body (H, M, F.Expr, To_Handle (F.Func));
               return;
            end if;

            Car_Of (H, F.Args, First, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            Cdr_Of (H, F.Args, Rest, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            Split_Binding (H, First, Var, Init, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;

            F.Sym := Var;
            F.Args := Rest;
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
            M.Ctl := Init;
            M.Env := F.Env;
            M.Mode := Mode_Eval;

         when K_Case =>
            --  The key is copied out of M first: SPARK forbids passing a
            --  component of M together with M itself.
            First := M.Result;
            Start_Case (H, M, F.Expr, First, F.Env);

         when K_Cond =>
            --  The environment the clause forms run in is the one the clause
            --  was started in: the test itself may have changed M.Env.
            M.Env := F.Env;

            if not Is_True (M.Result) then
               Start_Cond (H, M, F.Expr);
               return;
            end if;

            --  The test passed.  No forms means the test value is the answer;
            --  a (=> <expression>) clause calls that expression with it.
            Cdr_Of (H, F.Args, Rest, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            if Is_Nil (Rest) then
               M.Mode := Mode_Return;
               return;
            end if;

            Car_Of (H, Rest, First, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;

            if Is_Symbol_Named (H, First, "=>") then
               Cdr_Of (H, Rest, Init, Good);
               if not Good or else Is_Nil (Init) then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               Car_Of (H, Init, Proper, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               Cdr_Of (H, Init, New_Args, Good);
               if not Good or else not Is_Nil (New_Args) then
                  Fail (M, Error_Malformed);
                  return;
               end if;

               F.Kind := K_Cond_App;
               F.Alt := M.Result;
               Push (M, F, Good);
               if not Good then
                  Fail (M, Error_Step_Limit);
                  return;
               end if;
               M.Ctl := Proper;
               M.Mode := Mode_Eval;
               return;
            end if;

            Start_Body (H, M, Rest, F.Env);

         when K_Cond_App =>
            --  M.Result is the procedure `=>` named; call it with the value of
            --  the test, which has been waiting in Alt.  The procedure goes
            --  through a local because SPARK forbids passing a component of M
            --  together with M itself.
            First := M.Result;
            Cons (H, F.Alt, Nil_Value, New_Args, Good);
            if not Good then
               Fail (M, Error_Heap_Full);
               return;
            end if;
            Apply_Procedure (H, First, New_Args, M, B);

         when K_When | K_Unless =>
            if (F.Kind = K_When and then Is_True (M.Result))
              or else (F.Kind = K_Unless and then not Is_True (M.Result))
            then
               Start_Body (H, M, F.Expr, F.Env);
            else
               M.Result := Unspecified_Value;
               M.Mode := Mode_Return;
            end if;

         when K_And | K_Or =>
            --  A false operand decides `and`, a true one decides `or`; in
            --  both cases the value that decided is the value of the form.
            if (F.Kind = K_And and then not Is_True (M.Result))
              or else (F.Kind = K_Or and then Is_True (M.Result))
            then
               M.Mode := Mode_Return;
               return;
            end if;

            if Is_Nil (F.Expr) then
               M.Mode := Mode_Return;
               return;
            end if;

            Car_Of (H, F.Expr, First, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            Cdr_Of (H, F.Expr, Rest, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;

            F.Expr := Rest;
            if not Is_Nil (Rest) then
               Push (M, F, Good);
               if not Good then
                  Fail (M, Error_Step_Limit);
                  return;
               end if;
            end if;
            M.Ctl := First;
            M.Env := F.Env;
            M.Mode := Mode_Eval;

         when K_Argument =>
            Cons (H, M.Result, F.Args, New_Args, Good);
            if not Good then
               Fail (M, Error_Heap_Full);
               return;
            end if;
            if Is_Nil (F.Expr) then
               Reverse_List (H, New_Args, Proper, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               Apply_Procedure (H, F.Func, Proper, M, B);
            else
               Car_Of (H, F.Expr, First, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               Cdr_Of (H, F.Expr, Rest, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               F.Expr := Rest;
               F.Args := New_Args;
               Push (M, F, Good);
               if not Good then
                  Fail (M, Error_Step_Limit);
                  return;
               end if;
               M.Ctl := First;
               M.Env := F.Env;
               M.Mode := Mode_Eval;
            end if;
      end case;
   end Return_Step;

   procedure Step
     (H : in out Heap_Type;
      M : in out Machine;
      B : in out Output_Buffer)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
   begin
      if M.Mode = Mode_Eval then
         Eval_Step (H, M);
      elsif M.Mode = Mode_Return then
         Return_Step (H, M, B);
      end if;
   end Step;

   procedure Collect_Garbage
     (H   : in out Heap_Type;
      Env : Handle;
      M   : Machine)
   is
   begin
      --  The CEK state is a complete root set between steps: control, the
      --  value being delivered, the current environment and every frame on
      --  the continuation stack.
      Mark_Root (H, M.Ctl);
      Mark_Root (H, M.Result);
      Mark_Root (H, From_Handle (Env));
      Mark_Root (H, From_Handle (M.Env));

      for I in 1 .. M.Top loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (I <= M.Top);
         --  Rooting never touches the free list, so the free cells counted on
         --  entry are still there for Collect to report on.
         pragma Loop_Invariant (H.Free_Count = H.Free_Count'Loop_Entry);
         Mark_Root (H, M.Stack (I).Expr);
         Mark_Root (H, M.Stack (I).Alt);
         Mark_Root (H, M.Stack (I).Func);
         Mark_Root (H, M.Stack (I).Args);
         Mark_Root (H, M.Stack (I).Sym);
         Mark_Root (H, From_Handle (M.Stack (I).Env));
      end loop;

      Collect (H);
   end Collect_Garbage;

   procedure Evaluate
     (H      : in out Heap_Type;
      Env    : Handle;
      Expr   : Value;
      M      : in out Machine;
      B      : in out Output_Buffer)
   is
      Steps     : Natural := 0;
      --  Counts evaluator steps between stress collections; the subtype makes
      --  the increment below obviously safe.
      Stress_Due : Natural range 0 .. GC_Stress_Every := GC_Stress_Every;
   begin
      M.Mode := Mode_Eval;
      M.Ctl := Expr;
      M.Env := Env;
      M.Top := 0;
      M.Result := Nil_Value;
      M.Error := No_Error;

      --  The step counter is driver state, not machine state: no callee can
      --  touch it, so the loop invariant needs no frame reasoning about the
      --  machine record.
      while M.Mode /= Mode_Halt loop
         pragma Loop_Invariant (Steps <= Max_Steps);
         pragma Loop_Invariant (H.Ready);

         --  Safe point: collect before the step when the arena runs low, or
         --  on a fixed cadence under --stress-gc.
         if H.Free_Count <= GC_Low_Water
           or else (H.Stress_GC and then Stress_Due = 0)
         then
            Collect_Garbage (H, Env, M);
            Stress_Due := GC_Stress_Every;
         elsif H.Stress_GC then
            Stress_Due := Stress_Due - 1;
         end if;

         if Steps >= Max_Steps then
            M.Error := Error_Step_Limit;
            M.Mode := Mode_Halt;
         else
            Step (H, M, B);
            Steps := Steps + 1;
         end if;
      end loop;
   end Evaluate;

end Tr7.Machine;
