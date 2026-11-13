with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Env; use Tr7.Env;
with Tr7.Macros;
with Tr7.Pairs; use Tr7.Pairs;
with Tr7.Primitives; use Tr7.Primitives;
with Tr7.Reach;

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

   --  Encode/decode one continuation frame as a seven-element list:
   --  kind, Expr, Alt, Func, Args, Sym, Env.  Kept as heap data so a
   --  continuation is a persistent snapshot and can be invoked more than
   --  once.
   procedure Frame_To_Code
     (H : in out Heap_Type; F : Frame; Result : out Value; Ok : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Item : Value;
      Tmp  : Value;
   begin
      Result := Nil_Value;
      Cons (H, From_Handle (F.Env), Nil_Value, Item, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, F.Sym, Item, Tmp, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, F.Args, Tmp, Item, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, F.Func, Item, Tmp, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, F.Alt, Tmp, Item, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, F.Expr, Item, Tmp, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, From_Fixnum (Integer_64 (Frame_Kind'Pos (F.Kind))),
            Tmp, Result, Ok);
   end Frame_To_Code;

   procedure Code_To_Frame
     (H : Heap_Type; V : Value; F : out Frame; Ok : out Boolean)
     with
       Pre  => H.Ready,
       Post => True
   is
      Cur  : Value := V;
      Item : Value;
      Next : Value;
      Good : Boolean;
      Pos  : Integer_64;
   begin
      F := (Kind => K_If, others => <>);
      Ok := False;
      Car_Of (H, Cur, Item, Good);
      if not Good or else not Is_Fixnum (Item) then
         return;
      end if;
      Pos := Item.N;
      if Pos < 0 or else Pos > Integer_64 (Frame_Kind'Pos (Frame_Kind'Last))
      then
         return;
      end if;
      F.Kind := Frame_Kind'Val (Natural (Pos));
      Cdr_Of (H, Cur, Next, Good);
      if not Good then
         return;
      end if;
      Cur := Next;
      Car_Of (H, Cur, F.Expr, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Cur, Next, Good);
      if not Good then
         return;
      end if;
      Cur := Next;
      Car_Of (H, Cur, F.Alt, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Cur, Next, Good);
      if not Good then
         return;
      end if;
      Cur := Next;
      Car_Of (H, Cur, F.Func, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Cur, Next, Good);
      if not Good then
         return;
      end if;
      Cur := Next;
      Car_Of (H, Cur, F.Args, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Cur, Next, Good);
      if not Good then
         return;
      end if;
      Cur := Next;
      Car_Of (H, Cur, F.Sym, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Cur, Next, Good);
      if not Good then
         return;
      end if;
      Cur := Next;
      Car_Of (H, Cur, Item, Good);
      if not Good or else not Is_Handle (Item) then
         return;
      end if;
      F.Env := To_Handle (Item);
      Ok := True;
   end Code_To_Frame;

   procedure Capture_Stack
     (H : in out Heap_Type; M : Machine; Cont : Handle; Ok : out Boolean)
     with
       Pre  => H.Ready and then Cont.Index in Valid_Cell_Index,
       Post => H.Ready
   is
      Frames : Value := Nil_Value;
      Frame_V : Value;
      Tmp : Value;
      Good : Boolean;
   begin
      Ok := False;
      for I in reverse 1 .. M.Top loop
         pragma Loop_Invariant (H.Ready);
         Frame_To_Code (H, M.Stack (I), Frame_V, Good);
         if not Good then
            return;
         end if;
         Cons (H, Frame_V, Frames, Tmp, Good);
         if not Good then
            return;
         end if;
         Frames := Tmp;
      end loop;
      H.Cells (Cont.Index).Car := Frames;
      H.Cells (Cont.Index).Cont_Depth := M.Top;
      H.Cells (Cont.Index).Env := M.Env;
      Ok := True;
   end Capture_Stack;

   procedure Restore_Stack
     (H : Heap_Type;
      M : in out Machine;
      C : Cell;
      Val : Value;
      Ok : out Boolean)
     with Pre => H.Ready
   is
      Cur : Value := C.Car;
      Frame_V : Value;
      F : Frame;
      I : Natural := 0;
      Good : Boolean;
      Next : Value;
   begin
      Ok := False;
      while I < C.Cont_Depth loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (I <= C.Cont_Depth);
         if not Is_Handle (Cur) then
            return;
         end if;
         Car_Of (H, Cur, Frame_V, Good);
         if not Good then
            return;
         end if;
         Code_To_Frame (H, Frame_V, F, Good);
         if not Good then
            return;
         end if;
         I := I + 1;
         M.Stack (I) := F;
         Cdr_Of (H, Cur, Next, Good);
         if not Good then
            return;
         end if;
         Cur := Next;
      end loop;
      if not Is_Nil (Cur) then
         return;
      end if;
      M.Top := I;
      M.Env := C.Env;
      M.Result := Val;
      M.Mode := Mode_Return;
      Ok := True;
   end Restore_Stack;

   procedure Fail (M : in out Machine; E : Error_Code) is
   begin
      M.Error := E;
      M.Mode := Mode_Halt;
   end Fail;

   --  True when a validated parameter list ends in the symbol that collects
   --  the rest of the arguments; used at call time to choose between exact
   --  and rest arity.
   function Has_Rest (H : Heap_Type; Params : Value) return Boolean
     with Pre => H.Ready
   is
      Cur   : Value := Params;
      Node  : Cell;
      Good  : Boolean;
      --  Functions are implicitly Always_Terminates in SPARK, so this walk is
      --  bounded: Param_Fixed_Length rejected any parameter list longer than
      --  Max_List_Length at closure creation, which makes the bound -- and the
      --  variant below -- reachable only for a list that cannot exist.
      Steps : Natural range 0 .. Max_List_Length := 0;
   begin
      while Is_Handle (Cur) loop
         pragma Loop_Variant (Decreases => Max_List_Length - Steps);
         exit when Steps = Max_List_Length;
         Fetch (H, To_Handle (Cur), Node, Good);
         if not Good then
            return False;
         end if;
         if Node.Kind /= Cell_Pair then
            return Node.Kind = Cell_Symbol;
         end if;
         Cur := Node.Cdr;
         Steps := Steps + 1;
      end loop;
      return False;
   end Has_Rest;

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
      P     : Value := Params;
      A     : Value := Args;
      Sym   : Value;
      Val   : Value;
      Next  : Value;
      PC    : Cell;
      Good  : Boolean;
   begin
      Ok := False;
      loop
         pragma Loop_Invariant (H.Ready);
         if Is_Nil (P) then
            Ok := Is_Nil (A);
            return;
         end if;
         if not Is_Handle (P) then
            return;
         end if;

         Fetch (H, To_Handle (P), PC, Good);
         if not Good then
            return;
         end if;

         --  The rest parameter comes first: it may collect nothing at all,
         --  which is why this is checked before the "no arguments left" case.
         if PC.Kind = Cell_Symbol then
            Tr7.Env.Define (H, Env, P, A, Good);
            Ok := Good;
            return;
         end if;
         if PC.Kind /= Cell_Pair then
            return;
         end if;
         if Is_Nil (A) then
            return;
         end if;

         Sym := PC.Car;
         if not Is_Handle (Sym) then
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

         Next := PC.Cdr;
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
      First   : Value;
      Rest    : Value;
      F       : Frame;
      Target   : Natural;
      Old_Top  : Natural;
      Wind     : Value;
      New_Wind : Value;
      After_V  : Value;
      Befores  : Value;
      Rev      : Value;
      Cur      : Value;
      Tmp      : Value;
      Next     : Value;
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
         when Cell_Continuation =>
            --  A continuation is a persistent snapshot of the frames at the
            --  call/cc form.  Invoking it restores those frames and delivers
            --  the argument there; invoking it again restores the same
            --  snapshot, so it is re-entrant and multi-shot.
            Car_Of (H, Args, First, Good);
            if not Good then
               Fail (M, Error_Wrong_Arity);
               return;
            end if;
            Cdr_Of (H, Args, Rest, Good);
            if not Good or else not Is_Nil (Rest) then
               Fail (M, Error_Wrong_Arity);
               return;
            end if;
            Target := C.Cont_Depth;
            Old_Top := M.Top;

            --  Every wind the escape discards has an after to run.  Frames
            --  above the captured depth are the ones being crossed; the
            --  after procedure was evaluated when the wind form ran and
            --  rides in the frame's Expr.
            Wind := Nil_Value;
            for J in Target + 1 .. Old_Top loop
               pragma Loop_Invariant (Target < J and then J <= Old_Top);
               pragma Loop_Invariant (H.Ready);
               if M.Stack (J).Kind = K_Wind then
                  Cons (H, M.Stack (J).Expr, Wind, New_Wind, Good);
                  if not Good then
                     Fail (M, Error_Heap_Full);
                     return;
                  end if;
                  Wind := New_Wind;
               end if;
            end loop;

            Restore_Stack (H, M, C, First, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;

            --  Re-entering winds that were not active in the current stack
            --  runs their before procedures, outermost first.
            Befores := Nil_Value;
            for J in Old_Top + 1 .. Target loop
               pragma Loop_Invariant (Old_Top < J and then J <= Target);
               pragma Loop_Invariant (H.Ready);
               if M.Stack (J).Kind = K_Wind then
                  Cons (H, M.Stack (J).Sym, Befores, Tmp, Good);
                  if not Good then
                     Fail (M, Error_Heap_Full);
                     return;
                  end if;
                  Befores := Tmp;
               end if;
            end loop;
            Reverse_List (H, Befores, Rev, Good);
            if not Good then
               Fail (M, Error_Heap_Full);
               return;
            end if;

            --  Combine: afters first (inner to outer), then befores.
            if not Is_Nil (Wind) and then not Is_Nil (Rev) then
               Reverse_List (H, Wind, Tmp, Good);
               if not Good then
                  Fail (M, Error_Heap_Full);
                  return;
               end if;
               Cur := Tmp;
               while not Is_Nil (Cur) loop
                  pragma Loop_Invariant (H.Ready);
                  Car_Of (H, Cur, After_V, Good);
                  if not Good then
                     Fail (M, Error_Malformed);
                     return;
                  end if;
                  Cons (H, After_V, Rev, Tmp, Good);
                  if not Good then
                     Fail (M, Error_Heap_Full);
                     return;
                  end if;
                  Rev := Tmp;
                  Cdr_Of (H, Cur, Next, Good);
                  if not Good then
                     Fail (M, Error_Malformed);
                     return;
                  end if;
                  Cur := Next;
               end loop;
            elsif not Is_Nil (Wind) then
               Rev := Wind;
            end if;

            if Is_Nil (Rev) then
               return;
            end if;

            F := (Kind => K_Unwind,
                  Func => First,
                  Args => Rev,
                  others => <>);
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
            Car_Of (H, Rev, After_V, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            Apply_Procedure (H, After_V, Nil_Value, M, B);

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
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            if Has_Rest (H, C.Car) then
               if Arity < C.Arity then
                  Fail (M, Error_Wrong_Arity);
                  return;
               end if;
            elsif Arity /= C.Arity then
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
      Val    : Value;
      Status : Error_Code;
   begin
      Tr7.Env.Lookup (H, M.Env, M.Ctl, Val, Status);
      if Status /= No_Error then
         Fail (M, Status);
         return;
      end if;
      M.Result := Val;
      M.Mode := Mode_Return;
   end Eval_Symbol;

   --  Count a lambda's fixed parameters: the leading pairs of the parameter
   --  list, which must all be symbols, ending either at the empty list or at
   --  the one symbol that collects the rest of the arguments.  Length cannot
   --  do this job because it rejects the dotted list `(a . rest)` itself.
   procedure Param_Fixed_Length
     (H      : Heap_Type;
      Params : Value;
      N      : out Natural;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => (if Ok then N <= Max_List_Length)
   is
      Cur   : Value := Params;
      Node  : Cell;
      Param : Cell;
      Count : Natural := 0;
      Good  : Boolean;
   begin
      N := 0;
      Ok := False;
      loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (Count <= Max_List_Length);
         if Is_Nil (Cur) then
            N := Count;
            Ok := True;
            return;
         end if;
         if not Is_Handle (Cur) then
            return;
         end if;
         Fetch (H, To_Handle (Cur), Node, Good);
         if not Good then
            return;
         end if;
         if Node.Kind /= Cell_Pair then
            --  The tail: either the rest parameter, or a malformed list.
            if Node.Kind = Cell_Symbol then
               N := Count;
               Ok := True;
            end if;
            return;
         end if;

         if not Is_Handle (Node.Car) then
            return;
         end if;
         Fetch (H, To_Handle (Node.Car), Param, Good);
         if not Good or else Param.Kind /= Cell_Symbol then
            return;
         end if;
         if Count >= Max_List_Length then
            return;
         end if;
         Count := Count + 1;
         Cur := Node.Cdr;
      end loop;
   end Param_Fixed_Length;


   --  quasiquote support.  The template is turned into code -- cons for
   --  structure, quote for data, the unquoted expression itself where a value
   --  is wanted, append for splicing -- and the evaluator runs that code, so
   --  no new frame kind is needed and quoting a backtick form still behaves
   --  like data.

   --  Budget and nesting bound for the converter below.  Both sit far above
   --  what a reader-produced template can reach -- its depth is capped at
   --  Max_Reader_Depth -- so exhausting either is unreachable for any datum
   --  the reader made; the guards turn that impossible case into a clean
   --  error instead of a stack overflow or a range check.
   QQ_Limit : constant := 4 * Max_Reader_Depth;
   QQ_Fuel  : constant := 4 * Max_Reader_Depth + 64;

   function Is_Form
     (H    : Heap_Type;
      V    : Value;
      Name : String) return Boolean
     with Pre => H.Ready and then Name'First >= 1
   is
      C    : Cell;
      Good : Boolean;
   begin
      if not Is_Handle (V) then
         return False;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      if not Good or else C.Kind /= Cell_Pair then
         return False;
      end if;
      return Is_Symbol_Named (H, C.Car, Name);
   end Is_Form;

   function Is_Pair_Value (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready
   is
      C    : Cell;
      Good : Boolean;
   begin
      if not Is_Handle (V) then
         return False;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      return Good and then C.Kind = Cell_Pair;
   end Is_Pair_Value;

   --  True when V is itself one of the three keywords the converter reacts
   --  to -- not when V is a form headed by one, which is Is_Form's job.
   function Is_Keyword (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready
   is
      C    : Cell;
      Good : Boolean;
   begin
      if not Is_Handle (V) then
         return False;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      if not Good or else C.Kind /= Cell_Symbol then
         return False;
      end if;
      return (C.Name_Len = 7 and then C.Name (1 .. 7) = "unquote")
        or else
          (C.Name_Len = 16 and then C.Name (1 .. 16) = "unquote-splicing")
        or else
          (C.Name_Len = 10 and then C.Name (1 .. 10) = "quasiquote");
   end Is_Keyword;

   --  What evaluating this value should produce: symbols and heap values need
   --  (quote v), the immediate kinds are their own code.
   procedure Data_Code
     (H    : in out Heap_Type;
      V    : Value;
      Code : out Value;
      Ok   : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Quote_Sym : Value;
      Tmp       : Value;
   begin
      Code := Nil_Value;
      if V.Kind /= Kind_Handle then
         --  Immediate values are their own code: numbers, characters,
         --  booleans and ().
         Code := V;
         Ok := True;
         return;
      end if;

      --  Heap values -- symbols, strings -- are wrapped as (quote v), which
      --  evaluation reproduces unchanged.
      Intern (H, "quote", Quote_Sym, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, V, Nil_Value, Tmp, Ok);      -- (v . ())
      if not Ok then
         return;
      end if;
      Cons (H, Quote_Sym, Tmp, Code, Ok);   -- (quote v . ())
   end Data_Code;

   --  (fn a1 a2) as a value.
   procedure Build_Call2
     (H    : in out Heap_Type;
      Fn   : Value;
      A1   : Value;
      A2   : Value;
      Res  : out Value;
      Ok   : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      T1, T2 : Value;
   begin
      Res := Nil_Value;
      Cons (H, A2, Nil_Value, T2, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, A1, T2, T1, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, Fn, T1, Res, Ok);
   end Build_Call2;

   --  The single argument of a keyword form: (name arg) and nothing more, so
   --  (unquote) and (unquote a b) inside a template are both rejected rather
   --  than silently missing or ignoring an operand.
   procedure Form_Arg
     (H    : Heap_Type;
      T    : Value;
      Arg  : out Value;
      Good : out Boolean)
     with Pre => H.Ready
   is
      C    : Cell;
      Rest : Cell;
      C_Ok : Boolean;
      R_Ok : Boolean;
   begin
      Arg := Nil_Value;
      Good := False;
      if not Is_Handle (T) then
         return;
      end if;
      Fetch (H, To_Handle (T), C, C_Ok);
      if not C_Ok or else C.Kind /= Cell_Pair then
         return;
      end if;
      if not Is_Handle (C.Cdr) then
         return;
      end if;
      Fetch (H, To_Handle (C.Cdr), Rest, R_Ok);
      if not R_Ok or else Rest.Kind /= Cell_Pair then
         return;
      end if;
      if not Is_Nil (Rest.Cdr) then
         return;
      end if;
      Arg := Rest.Car;
      Good := True;
   end Form_Arg;

   --  The converter and the spine walk call each other, so both are declared
   --  before either body.  Every call spends one unit of Fuel, which bounds
   --  recursion by construction; Nesting counts the active quasiquotes and
   --  never leaves 1 .. QQ_Limit (the reader cannot nest a template deeply
   --  enough to reach the bound, so the guard there is a safety net).
   procedure QQ_To_Code
     (H       : in out Heap_Type;
      T       : Value;
      Nesting : Natural;
      Code    : out Value;
      Status  : out Error_Code;
      Fuel    : Natural)
     with
       Pre  => H.Ready
         and then Nesting >= 1
         and then Nesting <= QQ_Limit,
       Post => H.Ready,
       Subprogram_Variant => (Decreases => Fuel);

   procedure QQ_Spine
     (H       : in out Heap_Type;
      T       : Value;
      Nesting : Natural;
      Code    : out Value;
      Status  : out Error_Code;
      Fuel    : Natural)
     with
       Pre  => H.Ready
         and then Nesting >= 1
         and then Nesting <= QQ_Limit,
       Post => H.Ready,
       Subprogram_Variant => (Decreases => Fuel);

   procedure QQ_To_Code
     (H       : in out Heap_Type;
      T       : Value;
      Nesting : Natural;
      Code    : out Value;
      Status  : out Error_Code;
      Fuel    : Natural)
   is
      Pair_C     : Cell;
      Good       : Boolean;
      Inner      : Value;
      Inner_Code : Value;
      Kw_Code    : Value;
      List_Sym   : Value;
   begin
      Code := Nil_Value;
      Status := No_Error;
      if Fuel = 0 then
         Status := Error_Malformed;
         return;
      end if;

      if not Is_Handle (T) then
         --  Numbers, characters, booleans and () are their own code.
         Data_Code (H, T, Code, Good);
         if not Good then
            Status := Error_Heap_Full;
         end if;
         return;
      end if;

      if not Is_Pair_Value (H, T) then
         --  A symbol or a string: quote it so evaluation reproduces it.
         Data_Code (H, T, Code, Good);
         if not Good then
            Status := Error_Heap_Full;
         end if;
         return;
      end if;

      Fetch (H, To_Handle (T), Pair_C, Good);
      if not Good then
         Status := Error_Malformed;
         return;
      end if;

      if Is_Symbol_Named (H, Pair_C.Car, "unquote")
        or else Is_Symbol_Named (H, Pair_C.Car, "unquote-splicing")
      then
         Form_Arg (H, T, Inner, Good);
         if not Good then
            Status := Error_Malformed;
            return;
         end if;
         if Nesting = 1 then
            --  The expression itself.  In list position a splice is caught
            --  by QQ_Spine first, so what reaches here is `,x or a dotted
            --  tail -- both simply evaluate.
            Code := Inner;
            return;
         end if;

         --  Deeper nesting: the form survives as data -- the list
         --  (keyword <inner>) -- and the keyword symbol is taken from the
         --  template itself, so nothing has to be interned for it.
         QQ_To_Code (H, Inner, Nesting - 1, Inner_Code, Status, Fuel - 1);
         if Status /= No_Error then
            return;
         end if;
         Data_Code (H, Pair_C.Car, Kw_Code, Good);
         if not Good then
            Status := Error_Heap_Full;
            return;
         end if;
         Intern (H, "list", List_Sym, Good);
         if not Good then
            Status := Error_Heap_Full;
            return;
         end if;
         Build_Call2 (H, List_Sym, Kw_Code, Inner_Code, Code, Good);
         if not Good then
            Status := Error_Heap_Full;
         end if;
         return;
      end if;

      if Is_Symbol_Named (H, Pair_C.Car, "quasiquote") then
         Form_Arg (H, T, Inner, Good);
         if not Good then
            Status := Error_Malformed;
            return;
         end if;
         if Nesting >= QQ_Limit then
            Status := Error_Malformed;
            return;
         end if;
         QQ_To_Code (H, Inner, Nesting + 1, Inner_Code, Status, Fuel - 1);
         if Status /= No_Error then
            return;
         end if;
         Data_Code (H, Pair_C.Car, Kw_Code, Good);
         if not Good then
            Status := Error_Heap_Full;
            return;
         end if;
         Intern (H, "list", List_Sym, Good);
         if not Good then
            Status := Error_Heap_Full;
            return;
         end if;
         Build_Call2 (H, List_Sym, Kw_Code, Inner_Code, Code, Good);
         if not Good then
            Status := Error_Heap_Full;
         end if;
         return;
      end if;

      --  Structure: cons cells, splices and a dotted tail.
      QQ_Spine (H, T, Nesting, Code, Status, Fuel - 1);
   end QQ_To_Code;

   procedure QQ_Spine
     (H       : in out Heap_Type;
      T       : Value;
      Nesting : Natural;
      Code    : out Value;
      Status  : out Error_Code;
      Fuel    : Natural)
   is
      Rev        : Value := Nil_Value;
      Acc        : Value;
      Cur        : Value := T;
      Elem       : Value;
      Elem_Code  : Value;
      New_Rev    : Value;
      Splice     : Value;
      Cons_Sym   : Value;
      Append_Sym : Value;
      Node       : Cell;
      Good       : Boolean;
   begin
      Code := Nil_Value;
      if Fuel = 0 then
         Status := Error_Malformed;
         return;
      end if;
      Intern (H, "cons", Cons_Sym, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;

      --  Walk the spine, collecting the elements in reverse.  The walk stops
      --  at the tail: nil, a dotted datum, or a keyword form -- `(a . ,x)
      --  reads its tail as the list (unquote x), which is an expression to
      --  convert, not a cell to walk (and the same list written out longhand
      --  means the same thing, because it is the same datum).
      loop
         pragma Loop_Invariant (H.Ready);
         exit when not Is_Handle (Cur);
         Fetch (H, To_Handle (Cur), Node, Good);
         if not Good then
            Status := Error_Malformed;
            return;
         end if;
         if Node.Kind /= Cell_Pair then
            exit;
         end if;
         if Is_Keyword (H, Node.Car) then
            exit;
         end if;
         Cons (H, Node.Car, Rev, New_Rev, Good);
         if not Good then
            Status := Error_Heap_Full;
            return;
         end if;
         Rev := New_Rev;
         Cur := Node.Cdr;
      end loop;

      --  The tail's own code: () stays (), and a dotted datum or a keyword
      --  form is converted as one expression.
      QQ_To_Code (H, Cur, Nesting, Acc, Status, Fuel - 1);
      if Status /= No_Error then
         return;
      end if;

      --  Fold left over the reversed spine -- a right fold over the original
      --  -- so the conses come out in list order and an ,@ element appends
      --  exactly the code built for what follows it.
      while not Is_Nil (Rev) loop
         pragma Loop_Invariant (H.Ready);
         Car_Of (H, Rev, Elem, Good);
         if not Good then
            Status := Error_Malformed;
            return;
         end if;
         Cdr_Of (H, Rev, New_Rev, Good);
         if not Good then
            Status := Error_Malformed;
            return;
         end if;

         if Nesting = 1 and then Is_Form (H, Elem, "unquote-splicing") then
            Form_Arg (H, Elem, Splice, Good);
            if not Good then
               Status := Error_Malformed;
               return;
            end if;
            Intern (H, "append", Append_Sym, Good);
            if not Good then
               Status := Error_Heap_Full;
               return;
            end if;
            Build_Call2 (H, Append_Sym, Splice, Acc, Code, Good);
            if not Good then
               Status := Error_Heap_Full;
               return;
            end if;
         else
            QQ_To_Code (H, Elem, Nesting, Elem_Code, Status, Fuel - 1);
            if Status /= No_Error then
               return;
            end if;
            Build_Call2 (H, Cons_Sym, Elem_Code, Acc, Code, Good);
            if not Good then
               Status := Error_Heap_Full;
               return;
            end if;
         end if;
         Acc := Code;
         Rev := New_Rev;
      end loop;

      Code := Acc;
   end QQ_Spine;

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

   --  Split one do binding into its variable and initializer, accepting the
   --  optional step element and checking that nothing follows it: a binding
   --  is (var init) or (var init step) and nothing else.
   procedure Do_Binding
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
      --  Init starts here because the early returns below hand it to the
      --  caller before Car_Of ever runs; Var does not need the same, since
      --  Car_Of is the first thing that touches it and always writes it.
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
      if not Good then
         return;
      end if;
      if Is_Nil (More) then
         Ok := True;
         return;
      end if;
      Cdr_Of (H, More, Tail, Good);
      if not Good or else not Is_Nil (Tail) then
         return;
      end if;
      Ok := True;
   end Do_Binding;

   --  The same shape, but returning what the steps list needs: the variable
   --  and the step expression.  The initializer is stepped over without being
   --  named -- Cdr_Of is what proves an element is there at all.
   procedure Do_Step_Of
     (H        : Heap_Type;
      B        : Value;
      Var      : out Value;
      Step     : out Value;
      Has_Step : out Boolean;
      Ok       : out Boolean)
     with Pre => H.Ready
   is
      Tail : Value;
      More : Value;
      Good : Boolean;
   begin
      Step     := Nil_Value;
      Has_Step := False;
      Ok       := False;

      Car_Of (H, B, Var, Good);
      if not Good or else not Is_Handle (Var) then
         return;
      end if;
      Cdr_Of (H, B, Tail, Good);
      if not Good or else Is_Nil (Tail) then
         return;
      end if;
      Cdr_Of (H, Tail, More, Good);
      if not Good then
         return;
      end if;
      if Is_Nil (More) then
         Ok := True;
         return;
      end if;
      Car_Of (H, More, Step, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, More, Tail, Good);
      if not Good or else not Is_Nil (Tail) then
         return;
      end if;
      Has_Step := True;
      Ok       := True;
   end Do_Step_Of;

   --  Collect the step values into the bindings -- only variables that have
   --  a step are rebound; the others keep the binding they already have --
   --  and then test again.  The values arrive reversed (each step conses
   --  onto the front), so one Reverse puts them back in binding order for a
   --  lockstep walk over the (var . step) pairs.
   procedure Do_Restart
     (H     : in out Heap_Type;
      M     : in out Machine;
      F     : in Frame)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      F2     : Frame;
      Values : Value;
      Cursor : Value;
      Pair   : Value;
      Var    : Value;
      Val    : Value;
      Rest   : Value;
      Good   : Boolean;
   begin
      Reverse_List (H, F.Func, Values, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      Cursor := F.Expr;
      loop
         pragma Loop_Invariant (H.Ready);
         exit when Is_Nil (Cursor);
         Car_Of (H, Cursor, Pair, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Car_Of (H, Pair, Var, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Car_Of (H, Values, Val, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Tr7.Env.Define (H, F.Env, Var, Val, Good);
         if not Good then
            Fail (M, Error_Heap_Full);
            return;
         end if;
         Cdr_Of (H, Cursor, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cursor := Rest;
         Cdr_Of (H, Values, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Values := Rest;
      end loop;

      --  The frame comes back as K_Do with the test waiting in Alt.  The
      --  prepared frame is a copy: F itself is only ever read here, which
      --  keeps its callers from being warned that a call set what they never
      --  use again.
      F2 := F;
      F2.Kind := K_Do;
      F2.Func := Nil_Value;
      F2.Sym  := Nil_Value;
      Push (M, F2, Good);
      if not Good then
         Fail (M, Error_Step_Limit);
         return;
      end if;
      Car_Of (H, F.Alt, Val, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      M.Ctl := Val;
      M.Env := F.Env;
      M.Mode := Mode_Eval;
   end Do_Restart;

   --  Run the next step from the cursor in F.Sym, or finish the iteration
   --  when the cursor is empty.  The frame arrives popped, so every path
   --  either pushes it again or has already handed control elsewhere.
   procedure Do_Advance
     (H     : in out Heap_Type;
      M     : in out Machine;
      F     : in Frame)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      F2   : Frame;
      Pair : Value;
      Step : Value;
      Rest : Value;
      Good : Boolean;
   begin
      if Is_Nil (F.Sym) then
         Do_Restart (H, M, F);
         return;
      end if;

      Car_Of (H, F.Sym, Pair, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Cdr_Of (H, F.Sym, Rest, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Cdr_Of (H, Pair, Step, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      F2 := F;
      F2.Sym := Rest;
      F2.Kind := K_Do_Step;
      Push (M, F2, Good);
      if not Good then
         Fail (M, Error_Step_Limit);
         return;
      end if;
      M.Ctl := Step;
      M.Env := F.Env;
      M.Mode := Mode_Eval;
   end Do_Advance;

   --  Begin the step phase: every (var . step) pair is still to run and no
   --  step value has been collected yet.
   procedure Do_Steps
     (H     : in out Heap_Type;
      M     : in out Machine;
      F     : in Frame)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      F2 : Frame;
   begin
      F2 := F;
      F2.Kind := K_Do_Step;
      F2.Sym  := F.Expr;
      F2.Func := Nil_Value;
      Do_Advance (H, M, F2);
   end Do_Steps;

   --  Start one iteration: build the steps list -- one (var . step) pair per
   --  binding that has a step, in binding order -- push the do frame and
   --  evaluate the test.  The list is built once per iteration here and
   --  lives in the frame for every later phase, so a long-running loop never
   --  rebuilds it.
   procedure Do_Loop
     (H    : in out Heap_Type;
      M    : in out Machine;
      Form : Value;
      Env  : Handle)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Bindings  : Value;
      Test      : Value;
      Forms     : Value;
      Tail      : Value;
      Elem      : Value;
      Var       : Value;
      Step      : Value;
      Has_Step  : Boolean;
      Pair      : Value;
      Acc       : Value;
      Rev       : Value;
      Test_Expr : Value;
      F         : Frame;
      Good      : Boolean;
      Left      : Natural := Max_List_Length + 1;
   begin
      Cadr_Of (H, Form, Bindings, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Caddr_Of (H, Form, Test, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Cddr_Of (H, Form, Tail, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Cdr_Of (H, Tail, Forms, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      Acc := Nil_Value;
      Elem := Bindings;
      while not Is_Nil (Elem) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         declare
            Cur : Value;
         begin
            Car_Of (H, Elem, Cur, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            Do_Step_Of (H, Cur, Var, Step, Has_Step, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            if Has_Step then
               Cons (H, Var, Step, Pair, Good);   -- (var . step)
               if not Good then
                  Fail (M, Error_Heap_Full);
                  return;
               end if;
               Cons (H, Pair, Acc, Rev, Good);
               if not Good then
                  Fail (M, Error_Heap_Full);
                  return;
               end if;
               Acc := Rev;
            end if;
            Cdr_Of (H, Elem, Cur, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            Elem := Cur;
            Left := Left - 1;
         end;
      end loop;
      if not Is_Nil (Elem) then
         Fail (M, Error_Malformed);
         return;
      end if;
      Reverse_List (H, Acc, Rev, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      Car_Of (H, Test, Test_Expr, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      F := (Kind => K_Do,
            Expr => Rev,
            Alt  => Test,
            Args => Forms,
            Env  => Env,
            others => <>);
      Push (M, F, Good);
      if not Good then
         Fail (M, Error_Step_Limit);
         return;
      end if;
      M.Ctl := Test_Expr;
      M.Env := Env;
      M.Mode := Mode_Eval;
   end Do_Loop;

   --  (do ((var init [step]) ...) (test result ...) body ...): check the
   --  shape once so a malformed form fails before anything runs, bind the
   --  initializers where the form appears (parallel, like let), and hand the
   --  loop to Do_Loop with the environment they were bound into.  The K_Bind
   --  frame carries Alt = #t as the marker that says "when the initializers
   --  are done, start the loop instead of a body".
   procedure Start_Do
     (H : in out Heap_Type;
      M : in out Machine)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Bindings   : Value;
      Test       : Value;
      Elem       : Value;
      Bnd        : Value;
      Next       : Value;
      Var        : Value;
      Init       : Value;
      First_Var  : Value;
      First_Init : Value;
      First      : Boolean;
      Form       : Value;
      New_Env  : Handle;
      T_C      : Cell;
      V_C      : Cell;
      F        : Frame;
      Good     : Boolean;
      Left     : Natural;
   begin
      Form := M.Ctl;

      Cadr_Of (H, M.Ctl, Bindings, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      Caddr_Of (H, M.Ctl, Test, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;
      --  The test clause is (test result ...): at least the test, and it
      --  has to be a list to have one.
      if not Is_Handle (Test) then
         Fail (M, Error_Malformed);
         return;
      end if;
      Fetch (H, To_Handle (Test), T_C, Good);
      if not Good or else T_C.Kind /= Cell_Pair then
         Fail (M, Error_Malformed);
         return;
      end if;

      --  Every binding is (var init) or (var init step) with a symbol in
      --  front, checked before anything runs; the first one's variable and
      --  initializer are kept for the K_Bind frame below.
      First_Var  := Nil_Value;
      First_Init := Nil_Value;
      First      := True;
      Elem := Bindings;
      Left := Max_List_Length + 1;
      while not Is_Nil (Elem) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         Car_Of (H, Elem, Bnd, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Do_Binding (H, Bnd, Var, Init, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         if not Is_Handle (Var) then
            Fail (M, Error_Malformed);
            return;
         end if;
         Fetch (H, To_Handle (Var), V_C, Good);
         if not Good or else V_C.Kind /= Cell_Symbol then
            Fail (M, Error_Malformed);
            return;
         end if;
         if First then
            First_Var  := Var;
            First_Init := Init;
            First      := False;
         end if;
         Cdr_Of (H, Elem, Next, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Elem := Next;
         Left := Left - 1;
      end loop;
      if not Is_Nil (Elem) then
         Fail (M, Error_Malformed);
         return;
      end if;

      Tr7.Env.New_Environment (H, M.Env, New_Env, Good);
      if not Good then
         Fail (M, Error_Heap_Full);
         return;
      end if;

      if Is_Nil (Bindings) then
         Do_Loop (H, M, Form, New_Env);
         return;
      end if;

      --  The first binding's initializer runs where the form appears, and
      --  the K_Bind frame comes back through Do_Loop when the last is stored.
      Cdr_Of (H, Bindings, Next, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      F := (Kind => K_Bind,
            Sym  => First_Var,
            Args => Next,
            Func => From_Handle (New_Env),
            Expr => Form,
            Env  => M.Env,
            Alt  => True_Value);
      Push (M, F, Good);
      if not Good then
         Fail (M, Error_Step_Limit);
         return;
      end if;
      M.Ctl := First_Init;
      M.Mode := Mode_Eval;
   end Start_Do;

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
      Proc    : Value;
      Tail2   : Value;
      F       : Frame;
      Left    : Natural := Max_List_Length + 1;
      Left_D  : Natural;
   begin
      loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         if Left = 0 then
            Fail (M, Error_Malformed);
            return;
         end if;
         Left := Left - 1;
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

         --  ((datum ...) => proc): evaluate proc and apply it to the key,
         --  exactly as cond's => clause does.
         if not Is_Nil (Forms) then
            Car_Of (H, Forms, Proc, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            if Is_Symbol_Named (H, Proc, "=>") then
               Cdr_Of (H, Forms, Tail2, Good);
               if not Good or else Is_Nil (Tail2) then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               Car_Of (H, Tail2, Proc, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               Cdr_Of (H, Tail2, Next, Good);
               if not Good or else not Is_Nil (Next) then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               F := (Kind => K_Cond_App,
                     Alt  => Key,
                     Env  => Env,
                     others => <>);
               Push (M, F, Good);
               if not Good then
                  Fail (M, Error_Step_Limit);
                  return;
               end if;
               M.Ctl := Proc;
               M.Mode := Mode_Eval;
               return;
            end if;
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
         Left_D := Max_List_Length + 1;
         while not Is_Nil (Cur) and then Left_D > 0 loop
            pragma Loop_Invariant (H.Ready);
            pragma Loop_Variant (Decreases => Left_D);
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
            Left_D := Left_D - 1;
         end loop;
         if not Match and then not Is_Nil (Cur) then
            Fail (M, Error_Malformed);
            return;
         end if;

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

   --  Collect one element -- the car or the cdr -- from each list of a list of
   --  lists, reversed: both the next call's arguments and the next round's
   --  tails need it, and reversing is what turns it into order.
   procedure Map_Elements
     (H        : in out Heap_Type;
      Lists    : Value;
      Take_Car : Boolean;
      Reversed : out Value;
      Ok       : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Cur  : Value := Lists;
      Acc  : Value := Nil_Value;
      L    : Value;
      Elem    : Value;
      Rest    : Value;
      New_Acc : Value;
      Good    : Boolean;
      Left    : Natural := Max_List_Length + 1;
   begin
      Reversed := Nil_Value;
      Ok := False;
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         if not Is_Handle (Cur) then
            return;
         end if;
         Car_Of (H, Cur, L, Good);
         if not Good then
            return;
         end if;
         if not Is_Handle (L) then
            return;
         end if;
         if Take_Car then
            Car_Of (H, L, Elem, Good);
         else
            Cdr_Of (H, L, Elem, Good);
         end if;
         if not Good then
            return;
         end if;

         Cons (H, Elem, Acc, New_Acc, Good);
         if not Good then
            return;
         end if;
         Acc := New_Acc;

         Cdr_Of (H, Cur, Rest, Good);
         if not Good then
            return;
         end if;
         Cur := Rest;
         Left := Left - 1;
      end loop;
      if not Is_Nil (Cur) then
         return;
      end if;

      Reversed := Acc;
      Ok := True;
   end Map_Elements;

   --  Continue one round of map/for-each: State carries the procedure (Func),
   --  the lists (Args), the reversed results (Expr) and the choice in Alt.
   --  Pushing the state and starting the call, or finishing, all happen here
   --  so the entry point and the continuation cannot drift apart.
   procedure Map_Next
     (H     : in out Heap_Type;
      M     : in out Machine;
      B     : in out Output_Buffer;
      State : Frame)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Cur    : Value := State.Args;
      L      : Value;
      Rest   : Value;
      Heads  : Value;
      Temp   : Value;
      Proc   : Value;
      Good   : Boolean;
      Empty  : Boolean;
      Saw_Empty : Boolean := False;
      Saw_Some  : Boolean := False;
      Left   : Natural := Max_List_Length + 1;
      Is_Map : constant Boolean :=
        State.Alt.Kind = Kind_Boolean and then State.Alt.B;
   begin
      --  All lists must end together; a shorter list is an error rather
      --  than a silent truncation.
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         Car_Of (H, Cur, L, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         if Is_Nil (L) then
            Saw_Empty := True;
         else
            Saw_Some := True;
         end if;
         Cdr_Of (H, Cur, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cur := Rest;
         Left := Left - 1;
      end loop;
      if not Is_Nil (Cur) then
         Fail (M, Error_Malformed);
         return;
      end if;
      if Saw_Empty and then Saw_Some then
         Fail (M, Error_Type);
         return;
      end if;
      Empty := Saw_Empty;

      if Empty then
         if Is_Map then
            Reverse_List (H, State.Expr, M.Result, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
         else
            --  for-each is for effect only.
            M.Result := Unspecified_Value;
         end if;
         M.Mode := Mode_Return;
         return;
      end if;

      --  Build the heads before pushing, so a full heap leaves no frame.
      Map_Elements (H, State.Args, True, Temp, Good);
      if not Good then
         Fail (M, Error_Heap_Full);
         return;
      end if;
      Reverse_List (H, Temp, Heads, Good);
      if not Good then
         Fail (M, Error_Malformed);
         return;
      end if;

      --  The state goes on the stack so the procedure's value comes back to
      --  it, then the call starts.
      Push (M, State, Good);
      if not Good then
         Fail (M, Error_Step_Limit);
         return;
      end if;
      Proc := State.Func;
      Apply_Procedure (H, Proc, Heads, M, B);
   end Map_Next;

   --  let-values and let*-values are source-to-source rewrites into nested
   --  call-with-values forms; the existing K_Values machinery then does the
   --  work.  The nesting gives let*-values semantics.  For let-values this
   --  is a permissive superset: an initializer that refers to a name bound
   --  by an earlier clause is accepted instead of being a scope error.
   procedure Let_Values_To_Code
     (H        : in out Heap_Type;
      Bindings : Value;
      Body_Forms : Value;
      Result   : out Value;
      Ok       : out Boolean;
      Fuel     : Natural)
     with
       Pre  => H.Ready,
       Post => H.Ready,
       Subprogram_Variant => (Decreases => Fuel)
   is
      Lambda_Sym : Value;
      Begin_Sym  : Value;
      CWv_Sym    : Value;
      Binding    : Value;
      Formals    : Value;
      Init       : Value;
      Rest       : Value;
      Rest_Code  : Value;
      Producer   : Value;
      Consumer   : Value;
      Nil_List   : constant Value := Nil_Value;
      Item       : Value;
      Item2      : Value;
      Good       : Boolean;
   begin
      Result := Nil_Value;
      Ok := False;
      if Fuel = 0 then
         return;
      end if;
      Intern (H, "begin", Begin_Sym, Good);
      if not Good then
         return;
      end if;
      if Is_Nil (Bindings) then
         Cons (H, Begin_Sym, Body_Forms, Result, Ok);
         return;
      end if;
      Intern (H, "lambda", Lambda_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "call-with-values", CWv_Sym, Good);
      if not Good then
         return;
      end if;
      Car_Of (H, Bindings, Binding, Good);
      if not Good or else not Is_Handle (Binding) then
         return;
      end if;
      Car_Of (H, Binding, Formals, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Binding, Rest, Good);
      if not Good or else not Is_Handle (Rest) then
         return;
      end if;
      Car_Of (H, Rest, Init, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Bindings, Rest, Good);
      if not Good then
         return;
      end if;
      Let_Values_To_Code (H, Rest, Body_Forms, Rest_Code, Good, Fuel - 1);
      if not Good then
         return;
      end if;

      --  (lambda () init)
      Cons (H, Init, Nil_List, Item, Good);
      if not Good then
         return;
      end if;
      Cons (H, Nil_List, Item, Item2, Good);
      if not Good then
         return;
      end if;
      Cons (H, Lambda_Sym, Item2, Producer, Good);
      if not Good then
         return;
      end if;
      --  (lambda formals rest-code)
      Cons (H, Rest_Code, Nil_List, Item, Good);
      if not Good then
         return;
      end if;
      Cons (H, Formals, Item, Item2, Good);
      if not Good then
         return;
      end if;
      Cons (H, Lambda_Sym, Item2, Consumer, Good);
      if not Good then
         return;
      end if;
      --  (call-with-values producer consumer)
      Cons (H, Consumer, Nil_List, Item, Good);
      if not Good then
         return;
      end if;
      Cons (H, Producer, Item, Item2, Good);
      if not Good then
         return;
      end if;
      Cons (H, CWv_Sym, Item2, Result, Good);
      if not Good then
         return;
      end if;
      Ok := True;
   end Let_Values_To_Code;

   --  Named let:
   --    (let name ((v init) ...) body ...)
   --  becomes
   --    ((lambda (name)
   --       (set! name (lambda (v ...) body ...))
   --       (name init ...))
   --     #f)
   --  which gives the recursive binding without a new frame kind.
   --  let* is rewritten to nested lets so every binding gets its own
   --  environment frame.  Sharing one frame made a later duplicate binding
   --  overwrite the earlier one, so a closure created before the rebinding
   --  saw the new value.
   procedure Let_Star_To_Code
     (H        : in out Heap_Type;
      Bindings : Value;
      Body_F : Value;
      Result   : out Value;
      Ok       : out Boolean;
      Fuel     : Natural)
     with
       Pre  => H.Ready,
       Post => H.Ready,
       Subprogram_Variant => (Decreases => Fuel)
   is
      Let_Sym  : Value;
      Begin_Sym : Value;
      Bnd      : Value;
      Var      : Value;
      Init     : Value;
      Rest     : Value;
      Rest_Code : Value;
      Binding  : Value;
      Bindings1 : Value;
      Item     : Value;
      Tmp      : Value;
      Good     : Boolean;
   begin
      Result := Nil_Value;
      Ok := False;
      if Fuel = 0 then
         return;
      end if;
      Intern (H, "begin", Begin_Sym, Good);
      if not Good then
         return;
      end if;
      if Is_Nil (Bindings) then
         Cons (H, Begin_Sym, Body_F, Result, Ok);
         return;
      end if;
      Intern (H, "let", Let_Sym, Good);
      if not Good then
         return;
      end if;
      Car_Of (H, Bindings, Bnd, Good);
      if not Good or else not Is_Handle (Bnd) then
         return;
      end if;
      Car_Of (H, Bnd, Var, Good);
      if not Good or else not Is_Handle (Var) then
         return;
      end if;
      declare
         VC : Cell;
      begin
         Fetch (H, To_Handle (Var), VC, Good);
         if not Good or else VC.Kind /= Cell_Symbol then
            return;
         end if;
      end;
      Cadr_Of (H, Bnd, Init, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Bindings, Rest, Good);
      if not Good then
         return;
      end if;
      --  ((var init))
      Cons (H, Init, Nil_Value, Tmp, Good);
      if not Good then
         return;
      end if;
      Cons (H, Var, Tmp, Binding, Good);
      if not Good then
         return;
      end if;
      Cons (H, Binding, Nil_Value, Bindings1, Good);
      if not Good then
         return;
      end if;
      Let_Star_To_Code (H, Rest, Body_F, Rest_Code, Good, Fuel - 1);
      if not Good then
         return;
      end if;
      --  (let ((var init)) rest-code)
      Cons (H, Rest_Code, Nil_Value, Tmp, Good);
      if not Good then
         return;
      end if;
      Cons (H, Bindings1, Tmp, Item, Good);
      if not Good then
         return;
      end if;
      Cons (H, Let_Sym, Item, Result, Good);
      if Good then
         Ok := True;
      end if;
   end Let_Star_To_Code;

   procedure Named_Let_To_Code
     (H      : in out Heap_Type;
      Form   : Value;
      Result : out Value;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Lambda_Sym : Value;
      Set_Sym    : Value;
      Rest       : Value;
      Tail       : Value;
      Name       : Value;
      Bindings   : Value;
      Body_Forms : Value;
      Cur        : Value;
      Bnd        : Value;
      Var        : Value;
      Init       : Value;
      NC         : Cell;
      Formals    : Value;
      Inits      : Value;
      F_Rev      : Value := Nil_Value;
      I_Rev      : Value := Nil_Value;
      Tmp        : Value;
      Tmp2       : Value;
      Tmp3       : Value;
      Rec_Lambda : Value;
      Call_Form  : Value;
      App        : Value;
      Left       : Natural := Max_List_Length + 1;
      Good       : Boolean;
   begin
      Result := Nil_Value;
      Ok := False;
      Cdr_Of (H, Form, Rest, Good);
      if not Good or else Is_Nil (Rest) then
         return;
      end if;
      Car_Of (H, Rest, Name, Good);
      if not Good or else not Is_Handle (Name) then
         return;
      end if;
      Fetch (H, To_Handle (Name), NC, Good);
      if not Good or else NC.Kind /= Cell_Symbol then
         return;
      end if;
      Cdr_Of (H, Rest, Tail, Good);
      if not Good or else Is_Nil (Tail) then
         return;
      end if;
      Car_Of (H, Tail, Bindings, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Tail, Body_Forms, Good);
      if not Good or else Is_Nil (Body_Forms) then
         return;
      end if;

      Cur := Bindings;
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         Car_Of (H, Cur, Bnd, Good);
         if not Good or else not Is_Handle (Bnd) then
            return;
         end if;
         Car_Of (H, Bnd, Var, Good);
         if not Good or else not Is_Handle (Var) then
            return;
         end if;
         declare
            VC : Cell;
         begin
            Fetch (H, To_Handle (Var), VC, Good);
            if not Good or else VC.Kind /= Cell_Symbol then
               return;
            end if;
         end;
         Cadr_Of (H, Bnd, Init, Good);
         if not Good then
            return;
         end if;
         Cons (H, Var, F_Rev, Tmp, Good);
         if not Good then
            return;
         end if;
         F_Rev := Tmp;
         Cons (H, Init, I_Rev, Tmp, Good);
         if not Good then
            return;
         end if;
         I_Rev := Tmp;
         declare
            Next : Value;
         begin
            Cdr_Of (H, Cur, Next, Good);
            if not Good then
               return;
            end if;
            Cur := Next;
         end;
         Left := Left - 1;
      end loop;
      if not Is_Nil (Cur) then
         return;
      end if;
      Reverse_List (H, F_Rev, Formals, Good);
      if not Good then
         return;
      end if;
      Reverse_List (H, I_Rev, Inits, Good);
      if not Good then
         return;
      end if;

      Intern (H, "lambda", Lambda_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "letrec", Set_Sym, Good);
      if not Good then
         return;
      end if;

      --  (lambda (v ...) body ...)
      Cons (H, Formals, Body_Forms, Tmp, Good);
      if not Good then
         return;
      end if;
      Cons (H, Lambda_Sym, Tmp, Rec_Lambda, Good);
      if not Good then
         return;
      end if;
      --  (name rec-lambda)
      Cons (H, Rec_Lambda, Nil_Value, Tmp, Good);
      if not Good then
         return;
      end if;
      Cons (H, Name, Tmp, Tmp2, Good);
      if not Good then
         return;
      end if;
      --  ((name rec-lambda))
      Cons (H, Tmp2, Nil_Value, Tmp, Good);
      if not Good then
         return;
      end if;
      --  (name init ...)
      Cons (H, Name, Inits, Call_Form, Good);
      if not Good then
         return;
      end if;
      --  (letrec ((name rec-lambda)) (name init ...))
      Cons (H, Call_Form, Nil_Value, Tmp2, Good);
      if not Good then
         return;
      end if;
      Cons (H, Tmp, Tmp2, Tmp3, Good);
      if not Good then
         return;
      end if;
      Cons (H, Set_Sym, Tmp3, App, Good);
      if not Good then
         return;
      end if;
      Result := App;
      Ok := True;
   end Named_Let_To_Code;

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
      Tmpl      : Value;
      QQ_Code   : Value;
      QQ_Status : Error_Code;
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
            return;
         end if;
         Cddr_Of (H, M.Ctl, Rest, Good);
         if not Good or else not Is_Nil (Rest) then
            Fail (M, Error_Malformed);
            return;
         end if;
         M.Mode := Mode_Return;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "quasiquote") then
         Cadr_Of (H, M.Ctl, Tmpl, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cddr_Of (H, M.Ctl, Rest, Good);
         if not Good or else not Is_Nil (Rest) then
            Fail (M, Error_Malformed);
            return;
         end if;

         --  The template becomes code and that code is evaluated in place,
         --  so quasiquote is a tail position and needs no frame of its own.
         --  The conversion cannot collect: the evaluator only collects
         --  between steps, and this whole conversion is one step, so the
         --  values held in locals here are safe without being roots.
         QQ_To_Code (H, Tmpl, 1, QQ_Code, QQ_Status, QQ_Fuel);
         if QQ_Status /= No_Error then
            Fail (M, QQ_Status);
            return;
         end if;
         M.Ctl := QQ_Code;
         M.Mode := Mode_Eval;
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
            Cdr_Of (H, Tail2, Tail, Good);
            if not Good or else not Is_Nil (Tail) then
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
         if not Good or else Is_Nil (Forms) then
            Fail (M, Error_Malformed);
            return;
         end if;
         Param_Fixed_Length (H, Params, Arity, Good);
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

      if Is_Symbol_Named (H, Head, "define-syntax") then
         --  (define-syntax name (syntax-rules ...)): build the transformer
         --  and install it like any other definition; expansion happens when
         --  the macro name appears in operator position.
         Cadr_Of (H, M.Ctl, Name, Good);
         if not Good or else not Is_Handle (Name) then
            Fail (M, Error_Malformed);
            return;
         end if;
         declare
            NC : Cell;
         begin
            Fetch (H, To_Handle (Name), NC, Good);
            if not Good or else NC.Kind /= Cell_Symbol then
               Fail (M, Error_Malformed);
               return;
            end if;
         end;
         Caddr_Of (H, M.Ctl, Expr_V, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cddr_Of (H, M.Ctl, Tail, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Tail, Tail2, Good);
         if not Good or else not Is_Nil (Tail2) then
            Fail (M, Error_Malformed);
            return;
         end if;
         Tr7.Macros.Build (H, Expr_V, Tmp, Good);
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
         M.Result := Tmp;
         M.Mode := Mode_Return;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "define") then
         Cadr_Of (H, M.Ctl, Name, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         if not Is_Handle (Name) then
            Fail (M, Error_Malformed);
            return;
         end if;

         declare
            Sig  : Cell;
            PN   : Cell;
            Sig_Ok : Boolean;
         begin
            Fetch (H, To_Handle (Name), Sig, Sig_Ok);
            if not Sig_Ok then
               Fail (M, Error_Malformed);
               return;
            end if;

            if Sig.Kind = Cell_Pair then
               --  (define (f x ...) body ...): name, parameters and body come
               --  apart here and the closure is built directly, so no `lambda`
               --  symbol has to exist in the environment.
               Tmp := Sig.Car;
               if not Is_Handle (Tmp) then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               Fetch (H, To_Handle (Tmp), PN, Sig_Ok);
               if not Sig_Ok or else PN.Kind /= Cell_Symbol then
                  Fail (M, Error_Malformed);
                  return;
               end if;

               Params := Sig.Cdr;
               Cddr_Of (H, M.Ctl, Forms, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               Param_Fixed_Length (H, Params, Arity, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               New_Closure (H, Params, Forms, M.Env, Arity, Hd, Good);
               if not Good then
                  Fail (M, Error_Heap_Full);
                  return;
               end if;

               F := (Kind => K_Define,
                     Sym  => Tmp,
                     Env  => M.Env,
                     others => <>);
               Push (M, F, Good);
               if not Good then
                  Fail (M, Error_Step_Limit);
                  return;
               end if;
               M.Result := From_Handle (Hd);
               M.Mode := Mode_Return;
               return;
            end if;

            if Sig.Kind /= Cell_Symbol then
               Fail (M, Error_Malformed);
               return;
            end if;
         end;

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
         declare
            NC : Cell;
         begin
            Fetch (H, To_Handle (Name), NC, Good);
            if not Good or else NC.Kind /= Cell_Symbol then
               Fail (M, Error_Malformed);
               return;
            end if;
         end;
         Caddr_Of (H, M.Ctl, Expr_V, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cddr_Of (H, M.Ctl, Tail, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Tail, Tail2, Good);
         if not Good or else not Is_Nil (Tail2) then
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
         --  (let name ((v init) ...) body ...) is a named let.  Two-element
         --  Cdrs distinguish it from the ordinary binding-list form.
         Cadr_Of (H, M.Ctl, Tmp, Good);
         if Good and then Is_Handle (Tmp) then
            declare
               NC : Cell;
            begin
               Fetch (H, To_Handle (Tmp), NC, Good);
               if Good and then NC.Kind = Cell_Symbol then
                  Named_Let_To_Code (H, M.Ctl, Tmp, Good);
                  if not Good then
                     Fail (M, Error_Malformed);
                     return;
                  end if;
                  M.Ctl := Tmp;
                  M.Mode := Mode_Eval;
                  return;
               end if;
            end;
         end if;
         Start_Let (H, M, Let_Parallel);
         return;
      elsif Is_Symbol_Named (H, Head, "let*") then
         Cadr_Of (H, M.Ctl, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cddr_Of (H, M.Ctl, Tail, Good);
         if not Good or else Is_Nil (Tail) then
            Fail (M, Error_Malformed);
            return;
         end if;
         Let_Star_To_Code (H, Rest, Tail, Tmp, Good,
                           Max_List_Length + 1);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         M.Ctl := Tmp;
         M.Mode := Mode_Eval;
         return;
      elsif Is_Symbol_Named (H, Head, "letrec") then
         Start_Let (H, M, Let_Sequential);
         return;
      elsif Is_Symbol_Named (H, Head, "do") then
         Start_Do (H, M);
         return;
      elsif Is_Symbol_Named (H, Head, "dynamic-wind") then
         --  (dynamic-wind before thunk after): the three expressions are
         --  evaluated once, left to right -- they are arguments, and the
         --  reference implementation does exactly this -- then `before` is
         --  called, then `thunk` under the wind frame, then `after` when
         --  control leaves, normally or through an escape.  The frame
         --  pushed here carries the thunk expression in Expr and the after
         --  expression in Alt; each later phase adds the procedure the
         --  previous one produced.
         Cdr_Of (H, M.Ctl, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Car_Of (H, Rest, Tmp, Good);          --  before expression
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Rest, Tail2, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Car_Of (H, Tail2, Test, Good);        --  thunk expression
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Tail2, Tail, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Car_Of (H, Tail, Expr_V, Good);       --  after expression
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Tail, Tmpl, Good);
         if not Good or else not Is_Nil (Tmpl) then
            Fail (M, Error_Malformed);
            return;
         end if;

         F := (Kind => K_DW_Before,
               Expr => Test,
               Alt  => Expr_V,
               Env  => M.Env,
               others => <>);
         Push (M, F, Good);
         if not Good then
            Fail (M, Error_Step_Limit);
            return;
         end if;
         M.Ctl := Tmp;
         M.Mode := Mode_Eval;
         return;

      elsif Is_Symbol_Named (H, Head, "call/cc") then
         --  (call/cc proc): evaluate the procedure, hand it an escape
         --  continuation, and receive either the procedure's value or the
         --  escape's -- both land on the same trampoline frame.
         Cdr_Of (H, M.Ctl, Rest, Good);
         if not Good or else Is_Nil (Rest) then
            Fail (M, Error_Malformed);
            return;
         end if;
         Car_Of (H, Rest, Tmp, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Rest, Tail2, Good);
         if not Good or else not Is_Nil (Tail2) then
            Fail (M, Error_Malformed);
            return;
         end if;

         declare
            Cont : Handle;
         begin
            New_Continuation (H, Cont, Good);
            if not Good then
               Fail (M, Error_Heap_Full);
               return;
            end if;
            --  Capture the stack at the call/cc form, before any trampoline
            --  frame exists: a continuation is now a heap snapshot, so it is
            --  re-entrant and call/cc itself can be a proper tail call.
            Capture_Stack (H, M, Cont, Good);
            if not Good then
               Fail (M, Error_Heap_Full);
               return;
            end if;
            F := (Kind => K_CallCC,
                  Expr => Tmp,
                  Sym  => From_Handle (Cont),
                  Env  => M.Env,
                  others => <>);
         end;
         Push (M, F, Good);
         if not Good then
            Fail (M, Error_Step_Limit);
            return;
         end if;
         M.Ctl := Tmp;
         M.Mode := Mode_Eval;
         return;

      elsif Is_Symbol_Named (H, Head, "call-with-values") then
         --  (call-with-values producer consumer): the consumer is evaluated
         --  first and held while the producer runs, so its value is in hand
         --  when the producer's values arrive.
         Cdr_Of (H, M.Ctl, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
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
         Car_Of (H, Tail2, Expr_V, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Tail2, Rest, Good);
         if not Good or else not Is_Nil (Rest) then
            Fail (M, Error_Malformed);
            return;
         end if;

         F := (Kind => K_Values,
               Expr => Tmp,
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

      if Is_Symbol_Named (H, Head, "map")
        or else Is_Symbol_Named (H, Head, "for-each")
      then
         --  (map proc list ...): the operands are evaluated like an
         --  application's; Sym marks the family (apply shares that field with
         --  its own value) and Alt carries the map/for-each choice forward.
         Cdr_Of (H, M.Ctl, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         if Is_Nil (Rest) then
            Fail (M, Error_Malformed);
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
         if Is_Nil (Tail2) then
            --  (map f) has no list to walk.
            Fail (M, Error_Malformed);
            return;
         end if;

         --  Alt carries the choice: True collects (map), False discards
         --  (for-each).  It is set after the aggregate because GNATprove
         --  cannot untangle a conditional expression inside one.
         F := (Kind => K_Operator,
               Expr => Tail2,
               Env  => M.Env,
               Sym  => False_Value,
               others => <>);
         if Is_Symbol_Named (H, Head, "map") then
            F.Alt := True_Value;
         else
            F.Alt := False_Value;
         end if;
         Push (M, F, Good);
         if not Good then
            Fail (M, Error_Step_Limit);
            return;
         end if;
         M.Ctl := Tmp;
         M.Mode := Mode_Eval;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "apply") then
         --  (apply proc arg ... last-list): the operands are walked like an
         --  application, but the final one is spread instead of passed.  The
         --  marker travels in the frame's Sym, which ordinary application
         --  leaves alone.
         Cdr_Of (H, M.Ctl, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         if Is_Nil (Rest) then
            Fail (M, Error_Malformed);
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
         if Is_Nil (Tail2) then
            --  (apply f) has no list to spread.
            Fail (M, Error_Malformed);
            return;
         end if;

         F := (Kind => K_Operator,
               Expr => Tail2,
               Env  => M.Env,
               Sym  => True_Value,
               others => <>);
         Push (M, F, Good);
         if not Good then
            Fail (M, Error_Step_Limit);
            return;
         end if;
         M.Ctl := Tmp;
         M.Mode := Mode_Eval;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "interaction-environment") then
         --  The top-level environment, as a first-class value.  R7RS calls
         --  this a procedure; with no OS or library machinery here it is a
         --  zero-argument special form, which is enough for (eval ...).
         Cdr_Of (H, M.Ctl, Rest, Good);
         if not Good or else not Is_Nil (Rest) then
            Fail (M, Error_Wrong_Arity);
            return;
         end if;
         declare
            Root  : Handle := M.Env;
            E     : Cell;
            Found : Boolean := False;
         begin
            for Depth in 0 .. Max_Env_Depth loop
               pragma Unreferenced (Depth);
               Fetch (H, Root, E, Good);
               if not Good or else E.Kind /= Cell_Environment then
                  Fail (M, Error_Type);
                  return;
               end if;
               if E.Env = Null_Handle then
                  Found := True;
                  exit;
               end if;
               Root := E.Env;
            end loop;
            if not Found then
               Fail (M, Error_Type);
               return;
            end if;
            M.Result := From_Handle (Root);
            M.Mode := Mode_Return;
         end;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "import") then
         --  There is no library system: the core bindings are already in the
         --  initial environment, so accepting the declaration lets R7RS
         --  scripts that begin with (import (scheme base) ...) run.  The
         --  library names are not validated.
         M.Result := Unspecified_Value;
         M.Mode := Mode_Return;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "let-values")
        or else Is_Symbol_Named (H, Head, "let*-values")
      then
         Cadr_Of (H, M.Ctl, Rest, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cddr_Of (H, M.Ctl, Tail, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Let_Values_To_Code (H, Rest, Tail, Tmp, Good,
                            Max_List_Length + 1);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         M.Ctl := Tmp;
         M.Mode := Mode_Eval;
         return;
      end if;

      if Is_Symbol_Named (H, Head, "eval") then
         --  (eval expression environment): evaluate the environment value
         --  first, then run the expression in it.  K_Eval carries the
         --  expression across that first evaluation; the second evaluation
         --  is in tail position because the frame has been popped.
         Cdr_Of (H, M.Ctl, Rest, Good);
         if not Good or else Is_Nil (Rest) then
            Fail (M, Error_Malformed);
            return;
         end if;
         Car_Of (H, Rest, Expr_V, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Rest, Tail, Good);
         if not Good or else Is_Nil (Tail) then
            Fail (M, Error_Malformed);
            return;
         end if;
         Car_Of (H, Tail, Tmp, Good);
         if not Good then
            Fail (M, Error_Malformed);
            return;
         end if;
         Cdr_Of (H, Tail, Tail2, Good);
         if not Good or else not Is_Nil (Tail2) then
            Fail (M, Error_Wrong_Arity);
            return;
         end if;
         F := (Kind => K_Eval,
               Expr => Expr_V,
               Alt  => Tmp,
               Env  => M.Env,
               others => <>);
         Push (M, F, Good);
         if not Good then
            Fail (M, Error_Step_Limit);
            return;
         end if;
         M.Ctl := Tmp;
         M.Mode := Mode_Eval;
         return;
      end if;

      --  A macro use: the head is a symbol bound to a transformer.  Expand
      --  it and evaluate the expansion in the same step; the expansion can
      --  itself contain macro uses, handled on subsequent steps.
      if Is_Handle (Head) then
         declare
            Bound  : Value;
            MC     : Cell;
            Mok    : Boolean;
            Status : Error_Code;
         begin
            Lookup (H, M.Env, Head, Bound, Status);
            Mok := Status = No_Error;
            if Mok and then Is_Handle (Bound) then
               Fetch (H, To_Handle (Bound), MC, Mok);
               if Mok and then MC.Kind = Cell_Macro then
                  Tr7.Macros.Expand
                    (H, To_Handle (Bound), M.Ctl, Tmp, Mok);
                  if not Mok then
                     Fail (M, Error_Malformed);
                     return;
                  end if;
                  M.Ctl := Tmp;
                  M.Mode := Mode_Eval;
                  return;
               end if;
            end if;
         end;
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
        or else Is_Flonum (M.Ctl)
        or else Is_EOF (M.Ctl)
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
            | Cell_Primitive | Cell_Environment | Cell_Continuation
            | Cell_Input_Port | Cell_Output_Port | Cell_Values | Cell_Macro =>
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
      C    : Cell;
      New_Args : Value;
      Proper   : Value;
      First    : Value;
      Rest     : Value;
      Var      : Value;
      Init     : Value;
      Acc      : Value;
      Cur      : Value;
      N_Last   : Natural;
      N_Pfx    : Natural;
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
            declare
               Set_Status : Error_Code;
            begin
               Tr7.Env.Set (H, F.Env, F.Sym, M.Result, Set_Status);
               if Set_Status /= No_Error then
                  Fail (M, Set_Status);
                  return;
               end if;
            end;
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
               if F.Alt.Kind = Kind_Boolean and then F.Alt.B then
                  --  A do form's initializers are all stored: the loop runs
                  --  in the environment they were bound into.
                  Do_Loop (H, M, F.Expr, To_Handle (F.Func));
               else
                  Start_Body (H, M, F.Expr, To_Handle (F.Func));
               end if;
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

            if F.Alt.Kind = Kind_Boolean and then F.Alt.B then
               --  A do binding is (var init [step]): the step expression is
               --  not needed here -- Do_Loop rebuilt the list of them from
               --  the form -- but Split_Binding would reject the third
               --  element outright.
               Do_Binding (H, First, Var, Init, Good);
            else
               Split_Binding (H, First, Var, Init, Good);
            end if;
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

         when K_Do | K_Do_Body | K_Do_Step =>
            if F.Kind = K_Do then
               --  The test has been evaluated in the bindings environment.
               if Is_True (M.Result) then
                  Cdr_Of (H, F.Alt, Rest, Good);
                  if not Good then
                     Fail (M, Error_Malformed);
                     return;
                  end if;
                  --  The results are the form's value, in tail position;
                  --  an empty clause is unspecified (Start_Body's answer).
                  Start_Body (H, M, Rest, F.Env);
                  return;
               end if;

               --  False: the body runs next, then the steps.
               if Is_Nil (F.Args) then
                  Do_Steps (H, M, F);
                  return;
               end if;
               F.Kind := K_Do_Body;
               Push (M, F, Good);
               if not Good then
                  Fail (M, Error_Step_Limit);
                  return;
               end if;
               Start_Body (H, M, F.Args, F.Env);
               return;
            end if;

            if F.Kind = K_Do_Body then
               --  The body has run; its values are discarded.
               Do_Steps (H, M, F);
               return;
            end if;

            --  A step's value has been evaluated: collect it, then run the
            --  next step or rebind and test again.  Steps are all evaluated
            --  before any variable is rebound, which is what makes them
            --  parallel.
            Cons (H, M.Result, F.Func, New_Args, Good);
            if not Good then
               Fail (M, Error_Heap_Full);
               return;
            end if;
            F.Func := New_Args;
            Do_Advance (H, M, F);

         when K_Eval =>
            --  M.Result is the environment value.  Now evaluate the
            --  expression argument in the caller's environment; its value
            --  is the datum to run in the target environment.
            if not Is_Handle (M.Result) then
               Fail (M, Error_Type);
               return;
            end if;
            Fetch (H, To_Handle (M.Result), C, Good);
            if not Good or else C.Kind /= Cell_Environment then
               Fail (M, Error_Type);
               return;
            end if;
            F.Kind := K_Eval_Expr;
            F.Env := To_Handle (M.Result);
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
            M.Ctl := F.Expr;
            M.Mode := Mode_Eval;

         when K_Eval_Expr =>
            --  M.Result is the expression to evaluate; F.Env is where.
            M.Env := F.Env;
            M.Ctl := M.Result;
            M.Mode := Mode_Eval;

         when K_DW_Before =>
            --  The `before` expression has been evaluated; its value (the
            --  before procedure) rides in Func while the thunk expression
            --  is evaluated next.
            F.Kind := K_DW_Thunk;
            F.Func := M.Result;
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
            M.Ctl := F.Expr;
            M.Env := F.Env;
            M.Mode := Mode_Eval;

         when K_DW_Thunk =>
            --  The thunk expression has been evaluated: the after
            --  expression moves into Expr for its turn and the thunk
            --  procedure rides in Alt.
            First := M.Result;
            F.Expr := F.Alt;
            F.Alt := First;
            F.Kind := K_DW_After;
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
            M.Ctl := F.Expr;
            M.Env := F.Env;
            M.Mode := Mode_Eval;

         when K_DW_After =>
            --  All three procedures are in hand (the after expression's
            --  value just arrived): call `before` first, as the reference
            --  implementation does, and hold the other two for their turns.
            First := F.Func;
            F.Sym := First;          --  remember before for a re-entry
            F.Expr := M.Result;
            F.Func := F.Alt;
            F.Kind := K_DW_Call;
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
            Apply_Procedure (H, First, Nil_Value, M, B);

         when K_DW_Call =>
            --  `before` has returned (its value is unspecified): call the
            --  thunk -- the wind frame goes on the stack first, so the
            --  thunk runs *under* it, which is what makes the wind visible
            --  to an escape.
            First := F.Func;
            F.Kind := K_Wind;
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
            Apply_Procedure (H, First, Nil_Value, M, B);

         when K_Wind =>
            --  The thunk has run: its value becomes the form's and rides
            --  in Func while the after procedure (Expr) is called.
            First := F.Expr;
            F.Func := M.Result;
            F.Kind := K_Wind_After;
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
            Apply_Procedure (H, First, Nil_Value, M, B);

         when K_Wind_After =>
            --  `after` has returned (its value is discarded): the thunk's
            --  value is this form's.
            M.Result := F.Func;
            M.Mode := Mode_Return;

         when K_Unwind =>
            --  One after procedure has run while unwinding: call the next,
            --  or -- with the list exhausted -- deliver the value to the
            --  captured frame this one sits directly above.
            Cdr_Of (H, F.Args, Rest, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            if Is_Nil (Rest) then
               M.Result := F.Func;
               M.Mode := Mode_Return;
               return;
            end if;
            F.Args := Rest;
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
            Car_Of (H, Rest, First, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            Apply_Procedure (H, First, Nil_Value, M, B);

         when K_CallCC =>
            --  The procedure has been evaluated.  The continuation was
            --  captured before this frame was pushed; the frame is already
            --  popped, so applying the procedure is in tail position and
            --  call/cc adds no frame to the callee's dynamic extent.
            Cons (H, F.Sym, Nil_Value, Rest, Good);
            if not Good then
               Fail (M, Error_Heap_Full);
               return;
            end if;
            First := M.Result;
            Apply_Procedure (H, First, Rest, M, B);

         when K_Values =>
            --  The consumer has been evaluated; its value goes into Func
            --  while the producer expression runs.
            F.Func := M.Result;
            F.Kind := K_Values_App;
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
            M.Ctl := F.Expr;
            M.Env := F.Env;
            M.Mode := Mode_Eval;

         when K_Values_App =>
            --  The producer expression has been evaluated: now call it, with
            --  no arguments, over the frame that holds the consumer.
            First := M.Result;
            F.Kind := K_Values_Recv;
            Push (M, F, Good);
            if not Good then
               Fail (M, Error_Step_Limit);
               return;
            end if;
            Apply_Procedure (H, First, Nil_Value, M, B);

         when K_Values_Recv =>
            --  The producer has run.  A values wrapper carries every value
            --  in its Car; anything else is the single value itself, which
            --  becomes a one-element argument list.
            First := F.Func;
            if Is_Handle (M.Result) then
               Fetch (H, To_Handle (M.Result), C, Good);
               if Good and then C.Kind = Cell_Values then
                  Rest := C.Car;
               else
                  Cons (H, M.Result, Nil_Value, Rest, Good);
                  if not Good then
                     Fail (M, Error_Heap_Full);
                     return;
                  end if;
               end if;
            else
               Cons (H, M.Result, Nil_Value, Rest, Good);
               if not Good then
                  Fail (M, Error_Heap_Full);
                  return;
               end if;
            end if;
            Apply_Procedure (H, First, Rest, M, B);

         when K_Map =>
            --  The call for this round has just returned its value: keep it
            --  (map), then advance every list to its tail and continue.
            if F.Alt.Kind = Kind_Boolean and then F.Alt.B then
               Cons (H, M.Result, F.Expr, New_Args, Good);
               if not Good then
                  Fail (M, Error_Heap_Full);
                  return;
               end if;
               F.Expr := New_Args;
            end if;

            Map_Elements (H, F.Args, False, Acc, Good);
            if not Good then
               Fail (M, Error_Heap_Full);
               return;
            end if;
            Reverse_List (H, Acc, Proper, Good);
            if not Good then
               Fail (M, Error_Malformed);
               return;
            end if;
            F.Args := Proper;
            Map_Next (H, M, B, F);

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
            if Is_Nil (F.Expr)
              and then F.Sym.Kind = Kind_Boolean
              and then F.Sym.B
            then
               --  apply: the final argument is a list to spread.  F.Args holds
               --  the earlier arguments reversed, so walking it and consing
               --  each onto that list yields them in order and shares its
               --  tail.  Length validates that the last argument really is a
               --  proper list, and the pair of counts keeps the result inside
               --  Max_List_Length.
               Length (H, M.Result, N_Last, Good);
               if not Good then
                  Fail (M, Error_Type);
                  return;
               end if;
               Length (H, F.Args, N_Pfx, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               if N_Last + N_Pfx > Max_List_Length then
                  Fail (M, Error_Overflow);
                  return;
               end if;

               Acc := M.Result;
               Cur := F.Args;
               while not Is_Nil (Cur) loop
                  pragma Loop_Invariant (H.Ready);
                  Car_Of (H, Cur, First, Good);
                  if not Good then
                     Fail (M, Error_Malformed);
                     return;
                  end if;
                  Cons (H, First, Acc, New_Args, Good);
                  if not Good then
                     Fail (M, Error_Heap_Full);
                     return;
                  end if;
                  Acc := New_Args;
                  Cdr_Of (H, Cur, Rest, Good);
                  if not Good then
                     Fail (M, Error_Malformed);
                     return;
                  end if;
                  Cur := Rest;
               end loop;

               First := Acc;
               Apply_Procedure (H, F.Func, First, M, B);
               return;
            end if;

            if Is_Nil (F.Expr)
              and then F.Sym.Kind = Kind_Boolean
              and then not F.Sym.B
            then
               --  map / for-each: the value just returned is the *last* list,
               --  so it is accumulated exactly as in an application and the
               --  rounds start from the complete list of lists.  (apply, whose
               --  marker is the other boolean, must not do this: its final
               --  operand is spread, not passed.)
               Cons (H, M.Result, F.Args, New_Args, Good);
               if not Good then
                  Fail (M, Error_Heap_Full);
                  return;
               end if;
               Reverse_List (H, New_Args, Proper, Good);
               if not Good then
                  Fail (M, Error_Malformed);
                  return;
               end if;
               F.Kind := K_Map;
               F.Args := Proper;
               F.Expr := Nil_Value;
               Map_Next (H, M, B, F);
               return;
            end if;

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
      Msg   : Value;
      Roots : Root_Array := (others => Valid_Cell_Index'First);
      Count : Root_Count := 0;

      --  Resolve one root value to its live cell and append it.  Duplicates
      --  are fine -- the collector's rooting loop skips a cell it has
      --  already marked -- but the bound is never reached: there are at
      --  most Max_Cells distinct cells, and the array is sized for the
      --  deduplicated worst case of the raw root slots.
      procedure Add (V : Value) is
         Idx : Cell_Index;
      begin
         Idx := Live_Cell (H, V);
         if Idx /= 0 and then Count < Max_Roots then
            Count := Count + 1;
            Roots (Count) := Valid_Cell_Index (Idx);
         end if;
      end Add;

      --  One root value already resolved: either dead (nothing to keep) or
      --  present in the list built so far.  Proof-only -- it lives in loop
      --  invariants, which the policy file compiles away.
      function In_Roots (V : Value) return Boolean is
        (Live_Cell (H, V) = 0
         or else (for some K in 1 .. Count => Roots (K) = Live_Cell (H, V)));

   begin
      --  The CEK state is a complete root set between steps: control, the
      --  value being delivered, the current environment and every frame on
      --  the continuation stack.  Nothing is marked here -- Collect marks
      --  the cells, after it has jumped the epoch to a clean cycle.
      Add (M.Ctl);
      Add (M.Result);
      --  A pending user error's text.  It is only set on the step that
      --  halts, so nothing can collect it in between -- this is defence in
      --  depth -- and it is copied to a local first because a component of
      --  H cannot travel with H.
      Msg := H.Error_Msg;
      Add (Msg);
      Add (From_Handle (Env));
      Add (From_Handle (M.Env));

      for I in 1 .. M.Top loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (I <= M.Top);
         --  Rooting never touches the free list, so the free cells counted
         --  on entry are still there for Collect to report on.
         pragma Loop_Invariant (H.Free_Count = H.Free_Count'Loop_Entry);
         --  The list grows by at most six cells per frame plus the five
         --  direct roots, so the append guard can never drop a root.
         pragma Loop_Invariant (Count <= 6 * I + 5);
         --  Every root resolved so far is in the list: the reachability
         --  goal downstream is stated over this list, so completeness is
         --  what makes it a statement about the true roots.
         pragma Loop_Invariant
           (In_Roots (M.Ctl) and then In_Roots (M.Result)
            and then In_Roots (Msg)
            and then In_Roots (From_Handle (Env))
            and then In_Roots (From_Handle (M.Env)));
         pragma Loop_Invariant
           (for all K in 1 .. I - 1 =>
              (In_Roots (M.Stack (K).Expr)
               and then In_Roots (M.Stack (K).Alt)
               and then In_Roots (M.Stack (K).Func)
               and then In_Roots (M.Stack (K).Args)
               and then In_Roots (M.Stack (K).Sym)
               and then In_Roots (From_Handle (M.Stack (K).Env))));
         --  A list cell was live when appended and nothing between here
         --  and Collect frees, so Collect's precondition holds.
         pragma Loop_Invariant
           (for all K in 1 .. Count =>
              H.Cells (Roots (K)).Kind /= Cell_Free);
         Add (M.Stack (I).Expr);
         Add (M.Stack (I).Alt);
         Add (M.Stack (I).Func);
         Add (M.Stack (I).Args);
         Add (M.Stack (I).Sym);
         Add (From_Handle (M.Stack (I).Env));
      end loop;

      Collect (H, Roots, Count);
      if not H.Mark_Failed then
         Reach.Sweep (H, Roots, Count);
      end if;
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
      Stress_Due : Natural range 0 .. GC_Stress_Every :=
        GC_Stress_Every - 1;
   begin
      M.Mode := Mode_Eval;
      M.Ctl := Expr;
      M.Env := Env;
      M.Top := 0;
      M.Result := Nil_Value;
      M.Error := No_Error;
      H.Error_Msg := Nil_Value;

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
            Stress_Due := GC_Stress_Every - 1;
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
