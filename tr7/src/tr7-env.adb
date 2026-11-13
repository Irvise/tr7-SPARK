with Tr7.Config; use Tr7.Config;
with Tr7.Pairs; use Tr7.Pairs;

package body Tr7.Env with
   SPARK_Mode => On
is


   --  Locate the (symbol . value) cell for Sym in one frame.  Returning the
   --  cell rather than its value lets every caller both read and update the
   --  binding, so each of them walks the frame exactly once.
   procedure Find_In_Frame
     (H       : Heap_Type;
      List    : Value;
      Sym     : Value;
      Binding : out Handle;
      Found   : out Boolean;
      Ok      : out Boolean)
     with Pre => H.Ready
   is
      Cur : Value := List;
   begin
      Binding := Null_Handle;
      Found := False;
      Ok := False;
      loop
         if Is_Nil (Cur) then
            Ok := True;
            return;
         end if;

         if not Is_Handle (Cur) then
            return;
         end if;

         declare
            Node_Car, Node_Cdr : Value;
            Bind_Car : Value;
            Good : Boolean;
         begin
            Pair_Fields (H, To_Handle (Cur), Node_Car, Node_Cdr, Good);
            if not Good or else not Is_Handle (Node_Car) then
               return;
            end if;
            Pair_Car (H, To_Handle (Node_Car), Bind_Car, Good);
            if not Good then
               return;
            end if;

            if Is_Handle (Sym)
              and then Is_Handle (Bind_Car)
              and then Same_Handle (To_Handle (Bind_Car), To_Handle (Sym))
            then
               Binding := To_Handle (Node_Car);
               Found := True;
               Ok := True;
               return;
            end if;

            Cur := Node_Cdr;
         end;
      end loop;
   end Find_In_Frame;

   procedure New_Environment
     (H      : in out Heap_Type;
      Parent : Handle;
      Result : out Handle;
      Ok     : out Boolean)
   is
   begin
      Tr7.Heap.New_Environment (H, Parent, Result, Ok);
   end New_Environment;

   procedure Define
     (H   : in out Heap_Type;
      Env : Handle;
      Sym : Value;
      Val : Value;
      Ok  : out Boolean)
   is
      Bindings : Value;
      Found   : Boolean;
      Valid   : Boolean;
      Bind    : Handle;
      Binding : Value;
      New_List : Value;
      Hd      : Handle;
   begin
      Ok := False;
      Environment_Bindings (H, Env, Bindings, Valid);
      if not Valid then
         return;
      end if;

      Find_In_Frame (H, Bindings, Sym, Bind, Found, Valid);
      if not Valid then
         return;
      end if;

      if Found then
         Set_Cdr (H, Bind, Val, Valid);
         Ok := Valid;
      else
         New_Pair (H, Sym, Val, Hd, Valid);
         if not Valid then
            return;
         end if;
         Binding := From_Handle (Hd);
         Cons (H, Binding, Bindings, New_List, Valid);
         if not Valid or else Env.Index not in Valid_Cell_Index then
            return;
         end if;
         H.Cells (Valid_Cell_Index (Env.Index)).Car := New_List;
         Ok := True;
      end if;
   end Define;

   procedure Set
     (H      : in out Heap_Type;
      Env    : Handle;
      Sym    : Value;
      Val    : Value;
      Status : out Error_Code)
   is
      Cur_Env : Handle := Env;
      Parent  : Handle;
      Bindings : Value;
      Valid   : Boolean;
      Found   : Boolean;
      Bind    : Handle;
   begin
      for Depth in 0 .. Max_Env_Depth loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (H.Free_Count = H.Free_Count'Loop_Entry);
         if Cur_Env = Null_Handle then
            Status := Error_Unbound;
            return;
         end if;
         Environment_Fields (H, Cur_Env, Parent, Bindings, Valid);
         if not Valid then
            Status := Error_Type;
            return;
         end if;

         Find_In_Frame (H, Bindings, Sym, Bind, Found, Valid);
         if not Valid then
            Status := Error_Type;
            return;
         end if;

         if Found then
            Set_Cdr (H, Bind, Val, Valid);
            Status := (if Valid then No_Error else Error_Type);
            return;
         end if;

         Cur_Env := Parent;
      end loop;
      Status := Error_Env_Depth;
   end Set;

   procedure Lookup
     (H      : Heap_Type;
      Env    : Handle;
      Sym    : Value;
      Val    : out Value;
      Status : out Error_Code)
   is
      Cur_Env : Handle := Env;
      Parent  : Handle;
      Bindings : Value;
      B_Cdr : Value;
      Valid   : Boolean;
      Found   : Boolean;
      Bind    : Handle;
   begin
      Val := Nil_Value;
      for Depth in 0 .. Max_Env_Depth loop
         pragma Loop_Invariant (H.Ready);
         if Cur_Env = Null_Handle then
            Status := Error_Unbound;
            return;
         end if;
         Environment_Fields (H, Cur_Env, Parent, Bindings, Valid);
         if not Valid then
            Status := Error_Type;
            return;
         end if;

         Find_In_Frame (H, Bindings, Sym, Bind, Found, Valid);
         if not Valid then
            Status := Error_Type;
            return;
         end if;
         if Found then
            Pair_Cdr (H, Bind, B_Cdr, Valid);
            if not Valid then
               Status := Error_Type;
               return;
            end if;
            Val := B_Cdr;
            Status := No_Error;
            return;
         end if;

         Cur_Env := Parent;
      end loop;
      Status := Error_Env_Depth;
   end Lookup;

end Tr7.Env;
