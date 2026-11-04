with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Pairs; use Tr7.Pairs;
with Tr7.Writer; use Tr7.Writer;

package body Tr7.Primitives with
   SPARK_Mode => On
is


   subtype Fixnum is Integer_64 range Fixnum_Min .. Fixnum_Max;

   function Name_Of (P : Primitive_Id) return String is
   begin
      case P is
         when P_None            => return "";
         when P_Add             => return "+";
         when P_Sub             => return "-";
         when P_Mul             => return "*";
         when P_Num_Equal       => return "=";
         when P_Less            => return "<";
         when P_Greater         => return ">";
         when P_Less_Equal      => return "<=";
         when P_Greater_Equal   => return ">=";
         when P_Cons            => return "cons";
         when P_Car             => return "car";
         when P_Cdr             => return "cdr";
         when P_List            => return "list";
         when P_Null_P          => return "null?";
         when P_Pair_P          => return "pair?";
         when P_Eq_P            => return "eq?";
         when P_Not             => return "not";
         when P_Display         => return "display";
         when P_Newline         => return "newline";
         when P_Write           => return "write";
         when P_Free_Cells      => return "free-cells";
      end case;
   end Name_Of;

   function Bool (B : Boolean) return Value is
     (From_Boolean (B));

   procedure Get_Fixnum
     (V  : Value;
      N  : out Fixnum;
      Ok : out Boolean)
   is
   begin
      N := 0;
      Ok := Is_Fixnum (V) and then V.N in Fixnum_Min .. Fixnum_Max;
      if Ok then
         N := Fixnum (V.N);
      end if;
   end Get_Fixnum;

   procedure Args_Of
     (H    : Heap_Type;
      Args : Value;
      Arr  : out Value_Array;
      Len  : out Natural;
      Ok   : out Boolean)
     with
       Pre  => H.Ready,
       Post => (if Ok then Len <= Arr'Length)
   is
   begin
      To_Array (H, Args, Arr, Len, Ok);
   end Args_Of;

   procedure Check_Arity
     (Len      : Natural;
      Min, Max : Natural;
      Ok       : out Boolean)
     with Post => (if Ok then Len in Min .. Max)
   is
   begin
      Ok := Len >= Min and then Len <= Max;
   end Check_Arity;

   procedure Add
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Sum  : Fixnum := 0;
      Term : Fixnum;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;

      for I in 1 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         pragma Loop_Invariant (Sum >= Fixnum_Min);
         pragma Loop_Invariant (Sum <= Fixnum_Max);
         Get_Fixnum (Arr (I), Term, Good);
         if not Good then
            return;
         end if;
         if Term > 0 then
            if Sum > Fixnum_Max - Term then
               Status := Error_Overflow;
               return;
            end if;
         elsif Term < 0 then
            if Sum < Fixnum_Min - Term then
               Status := Error_Overflow;
               return;
            end if;
         end if;
         Sum := Sum + Term;
      end loop;

      Result := From_Fixnum (Integer_64 (Sum));
      Status := No_Error;
   end Add;

   procedure Sub
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Acc  : Fixnum;
      Term : Fixnum;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      if Len = 0 then
         Status := Error_Wrong_Arity;
         return;
      end if;

      Get_Fixnum (Arr (1), Acc, Good);
      if not Good then
         return;
      end if;

      if Len = 1 then
         if Acc = Fixnum_Min then
            Status := Error_Overflow;
            return;
         end if;
         Result := From_Fixnum (Integer_64 (-Acc));
         Status := No_Error;
         return;
      end if;

      for I in 2 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         pragma Loop_Invariant (Acc >= Fixnum_Min);
         pragma Loop_Invariant (Acc <= Fixnum_Max);
         Get_Fixnum (Arr (I), Term, Good);
         if not Good then
            return;
         end if;
         if Term > 0 then
            if Acc < Fixnum_Min + Term then
               Status := Error_Overflow;
               return;
            end if;
         elsif Term < 0 then
            if Acc > Fixnum_Max + Term then
               Status := Error_Overflow;
               return;
            end if;
         end if;
         Acc := Acc - Term;
      end loop;

      Result := From_Fixnum (Integer_64 (Acc));
      Status := No_Error;
   end Sub;

   procedure Mul_Fixnum
     (A  : Fixnum;
      B  : Fixnum;
      R  : out Fixnum;
      Ok : out Boolean)
     with Post => (if Ok then Integer_64 (R) = Integer_64 (A) * Integer_64 (B))
   is
      P : Integer_64;
   begin
      R := 0;
      Ok := False;

      --  Both operands are in -(2**31) .. 2**31 - 1, so the mathematical
      --  product is at most 2**62 and fits in Integer_64.  The multiplication
      --  cannot overflow, and exactness reduces to one range check, which is
      --  what the postcondition above records.
      P := Integer_64 (A) * Integer_64 (B);
      if P in Fixnum_Min .. Fixnum_Max then
         R := Fixnum (P);
         Ok := True;
      end if;
   end Mul_Fixnum;

   procedure Mul
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Acc  : Fixnum := 1;
      Term : Fixnum;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;

      for I in 1 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         pragma Loop_Invariant (Acc >= Fixnum_Min);
         pragma Loop_Invariant (Acc <= Fixnum_Max);
         Get_Fixnum (Arr (I), Term, Good);
         if not Good then
            return;
         end if;
         Mul_Fixnum (Acc, Term, Acc, Good);
         if not Good then
            Status := Error_Overflow;
            return;
         end if;
      end loop;

      Result := From_Fixnum (Integer_64 (Acc));
      Status := No_Error;
   end Mul;

   procedure Compare_Chain
     (H       : Heap_Type;
      Args    : Value;
      Mode    : Primitive_Id;
      Result  : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Prev : Fixnum;
      Cur  : Fixnum;
      Res  : Boolean := True;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;

      if Len = 0 then
         Result := True_Value;
         Status := No_Error;
         return;
      end if;

      Get_Fixnum (Arr (1), Prev, Good);
      if not Good then
         return;
      end if;

      for I in 2 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         Get_Fixnum (Arr (I), Cur, Good);
         if not Good then
            return;
         end if;
         case Mode is
            when P_Num_Equal =>
               Res := Res and then Prev = Cur;
            when P_Less =>
               Res := Res and then Prev < Cur;
            when P_Greater =>
               Res := Res and then Prev > Cur;
            when P_Less_Equal =>
               Res := Res and then Prev <= Cur;
            when P_Greater_Equal =>
               Res := Res and then Prev >= Cur;
            when others =>
               return;
         end case;
         Prev := Cur;
      end loop;

      Result := Bool (Res);
      Status := No_Error;
   end Compare_Chain;

   procedure Cons_Prim
     (H      : in out Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 2, 2, Good);
      if not Good then
      Status := Error_Wrong_Arity;
      return;
      end if;
      Cons (H, Arr (1), Arr (2), Result, Good);
      Status := (if Good then No_Error else Error_Heap_Full);
   end Cons_Prim;

   procedure Car_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 1, 1, Good);
      if not Good then
      Status := Error_Wrong_Arity;
      return;
      end if;
      Car_Of (H, Arr (1), Result, Good);
      Status := (if Good then No_Error else Error_Type);
   end Car_Prim;

   procedure Cdr_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 1, 1, Good);
      if not Good then
      Status := Error_Wrong_Arity;
      return;
      end if;
      Cdr_Of (H, Arr (1), Result, Good);
      Status := (if Good then No_Error else Error_Type);
   end Cdr_Prim;

   procedure List_Prim
     (H      : in out Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Arr   : Value_Array;
      Len   : Natural;
      Good  : Boolean;
      Head  : Handle := Null_Handle;
      Tail  : Handle := Null_Handle;
      Hd    : Handle;
   begin
      Result := Nil_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;

      for I in 1 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         pragma Loop_Invariant (H.Ready);
         New_Pair (H, Arr (I), Nil_Value, Hd, Good);
         if not Good then
            return;
         end if;
         if I = 1 then
            Head := Hd;
         else
            Set_Cdr (H, Tail, From_Handle (Hd), Good);
            if not Good then
               return;
            end if;
         end if;
         Tail := Hd;
      end loop;

      if Len = 0 then
         Result := Nil_Value;
      else
         Result := From_Handle (Head);
      end if;
      Status := No_Error;
   end List_Prim;

   procedure Eq_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      A, B : Value;
      Equal : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 2, 2, Good);
      if not Good then
      Status := Error_Wrong_Arity;
      return;
      end if;

      A := Arr (1);
      B := Arr (2);
      if A.Kind /= B.Kind then
         Equal := False;
      else
         case A.Kind is
            when Kind_Void | Kind_Nil | Kind_Unspecified =>
               Equal := True;
            when Kind_Boolean =>
               Equal := A.B = B.B;
            when Kind_Fixnum =>
               Equal := A.N = B.N;
            when Kind_Character =>
               Equal := A.C = B.C;
            when Kind_Handle =>
               Equal := Same_Handle (A.H, B.H);
         end case;
      end if;
      Result := Bool (Equal);
      Status := No_Error;
   end Eq_Prim;

   procedure Predicate
     (H      : Heap_Type;
      Args   : Value;
      P      : Primitive_Id;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Res  : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 1, 1, Good);
      if not Good then
      Status := Error_Wrong_Arity;
      return;
      end if;

      if P = P_Null_P then
         Res := Is_Nil (Arr (1));
      elsif P = P_Pair_P then
         Res := Is_Handle (Arr (1));
         if Res then
            declare
               Kind  : Cell_Kind;
               Valid : Boolean;
            begin
               Kind_Of (H, To_Handle (Arr (1)), Kind, Valid);
               Res := Valid and then Kind = Cell_Pair;
            end;
         end if;
      else
         Res := Is_False (Arr (1));
      end if;

      Result := Bool (Res);
      Status := No_Error;
   end Predicate;

   procedure Display_Prim
     (H      : Heap_Type;
      Args   : Value;
      Display : Boolean;
      Result : out Value;
      B      : in out Output_Buffer;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      W    : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 1, 1, Good);
      if not Good then
      Status := Error_Wrong_Arity;
      return;
      end if;

      Write_Value (H, Arr (1), B, W, Display);
      Status := (if W then No_Error else Error_Output_Full);
   end Display_Prim;

   procedure Call
     (H      : in out Heap_Type;
      P      : Primitive_Id;
      Args   : Value;
      Result : out Value;
      B      : in out Output_Buffer;
      Status : out Error_Code)
   is
      Good : Boolean;
      Len  : Natural;
   begin
      Result := Void_Value;
      --  A path that does not report success explicitly reports a type error,
      --  so a forgotten assignment can only produce an error, never silence.
      Status := Error_Type;

      case P is
         when P_Add =>
            Add (H, Args, Result, Status);

         when P_Sub =>
            Sub (H, Args, Result, Status);

         when P_Mul =>
            Mul (H, Args, Result, Status);

         when P_Num_Equal | P_Less | P_Greater | P_Less_Equal | P_Greater_Equal =>
            Compare_Chain (H, Args, P, Result, Status);

         when P_Cons =>
            Cons_Prim (H, Args, Result, Status);

         when P_Car =>
            Car_Prim (H, Args, Result, Status);

         when P_Cdr =>
            Cdr_Prim (H, Args, Result, Status);

         when P_List =>
            List_Prim (H, Args, Result, Status);

         when P_Null_P | P_Pair_P | P_Not =>
            Predicate (H, Args, P, Result, Status);

         when P_Eq_P =>
            Eq_Prim (H, Args, Result, Status);

         when P_Display =>
            Display_Prim (H, Args, True, Result, B, Status);

         when P_Write =>
            Display_Prim (H, Args, False, Result, B, Status);

         when P_Newline =>
            Length (H, Args, Len, Good);
            if not Good then
               return;
            end if;
            Check_Arity (Len, 0, 0, Good);
            if not Good then
               Status := Error_Wrong_Arity;
               return;
            end if;
            Put_Char (B, LF, Good);
            Result := Unspecified_Value;
            Status := (if Good then No_Error else Error_Output_Full);

         when P_Free_Cells =>
            Length (H, Args, Len, Good);
            if not Good then
               return;
            end if;
            Check_Arity (Len, 0, 0, Good);
            if not Good then
               Status := Error_Wrong_Arity;
               return;
            end if;
            Result := From_Fixnum (Integer_64 (H.Free_Count));
            Status := No_Error;

         when P_None =>
            return;
      end case;
   end Call;

end Tr7.Primitives;
