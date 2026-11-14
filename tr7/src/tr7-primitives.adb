with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.IEEE;
with Tr7.Numbers;
with Tr7.Pairs; use Tr7.Pairs;
with Tr7.Writer; use Tr7.Writer;
with Tr7.Reader;
use type Tr7.Reader.Read_Status;

package body Tr7.Primitives with
   SPARK_Mode => On
is


   subtype Fixnum is Integer_64 range Fixnum_Min .. Fixnum_Max;

   --  The square root of the largest fixnum is 46340, so every root we can
   --  return lives here.
   subtype Root_Range is Natural range 0 .. 46_341;

   --  floor(sqrt(V)) for V below 2**126 lands below 2**63.
   subtype Wide_Root is Integer_128 range 0 .. 9_223_372_036_854_775_808;

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
         when P_String_P         => return "string?";
         when P_String_Length    => return "string-length";
         when P_String_Ref       => return "string-ref";
         when P_String_Append    => return "string-append";
         when P_Substring        => return "substring";
         when P_String_Equal     => return "string=?";
         when P_Vector_P          => return "vector?";
         when P_Vector_Length     => return "vector-length";
         when P_Vector_Ref        => return "vector-ref";
         when P_Vector_Set        => return "vector-set!";
         when P_Vector            => return "vector";
         when P_Bytevector_P      => return "bytevector?";
         when P_Bytevector_Length => return "bytevector-length";
         when P_Bytevector_U8_Ref => return "bytevector-u8-ref";
         when P_Bytevector_U8_Set => return "bytevector-u8-set!";
         when P_Bytevector        => return "bytevector";
         when P_Length             => return "length";
         when P_Append             => return "append";
         when P_Reverse            => return "reverse";
         when P_List_Ref           => return "list-ref";
         when P_Assq               => return "assq";
         when P_Memq               => return "memq";
         when P_Abs                => return "abs";
         when P_Min                => return "min";
         when P_Max                => return "max";
         when P_Quotient           => return "quotient";
         when P_Remainder          => return "remainder";
         when P_Modulo             => return "modulo";
         when P_Expt               => return "expt";
         when P_Sqrt               => return "sqrt";
         when P_Exact_To_Inexact   => return "exact->inexact";
         when P_Open_Input_String  => return "open-input-string";
         when P_Open_Output_String => return "open-output-string";
         when P_Get_Output_String  => return "get-output-string";
         when P_Read               => return "read";
         when P_Read_Char          => return "read-char";
         when P_Peek_Char          => return "peek-char";
         when P_Char_Ready         => return "char-ready?";
         when P_Port_P             => return "port?";
         when P_Eof_Object_P       => return "eof-object?";
         when P_Div                => return "/";
         when P_Error              => return "error";
         when P_Values             => return "values";
         when P_Boolean_P          => return "boolean?";
         when P_Symbol_P           => return "symbol?";
         when P_Char_P             => return "char?";
         when P_Number_P           => return "number?";
         when P_Integer_P          => return "integer?";
         when P_Rational_P         => return "rational?";
         when P_Real_P             => return "real?";
         when P_Complex_P          => return "complex?";
         when P_Procedure_P        => return "procedure?";
         when P_Set_Car            => return "set-car!";
         when P_Set_Cdr            => return "set-cdr!";
         when P_Caar               => return "caar";
         when P_Cadr               => return "cadr";
         when P_Cdar               => return "cdar";
         when P_Cddr               => return "cddr";
         when P_Symbol_To_String   => return "symbol->string";
         when P_String_To_Symbol   => return "string->symbol";
         when P_Char_To_Integer    => return "char->integer";
         when P_Integer_To_Char    => return "integer->char";
         when P_List_To_Vector     => return "list->vector";
         when P_Vector_To_List     => return "vector->list";
         when P_List_To_String     => return "list->string";
         when P_String_To_List     => return "string->list";
         when P_String_Copy        => return "string-copy";
         when P_Number_To_String   => return "number->string";
         when P_String_To_Number   => return "string->number";
         when P_Exact_P            => return "exact?";
         when P_Inexact_P          => return "inexact?";
         when P_Zero_P             => return "zero?";
         when P_Positive_P         => return "positive?";
         when P_Negative_P         => return "negative?";
         when P_Odd_P              => return "odd?";
         when P_Even_P             => return "even?";
         when P_Memv               => return "memv";
         when P_Assv               => return "assv";
         when P_Char_Equal         => return "char=?";
         when P_Char_Less          => return "char<?";
         when P_Char_Greater       => return "char>?";
         when P_Char_Less_Equal    => return "char<=?";
         when P_Char_Greater_Equal => return "char>=?";
         when P_String_Less        => return "string<?";
         when P_String_Greater     => return "string>?";
         when P_String_Less_Equal  => return "string<=?";
         when P_String_Greater_Equal => return "string>=?";
         when P_Make_String        => return "make-string";
         when P_String_Set         => return "string-set!";
         when P_Make_Vector        => return "make-vector";
         when P_Vector_Fill        => return "vector-fill!";
         when P_List_Tail          => return "list-tail";
         when P_List_Copy          => return "list-copy";
         when P_Last_Pair          => return "last-pair";
         when P_Eqv_P              => return "eqv?";
         when P_Boolean_Equal      => return "boolean=?";
         when P_Symbol_Equal       => return "symbol=?";
         when P_Values_P           => return "values?";
         when P_Member             => return "member";
         when P_Assoc              => return "assoc";
         when P_Equal_P            => return "equal?";
         when P_Make_Rectangular   => return "make-rectangular";
         when P_Make_Polar         => return "make-polar";
         when P_Real_Part          => return "real-part";
         when P_Imag_Part          => return "imag-part";
         when P_Magnitude          => return "magnitude";
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

   --  Fetch V as a string cell: the shared start of every string primitive.
   procedure String_Cell
     (H  : Heap_Type;
      V  : Value;
      C  : out Cell;
      Ok : out Boolean)
     with Pre => H.Ready
   is
   begin
      C := (Kind => Cell_Free, others => <>);
      Ok := False;
      if not Is_Handle (V) then
         return;
      end if;
      Fetch (H, To_Handle (V), C, Ok);
      if Ok and then C.Kind /= Cell_String then
         Ok := False;
      end if;
   end String_Cell;

   --  Fetch V as a vector cell: the shared start of the vector primitives.
   procedure Vector_Cell
     (H  : Heap_Type;
      V  : Value;
      C  : out Cell;
      Ok : out Boolean)
     with Pre => H.Ready
   is
   begin
      C := (Kind => Cell_Free, others => <>);
      Ok := False;
      if not Is_Handle (V) then
         return;
      end if;
      Fetch (H, To_Handle (V), C, Ok);
      if Ok and then C.Kind /= Cell_Vector then
         Ok := False;
      end if;
   end Vector_Cell;

   --  Fetch V as a bytevector cell.
   procedure Bytevector_Cell
     (H  : Heap_Type;
      V  : Value;
      C  : out Cell;
      Ok : out Boolean)
     with Pre => H.Ready
   is
   begin
      C := (Kind => Cell_Free, others => <>);
      Ok := False;
      if not Is_Handle (V) then
         return;
      end if;
      Fetch (H, To_Handle (V), C, Ok);
      if Ok and then C.Kind /= Cell_Bytevector then
         Ok := False;
      end if;
   end Bytevector_Cell;

   --  True when any argument is inexact: R7RS makes the whole operation
   --  inexact then, which is what selects between the two paths below.
   function Any_Flonum (Arr : Value_Array; Len : Natural) return Boolean is
     (for some I in 1 .. Len => Arr (I).Kind = Kind_Flonum)
     with Pre => Len <= Arr'Length;

   --  The numeric-kind test the inexact paths repeat: anything else is a
   --  type error, reported by leaving Status where the caller set it.
   function Is_Number (V : Value) return Boolean is
     (V.Kind = Kind_Fixnum or else V.Kind = Kind_Flonum);

   --  Finite: neither NaN nor an infinity.  All comparisons, so no check
   --  hangs off it.
   function In_Range (V : Long_Float) return Boolean is
     (V = V and then V <= Long_Float'Last and then V >= -Long_Float'Last);

   procedure Add
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
      Sum  : Fixnum := 0;
      Term : Fixnum;
      Acc_F : Long_Float;
      Term_F : Long_Float;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      if Tr7.Numbers.Any_Tower_Value (H, Arr, Len) then
         Tr7.Numbers.Add_All (H, Arr, Len, Result, Status);
         return;
      end if;

      if Any_Flonum (Arr, Len) then
         Acc_F := 0.0;
         for I in 1 .. Len loop
            pragma Loop_Invariant (Len <= Arr'Length);
            pragma Loop_Invariant (abs Acc_F <= Long_Float'Last);
            if not Is_Number (Arr (I)) then
               return;
            end if;
            Term_F := As_Float (Arr (I));
            if not In_Range (Acc_F) or else not In_Range (Term_F) then
               Status := Error_Overflow;
               return;
            end if;
            --  Provably inside the range: one operand under one (the sum is
            --  then at most the larger plus a fraction of it), or both under
            --  half the range (the sum is then at most the range).  Anything
            --  else -- two operands whose sum might not fit -- reports an
            --  overflow rather than risking an unprovable check.
            if abs Acc_F <= 1.0 or else abs Term_F <= 1.0
              or else (abs Acc_F <= Long_Float'Last / 2.0
                       and then abs Term_F <= Long_Float'Last / 2.0)
            then
               Acc_F := Acc_F + Term_F;
            else
               Status := Error_Overflow;
               return;
            end if;
         end loop;
         Result := From_Flonum (Acc_F);
         Status := No_Error;
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
               --  Fixnums are the fast path, not the range limit: fall back
               --  to the exact bignum fold rather than reporting overflow.
               Tr7.Numbers.Add_All (H, Arr, Len, Result, Status);
               return;
            end if;
         elsif Term < 0 then
            if Sum < Fixnum_Min - Term then
               Tr7.Numbers.Add_All (H, Arr, Len, Result, Status);
               return;
            end if;
         end if;
         Sum := Sum + Term;
      end loop;

      Result := From_Fixnum (Integer_64 (Sum));
      Status := No_Error;
   end Add;

   procedure Sub
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
      Acc  : Fixnum;
      Term : Fixnum;
      Acc_F : Long_Float;
      Term_F : Long_Float;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      if Tr7.Numbers.Any_Tower_Value (H, Arr, Len) then
         Tr7.Numbers.Sub_All (H, Arr, Len, Result, Status);
         return;
      end if;
      if Len = 0 then
         Status := Error_Wrong_Arity;
         return;
      end if;

      if Any_Flonum (Arr, Len) then
         if not Is_Number (Arr (1)) then
            return;
         end if;
         Acc_F := As_Float (Arr (1));
         if not In_Range (Acc_F) then
            Status := Error_Overflow;
            return;
         end if;
         if Len = 1 then
            Acc_F := -Acc_F;
         else
            for I in 2 .. Len loop
               pragma Loop_Invariant (Len <= Arr'Length);
               pragma Loop_Invariant (abs Acc_F <= Long_Float'Last);
               if not Is_Number (Arr (I)) then
                  return;
               end if;
               Term_F := As_Float (Arr (I));
               if not In_Range (Acc_F) or else not In_Range (Term_F) then
                  Status := Error_Overflow;
                  return;
               end if;
               if abs Acc_F <= 1.0 or else abs Term_F <= 1.0
                 or else (abs Acc_F <= Long_Float'Last / 2.0
                          and then abs Term_F <= Long_Float'Last / 2.0)
               then
                  Acc_F := Acc_F - Term_F;
               else
                  Status := Error_Overflow;
                  return;
               end if;
            end loop;
         end if;
         Result := From_Flonum (Acc_F);
         Status := No_Error;
         return;
      end if;

      Get_Fixnum (Arr (1), Acc, Good);
      if not Good then
         return;
      end if;

      if Len = 1 then
         if Acc = Fixnum_Min then
            Tr7.Numbers.Sub_All (H, Arr, Len, Result, Status);
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
               Tr7.Numbers.Sub_All (H, Arr, Len, Result, Status);
               return;
            end if;
         elsif Term < 0 then
            if Acc > Fixnum_Max + Term then
               Tr7.Numbers.Sub_All (H, Arr, Len, Result, Status);
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
      Acc  : Fixnum := 1;
      Term : Fixnum;
      Acc_F : Long_Float;
      Term_F : Long_Float;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      if Tr7.Numbers.Any_Tower_Value (H, Arr, Len) then
         Tr7.Numbers.Mul_All (H, Arr, Len, Result, Status);
         return;
      end if;

      if Any_Flonum (Arr, Len) then
         Acc_F := 1.0;
         for I in 1 .. Len loop
            pragma Loop_Invariant (Len <= Arr'Length);
            pragma Loop_Invariant (abs Acc_F <= Long_Float'Last);
            if not Is_Number (Arr (I)) then
               return;
            end if;
            Term_F := As_Float (Arr (I));
            if not In_Range (Acc_F) or else not In_Range (Term_F) then
               Status := Error_Overflow;
               return;
            end if;
            --  One operand at most one (the product cannot exceed the
            --  other), both under 1.3e154 (whose square is below the
            --  range), or one under two and the other under half the range.
            --  The last case accepts representable products such as
            --  2e154 * 2 while still rejecting real overflow.
            if abs Acc_F <= 1.0 or else abs Term_F <= 1.0
              or else (abs Acc_F <= 1.3E154 and then abs Term_F <= 1.3E154)
              or else (abs Acc_F <= Long_Float'Last / 2.0
                       and then abs Term_F <= 2.0)
            then
               Acc_F := Acc_F * Term_F;
            else
               Status := Error_Overflow;
               return;
            end if;
         end loop;
         Result := From_Flonum (Acc_F);
         Status := No_Error;
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
            Tr7.Numbers.Mul_All (H, Arr, Len, Result, Status);
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
      Arr   : Value_Array;
      Len   : Natural;
      Good  : Boolean;
      Prev  : Fixnum;
      Cur   : Fixnum;
      Prev_F : Long_Float;
      Cur_F  : Long_Float;
      Res   : Boolean := True;
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

      if Tr7.Numbers.Any_Tower_Value (H, Arr, Len) then
         declare
            CM : Tr7.Numbers.Compare_Mode;
         begin
            case Mode is
               when P_Num_Equal       => CM := Tr7.Numbers.Cmp_Equal;
               when P_Less            => CM := Tr7.Numbers.Cmp_Less;
               when P_Greater         => CM := Tr7.Numbers.Cmp_Greater;
               when P_Less_Equal      => CM := Tr7.Numbers.Cmp_Less_Equal;
               when P_Greater_Equal   => CM := Tr7.Numbers.Cmp_Greater_Equal;
               when others            => return;
            end case;
            Tr7.Numbers.Compare_All (H, Arr, Len, CM, Result, Status);
            return;
         end;
      end if;

      if Any_Flonum (Arr, Len) then
         --  A NaN makes every comparison false, which is what IEEE
         --  comparison gives for free and what R7RS asks for.
         if not Is_Number (Arr (1)) then
            return;
         end if;
         Prev_F := As_Float (Arr (1));
         for I in 2 .. Len loop
            pragma Loop_Invariant (Len <= Arr'Length);
            if not Is_Number (Arr (I)) then
               return;
            end if;
            Cur_F := As_Float (Arr (I));
            case Mode is
               when P_Num_Equal =>
                  Res := Res and then Prev_F = Cur_F;
               when P_Less =>
                  Res := Res and then Prev_F < Cur_F;
               when P_Greater =>
                  Res := Res and then Prev_F > Cur_F;
               when P_Less_Equal =>
                  Res := Res and then Prev_F <= Cur_F;
               when P_Greater_Equal =>
                  Res := Res and then Prev_F >= Cur_F;
               when others =>
                  return;
            end case;
            Prev_F := Cur_F;
         end loop;
         Result := Bool (Res);
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

      Result := Bool (Same_Value (Arr (1), Arr (2)));
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
      elsif P = P_Bytevector_P then
         Res := Is_Handle (Arr (1));
         if Res then
            declare
               Kind  : Cell_Kind;
               Valid : Boolean;
            begin
               Kind_Of (H, To_Handle (Arr (1)), Kind, Valid);
               Res := Valid and then Kind = Cell_Bytevector;
            end;
         end if;
      elsif P = P_Vector_P then
         Res := Is_Handle (Arr (1));
         if Res then
            declare
               Kind  : Cell_Kind;
               Valid : Boolean;
            begin
               Kind_Of (H, To_Handle (Arr (1)), Kind, Valid);
               Res := Valid and then Kind = Cell_Vector;
            end;
         end if;
      elsif P = P_Port_P then
         Res := Is_Handle (Arr (1));
         if Res then
            declare
               Kind  : Cell_Kind;
               Valid : Boolean;
            begin
               Kind_Of (H, To_Handle (Arr (1)), Kind, Valid);
               Res := Valid
                 and then (Kind = Cell_Input_Port
                             or else Kind = Cell_Output_Port);
            end;
         end if;
      elsif P = P_Eof_Object_P then
         Res := Is_EOF (Arr (1));
      elsif P = P_String_P then
         Res := Is_Handle (Arr (1));
         if Res then
            declare
               Kind  : Cell_Kind;
               Valid : Boolean;
            begin
               Kind_Of (H, To_Handle (Arr (1)), Kind, Valid);
               Res := Valid and then Kind = Cell_String;
            end;
         end if;
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
      elsif P = P_Boolean_P then
         Res := Arr (1).Kind = Kind_Boolean;
      elsif P = P_Char_P then
         Res := Arr (1).Kind = Kind_Character;
      elsif P = P_Number_P then
         Res := Tr7.Numbers.Is_Number (H, Arr (1));
      elsif P = P_Integer_P then
         Res := Tr7.Numbers.Is_Integer_Value (H, Arr (1));
      elsif P = P_Rational_P then
         Res := Tr7.Numbers.Is_Rational_Value (H, Arr (1));
      elsif P = P_Real_P then
         Res := Tr7.Numbers.Is_Real_Value (H, Arr (1));
      elsif P = P_Complex_P then
         Res := Tr7.Numbers.Is_Complex_Value (H, Arr (1));
      elsif P = P_Symbol_P then
         Res := Is_Handle (Arr (1));
         if Res then
            declare
               Kind  : Cell_Kind;
               Valid : Boolean;
            begin
               Kind_Of (H, To_Handle (Arr (1)), Kind, Valid);
               Res := Valid and then Kind = Cell_Symbol;
            end;
         end if;
      elsif P = P_Procedure_P then
         Res := Is_Handle (Arr (1));
         if Res then
            declare
               Kind  : Cell_Kind;
               Valid : Boolean;
            begin
               Kind_Of (H, To_Handle (Arr (1)), Kind, Valid);
               Res := Valid
                 and then (Kind = Cell_Closure
                             or else Kind = Cell_Primitive
                             or else Kind = Cell_Continuation);
            end;
         end if;
      elsif P = P_Values_P then
         Res := Is_Handle (Arr (1));
         if Res then
            declare
               Kind  : Cell_Kind;
               Valid : Boolean;
            begin
               Kind_Of (H, To_Handle (Arr (1)), Kind, Valid);
               Res := Valid and then Kind = Cell_Values;
            end;
         end if;
      else
         Res := Is_False (Arr (1));
      end if;

      Result := Bool (Res);
      Status := No_Error;
   end Predicate;

   --  Is V a port of the requested direction?
   procedure Port_Ok
     (H     : Heap_Type;
      V     : Value;
      Input : Boolean;
      Ok    : out Boolean)
     with
       Pre  => H.Ready,
       Post => (if Ok then Is_Handle (V))
   is
      C : Cell;
   begin
      Ok := False;
      if not Is_Handle (V) then
         return;
      end if;
      Fetch (H, To_Handle (V), C, Ok);
      if not Ok then
         return;
      end if;
      if Input then
         Ok := C.Kind = Cell_Input_Port;
      else
         Ok := C.Kind = Cell_Output_Port;
      end if;
   end Port_Ok;

   --  Fetch V as a port of the requested direction.
   procedure Port_Cell
     (H     : Heap_Type;
      V     : Value;
      Input : Boolean;
      C     : out Cell;
      Ok    : out Boolean)
     with Pre => H.Ready
   is
   begin
      C  := (Kind => Cell_Free, others => <>);
      Port_Ok (H, V, Input, Ok);
      if not Ok then
         return;
      end if;
      Fetch (H, To_Handle (V), C, Ok);
   end Port_Cell;

   --  Write one value into a string port.  The port's text is seeded into a
   --  local output buffer, the writer runs there, and the result goes back
   --  in one assignment -- so a buffer that fills up leaves the port exactly
   --  as it was.  SPARK forbids handing a slice of the heap to a procedure
   --  that also takes the heap, which is what the local buffer is for.
   procedure Emit_To_Port
     (H       : in out Heap_Type;
      V       : Value;
      Port    : Value;
      Display : Boolean;
      Status  : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      C     : Cell;
      PB    : Output_Buffer;
      W     : Boolean;
      Good  : Boolean;
   begin
      Status := Error_Type;
      Port_Cell (H, Port, False, C, Good);
      if not Good then
         return;
      end if;
      if C.Arity > Max_Text then
         --  Unreachable: a port's length only ever moves within Max_Text.
         return;
      end if;
      PB.Len := C.Arity;
      for I in 1 .. C.Arity loop
         pragma Loop_Invariant (I <= Max_Text);
         PB.Data (I) := C.Name (I);
      end loop;
      Write_Value (H, V, PB, W, Display);
      if not W then
         Status := Error_Output_Full;
         return;
      end if;
      if PB.Len > Max_Text then
         Status := Error_Output_Full;
         return;
      end if;
      declare
         --  Started full: only the first PB.Len entries are read, but flow
         --  cannot follow writes through a computed index.
         T : Text_Buffer := (others => ' ');
      begin
         for I in 1 .. PB.Len loop
            pragma Loop_Invariant (I <= Max_Text);
            T (I) := PB.Data (I);
         end loop;
         Set_Port_Text (H, Port, T (1 .. PB.Len), Good);
      end;
      if not Good then
         return;
      end if;
      Status := No_Error;
   end Emit_To_Port;

   procedure Display_Prim
     (H      : in out Heap_Type;
      Args   : Value;
      Display : Boolean;
      Result : out Value;
      B      : in out Output_Buffer;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
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
      Check_Arity (Len, 1, 2, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;

      if Len = 2 then
         --  (display obj port): into the port, not the engine's buffer.
         Emit_To_Port (H, Arr (1), Arr (2), Display, Status);
         Result := Unspecified_Value;
         return;
      end if;

      Write_Value (H, Arr (1), B, W, Display);
      Status := (if W then No_Error else Error_Output_Full);
   end Display_Prim;

   --  The nine string-port procedures: ports are values over cells whose
   --  text lives inline, so every one of them is a bounded walk over a
   --  Max_Text buffer and none of them can touch the OS.

   procedure Open_Input_String_Prim
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
      Hd   : Handle;
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
      if not Is_Handle (Arr (1)) then
         return;
      end if;
      declare
         Kind  : Cell_Kind;
         Valid : Boolean;
      begin
         Kind_Of (H, To_Handle (Arr (1)), Kind, Valid);
         if not Valid or else Kind /= Cell_String then
            return;
         end if;
      end;
      New_Input_Port (H, Arr (1), Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Open_Input_String_Prim;

   procedure Open_Output_String_Prim
     (H      : in out Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Len  : Natural;
      Good : Boolean;
      Hd   : Handle;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Length (H, Args, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 0, 0, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      New_Output_Port (H, Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Open_Output_String_Prim;

   procedure Get_Output_String_Prim
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
      C    : Cell;
      Hd   : Handle;
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
      Port_Cell (H, Arr (1), False, C, Good);
      if not Good then
         return;
      end if;
      New_String (H, C.Name (1 .. C.Name_Len), Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Get_Output_String_Prim;

   procedure Read_Char_Prim
     (H       : in out Heap_Type;
      Args    : Value;
      Advance : Boolean;
      Result  : out Value;
      Status  : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      C    : Cell;
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
      Port_Cell (H, Arr (1), True, C, Good);
      if not Good then
         return;
      end if;
      if C.Arity >= C.Name_Len then
         Result := Eof_Value;
         Status := No_Error;
         return;
      end if;
      Result :=
        From_Character
          (Unsigned_32 (Character'Pos (C.Name (C.Arity + 1))));
      Status := No_Error;
      if Advance then
         Set_Port_Pos (H, Arr (1), C.Arity + 1, Good);
         if not Good then
            Status := Error_Type;
         end if;
      end if;
   end Read_Char_Prim;

   procedure Char_Ready_Prim
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
      Port_Ok (H, Arr (1), True, Good);
      if not Good then
         return;
      end if;
      Result := True_Value;
      Status := No_Error;
   end Char_Ready_Prim;

   --  (read port): the next datum, or the EOF object.  The text is copied
   --  to a local buffer first because Read_Datum takes the heap and a
   --  source string, and SPARK forbids passing a slice of the heap along
   --  with the heap itself.
   procedure Read_Prim
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
      C    : Cell;
      Src  : Text_Buffer;
      Pos  : Natural;
      Old  : Natural;
      RS   : Tr7.Reader.Read_Status;
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
      Port_Cell (H, Arr (1), True, C, Good);
      if not Good then
         return;
      end if;
      if C.Arity > C.Name_Len then
         --  Unreachable: a position only ever moves within the text.
         return;
      end if;

      Src := C.Name;
      Pos := C.Arity;
      Old := Pos;
      Tr7.Reader.Read_Datum (H, Src (1 .. C.Name_Len), Pos, Result, RS);
      case RS is
         when Tr7.Reader.Read_Ok =>
            if Pos = Old then
               Status := Error_Parse;
               return;
            end if;
            Set_Port_Pos (H, Arr (1), Pos, Good);
            if not Good then
               Status := Error_Type;
               return;
            end if;
            Status := No_Error;
         when Tr7.Reader.Read_End =>
            Result := Eof_Value;
            Status := No_Error;
         when Tr7.Reader.Read_Error =>
            Result := Void_Value;
            Status := Error_Parse;
         when Tr7.Reader.Read_Heap_Full =>
            Result := Void_Value;
            Status := Error_Heap_Full;
      end case;
   end Read_Prim;

   procedure String_Length_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      C    : Cell;
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
      String_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      Result := From_Fixnum (Integer_64 (C.Name_Len));
      Status := No_Error;
   end String_Length_Prim;

   procedure String_Ref_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      C    : Cell;
      Idx  : Fixnum;
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
      String_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      Get_Fixnum (Arr (2), Idx, Good);
      if not Good then
         return;
      end if;
      if Idx < 0 or else Idx >= Integer_64 (C.Name_Len) then
         Status := Error_Index;
         return;
      end if;
      Result :=
        From_Character (Unsigned_32 (Character'Pos (C.Name (Natural (Idx) + 1))));
      Status := No_Error;
   end String_Ref_Prim;

   procedure Substring_Prim
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
      C     : Cell;
      Start : Fixnum;
      Stop  : Fixnum;
      Size  : Natural;
      Hd    : Handle;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 3, 3, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      String_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      Get_Fixnum (Arr (2), Start, Good);
      if not Good then
         return;
      end if;
      Get_Fixnum (Arr (3), Stop, Good);
      if not Good then
         return;
      end if;
      --  [Start, Stop) as R7RS defines it: start inside the string, stop past
      --  it only far enough to be equal to it.
      if Start < 0
        or else Stop < Start
        or else Stop > Integer_64 (C.Name_Len)
      then
         Status := Error_Index;
         return;
      end if;

      Size := Natural (Stop - Start);
      New_String (H, C.Name (Natural (Start) + 1 .. Natural (Start) + Size),
                  Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Substring_Prim;

   procedure String_Append_Prim
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
      C     : Cell;
      Total : Natural := 0;
      Buf   : Text_Buffer := (others => ' ');
      Hd    : Handle;
      Pos   : Natural;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 0, Max_Arguments, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;

      for J in 1 .. Len loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (Total <= Max_Text);
         String_Cell (H, Arr (J), C, Good);
         if not Good then
            return;
         end if;
         if Total + C.Name_Len > Max_Text then
            Status := Error_Overflow;
            return;
         end if;
         Pos := Total;
         for I in 1 .. C.Name_Len loop
            pragma Loop_Invariant (Pos = Total + (I - 1));
            pragma Loop_Invariant (Pos < Max_Text);
            Pos := Pos + 1;
            Buf (Pos) := C.Name (I);
         end loop;
         Total := Pos;
      end loop;

      New_String (H, Buf (1 .. Total), Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end String_Append_Prim;

   procedure String_Equal_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      A    : Cell;
      B    : Cell;
      Same : Boolean := True;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 2, Max_Arguments, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      for J in 1 .. Len - 1 loop
         String_Cell (H, Arr (J), A, Good);
         if not Good then
            return;
         end if;
         String_Cell (H, Arr (J + 1), B, Good);
         if not Good then
            return;
         end if;
         if A.Name_Len /= B.Name_Len then
            Same := False;
         else
            for I in 1 .. A.Name_Len loop
               if A.Name (I) /= B.Name (I) then
                  Same := False;
                  exit;
               end if;
            end loop;
         end if;
      end loop;
      Result := Bool (Same);
      Status := No_Error;
   end String_Equal_Prim;


   procedure Vector_Length_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      C    : Cell;
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
      Vector_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      Result := From_Fixnum (Integer_64 (C.Arity));
      Status := No_Error;
   end Vector_Length_Prim;

   procedure Vector_Ref_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      C    : Cell;
      Idx  : Fixnum;
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
      Vector_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      Get_Fixnum (Arr (2), Idx, Good);
      if not Good then
         return;
      end if;
      if Idx < 0 or else Idx >= Integer_64 (C.Arity) then
         Status := Error_Index;
         return;
      end if;
      Nth (H, C.Car, Natural (Idx), Result, Good);
      if not Good then
         --  The element chain is as long as Arity says, so this only happens
         --  if the vector's internals were damaged.
         Status := Error_Type;
         return;
      end if;
      Status := No_Error;
   end Vector_Ref_Prim;

   procedure Vector_Set_Prim
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
      C     : Cell;
      Idx   : Fixnum;
      Cur   : Value;
      Node  : Cell;
      --  Bounded by construction: a vector holds at most Max_Arguments
      --  elements, so no valid chain can walk past Max_List_Length.
      Walk  : Natural range 0 .. Max_List_Length;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 3, 3, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      Vector_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      Get_Fixnum (Arr (2), Idx, Good);
      if not Good then
         return;
      end if;
      if Idx < 0 or else Idx >= Integer_64 (C.Arity) then
         Status := Error_Index;
         return;
      end if;

      --  Walk to the Idx-th element cell and store into it.
      Cur := C.Car;
      Walk := 0;
      loop
         if not Is_Handle (Cur) then
            Status := Error_Type;
            return;
         end if;
         Fetch (H, To_Handle (Cur), Node, Good);
         if not Good or else Node.Kind /= Cell_Pair then
            Status := Error_Type;
            return;
         end if;
         if Walk = Natural (Idx) then
            Set_Car (H, To_Handle (Cur), Arr (3), Good);
            if not Good then
               Status := Error_Heap_Full;
               return;
            end if;
            Result := Unspecified_Value;
            Status := No_Error;
            return;
         end if;
         if Walk = Max_List_Length then
            Status := Error_Type;
            return;
         end if;
         Cur := Node.Cdr;
         Walk := Walk + 1;
      end loop;
   end Vector_Set_Prim;

   procedure Vector_Prim
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
      Elems : Value;
   begin
      Result := Void_Value;
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
            Status := Error_Heap_Full;
            return;
         end if;
         if I = 1 then
            Head := Hd;
         else
            Set_Cdr (H, Tail, From_Handle (Hd), Good);
            if not Good then
               Status := Error_Heap_Full;
               return;
            end if;
         end if;
         Tail := Hd;
      end loop;

      if Len = 0 then
         Elems := Nil_Value;
      else
         Elems := From_Handle (Head);
      end if;
      New_Vector (H, Elems, Len, Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Vector_Prim;


   procedure Bytevector_Length_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      C    : Cell;
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
      Bytevector_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      Result := From_Fixnum (Integer_64 (C.Name_Len));
      Status := No_Error;
   end Bytevector_Length_Prim;

   procedure Bytevector_U8_Ref_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      C    : Cell;
      Idx  : Fixnum;
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
      Bytevector_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      Get_Fixnum (Arr (2), Idx, Good);
      if not Good then
         return;
      end if;
      if Idx < 0 or else Idx >= Integer_64 (C.Name_Len) then
         Status := Error_Index;
         return;
      end if;
      Result :=
        From_Fixnum (Integer_64 (Character'Pos (C.Name (Natural (Idx) + 1))));
      Status := No_Error;
   end Bytevector_U8_Ref_Prim;

   procedure Bytevector_U8_Set_Prim
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
      C     : Cell;
      Idx   : Fixnum;
      Byte_Val : Fixnum;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 3, 3, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      Bytevector_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      Get_Fixnum (Arr (2), Idx, Good);
      if not Good then
         return;
      end if;
      if Idx < 0 or else Idx >= Integer_64 (C.Name_Len) then
         Status := Error_Index;
         return;
      end if;
      Get_Fixnum (Arr (3), Byte_Val, Good);
      if not Good then
         return;
      end if;
      if Byte_Val < 0 or else Byte_Val > 255 then
         Status := Error_Range;
         return;
      end if;

      Set_Byte (H, Arr (1), Natural (Idx),
                Character'Val (Integer (Byte_Val)), Good);
      if not Good then
         Status := Error_Type;
         return;
      end if;
      Result := Unspecified_Value;
      Status := No_Error;
   end Bytevector_U8_Set_Prim;

   procedure Bytevector_Prim
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
      Buf  : Text_Buffer := (others => ' ');
      Hd   : Handle;
      V    : Fixnum;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      if Len > Max_Text then
         Status := Error_Overflow;
         return;
      end if;

      for I in 1 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         Get_Fixnum (Arr (I), V, Good);
         if not Good then
            return;
         end if;
         if V < 0 or else V > 255 then
            Status := Error_Range;
            return;
         end if;
         Buf (I) := Character'Val (Integer (V));
      end loop;

      New_Bytevector (H, Buf (1 .. Len), Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Bytevector_Prim;


   procedure Length_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      N    : Natural;
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
      Length (H, Arr (1), N, Good);
      if not Good then
         --  Not a proper list, or a ring (the walk is bounded by the
         --  arena, which no proper list exceeds).
         return;
      end if;
      Result := From_Fixnum (Integer_64 (N));
      Status := No_Error;
   end Length_Prim;

   procedure Append_Prim
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
      Head  : Handle;
      Tail  : Handle;
      Hd    : Handle;
      Cur   : Value;
      Node  : Cell;
      Count : Natural := 0;
      Any   : Boolean := False;
      Left  : Natural;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      if Len = 0 then
         Result := Nil_Value;
         Status := No_Error;
         return;
      end if;
      if Len = 1 then
         --  append with one argument returns it unchanged, even if it is
         --  not a list.
         Result := Arr (1);
         Status := No_Error;
         return;
      end if;

      --  Every argument but the last must be a proper list; the last may be
      --  any object and becomes the final tail (R7RS 6.4).
      --  The copy is bounded by the arena, not by Max_List_Length: a
      --  result too big for the remaining cells reports heap exhausted,
      --  which is the honest limit.
      for J in 1 .. Len - 1 loop
         pragma Loop_Invariant (Len <= Arr'Length);
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (Count <= Max_Cells);
         Cur := Arr (J);
         Left := Max_Cells + 1;
         while not Is_Nil (Cur) and then Left > 0 loop
            pragma Loop_Invariant (H.Ready);
            pragma Loop_Invariant (Count <= Max_Cells);
            pragma Loop_Variant (Decreases => Left);
            if not Is_Handle (Cur) then
               Status := Error_Type;
               return;
            end if;
            Fetch (H, To_Handle (Cur), Node, Good);
            if not Good or else Node.Kind /= Cell_Pair then
               Status := Error_Type;
               return;
            end if;
            if Count >= Max_Cells then
               Status := Error_Heap_Full;
               return;
            end if;
            New_Pair (H, Node.Car, Nil_Value, Hd, Good);
            if not Good then
               Status := Error_Heap_Full;
               return;
            end if;
            if Any then
               Set_Cdr (H, Tail, From_Handle (Hd), Good);
               if not Good then
                  Status := Error_Heap_Full;
                  return;
               end if;
            else
               Head := Hd;
               Any := True;
            end if;
            Tail := Hd;
            Count := Count + 1;
            Cur := Node.Cdr;
            Left := Left - 1;
         end loop;
         if not Is_Nil (Cur) then
            Status := Error_Overflow;
            return;
         end if;
      end loop;

      if Any then
         Set_Cdr (H, Tail, Arr (Len), Good);
         if not Good then
            Status := Error_Heap_Full;
            return;
         end if;
         Result := From_Handle (Head);
      else
         Result := Arr (Len);
      end if;
      Status := No_Error;
   end Append_Prim;

   procedure Reverse_Prim
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
      Check_Arity (Len, 1, 1, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      Reverse_List (H, Arr (1), Result, Good, Status);
      if not Good then
         return;
      end if;
      Status := No_Error;
   end Reverse_Prim;

   procedure List_Ref_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      N    : Natural;
      Idx  : Fixnum;
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
      Get_Fixnum (Arr (2), Idx, Good);
      if not Good then
         return;
      end if;
      Length (H, Arr (1), N, Good);
      if not Good then
         return;
      end if;
      if Idx < 0 or else Idx >= Integer_64 (N) then
         Status := Error_Index;
         return;
      end if;
      Nth (H, Arr (1), Natural (Idx), Result, Good);
      if not Good then
         return;
      end if;
      Status := No_Error;
   end List_Ref_Prim;

   procedure Assq_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr   : Value_Array;
      Len   : Natural;
      Good  : Boolean;
      Cur   : Value;
      Node  : Cell;
      Assoc : Cell;
      Left  : Natural := Max_Cells + 1;
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

      Cur := Arr (2);
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         if not Is_Handle (Cur) then
            Status := Error_Type;
            return;
         end if;
         Fetch (H, To_Handle (Cur), Node, Good);
         if not Good or else Node.Kind /= Cell_Pair then
            Status := Error_Type;
            return;
         end if;
         if not Is_Handle (Node.Car) then
            Status := Error_Type;
            return;
         end if;
         Fetch (H, To_Handle (Node.Car), Assoc, Good);
         if not Good or else Assoc.Kind /= Cell_Pair then
            Status := Error_Type;
            return;
         end if;
         if Same_Value (Assoc.Car, Arr (1)) then
            Result := Node.Car;
            Status := No_Error;
            return;
         end if;
         Cur := Node.Cdr;
         Left := Left - 1;
      end loop;
      if not Is_Nil (Cur) then
         Status := Error_Malformed;
         return;
      end if;

      Result := False_Value;
      Status := No_Error;
   end Assq_Prim;
   procedure Memq_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Cur  : Value;
      Node : Cell;
      Left : Natural := Max_Cells + 1;
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

      Cur := Arr (2);
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         if not Is_Handle (Cur) then
            Status := Error_Type;
            return;
         end if;
         Fetch (H, To_Handle (Cur), Node, Good);
         if not Good or else Node.Kind /= Cell_Pair then
            Status := Error_Type;
            return;
         end if;
         if Same_Value (Node.Car, Arr (1)) then
            --  memq returns the tail starting at the match, not a boolean.
            Result := Cur;
            Status := No_Error;
            return;
         end if;
         Cur := Node.Cdr;
         Left := Left - 1;
      end loop;
      if not Is_Nil (Cur) then
         Status := Error_Malformed;
         return;
      end if;

      Result := False_Value;
      Status := No_Error;
   end Memq_Prim;

   --  R7RS member/assoc: the equal?-based relations over the same walks.
   --  The optional comparison argument is outside v1: it needs to call a
   --  procedure from a primitive, which the synchronous Call cannot do.
   procedure Member_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Cur  : Value;
      Node : Cell;
      Eq   : Boolean;
      Fine : Boolean;
      Left : Natural := Max_Cells + 1;
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

      Cur := Arr (2);
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         if not Is_Handle (Cur) then
            Status := Error_Type;
            return;
         end if;
         Fetch (H, To_Handle (Cur), Node, Good);
         if not Good or else Node.Kind /= Cell_Pair then
            Status := Error_Type;
            return;
         end if;
         Deep_Equal (H, Arr (1), Node.Car, Eq, Fine);
         if not Fine then
            Status := Error_Malformed;
            return;
         end if;
         if Eq then
            --  member returns the tail starting at the match.
            Result := Cur;
            Status := No_Error;
            return;
         end if;
         Cur := Node.Cdr;
         Left := Left - 1;
      end loop;
      if not Is_Nil (Cur) then
         Status := Error_Malformed;
         return;
      end if;

      Result := False_Value;
      Status := No_Error;
   end Member_Prim;

   procedure Assoc_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr   : Value_Array;
      Len   : Natural;
      Good  : Boolean;
      Cur   : Value;
      Node  : Cell;
      Assoc : Cell;
      Eq    : Boolean;
      Fine  : Boolean;
      Left  : Natural := Max_Cells + 1;
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

      Cur := Arr (2);
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         if not Is_Handle (Cur) then
            Status := Error_Type;
            return;
         end if;
         Fetch (H, To_Handle (Cur), Node, Good);
         if not Good or else Node.Kind /= Cell_Pair then
            Status := Error_Type;
            return;
         end if;
         if not Is_Handle (Node.Car) then
            Status := Error_Type;
            return;
         end if;
         Fetch (H, To_Handle (Node.Car), Assoc, Good);
         if not Good or else Assoc.Kind /= Cell_Pair then
            Status := Error_Type;
            return;
         end if;
         Deep_Equal (H, Arr (1), Assoc.Car, Eq, Fine);
         if not Fine then
            Status := Error_Malformed;
            return;
         end if;
         if Eq then
            Result := Node.Car;
            Status := No_Error;
            return;
         end if;
         Cur := Node.Cdr;
         Left := Left - 1;
      end loop;
      if not Is_Nil (Cur) then
         Status := Error_Malformed;
         return;
      end if;

      Result := False_Value;
      Status := No_Error;
   end Assoc_Prim;


   procedure Abs_Prim
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
      N    : Fixnum;
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
      if Arr (1).Kind = Kind_Flonum then
         Result := From_Flonum (abs Arr (1).F);
         Status := No_Error;
         return;
      end if;
      if Tr7.Numbers.Is_Tower_Value (H, Arr (1)) then
         Tr7.Numbers.Abs_Value (H, Arr (1), Result, Status);
         return;
      end if;
      Get_Fixnum (Arr (1), N, Good);
      if not Good then
         return;
      end if;
      if N = Fixnum_Min then
         --  The positive counterpart does not fit a fixnum: the tower
         --  represents it as a bignum.
         Tr7.Numbers.Abs_Value (H, Arr (1), Result, Status);
         return;
      end if;
      if N < 0 then
         Result := From_Fixnum (-Integer_64 (N));
      else
         Result := From_Fixnum (Integer_64 (N));
      end if;
      Status := No_Error;
   end Abs_Prim;

   procedure Min_Max_Prim
     (H      : Heap_Type;
      Args   : Value;
      Pick   : Boolean;  --  True for max, False for min
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr    : Value_Array;
      Len    : Natural;
      Good   : Boolean;
      Best   : Fixnum;
      Term   : Fixnum;
      Best_I : Natural range 1 .. Max_Arguments;
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
      if Tr7.Numbers.Any_Tower_Value (H, Arr, Len) then
         Tr7.Numbers.Min_Max (H, Arr, Len, Pick, Result, Status);
         return;
      end if;

      if Any_Flonum (Arr, Len) then
         --  One inexact argument makes the whole operation inexact (R7RS),
         --  and every argument must still be a number: each one is checked
         --  as the winner loop reaches it, and the invariant carries the
         --  winner's checked status to the next comparison.
         Best_I := 1;
         if not Is_Number (Arr (Best_I)) then
            return;
         end if;
         for I in 2 .. Len loop
            pragma Loop_Invariant (Len <= Arr'Length);
            pragma Loop_Invariant (Is_Number (Arr (Best_I)));
            if not Is_Number (Arr (I)) then
               return;
            end if;
            --  Comparisons only -- no float arithmetic, so no range reasoning.
            if (Pick
                  and then As_Float (Arr (I)) > As_Float (Arr (Best_I)))
              or else
                 ((not Pick)
                    and then As_Float (Arr (I)) < As_Float (Arr (Best_I)))
            then
               Best_I := I;
            end if;
         end loop;
         --  The winner as a float: an exact winner converts, which is what
         --  makes (min 1 2.0) 1.0 and (max 3 1 2.0) 3.0.
         Result := From_Flonum (As_Float (Arr (Best_I)));
         Status := No_Error;
         return;
      end if;

      Get_Fixnum (Arr (1), Best, Good);
      if not Good then
         return;
      end if;
      for I in 2 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         pragma Loop_Invariant (Best >= Fixnum_Min);
         pragma Loop_Invariant (Best <= Fixnum_Max);
         Get_Fixnum (Arr (I), Term, Good);
         if not Good then
            return;
         end if;
         if Pick then
            if Term > Best then
               Best := Term;
            end if;
         else
            if Term < Best then
               Best := Term;
            end if;
         end if;
      end loop;

      Result := From_Fixnum (Integer_64 (Best));
      Status := No_Error;
   end Min_Max_Prim;

   --  An integral operand for the mixed flonum branches: a fixnum, or an
   --  integral flonum inside the fixnum range.  Anything else is a type
   --  error or an overflow, by name.
   procedure Integral_Operand
     (V      : Value;
      N      : out Fixnum;
      Ok     : out Boolean;
      Status : out Error_Code)
   is
      F : Long_Float;
   begin
      N := 0;
      Ok := False;
      Status := Error_Type;
      if Is_Fixnum (V) then
         Get_Fixnum (V, N, Ok);
         if Ok then
            Status := No_Error;
         end if;
         return;
      elsif Is_Flonum (V) then
         F := V.F;
         if F /= F then
            Status := Error_Not_Implemented;
            return;
         elsif F < Long_Float (Fixnum_Min)
           or else F > Long_Float (Fixnum_Max)
         then
            Status := Error_Overflow;
            return;
         elsif Long_Float'Floor (F) /= F then
            Status := Error_Type;
            return;
         end if;
         N := Fixnum (Integer_64 (F));
         Ok := True;
         Status := No_Error;
      end if;
   end Integral_Operand;

   procedure Div_Guard
     (A      : Fixnum;
      B      : Fixnum;
      Status : out Error_Code)
   is
   begin
      if B = 0 then
         Status := Error_Division_By_Zero;
      elsif A = Fixnum_Min and then B = -1 then
         Status := Error_Overflow;
      else
         Status := No_Error;
      end if;
   end Div_Guard;

   procedure Quotient_Prim
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
      if Any_Flonum (Arr, Len) then
         declare
            A, B, R : Fixnum;
         begin
            Integral_Operand (Arr (1), A, Good, Status);
            if not Good then
               return;
            end if;
            Integral_Operand (Arr (2), B, Good, Status);
            if not Good then
               return;
            end if;
            Div_Guard (A, B, Status);
            if Status /= No_Error then
               return;
            end if;
            R := A / B;
            Result := From_Flonum (Long_Float (R));
            Status := No_Error;
         end;
         return;
      end if;
      Tr7.Numbers.Integer_Divide
        (H, Arr (1), Arr (2), Tr7.Numbers.Op_Quotient, Result, Status);
   end Quotient_Prim;

   procedure Remainder_Prim
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
      if Any_Flonum (Arr, Len) then
         declare
            A, B, R : Fixnum;
         begin
            Integral_Operand (Arr (1), A, Good, Status);
            if not Good then
               return;
            end if;
            Integral_Operand (Arr (2), B, Good, Status);
            if not Good then
               return;
            end if;
            Div_Guard (A, B, Status);
            if Status /= No_Error then
               return;
            end if;
            R := A rem B;
            Result := From_Flonum (Long_Float (R));
            Status := No_Error;
         end;
         return;
      end if;
      Tr7.Numbers.Integer_Divide
        (H, Arr (1), Arr (2), Tr7.Numbers.Op_Remainder, Result, Status);
   end Remainder_Prim;

   procedure Modulo_Prim
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
      if Any_Flonum (Arr, Len) then
         declare
            A, B, R : Fixnum;
         begin
            Integral_Operand (Arr (1), A, Good, Status);
            if not Good then
               return;
            end if;
            Integral_Operand (Arr (2), B, Good, Status);
            if not Good then
               return;
            end if;
            Div_Guard (A, B, Status);
            if Status /= No_Error then
               return;
            end if;
            R := A mod B;
            Result := From_Flonum (Long_Float (R));
            Status := No_Error;
         end;
         return;
      end if;
      Tr7.Numbers.Integer_Divide
        (H, Arr (1), Arr (2), Tr7.Numbers.Op_Modulo, Result, Status);
   end Modulo_Prim;

   procedure Expt_Prim
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
      if not (Is_Number (Arr (1)) and then Is_Number (Arr (2))) then
         return;
      end if;

      if Any_Flonum (Arr, Len) then
         --  One inexact operand makes the result inexact (R7RS).  The
         --  power itself comes from the trusted libm boundary, so every
         --  outcome is checked here: NaN means an undefined power (a
         --  negative base with a fractional exponent leaves the reals --
         --  v1 has no complex numbers), an infinity leaves the range
         --  every other arithmetic path stays inside.
         declare
            A_F : constant Long_Float := As_Float (Arr (1));
            N_F : constant Long_Float := As_Float (Arr (2));
            R_F : Long_Float;
         begin
            if A_F = 0.0 and then N_F < 0.0 then
               --  0 to a negative power is 1/0.
               Status := Error_Division_By_Zero;
               return;
            end if;
            R_F := Tr7.IEEE.Power (A_F, N_F);
            if R_F /= R_F then
               Status := Error_Not_Implemented;
               return;
            end if;
            if R_F > Long_Float'Last or else R_F < -Long_Float'Last then
               Status := Error_Overflow;
               return;
            end if;
            Result := From_Flonum (R_F);
            Status := No_Error;
         end;
         return;
      end if;

      Tr7.Numbers.Expt (H, Arr (1), Arr (2), Result, Status);
   end Expt_Prim;


   --  exact->inexact: an exact integer as the double nearest its value
   --  (every fixnum is far inside a double's precision), an inexact number
   --  unchanged.
   --  (/ x ...) with no rationals in v1: an exact quotient when every step
   --  divides evenly, and the inexact double otherwise -- so (/ 6 3) is 2
   --  and (/ 1 2) is 0.5.  A single flonum anywhere makes every step
   --  inexact (R7RS), and the float division splits into the branches the
   --  provers discharge: a divisor of at least one (the quotient cannot
   --  grow), or both operands inside a fixed window whose ratio is below
   --  the range; anything else reports an overflow rather than an
   --  infinity.
   --  (error message irritant ...): R7RS's raiser.  The text is assembled
   --  here -- the message, then each irritant displayed with a space -- and
   --  parked in the heap record, because a primitive sees the heap and not
   --  the machine; the returned Status is what stops the evaluator, and the
   --  printer prefers this text over the generic name.
   --  (values v ...) with R7RS's shape: nothing is a zero-value wrapper,
   --  one value is that value itself (so it binds and passes like any
   --  other), and several become a wrapper cell the evaluator spreads --
   --  the argument list it already built is adopted as the contents.
   procedure Values_Prim
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
      Hd   : Handle;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      if Len = 1 then
         Result := Arr (1);
         Status := No_Error;
         return;
      end if;
      New_Values (H, Args, Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Values_Prim;

   procedure Error_Prim
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
      C    : Cell;
      Buf  : Output_Buffer;
      W    : Boolean;
      Hd   : Handle;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      if Len < 1 then
         Status := Error_Wrong_Arity;
         return;
      end if;
      String_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;

      Buf.Len := C.Name_Len;
      for I in 1 .. C.Name_Len loop
         Buf.Data (I) := C.Name (I);
      end loop;
      for I in 2 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         Put_Char (Buf, ' ', W);
         if not W then
            Status := Error_Output_Full;
            return;
         end if;
         Write_Value (H, Arr (I), Buf, W, True);
         if not W then
            Status := Error_Output_Full;
            return;
         end if;
      end loop;

      --  Whatever fits: a message longer than a string cell keeps its first
      --  Max_Text bytes rather than losing the error itself.  (The copy
      --  through a local Text_Buffer is the Output_Array/String bridge
      --  again: New_String takes a String, Buf.Data is not one.)
      declare
         T : Text_Buffer := (others => ' ');
         N : Natural := Buf.Len;
      begin
         if N > Max_Text then
            N := Max_Text;
         end if;
         for I in 1 .. N loop
            T (I) := Buf.Data (I);
         end loop;
         New_String (H, T (1 .. N), Hd, Good);
      end;
      if Good then
         H.Error_Msg := From_Handle (Hd);
      end if;
      Status := Error_User;
   end Error_Prim;

   --  One guarded float division.  The guard keeps the quotient provably
   --  finite: a divisor of magnitude at least one cannot overflow, and a
   --  divisor below one is accepted only when the numerator is bounded and
   --  the divisor is not tiny.  The postcondition states the arithmetic
   --  relation whenever the operation succeeds, which is exactly what the
   --  chain fold below relies on.


   procedure Div_Prim
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
      --  Division always goes through the tower: an exact quotient that
      --  does not divide evenly is a rational, and one inexact operand
      --  still makes the whole chain inexact.
      Tr7.Numbers.Div_All (H, Arr, Len, Result, Status);
   end Div_Prim;

   procedure Exact_To_Inexact_Prim
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
      Check_Arity (Len, 1, 1, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      if Tr7.Numbers.Is_Tower_Value (H, Arr (1)) then
         Tr7.Numbers.Exact_To_Inexact (H, Arr (1), Result, Status);
         return;
      end if;

      case Arr (1).Kind is
         when Kind_Fixnum =>
            Result := From_Flonum (Long_Float (Arr (1).N));
            Status := No_Error;
         when Kind_Flonum =>
            Result := Arr (1);
            Status := No_Error;
         when others =>
            null;
      end case;
   end Exact_To_Inexact_Prim;

   --  The integer square root of a non-negative fixnum: the largest s with
   --  s*s <= n, and whether that product is exactly n.  Binary search over
   --  0 .. 46_341 -- the root of Fixnum_Max is 46340 -- with every product
   --  taken in Integer_64 so no intermediate can overflow.  Pure integer
   --  arithmetic on purpose: the float path below never has to justify a
   --  range check hanging off the unanalyzed library sqrt.
   procedure ISqrt
     (N       : Fixnum;
      S       : out Root_Range;
      Perfect : out Boolean)
     with Pre => N >= 0
   is
      Lo  : Natural range 0 .. 46_341 := 0;
      Hi  : Natural range 0 .. 46_341 := 46_341;
      Mid : Natural range 0 .. 46_341;
      Sq  : Integer_64;
   begin
      while Lo < Hi loop
         Mid := (Lo + Hi + 1) / 2;
         Sq := Integer_64 (Mid) * Integer_64 (Mid);
         if Sq <= Integer_64 (N) then
            Lo := Mid;
         else
            Hi := Mid - 1;
         end if;
      end loop;
      S := Lo;
      Sq := Integer_64 (Lo) * Integer_64 (Lo);
      Perfect := Sq = Integer_64 (N);
   end ISqrt;

   --  GNATprove does not yet model the floating-point manipulation
   --  attributes ('Fraction, 'Exponent, 'Scaling, 'Adjacent -- all four were
   --  rejected as "not yet supported"), so the three operations sqrt needs
   --  from them are spelled out below in arithmetic it can see.  Every step
   --  is a power of two, hence exact; the guards are unreachable for finite
   --  doubles (which need at most ~1074 steps) and exist so the loops and
   --  the conversions around them have constant bounds to prove against.

   --  Split a positive double into f * 2**e with f in [0.5, 1), which is
   --  what 'Fraction and 'Exponent would give.
   procedure Decompose
     (X : Long_Float;
      F : out Long_Float;
      E : out Integer)
     with
       Pre  => X > 0.0 and then X <= Long_Float'Last,
       Post => F >= 0.5 and then F < 1.0
         and then E >= -1_074 and then E <= 1_025,
       Always_Terminates
   is
      FF : Long_Float := X;
      EE : Integer range -1_074 .. 1_025 := 0;
   begin
      while FF >= 1.0 loop
         pragma Loop_Invariant (FF >= 0.0);
         pragma Loop_Invariant (FF <= Long_Float'Last);
         pragma Loop_Variant (Decreases => 1_025 - EE);
         if EE = 1_025 then
            FF := 0.75;
            exit;
         end if;
         FF := FF / 2.0;
         EE := EE + 1;
      end loop;
      while FF < 0.5 loop
         pragma Loop_Invariant (FF >= 0.0);
         pragma Loop_Invariant (FF <= 1.0);
         pragma Loop_Variant (Decreases => EE + 1_074);
         if EE = -1_074 then
            FF := 0.75;
            exit;
         end if;
         FF := FF * 2.0;
         EE := EE - 1;
      end loop;
      --  The second loop's exit gives the lower bound; the upper one comes
      --  from the first loop's exit, with a clamp for the guard path so the
      --  postcondition needs no loop invariant about floating-point scaling.
      if FF >= 1.0 or else FF < 0.5 then
         FF := 0.75;
      end if;
      F := FF;
      E := EE;
   end Decompose;

   --  The 53-bit mantissa of a value in [0.5, 1) as an integer: one
   --  multiply by the exact power, whose bounds then follow from F's.
   function Mant_Of (F : Long_Float) return Integer_128
     with
       Pre  => F >= 0.5 and then F < 1.0,
       Post => Mant_Of'Result >= 4_503_599_627_370_496
         and then Mant_Of'Result <= 9_007_199_254_740_991
   is
      V : Long_Float;
   begin
      V := F * (2.0 ** 53);
      return Integer_128 (V);
   end Mant_Of;

   --  The next double toward +inf (Up) or toward zero: the ulp is exactly
   --  X / mantissa, and that division is bounded because the mantissa is at
   --  least 2**52 -- the shape GNATprove discharges for a divisor of at least
   --  one.  The postcondition is what lets the floor loops re-establish this
   --  function's preconditions on every iteration; the fallback branches it
   --  contains are unreachable for sqrt's candidates (they stay under
   --  2e160, far below half the range) and exist only so the postcondition
   --  needs no reasoning about a near-range sum.
   function Step_Toward (X : Long_Float; Up : Boolean) return Long_Float
     with
       Pre  => X >= -Long_Float'Last and then X <= Long_Float'Last,
       Post => Step_Toward'Result >= -Long_Float'Last
         and then Step_Toward'Result <= Long_Float'Last
   is
      F : Long_Float;
      E : Integer;
      U : Long_Float;
   begin
      if X > Long_Float'Last then
         return Long_Float'Last;
      end if;
      if X <= 0.0 then
         --  Zero, a negative, or an odd input; sqrt's candidate is positive
         --  and stays so.
         return X;
      end if;
      Decompose (X, F, E);
      if E < -1_021 then
         --  Below the smallest normal every value shares one ulp; the sqrt
         --  candidates never get here, since their roots stay far above the
         --  denormal range.
         return X;
      end if;
      U := X / Long_Float (Mant_Of (F));
      if not Up then
         return X - U;
      end if;
      if abs X < 1.0 or else abs U < 1.0
        or else (abs X <= Long_Float'Last / 2.0
                 and then abs U <= Long_Float'Last / 2.0)
      then
         return X + U;
      end if;
      return Long_Float'Last;
   end Step_Toward;

   --  Exact integer comparisons for the sqrt decision.  A double decomposes
   --  into a mantissa below 2**53 and a power of two; squared, the products
   --  need at most 109 bits, which Interfaces.Integer_128 holds -- so these
   --  answers are exact where a floating-point product would be rounded by
   --  up to half an ulp (which is what made a neighbour-of-the-fixed-point
   --  test tie).  Every guard below is dead for the values sqrt compares --
   --  a Newton result against its own radicand -- and exists so the
   --  arithmetic around it has constant bounds to prove against.
   function Sq_Le (C, X : Long_Float) return Boolean
   is
      Fc, Fx : Long_Float;
      Ec, Ex : Integer;
      MC, MX : Integer_128;
      L      : Integer_128;
      R      : Integer_128 range 0 .. 1_000_000_000_000_000_000_000_000_000_000_000;
      D      : Integer;
   begin
      if not (C > 0.0) or else not (X > 0.0)
        or else C > Long_Float'Last or else X > Long_Float'Last
      then
         return C <= X;
      end if;
      Decompose (C, Fc, Ec);
      Decompose (X, Fx, Ex);
      MC := Mant_Of (Fc);
      MX := Mant_Of (Fx);

      --  C = MC * 2**(Ec - 53), so C*C <= X reads as
      --  MC*MC <= MX * 2**(Ex - 2*Ec + 53), with the shift in [0, 60] for
      --  any pair this close together.
      D := Ex - 2 * Ec + 53;
      if D < 0 or else D > 60 then
         return C <= X;
      end if;

      L := MC * MC;
      R := MX;
      for I in 1 .. D loop
         pragma Loop_Invariant
           (R <= 1_000_000_000_000_000_000_000_000_000_000_000);
         --  The real value (at most 1e16 * 2**60) never reaches the
         --  saturation point, so this guard only ever lets the doubling
         --  happen; it is what makes the assignment's subtype check a
         --  constant-bound question.
         if R <= 500_000_000_000_000_000_000_000_000_000_000 then
            R := R + R;
         end if;
      end loop;
      return L <= R;
   end Sq_Le;

   --  Is the square of the midpoint between G and its successor at most X?
   --  The midpoint itself is not representable (it has 54 significant bits),
   --  so it is compared in its exact integer form:
   --  m = (2*MG + 1) * 2**(Eg - 54), m*m = (2*MG+1)**2 * 2**(2*Eg - 108).
   function Mid_Le (G, X : Long_Float) return Boolean
   is
      Fg, Fx : Long_Float;
      Eg, Ex : Integer;
      MG, MX : Integer_128;
      T, L   : Integer_128;
      R      : Integer_128 range 0 .. 1_000_000_000_000_000_000_000_000_000_000_000;
      D      : Integer;
   begin
      if not (G > 0.0) or else not (X > 0.0)
        or else G > Long_Float'Last or else X > Long_Float'Last
      then
         return G <= X;
      end if;
      Decompose (G, Fg, Eg);
      Decompose (X, Fx, Ex);
      MG := Mant_Of (Fg);
      MX := Mant_Of (Fx);

      D := Ex - 2 * Eg + 55;
      if D < 0 or else D > 60 then
         return G <= X;
      end if;

      T := 2 * MG + 1;
      L := T * T;
      R := MX;
      for I in 1 .. D loop
         pragma Loop_Invariant
           (R <= 1_000_000_000_000_000_000_000_000_000_000_000);
         if R <= 500_000_000_000_000_000_000_000_000_000_000 then
            R := R + R;
         end if;
      end loop;
      return L <= R;
   end Mid_Le;

   --  floor(sqrt(V)) for V below 2**126, by binary search: the root fits in
   --  63 bits, and every product stays inside Integer_128.  What it must
   --  give the proof is only that its arithmetic is safe and it terminates;
   --  that the candidate is near the root -- and the floor loops below make
   --  it the exact one -- is what the test suite checks.
   procedure ISqrt128
     (V : Integer_128;
      R : out Wide_Root)
     with
       Pre  => V >= 0,
       Always_Terminates
   is
      Lo  : Wide_Root := 0;
      Hi  : Wide_Root := 9_223_372_036_854_775_808;
      Mid : Wide_Root;
      Sq  : Integer_128;
   begin
      while Lo < Hi loop
         pragma Loop_Variant (Decreases => Hi - Lo);
         Mid := (Lo + Hi + 1) / 2;
         Sq := Mid * Mid;
         if Sq <= V then
            Lo := Mid;
         else
            Hi := Mid - 1;
         end if;
      end loop;
      R := Lo;
   end ISqrt128;

   --  The principal square root of a non-negative double.  Newton's method
   --  (seeded from the value's binary exponent) lands within a ulp of the
   --  root; the two exact comparisons then make that the true floor and
   --  choose the nearer neighbour across the midpoint, which is the
   --  correctly rounded result.  Every operation outside the iteration is
   --  integer or comparison arithmetic, so no range check hangs off an
   --  unanalyzed result.
   function Sqrt_Of (X : Long_Float) return Long_Float
     with Pre => X >= 0.0 and then X <= Long_Float'Last
   is
      F0    : Long_Float;
      E0    : Integer;
      M2    : Integer_128;
      K     : Integer;
      V     : Integer_128;
      R     : Wide_Root;
      R53   : Integer_128;
      P     : Integer;
      G     : Long_Float;
      Nudge : Natural range 0 .. 8 := 0;
   begin
      if X = 0.0 then
         --  Includes a negative zero, whose root the IEEE rules define.
         return X;
      end if;

      --  X = M * 2**(E0 - 53) with M in [2**52, 2**53): the power is
      --  E0 - 53, not E0, and its parity decides whether one power moves
      --  into the mantissa -- then both cases read X = M2 * 2**(2*K) and the
      --  root is sqrt(M2) * 2**K.
      Decompose (X, F0, E0);
      M2 := Mant_Of (F0);
      if E0 mod 2 /= 0 then
         K := (E0 - 53) / 2;
      else
         M2 := M2 + M2;
         K := (E0 - 54) / 2;
      end if;

      --  floor(sqrt(M2 * 2**72)) is floor(sqrt(M2) * 2**36): a 63-bit root
      --  of a value below 2**126, all in Integer_128.  Rounding it to 53
      --  bits -- R is in [2**62, 2**63), so the shift is ten -- gives a
      --  candidate within a small fraction of an ulp of the true root.
      V := M2 * 4_722_366_482_869_645_213_696;
      ISqrt128 (V, R);
      --  R = sqrt(M2) * 2**36 to within one, so R53 = R / 2**10 is
      --  sqrt(M2) * 2**26 to within a fraction of a unit in the last place.
      R53 := (R + 512) / 1024;
      G := Long_Float (R53);

      --  Scale by 2**(K - 26).  The doubling is guarded by a bound the
      --  real value never reaches (2**529), which is what makes each step's
      --  range check a constant-bound question.
      P := K - 26;
      if P >= 0 then
         for I in 1 .. P loop
            pragma Loop_Invariant (G >= 0.0);
            pragma Loop_Invariant (G <= 2.0E160);
            if G <= 1.0E160 then
               G := G * 2.0;
            end if;
         end loop;
      else
         for I in 1 .. (0 - P) loop
            pragma Loop_Invariant (G >= 0.0);
            pragma Loop_Invariant (G <= 9.1E15);
            G := G / 2.0;
         end loop;
      end if;

      --  The candidate is positive for every real input (the root of a
      --  positive value); the guard exists so the callees' G > 0.0
      --  preconditions are facts rather than hopes.
      if not (G > 0.0) then
         return X;
      end if;

      --  Step down while G's square exceeds X, then up while the
      --  successor's does not: G becomes the exact floor of the root.
      while Nudge < 8 and then not Sq_Le (G, X) loop
         pragma Loop_Variant (Decreases => 8 - Nudge);
         G := Step_Toward (G, False);
         Nudge := Nudge + 1;
      end loop;
      Nudge := 0;
      while Nudge < 8
        and then Sq_Le (Step_Toward (G, True), X)
      loop
         pragma Loop_Variant (Decreases => 8 - Nudge);
         G := Step_Toward (G, True);
         Nudge := Nudge + 1;
      end loop;

      --  G*G <= X < next(G)*next(G): round across the midpoint.
      if Mid_Le (G, X) then
         return Step_Toward (G, True);
      end if;
      return G;
   end Sqrt_Of;

   --  sqrt: exact when the argument is exact and the root is (R7RS), which
   --  the integer search settles without touching a float; otherwise
   --  Sqrt_Of, whose result only ever flows into check-free float contexts
   --  -- a flonum value and the writer's formatter.
   procedure Sqrt_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr     : Value_Array;
      Len     : Natural;
      Good    : Boolean;
      N       : Fixnum;
      S       : Root_Range;
      Perfect : Boolean;
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

      if Arr (1).Kind = Kind_Fixnum then
         Get_Fixnum (Arr (1), N, Good);
         if not Good then
            return;
         end if;
         if N < 0 then
            Status := Error_Range;
            return;
         end if;
         ISqrt (N, S, Perfect);
         if Perfect then
            Result := From_Fixnum (Integer_64 (S));
         else
            Result := From_Flonum (Sqrt_Of (Long_Float (N)));
         end if;
         Status := No_Error;
      elsif Arr (1).Kind = Kind_Flonum then
         if Arr (1).F /= Arr (1).F then
            --  NaN roots to NaN; the guard also keeps Sqrt_Of's precondition
            --  honest, since NaN satisfies no comparison at all.
            Result := Arr (1);
            Status := No_Error;
            return;
         end if;
         if Arr (1).F > Long_Float'Last then
            --  Positive infinity roots to itself.
            Result := Arr (1);
            Status := No_Error;
            return;
         end if;
         if Arr (1).F < 0.0 then
            Status := Error_Range;
            return;
         end if;
         Result := From_Flonum (Sqrt_Of (Arr (1).F));
         Status := No_Error;
      end if;
   end Sqrt_Prim;

   --  (set-car! pair value) / (set-cdr! pair value): the heap already owns
   --  the mutation, so these only validate the pair and report Scheme errors.
   procedure Set_Car_Prim
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
      if not Is_Handle (Arr (1)) then
         return;
      end if;
      Set_Car (H, To_Handle (Arr (1)), Arr (2), Good);
      if not Good then
         return;
      end if;
      Result := Unspecified_Value;
      Status := No_Error;
   end Set_Car_Prim;

   procedure Set_Cdr_Prim
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
      if not Is_Handle (Arr (1)) then
         return;
      end if;
      Set_Cdr (H, To_Handle (Arr (1)), Arr (2), Good);
      if not Good then
         return;
      end if;
      Result := Unspecified_Value;
      Status := No_Error;
   end Set_Cdr_Prim;

   --  caar / cadr / cdar / cddr.  The single-level helpers live in
   --  Tr7.Pairs; the two-level forms compose them so no new traversal code
   --  is needed.
   procedure Selector_Prim
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
      Tmp  : Value;
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

      case P is
         when P_Caar =>
            Car_Of (H, Arr (1), Tmp, Good);
            if Good then
               Car_Of (H, Tmp, Result, Good);
            end if;
         when P_Cadr =>
            Cadr_Of (H, Arr (1), Result, Good);
         when P_Cdar =>
            Car_Of (H, Arr (1), Tmp, Good);
            if Good then
               Cdr_Of (H, Tmp, Result, Good);
            end if;
         when P_Cddr =>
            Cddr_Of (H, Arr (1), Result, Good);
         when others =>
            Status := Error_Not_Implemented;
            return;
      end case;

      if not Good then
         Result := Void_Value;
         Status := Error_Type;
      else
         Status := No_Error;
      end if;
   end Selector_Prim;

   procedure Symbol_To_String_Prim
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
      C    : Cell;
      Hd   : Handle;
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
      if not Is_Handle (Arr (1)) then
         return;
      end if;
      Fetch (H, To_Handle (Arr (1)), C, Good);
      if not Good or else C.Kind /= Cell_Symbol then
         return;
      end if;
      New_String (H, Text_Of (C), Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Symbol_To_String_Prim;

   procedure String_To_Symbol_Prim
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
      C    : Cell;
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
      String_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      Intern (H, C.Name (1 .. C.Name_Len), Result, Good);
      if not Good then
         Result := Void_Value;
         Status := Error_Heap_Full;
         return;
      end if;
      Status := No_Error;
   end String_To_Symbol_Prim;

   procedure Char_To_Integer_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Code : Unsigned_32;
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
      if Arr (1).Kind /= Kind_Character then
         return;
      end if;
      Code := To_Character (Arr (1));
      if Code > Unsigned_32 (Fixnum_Max) then
         Status := Error_Range;
         return;
      end if;
      Result := From_Fixnum (Integer_64 (Code));
      Status := No_Error;
   end Char_To_Integer_Prim;

   procedure Integer_To_Char_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      N    : Fixnum;
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
      Get_Fixnum (Arr (1), N, Good);
      if not Good then
         return;
      end if;
      if N < 0 or else N > 16#10FFFF# then
         Status := Error_Range;
         return;
      end if;
      Result := From_Character (Unsigned_32 (N));
      Status := No_Error;
   end Integer_To_Char_Prim;

   --  A numeric argument: fixnum or flonum.  Comparison predicates use the
   --  two branches directly; conversions use the typed values.
   procedure Number_Value
     (V      : Value;
      I      : out Fixnum;
      F      : out Long_Float;
      Is_Int : out Boolean;
      Ok     : out Boolean)
   is
   begin
      I := 0;
      F := 0.0;
      Is_Int := Is_Fixnum (V);
      Ok := Is_Int or else Is_Flonum (V);
      if Is_Int then
         Get_Fixnum (V, I, Ok);
         F := Long_Float (I);
      elsif Is_Flonum (V) then
         F := V.F;
      end if;
   end Number_Value;

   procedure List_To_Vector_Prim
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
      N    : Natural;
      Hd   : Handle;
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
      Length (H, Arr (1), N, Good);
      if not Good then
         return;
      end if;
      if N > Max_List_Length then
         --  A vector cell keeps its length in Arity, which is a
         --  Max_List_Length-bounded field: say so instead of tripping the
         --  callee's precondition.
         Status := Error_Range;
         return;
      end if;
      New_Vector (H, Arr (1), N, Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end List_To_Vector_Prim;

   procedure Vector_To_List_Prim
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
      C    : Cell;
      Tmp  : Value;
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
      Vector_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      --  A fresh list: reverse twice rather than returning the vector's own
      --  spine, so mutating one cannot change the other.
      Reverse_List (H, C.Car, Tmp, Good, Status);
      if not Good then
         return;
      end if;
      Reverse_List (H, Tmp, Result, Good, Status);
      if not Good then
         return;
      end if;
      Status := No_Error;
   end Vector_To_List_Prim;

   procedure List_To_String_Prim
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
      N    : Natural;
      Hd   : Handle;
      Buf  : String (1 .. Max_Text) := (others => ' ');
      Elem : Value;
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
      Length (H, Arr (1), N, Good);
      if not Good then
         return;
      end if;
      if N > Max_Text then
         Status := Error_Range;
         return;
      end if;
      for I in 1 .. N loop
         pragma Loop_Invariant (H.Ready);
         Nth (H, Arr (1), I - 1, Elem, Good);
         if not Good or else Elem.Kind /= Kind_Character then
            return;
         end if;
         if Elem.C > 255 then
            Status := Error_Range;
            return;
         end if;
         Buf (I) := Character'Val (Integer (Elem.C));
      end loop;
      New_String (H, Buf (1 .. N), Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end List_To_String_Prim;

   procedure String_To_List_Prim
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
      C    : Cell;
      Acc  : Value := Nil_Value;
      Cell_V : Value;
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
      String_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      --  Build from the end so the result is in string order.
      for I in reverse 1 .. C.Name_Len loop
         pragma Loop_Invariant (H.Ready);
         Cell_V := From_Character
           (Unsigned_32 (Character'Pos (C.Name (I))));
         Cons (H, Cell_V, Acc, Result, Good);
         if not Good then
            Status := Error_Heap_Full;
            return;
         end if;
         Acc := Result;
      end loop;
      Result := Acc;
      Status := No_Error;
   end String_To_List_Prim;

   procedure String_Copy_Prim
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
      C    : Cell;
      Hd   : Handle;
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
      String_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      New_String (H, Text_Of (C), Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end String_Copy_Prim;

   procedure Number_To_String_Prim
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
      B    : Output_Buffer;
      Hd   : Handle;
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
      if not Tr7.Numbers.Is_Number (H, Arr (1)) then
         return;
      end if;
      Write_Value (H, Arr (1), B, Good);
      if not Good then
         Status := Error_Output_Full;
         return;
      end if;
      if B.Len > Max_Text then
         Status := Error_Range;
         return;
      end if;
      declare
         Text : String (1 .. Max_Text) := (others => ' ');
      begin
         for I in 1 .. B.Len loop
            Text (I) := B.Data (I);
         end loop;
         New_String (H, Text (1 .. B.Len), Hd, Good);
      end;
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Number_To_String_Prim;

   procedure String_To_Number_Prim
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
      C    : Cell;
      Pos  : Natural;
      V    : Value;
      St   : Tr7.Reader.Read_Status;
      Space : Boolean;
   begin
      Result := False_Value;
      Status := No_Error;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         Status := Error_Type;
         return;
      end if;
      Check_Arity (Len, 1, 1, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      String_Cell (H, Arr (1), C, Good);
      if not Good then
         Status := Error_Type;
         return;
      end if;
      if C.Name_Len = 0 then
         return;
      end if;

      Pos := 0;
      Tr7.Reader.Read_Datum (H, C.Name (1 .. C.Name_Len), Pos, V, St);
      if St /= Tr7.Reader.Read_Ok then
         return;
      end if;
      --  Only trailing whitespace may follow the number.  Pos is the last
      --  consumed character (the reader's convention), so start at Pos + 1.
      Pos := Pos + 1;
      while Pos <= C.Name_Len loop
         pragma Loop_Invariant (Pos >= 1);
         pragma Loop_Invariant (Pos <= C.Name_Len + 1);
         Space := C.Name (Pos) = ' '
           or else C.Name (Pos) = Character'Val (9)
           or else C.Name (Pos) = Character'Val (10)
           or else C.Name (Pos) = Character'Val (13);
         exit when not Space;
         Pos := Pos + 1;
      end loop;
      if Pos <= C.Name_Len then
         return;
      end if;
      if Tr7.Numbers.Is_Number (H, V) then
         Result := V;
      end if;
   end String_To_Number_Prim;

   procedure Numeric_Predicate_Prim
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
      I    : Fixnum;
      F    : Long_Float;
      Int  : Boolean;
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
      if P = P_Exact_P or else P = P_Inexact_P then
         if not Tr7.Numbers.Is_Number (H, Arr (1)) then
            return;
         end if;
         if P = P_Exact_P then
            Result := Bool (Tr7.Numbers.Is_Exact (H, Arr (1)));
         else
            Result := Bool (not Tr7.Numbers.Is_Exact (H, Arr (1)));
         end if;
         Status := No_Error;
         return;
      end if;
      if Tr7.Numbers.Is_Tower_Value (H, Arr (1)) then
         case P is
            when P_Zero_P =>
               Res := Tr7.Numbers.Is_Zero_Number (H, Arr (1));
            when P_Positive_P =>
               if not Tr7.Numbers.Is_Real_Value (H, Arr (1)) then
                  return;
               end if;
               Res := Tr7.Numbers.Is_Positive_Number (H, Arr (1));
            when P_Negative_P =>
               if not Tr7.Numbers.Is_Real_Value (H, Arr (1)) then
                  return;
               end if;
               Res := Tr7.Numbers.Is_Negative_Number (H, Arr (1));
            when P_Odd_P | P_Even_P =>
               if not Tr7.Numbers.Is_Exact_Integer (H, Arr (1)) then
                  return;
               end if;
               if P = P_Odd_P then
                  Res := Tr7.Numbers.Is_Odd_Integer (H, Arr (1));
               else
                  Res := Tr7.Numbers.Is_Even_Integer (H, Arr (1));
               end if;
            when others =>
               Status := Error_Not_Implemented;
               return;
         end case;
         Result := Bool (Res);
         Status := No_Error;
         return;
      end if;
      Number_Value (Arr (1), I, F, Int, Good);
      if not Good then
         return;
      end if;
      case P is
         when P_Zero_P =>
            Res := (if Int then I = 0 else F = 0.0);
         when P_Positive_P =>
            Res := (if Int then I > 0 else F > 0.0);
         when P_Negative_P =>
            Res := (if Int then I < 0 else F < 0.0);
         when P_Odd_P =>
            if not Int then
               return;
            end if;
            Res := I mod 2 /= 0;
         when P_Even_P =>
            if not Int then
               return;
            end if;
            Res := I mod 2 = 0;
         when others =>
            Status := Error_Not_Implemented;
            return;
      end case;
      Result := Bool (Res);
      Status := No_Error;
   end Numeric_Predicate_Prim;

   procedure Char_Compare_Prim
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
      Ok   : Boolean := True;
      A, B : Unsigned_32;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 2, Max_Arguments, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      for I in 1 .. Len loop
         if Arr (I).Kind /= Kind_Character then
            return;
         end if;
      end loop;
      for I in 1 .. Len - 1 loop
         if Arr (I).Kind /= Kind_Character
           or else Arr (I + 1).Kind /= Kind_Character
         then
            return;
         end if;
         A := To_Character (Arr (I));
         B := To_Character (Arr (I + 1));
         case P is
            when P_Char_Equal =>
               Ok := Ok and then A = B;
            when P_Char_Less =>
               Ok := Ok and then A < B;
            when P_Char_Greater =>
               Ok := Ok and then A > B;
            when P_Char_Less_Equal =>
               Ok := Ok and then A <= B;
            when others =>
               Ok := Ok and then A >= B;
         end case;
      end loop;
      Result := Bool (Ok);
      Status := No_Error;
   end Char_Compare_Prim;

   --  Lexicographic comparison of two string cells.
   procedure String_Compare
     (H   : Heap_Type;
      A   : Value;
      B   : Value;
      Cmp : out Integer;
      Ok  : out Boolean)
     with
       Pre  => H.Ready,
       Post => (if Ok then Cmp in -1 .. 1)
   is
      CA, CB : Cell;
      N      : Natural;
      X, Y   : Character;
   begin
      Cmp := 0;
      String_Cell (H, A, CA, Ok);
      if not Ok then
         return;
      end if;
      String_Cell (H, B, CB, Ok);
      if not Ok then
         return;
      end if;
      N := Natural'Min (CA.Name_Len, CB.Name_Len);
      for I in 1 .. N loop
         X := CA.Name (I);
         Y := CB.Name (I);
         if X < Y then
            Cmp := -1;
            Ok := True;
            return;
         elsif X > Y then
            Cmp := 1;
            Ok := True;
            return;
         end if;
      end loop;
      if CA.Name_Len < CB.Name_Len then
         Cmp := -1;
      elsif CA.Name_Len > CB.Name_Len then
         Cmp := 1;
      end if;
      Ok := True;
   end String_Compare;

   procedure String_Compare_Prim
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
      Ok   : Boolean := True;
      Cmp  : Integer;
      This : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 2, Max_Arguments, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      for I in 1 .. Len - 1 loop
         String_Compare (H, Arr (I), Arr (I + 1), Cmp, Good);
         if not Good then
            return;
         end if;
         case P is
            when P_String_Less =>
               This := Cmp < 0;
            when P_String_Greater =>
               This := Cmp > 0;
            when P_String_Less_Equal =>
               This := Cmp <= 0;
            when others =>
               This := Cmp >= 0;
         end case;
         Ok := Ok and then This;
      end loop;
      Result := Bool (Ok);
      Status := No_Error;
   end String_Compare_Prim;

   procedure Make_String_Prim
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
      K    : Fixnum;
      Ch   : Value;
      Code : Unsigned_32 := Unsigned_32 (Character'Pos (' '));
      Hd   : Handle;
      Buf  : String (1 .. Max_Text) := (others => ' ');
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 1, 2, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      Get_Fixnum (Arr (1), K, Good);
      if not Good or else K < 0 or else K > Max_Text then
         Status := Error_Range;
         return;
      end if;
      if Len = 2 then
         Ch := Arr (2);
         if Ch.Kind /= Kind_Character then
            Status := Error_Type;
            return;
         end if;
         Code := To_Character (Ch);
         if Code > 255 then
            Status := Error_Range;
            return;
         end if;
      end if;
      for I in 1 .. Natural (K) loop
         Buf (I) := Character'Val (Integer (Code));
      end loop;
      New_String (H, Buf (1 .. Natural (K)), Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Make_String_Prim;

   procedure String_Set_Prim
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
      C    : Cell;
      K    : Fixnum;
      Ch   : Value;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 3, 3, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      String_Cell (H, Arr (1), C, Good);
      if not Good or else not Is_Handle (Arr (1)) then
         return;
      end if;
      declare
         Ix : constant Cell_Index := To_Handle (Arr (1)).Index;
      begin
         if Ix not in Valid_Cell_Index then
            return;
         end if;
         Get_Fixnum (Arr (2), K, Good);
         if not Good or else K < 0 or else K >= Fixnum (C.Name_Len) then
            Status := Error_Index;
            return;
         end if;
         Ch := Arr (3);
         if Ch.Kind /= Kind_Character or else Ch.C > 255 then
            Status := Error_Type;
            return;
         end if;
         H.Cells (Ix).Name (Natural (K) + 1) :=
           Character'Val (Integer (Ch.C));
      end;
      Result := Unspecified_Value;
      Status := No_Error;
   end String_Set_Prim;

   procedure Make_Vector_Prim
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
      K     : Fixnum;
      Fill  : Value := Unspecified_Value;
      Acc   : Value := Nil_Value;
      Item  : Value;
      Hd    : Handle;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 1, 2, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      Get_Fixnum (Arr (1), K, Good);
      if not Good or else K < 0 or else K > Max_List_Length then
         --  A vector cell stores its length in a Max_List_Length-bounded
         --  field, so this is an honest capacity report, not a hidden cap.
         Status := Error_Range;
         return;
      end if;
      if Len = 2 then
         Fill := Arr (2);
      end if;
      for I in 1 .. Natural (K) loop
         pragma Loop_Invariant (H.Ready);
         Cons (H, Fill, Acc, Item, Good);
         if not Good then
            Status := Error_Heap_Full;
            return;
         end if;
         Acc := Item;
      end loop;
      New_Vector (H, Acc, Natural (K), Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Make_Vector_Prim;

   procedure Vector_Fill_Prim
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
      C    : Cell;
      Cur  : Value;
      Node : Cell;
      Hd   : Handle;
      Left : Natural;
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
      Vector_Cell (H, Arr (1), C, Good);
      if not Good then
         return;
      end if;
      Cur := C.Car;
      Left := Max_Cells + 1;
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         if not Is_Handle (Cur) then
            return;
         end if;
         Fetch (H, To_Handle (Cur), Node, Good);
         if not Good or else Node.Kind /= Cell_Pair then
            return;
         end if;
         Hd := To_Handle (Cur);
         Set_Car (H, Hd, Arr (2), Good);
         if not Good then
            return;
         end if;
         Cur := Node.Cdr;
         Left := Left - 1;
      end loop;
      Result := Unspecified_Value;
      Status := No_Error;
   end Vector_Fill_Prim;

   procedure List_Tail_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      K    : Fixnum;
      V    : Value;
      Tmp  : Value;
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
      Get_Fixnum (Arr (2), K, Good);
      if not Good or else K < 0 or else K > Max_Cells then
         --  A proper list has at most Max_Cells elements (one cell per
         --  pair), so this bound cannot reject a tail a caller could
         --  legitimately want.
         Status := Error_Index;
         return;
      end if;
      Tmp := Arr (1);
      for I in 1 .. Natural (K) loop
         Cdr_Of (H, Tmp, V, Good);
         if not Good then
            Status := Error_Type;
            return;
         end if;
         Tmp := V;
      end loop;
      Result := Tmp;
      Status := No_Error;
   end List_Tail_Prim;

   procedure List_Copy_Prim
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
      Tmp  : Value;
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
      Reverse_List (H, Arr (1), Tmp, Good, Status);
      if not Good then
         return;
      end if;
      Reverse_List (H, Tmp, Result, Good, Status);
      if not Good then
         return;
      end if;
      Status := No_Error;
   end List_Copy_Prim;

   procedure Last_Pair_Prim
     (H      : Heap_Type;
      Args   : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      Arr  : Value_Array;
      Len  : Natural;
      Good : Boolean;
      Cur  : Value;
      Node : Cell;
      Next : Value;
      Left : Natural := Max_Cells + 1;
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
      if not Is_Handle (Arr (1)) then
         return;
      end if;
      Cur := Arr (1);
      loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (Is_Handle (Cur));
         pragma Loop_Variant (Decreases => Left);
         if Left = 0 then
            return;
         end if;
         Left := Left - 1;
         Fetch (H, To_Handle (Cur), Node, Good);
         if not Good or else Node.Kind /= Cell_Pair then
            return;
         end if;
         if Is_Nil (Node.Cdr) then
            Result := Cur;
            Status := No_Error;
            return;
         end if;
         Next := Node.Cdr;
         if not Is_Handle (Next) then
            return;
         end if;
         Cur := Next;
      end loop;
   end Last_Pair_Prim;

   procedure Complex_Constructor_Prim
     (H      : in out Heap_Type;
      Args   : Value;
      Polar  : Boolean;
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
      if Polar then
         Tr7.Numbers.Make_Polar (H, Arr (1), Arr (2), Result, Status);
      else
         Tr7.Numbers.Make_Complex (H, Arr (1), Arr (2), Result, Status);
      end if;
   end Complex_Constructor_Prim;

   procedure Complex_Selector_Prim
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
      if P = P_Real_Part then
         Tr7.Numbers.Real_Part (H, Arr (1), Result, Status);
      else
         Tr7.Numbers.Imag_Part (H, Arr (1), Result, Status);
      end if;
   end Complex_Selector_Prim;

   procedure Magnitude_Prim
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
      Check_Arity (Len, 1, 1, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      Tr7.Numbers.Magnitude (H, Arr (1), Result, Status);
   end Magnitude_Prim;

   procedure Equal_Prim
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
      Ok   : Boolean := True;
   begin
      Result := Void_Value;
      Status := Error_Type;
      Args_Of (H, Args, Arr, Len, Good);
      if not Good then
         return;
      end if;
      Check_Arity (Len, 2, Max_Arguments, Good);
      if not Good then
         Status := Error_Wrong_Arity;
         return;
      end if;
      for I in 2 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         if P = P_Equal_P then
            declare
               Eq   : Boolean;
               Fine : Boolean;
            begin
               Deep_Equal (H, Arr (1), Arr (I), Eq, Fine);
               if not Fine then
                  --  The pairing table filled: pathological sharing, not
                  --  an answer, so say so (the same verdict memq gives a
                  --  ring it cannot finish walking).
                  Status := Error_Malformed;
                  return;
               end if;
               Ok := Ok and then Eq;
            end;
         elsif P = P_Eqv_P then
            if Tr7.Numbers.Is_Number (H, Arr (1))
              and then Tr7.Numbers.Is_Number (H, Arr (I))
            then
               Ok := Ok and then
                 Tr7.Numbers.Eqv_Numeric (H, Arr (1), Arr (I));
            else
               Ok := Ok and then Same_Value (Arr (1), Arr (I));
            end if;
         elsif P = P_Boolean_Equal then
            Ok := Ok
              and then Arr (1).Kind = Kind_Boolean
              and then Arr (I).Kind = Kind_Boolean
              and then Arr (1).B = Arr (I).B;
         else
            Ok := Ok
              and then Is_Handle (Arr (1))
              and then Is_Handle (Arr (I))
              and then Same_Value (Arr (1), Arr (I));
         end if;
      end loop;
      --  Every argument must have the right type even if an early pair
      --  already decided the answer.
      if P /= P_Eqv_P and then P /= P_Equal_P then
         for I in 1 .. Len loop
            if P = P_Boolean_Equal then
               if Arr (I).Kind /= Kind_Boolean then
                  Status := Error_Type;
                  return;
               end if;
            else
               declare
                  Tmp  : Cell;
                  Fine : Boolean;
               begin
                  if not Is_Handle (Arr (I)) then
                     Status := Error_Type;
                     return;
                  end if;
                  Fetch (H, To_Handle (Arr (I)), Tmp, Fine);
                  if not Fine or else Tmp.Kind /= Cell_Symbol then
                     Status := Error_Type;
                     return;
                  end if;
               end;
            end if;
         end loop;
      end if;
      Result := Bool (Ok);
      Status := No_Error;
   end Equal_Prim;

   procedure Call
     (H      : in out Heap_Type;
      P      : Primitive_Id;
      Args   : Value;
      Result : out Value;
      B      : in out Output_Buffer;
      Status : out Error_Code)
   is
      Good  : Boolean;
      Len   : Natural;
      Port_V : Value;
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

         when P_Div =>
            Div_Prim (H, Args, Result, Status);

         when P_Error =>
            Error_Prim (H, Args, Result, Status);

         when P_Values =>
            Values_Prim (H, Args, Result, Status);

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

         when P_Null_P | P_Pair_P | P_Not | P_String_P | P_Vector_P
           | P_Bytevector_P | P_Port_P | P_Eof_Object_P
           | P_Boolean_P | P_Symbol_P | P_Char_P | P_Number_P
           | P_Integer_P | P_Rational_P | P_Real_P | P_Complex_P
           | P_Procedure_P | P_Values_P =>
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
            Check_Arity (Len, 0, 1, Good);
            if not Good then
               Status := Error_Wrong_Arity;
               return;
            end if;
            if Len = 1 then
               --  A newline is a character with display semantics, so the
               --  port path is the display path.
               Car_Of (H, Args, Port_V, Good);
               if not Good then
                  Status := Error_Malformed;
                  return;
               end if;
               Emit_To_Port
                 (H, From_Character (Unsigned_32 (Character'Pos (LF))),
                  Port_V, True, Status);
               Result := Unspecified_Value;
               return;
            end if;
            Put_Char (B, LF, Good);
            Result := Unspecified_Value;
            Status := (if Good then No_Error else Error_Output_Full);

         when P_Abs =>
            Abs_Prim (H, Args, Result, Status);

         when P_Min =>
            Min_Max_Prim (H, Args, False, Result, Status);

         when P_Max =>
            Min_Max_Prim (H, Args, True, Result, Status);

         when P_Quotient =>
            Quotient_Prim (H, Args, Result, Status);

         when P_Remainder =>
            Remainder_Prim (H, Args, Result, Status);

         when P_Modulo =>
            Modulo_Prim (H, Args, Result, Status);

         when P_Expt =>
            Expt_Prim (H, Args, Result, Status);

         when P_Exact_To_Inexact =>
            Exact_To_Inexact_Prim (H, Args, Result, Status);

         when P_Open_Input_String =>
            Open_Input_String_Prim (H, Args, Result, Status);

         when P_Open_Output_String =>
            Open_Output_String_Prim (H, Args, Result, Status);

         when P_Get_Output_String =>
            Get_Output_String_Prim (H, Args, Result, Status);

         when P_Read =>
            Read_Prim (H, Args, Result, Status);

         when P_Read_Char =>
            Read_Char_Prim (H, Args, True, Result, Status);

         when P_Peek_Char =>
            Read_Char_Prim (H, Args, False, Result, Status);

         when P_Char_Ready =>
            Char_Ready_Prim (H, Args, Result, Status);

         when P_Sqrt =>
            Sqrt_Prim (H, Args, Result, Status);

         when P_Length =>
            Length_Prim (H, Args, Result, Status);

         when P_Append =>
            Append_Prim (H, Args, Result, Status);

         when P_Reverse =>
            Reverse_Prim (H, Args, Result, Status);

         when P_List_Ref =>
            List_Ref_Prim (H, Args, Result, Status);

         when P_Assq | P_Assv =>
            Assq_Prim (H, Args, Result, Status);

         when P_Memq | P_Memv =>
            Memq_Prim (H, Args, Result, Status);

         when P_Member =>
            Member_Prim (H, Args, Result, Status);

         when P_Assoc =>
            Assoc_Prim (H, Args, Result, Status);

         when P_Bytevector_Length =>
            Bytevector_Length_Prim (H, Args, Result, Status);

         when P_Bytevector_U8_Ref =>
            Bytevector_U8_Ref_Prim (H, Args, Result, Status);

         when P_Bytevector_U8_Set =>
            Bytevector_U8_Set_Prim (H, Args, Result, Status);

         when P_Bytevector =>
            Bytevector_Prim (H, Args, Result, Status);

         when P_Vector_Length =>
            Vector_Length_Prim (H, Args, Result, Status);

         when P_Vector_Ref =>
            Vector_Ref_Prim (H, Args, Result, Status);

         when P_Vector_Set =>
            Vector_Set_Prim (H, Args, Result, Status);

         when P_Vector =>
            Vector_Prim (H, Args, Result, Status);

         when P_String_Length =>
            String_Length_Prim (H, Args, Result, Status);

         when P_String_Ref =>
            String_Ref_Prim (H, Args, Result, Status);

         when P_Substring =>
            Substring_Prim (H, Args, Result, Status);

         when P_String_Append =>
            String_Append_Prim (H, Args, Result, Status);

         when P_String_Equal =>
            String_Equal_Prim (H, Args, Result, Status);

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

         when P_Set_Car =>
            Set_Car_Prim (H, Args, Result, Status);

         when P_Set_Cdr =>
            Set_Cdr_Prim (H, Args, Result, Status);

         when P_Caar | P_Cadr | P_Cdar | P_Cddr =>
            Selector_Prim (H, Args, P, Result, Status);

         when P_Symbol_To_String =>
            Symbol_To_String_Prim (H, Args, Result, Status);

         when P_String_To_Symbol =>
            String_To_Symbol_Prim (H, Args, Result, Status);

         when P_Char_To_Integer =>
            Char_To_Integer_Prim (H, Args, Result, Status);

         when P_Integer_To_Char =>
            Integer_To_Char_Prim (H, Args, Result, Status);

         when P_List_To_Vector =>
            List_To_Vector_Prim (H, Args, Result, Status);

         when P_Vector_To_List =>
            Vector_To_List_Prim (H, Args, Result, Status);

         when P_List_To_String =>
            List_To_String_Prim (H, Args, Result, Status);

         when P_String_To_List =>
            String_To_List_Prim (H, Args, Result, Status);

         when P_String_Copy =>
            String_Copy_Prim (H, Args, Result, Status);

         when P_Number_To_String =>
            Number_To_String_Prim (H, Args, Result, Status);

         when P_String_To_Number =>
            String_To_Number_Prim (H, Args, Result, Status);

         when P_Exact_P | P_Inexact_P | P_Zero_P | P_Positive_P
           | P_Negative_P | P_Odd_P | P_Even_P =>
            Numeric_Predicate_Prim (H, Args, P, Result, Status);

         when P_Char_Equal | P_Char_Less | P_Char_Greater
           | P_Char_Less_Equal | P_Char_Greater_Equal =>
            Char_Compare_Prim (H, Args, P, Result, Status);

         when P_String_Less | P_String_Greater | P_String_Less_Equal
           | P_String_Greater_Equal =>
            String_Compare_Prim (H, Args, P, Result, Status);

         when P_Make_String =>
            Make_String_Prim (H, Args, Result, Status);

         when P_String_Set =>
            String_Set_Prim (H, Args, Result, Status);

         when P_Make_Vector =>
            Make_Vector_Prim (H, Args, Result, Status);

         when P_Vector_Fill =>
            Vector_Fill_Prim (H, Args, Result, Status);

         when P_List_Tail =>
            List_Tail_Prim (H, Args, Result, Status);

         when P_List_Copy =>
            List_Copy_Prim (H, Args, Result, Status);

         when P_Last_Pair =>
            Last_Pair_Prim (H, Args, Result, Status);

         when P_Eqv_P | P_Boolean_Equal | P_Symbol_Equal | P_Equal_P =>
            Equal_Prim (H, Args, P, Result, Status);

         when P_Make_Rectangular =>
            Complex_Constructor_Prim (H, Args, False, Result, Status);

         when P_Make_Polar =>
            Complex_Constructor_Prim (H, Args, True, Result, Status);

         when P_Real_Part | P_Imag_Part =>
            Complex_Selector_Prim (H, Args, P, Result, Status);

         when P_Magnitude =>
            Magnitude_Prim (H, Args, Result, Status);

         when P_None =>
            return;
      end case;
   end Call;

end Tr7.Primitives;
