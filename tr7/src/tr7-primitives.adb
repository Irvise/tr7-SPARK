with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Heap; use Tr7.Heap;
with Tr7.Ids; use Tr7.Ids;
with Tr7.Pairs; use Tr7.Pairs;
with Tr7.Runtime; use Tr7.Runtime;
with Tr7.Values; use Tr7.Values;
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
     with Pre => H.Ready
   is
   begin
      To_Array (H, Args, Arr, Len, Ok);
   end Args_Of;

   procedure Check_Arity
     (Len      : Natural;
      Min, Max : Natural;
      Ok       : out Boolean)
   is
   begin
      Ok := Len >= Min and then Len <= Max;
   end Check_Arity;

   procedure Add
     (H      : in out Heap_Type;
      Args   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Sum  : Fixnum := 0;
      Term : Fixnum;
   begin
      Result := Void_Value;
      Ok := False;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;

      for I in 1 .. Len loop
         pragma Loop_Invariant (Sum in Fixnum);
         Get_Fixnum (Arr (I), Term, Good);
         if not Good then
            return;
         end if;
         if Term > 0 then
            if Sum > Fixnum_Max - Term then
               return;
            end if;
         elsif Term < 0 then
            if Sum < Fixnum_Min - Term then
               return;
            end if;
         end if;
         Sum := Sum + Term;
      end loop;

      Result := From_Fixnum (Integer_64 (Sum));
      Ok := True;
   end Add;

   procedure Sub
     (H      : in out Heap_Type;
      Args   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Acc  : Fixnum;
      Term : Fixnum;
   begin
      Result := Void_Value;
      Ok := False;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good or else Len = 0 then
         return;
      end if;

      Get_Fixnum (Arr (1), Acc, Good);
      if not Good then
         return;
      end if;

      if Len = 1 then
         if Acc = Fixnum_Min then
            return;
         end if;
         Result := From_Fixnum (Integer_64 (-Acc));
         Ok := True;
         return;
      end if;

      for I in 2 .. Len loop
         pragma Loop_Invariant (Acc in Fixnum);
         Get_Fixnum (Arr (I), Term, Good);
         if not Good then
            return;
         end if;
         if Term > 0 then
            if Acc < Fixnum_Min + Term then
               return;
            end if;
         elsif Term < 0 then
            if Acc > Fixnum_Max + Term then
               return;
            end if;
         end if;
         Acc := Acc - Term;
      end loop;

      Result := From_Fixnum (Integer_64 (Acc));
      Ok := True;
   end Sub;

   procedure Mul_Fixnum
     (A  : Fixnum;
      B  : Fixnum;
      R  : out Fixnum;
      Ok : out Boolean)
   is
      Neg    : constant Boolean := (A < 0) xor (B < 0);
      Abs_A  : Unsigned_64;
      Abs_B  : Unsigned_64;
      Limit  : Unsigned_64;
      Prod   : Unsigned_64;
   begin
      R := 0;
      Ok := False;
      if A = 0 or else B = 0 then
         Ok := True;
         return;
      end if;

      Abs_A := Unsigned_64 (abs (Integer_64 (A)));
      Abs_B := Unsigned_64 (abs (Integer_64 (B)));
      if Neg then
         Limit := 2 ** 61;
      else
         Limit := Unsigned_64 (Fixnum_Max);
      end if;

      if Abs_A > Limit / Abs_B then
         return;
      end if;

      Prod := Abs_A * Abs_B;
      if Neg then
         if Prod = 2 ** 61 then
            R := Fixnum_Min;
         else
            R := Fixnum (-Integer_64 (Prod));
         end if;
      else
         R := Fixnum (Integer_64 (Prod));
      end if;
      Ok := True;
   end Mul_Fixnum;

   procedure Mul
     (H      : in out Heap_Type;
      Args   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Acc  : Fixnum := 1;
      Term : Fixnum;
   begin
      Result := Void_Value;
      Ok := False;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;

      for I in 1 .. Len loop
         pragma Loop_Invariant (Acc in Fixnum);
         Get_Fixnum (Arr (I), Term, Good);
         if not Good then
            return;
         end if;
         Mul_Fixnum (Acc, Term, Acc, Good);
         if not Good then
            return;
         end if;
      end loop;

      Result := From_Fixnum (Integer_64 (Acc));
      Ok := True;
   end Mul;

   procedure Compare_Chain
     (H       : in out Heap_Type;
      Args    : Value;
      Mode    : Primitive_Id;
      Result  : out Value;
      Ok      : out Boolean)
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Prev : Fixnum;
      Cur  : Fixnum;
      Res  : Boolean := True;
   begin
      Result := Void_Value;
      Ok := False;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;

      if Len = 0 then
         Result := True_Value;
         Ok := True;
         return;
      end if;

      Get_Fixnum (Arr (1), Prev, Good);
      if not Good then
         return;
      end if;

      for I in 2 .. Len loop
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
      Ok := True;
   end Compare_Chain;

   procedure Cons_Prim
     (H      : in out Heap_Type;
      Args   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
   begin
      Result := Void_Value;
      Ok := False;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 2, 2, Good);
      if not Good then
         return;
      end if;
      Cons (H, Arr (1), Arr (2), Result, Ok);
   end Cons_Prim;

   procedure Car_Prim
     (H      : in out Heap_Type;
      Args   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
   begin
      Result := Void_Value;
      Ok := False;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 1, 1, Good);
      if not Good then
         return;
      end if;
      Car_Of (H, Arr (1), Result, Ok);
   end Car_Prim;

   procedure Cdr_Prim
     (H      : in out Heap_Type;
      Args   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
   begin
      Result := Void_Value;
      Ok := False;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 1, 1, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Arr (1), Result, Ok);
   end Cdr_Prim;

   procedure List_Prim
     (H      : in out Heap_Type;
      Args   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Arr   : Value_Array;
      Len   : Natural;
      Good  : Boolean;
      Head  : Handle := Null_Handle;
      Tail  : Handle := Null_Handle;
      Hd    : Handle;
   begin
      Result := Nil_Value;
      Ok := False;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;

      for I in 1 .. Len loop
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
      Ok := True;
   end List_Prim;

   procedure Eq_Prim
     (H      : in out Heap_Type;
      Args   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      A, B : Value;
      Equal : Boolean;
   begin
      Result := Void_Value;
      Ok := False;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 2, 2, Good);
      if not Good then
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
      Ok := True;
   end Eq_Prim;

   procedure Predicate
     (H      : in out Heap_Type;
      Args   : Value;
      P      : Primitive_Id;
      Result : out Value;
      Ok     : out Boolean)
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Res  : Boolean;
   begin
      Result := Void_Value;
      Ok := False;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 1, 1, Good);
      if not Good then
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
      Ok := True;
   end Predicate;

   procedure Display_Prim
     (H      : in out Heap_Type;
      Args   : Value;
      Display : Boolean;
      Result : out Value;
      B      : in out Output_Buffer;
      Ok     : out Boolean)
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      W    : Boolean;
   begin
      Result := Void_Value;
      Ok := False;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 1, 1, Good);
      if not Good then
         return;
      end if;

      Write_Value (H, Arr (1), B, W, Display);
      Ok := W;
   end Display_Prim;

   procedure Call
     (H      : in out Heap_Type;
      P      : Primitive_Id;
      Args   : Value;
      Result : out Value;
      B      : in out Output_Buffer;
      Ok     : out Boolean)
   is
      Good : Boolean;
      Arr  : Value_Array;
      Len  : Natural;
   begin
      Result := Void_Value;
      Ok := False;

      case P is
         when P_Add =>
            Add (H, Args, Result, Ok);

         when P_Sub =>
            Sub (H, Args, Result, Ok);

         when P_Mul =>
            Mul (H, Args, Result, Ok);

         when P_Num_Equal | P_Less | P_Greater | P_Less_Equal | P_Greater_Equal =>
            Compare_Chain (H, Args, P, Result, Ok);

         when P_Cons =>
            Cons_Prim (H, Args, Result, Ok);

         when P_Car =>
            Car_Prim (H, Args, Result, Ok);

         when P_Cdr =>
            Cdr_Prim (H, Args, Result, Ok);

         when P_List =>
            List_Prim (H, Args, Result, Ok);

         when P_Null_P | P_Pair_P | P_Not =>
            Predicate (H, Args, P, Result, Ok);

         when P_Eq_P =>
            Eq_Prim (H, Args, Result, Ok);

         when P_Display =>
            Display_Prim (H, Args, True, Result, B, Ok);

         when P_Write =>
            Display_Prim (H, Args, False, Result, B, Ok);

         when P_Newline =>
            Args_Of (H, Args, Arr, Len, Good);
            if not Good then
               return;
            end if;
            Check_Arity (Len, 0, 0, Good);
            if not Good then
               return;
            end if;
            Put_Char (B, LF, Good);
            Result := Unspecified_Value;
            Ok := Good;

         when P_None =>
            return;
      end case;
   end Call;

end Tr7.Primitives;
