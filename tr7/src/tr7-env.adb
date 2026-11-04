with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Pairs; use Tr7.Pairs;

package body Tr7.Env with
   SPARK_Mode => On
is

   procedure Environment_Cell
     (H   : Heap_Type;
      Env : Handle;
      C   : out Cell;
      Ok  : out Boolean)
     with Pre => H.Ready
   is
   begin
      Fetch (H, Env, C, Ok);
      if Ok and then C.Kind /= Cell_Environment then
         Ok := False;
      end if;
   end Environment_Cell;

   procedure Find_In_Frame
     (H     : Heap_Type;
      List  : Value;
      Sym   : Value;
      Found : out Boolean;
      Val   : out Value;
      Ok    : out Boolean)
     with Pre => H.Ready
   is
      Cur : Value := List;
   begin
      Found := False;
      Val := Nil_Value;
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
            Node  : Cell;
            Binding_Cell : Cell;
            Good  : Boolean;
         begin
            Fetch (H, To_Handle (Cur), Node, Good);
            if not Good or else Node.Kind /= Cell_Pair
              or else not Is_Handle (Node.Car)
            then
               return;
            end if;
            Fetch (H, To_Handle (Node.Car), Binding_Cell, Good);
            if not Good or else Binding_Cell.Kind /= Cell_Pair then
               return;
            end if;

            if Is_Handle (Sym)
              and then Is_Handle (Binding_Cell.Car)
              and then Same_Handle (To_Handle (Binding_Cell.Car), To_Handle (Sym))
            then
               Found := True;
               Val := Binding_Cell.Cdr;
               Ok := True;
               return;
            end if;

            Cur := Node.Cdr;
         end;
      end loop;
   end Find_In_Frame;

   procedure Update_In_Frame
     (H    : in out Heap_Type;
      List : Value;
      Sym  : Value;
      Val  : Value;
      Ok   : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Cur : Value := List;
   begin
      Ok := False;
      while not Is_Nil (Cur) loop
         if not Is_Handle (Cur) then
            return;
         end if;

         declare
            Node  : Cell;
            Binding_Cell : Cell;
            Good  : Boolean;
         begin
            Fetch (H, To_Handle (Cur), Node, Good);
            if not Good or else Node.Kind /= Cell_Pair
              or else not Is_Handle (Node.Car)
            then
               return;
            end if;
            Fetch (H, To_Handle (Node.Car), Binding_Cell, Good);
            if not Good or else Binding_Cell.Kind /= Cell_Pair then
               return;
            end if;
            if Is_Handle (Sym)
              and then Is_Handle (Binding_Cell.Car)
              and then Same_Handle (To_Handle (Binding_Cell.Car), To_Handle (Sym))
            then
               Set_Cdr (H, To_Handle (Node.Car), Val, Good);
               Ok := Good;
               return;
            end if;
            Cur := Node.Cdr;
         end;
      end loop;
   end Update_In_Frame;

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
      E       : Cell;
      Found   : Boolean;
      Old     : Value;
      Valid   : Boolean;
      Binding : Value;
      New_List : Value;
      Hd      : Handle;
   begin
      Ok := False;
      Environment_Cell (H, Env, E, Valid);
      if not Valid then
         return;
      end if;

      Find_In_Frame (H, E.Car, Sym, Found, Old, Valid);
      if not Valid then
         return;
      end if;

      if Found then
         Update_In_Frame (H, E.Car, Sym, Val, Valid);
         Ok := Valid;
      else
         New_Pair (H, Sym, Val, Hd, Valid);
         if not Valid then
            return;
         end if;
         Binding := From_Handle (Hd);
         Cons (H, Binding, E.Car, New_List, Valid);
         if not Valid or else Env.Index not in Valid_Cell_Index then
            return;
         end if;
         H.Cells (Valid_Cell_Index (Env.Index)).Car := New_List;
         Ok := True;
      end if;
   end Define;

   procedure Set
     (H   : in out Heap_Type;
      Env : Handle;
      Sym : Value;
      Val : Value;
      Ok  : out Boolean)
   is
      Cur_Env : Handle := Env;
      E       : Cell;
      Valid   : Boolean;
      Found   : Boolean;
      Old     : Value;
   begin
      Ok := False;
      for Depth in 0 .. Max_Env_Depth loop
         pragma Loop_Invariant (H.Ready);
         Environment_Cell (H, Cur_Env, E, Valid);
         if not Valid then
            return;
         end if;

         Find_In_Frame (H, E.Car, Sym, Found, Old, Valid);
         if not Valid then
            return;
         end if;

         if Found then
            Update_In_Frame (H, E.Car, Sym, Val, Valid);
            Ok := Valid;
            return;
         end if;

         Cur_Env := E.Env;
      end loop;
   end Set;

   procedure Lookup
     (H   : Heap_Type;
      Env : Handle;
      Sym : Value;
      Val : out Value;
      Ok  : out Boolean)
   is
      Cur_Env : Handle := Env;
      E       : Cell;
      Valid   : Boolean;
      Found   : Boolean;
   begin
      Val := Nil_Value;
      Ok := False;
      for Depth in 0 .. Max_Env_Depth loop
         Environment_Cell (H, Cur_Env, E, Valid);
         if not Valid then
            return;
         end if;

         Find_In_Frame (H, E.Car, Sym, Found, Val, Valid);
         if not Valid then
            return;
         end if;
         if Found then
            Ok := True;
            return;
         end if;

         Cur_Env := E.Env;
      end loop;
   end Lookup;

end Tr7.Env;
