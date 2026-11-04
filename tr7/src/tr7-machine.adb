with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Env; use Tr7.Env;
with Tr7.Heap; use Tr7.Heap;
with Tr7.Pairs; use Tr7.Pairs;
with Tr7.Primitives; use Tr7.Primitives;
with Tr7.Runtime; use Tr7.Runtime;
with Tr7.Values; use Tr7.Values;

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
      if M.Top >= Max_Stack then
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
     with Pre => H.Ready
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
     with Pre => H.Ready
   is
      C     : Cell;
      Valid : Boolean;
      Good  : Boolean;
      Res   : Value;
      Arity : Natural;
      New_Env : Handle;
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
            Call (H, C.Prim, Args, Res, B, Good);
            if not Good then
               Fail (M, Error_Type);
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
            Cdr_Of (H, Lambda_Body, Rest, Good);
            if not Good then
               Fail (M, Error_Malformed);
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
     (H : in out Heap_Type;
      M : in out Machine)
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

   procedure Eval_Pair
     (H : in out Heap_Type;
      M : in out Machine)
     with Pre => H.Ready
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
         F := (Kind => K_Begin,
               Expr => Tail2,
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
     with Pre => H.Ready
   is
      C     : Cell;
      Valid : Boolean;
      Good  : Boolean;
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

         when Cell_String | Cell_Closure | Cell_Primitive
            | Cell_Environment | Cell_Continuation =>
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
     with Pre => H.Ready
   is
      F    : Frame;
      Good : Boolean;
      New_Args : Value;
      Proper   : Value;
      First    : Value;
      Rest     : Value;
      New_Env  : Handle;
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
               Apply_Procedure (H, M.Result, Nil_Value, M, B);
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
     with Pre => H.Ready
   is
   begin
      if M.Mode = Mode_Eval then
         Eval_Step (H, M);
      elsif M.Mode = Mode_Return then
         Return_Step (H, M, B);
      end if;
   end Step;

   procedure Evaluate
     (H      : in out Heap_Type;
      Env    : Handle;
      Expr   : Value;
      M      : in out Machine;
      B      : in out Output_Buffer)
   is
   begin
      M.Mode := Mode_Eval;
      M.Ctl := Expr;
      M.Env := Env;
      M.Top := 0;
      M.Result := Nil_Value;
      M.Error := No_Error;
      M.Steps := 0;

      while M.Mode /= Mode_Halt loop
         pragma Loop_Invariant (M.Steps <= Max_Steps);
         if M.Steps >= Max_Steps then
            M.Error := Error_Step_Limit;
            M.Mode := Mode_Halt;
         else
            Step (H, M, B);
            M.Steps := M.Steps + 1;
         end if;
      end loop;
   end Evaluate;

end Tr7.Machine;
