pragma Ada_2022;

with Ada.Numerics.Big_Numbers.Big_Integers; use Ada.Numerics.Big_Numbers.Big_Integers;
with Interfaces; use Interfaces;
with Tr7.Bignums; use Tr7.Bignums;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.IEEE;
with Tr7.Reader;

package body Tr7.Numbers with
   SPARK_Mode => On
is

   function Kind_Of_Value (H : Heap_Type; V : Value) return Cell_Kind
     with Pre => H.Ready
   is
      C    : Cell;
      Good : Boolean;
   begin
      if not Is_Handle (V) then
         return Cell_Free;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      if not Good then
         return Cell_Free;
      end if;
      return C.Kind;
   end Kind_Of_Value;

   function Float_In_Range (V : Long_Float) return Boolean is
     (V = V and then V <= Long_Float'Last and then V >= -Long_Float'Last);

   function Is_Tower_Value (H : Heap_Type; V : Value) return Boolean
   is
      K : constant Cell_Kind := Kind_Of_Value (H, V);
   begin
      return K = Cell_Bigint or else K = Cell_Rational
        or else K = Cell_Complex;
   end Is_Tower_Value;

   function Is_Number (H : Heap_Type; V : Value) return Boolean is
     (Is_Fixnum (V) or else Is_Flonum (V) or else Is_Tower_Value (H, V));

   --  A real exact part: no complex recursion, because the constructors
   --  keep complex parts real by construction.
   function Is_Exact_Real (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready
   is
      K : constant Cell_Kind := Kind_Of_Value (H, V);
   begin
      return Is_Fixnum (V) or else K = Cell_Bigint
        or else K = Cell_Rational;
   end Is_Exact_Real;

   function Is_Exact (H : Heap_Type; V : Value) return Boolean
   is
      K    : constant Cell_Kind := Kind_Of_Value (H, V);
      C    : Cell;
      Good : Boolean;
   begin
      if Is_Fixnum (V) then
         return True;
      elsif Is_Flonum (V) then
         return False;
      elsif K = Cell_Bigint or else K = Cell_Rational then
         return True;
      elsif K = Cell_Complex then
         if not Is_Handle (V) then
            return False;
         end if;
         Fetch (H, To_Handle (V), C, Good);
         if not Good then
            return False;
         end if;
         return Is_Exact_Real (H, C.Car) and then Is_Exact_Real (H, C.Cdr);
      end if;
      return False;
   end Is_Exact;

   function Is_Exact_Integer (H : Heap_Type; V : Value) return Boolean is
     (Tr7.Bignums.Is_Exact_Integer (H, V));

   function Rat_Field
     (H : Heap_Type;
      V : Value;
      Num : Boolean) return Value
     with Pre => H.Ready
   is
      C    : Cell;
      Good : Boolean;
   begin
      if not Is_Handle (V) then
         return Void_Value;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      if not Good or else C.Kind /= Cell_Rational then
         return Void_Value;
      end if;
      return (if Num then C.Car else C.Cdr);
   end Rat_Field;

   function Numerator_Of
     (H : Heap_Type;
      V : Value) return Valid_Big_Integer
     with Pre => H.Ready
   is
   begin
      if Kind_Of_Value (H, V) = Cell_Rational then
         return To_Big_Value (H, Rat_Field (H, V, True));
      end if;
      return To_Big_Value (H, V);
   end Numerator_Of;

   function Denominator_Of
     (H : Heap_Type;
      V : Value) return Valid_Big_Integer
     with Pre => H.Ready
   is
   begin
      if Kind_Of_Value (H, V) = Cell_Rational then
         return To_Big_Value (H, Rat_Field (H, V, False));
      end if;
      return To_Big_Integer (1);
   end Denominator_Of;

   procedure Normalize
     (H      : in out Heap_Type;
      N      : Valid_Big_Integer;
      D      : Valid_Big_Integer;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
   begin
      Result := Void_Value;
      if D = To_Big_Integer (0) then
         Status := Error_Division_By_Zero;
         return;
      end if;
      From_Big_Ratio (H, N, D, Result, Status);
   end Normalize;

   procedure Real_Add
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      N1 : constant Valid_Big_Integer := Numerator_Of (H, A);
      D1 : constant Valid_Big_Integer := Denominator_Of (H, A);
      N2 : constant Valid_Big_Integer := Numerator_Of (H, B);
      D2 : constant Valid_Big_Integer := Denominator_Of (H, B);
   begin
      Normalize (H, N1 * D2 + N2 * D1, D1 * D2, Result, Status);
   end Real_Add;

   procedure Real_Sub
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      N1 : constant Valid_Big_Integer := Numerator_Of (H, A);
      D1 : constant Valid_Big_Integer := Denominator_Of (H, A);
      N2 : constant Valid_Big_Integer := Numerator_Of (H, B);
      D2 : constant Valid_Big_Integer := Denominator_Of (H, B);
   begin
      Normalize (H, N1 * D2 - N2 * D1, D1 * D2, Result, Status);
   end Real_Sub;

   procedure Real_Mul
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      N1 : constant Valid_Big_Integer := Numerator_Of (H, A);
      D1 : constant Valid_Big_Integer := Denominator_Of (H, A);
      N2 : constant Valid_Big_Integer := Numerator_Of (H, B);
      D2 : constant Valid_Big_Integer := Denominator_Of (H, B);
   begin
      Normalize (H, N1 * N2, D1 * D2, Result, Status);
   end Real_Mul;

   procedure Real_Div
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      N1 : constant Valid_Big_Integer := Numerator_Of (H, A);
      D1 : constant Valid_Big_Integer := Denominator_Of (H, A);
      N2 : constant Valid_Big_Integer := Numerator_Of (H, B);
      D2 : constant Valid_Big_Integer := Denominator_Of (H, B);
   begin
      Result := Void_Value;
      if N2 = To_Big_Integer (0) then
         Status := Error_Division_By_Zero;
         return;
      end if;
      Normalize (H, N1 * D2, D1 * N2, Result, Status);
   end Real_Div;

   --  Compare two exact reals: -1, 0 or 1.  Cross-multiplication keeps the
   --  comparison exact; both denominators are positive by construction.
   procedure Compare_Real
     (H   : Heap_Type;
      A   : Value;
      B   : Value;
      Cmp : out Integer;
      Ok  : out Boolean)
     with Pre => H.Ready
   is
      N1 : constant Valid_Big_Integer := Numerator_Of (H, A);
      N2 : constant Valid_Big_Integer := Numerator_Of (H, B);
      L  : constant Valid_Big_Integer := N1 * Denominator_Of (H, B);
      R  : constant Valid_Big_Integer := N2 * Denominator_Of (H, A);
   begin
      Cmp := 0;
      Ok := False;
      if not Is_Exact_Real (H, A) or else not Is_Exact_Real (H, B) then
         return;
      end if;
      if L < R then
         Cmp := -1;
      elsif L > R then
         Cmp := 1;
      end if;
      Ok := True;
   end Compare_Real;

   function Is_Zero_Real (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready
   is
      K : constant Cell_Kind := Kind_Of_Value (H, V);
   begin
      if Is_Fixnum (V) then
         return V.N = 0;
      elsif Is_Flonum (V) then
         return V.F = 0.0;
      elsif K = Cell_Bigint then
         return To_Big_Value (H, V) = To_Big_Integer (0);
      elsif K = Cell_Rational then
         return Numerator_Of (H, V) = To_Big_Integer (0);
      end if;
      return False;
   end Is_Zero_Real;

   function Is_Positive_Real (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready
   is
      K : constant Cell_Kind := Kind_Of_Value (H, V);
   begin
      if Is_Fixnum (V) then
         return V.N > 0;
      elsif Is_Flonum (V) then
         return V.F > 0.0;
      elsif K = Cell_Bigint then
         return To_Big_Value (H, V) > To_Big_Integer (0);
      elsif K = Cell_Rational then
         return Numerator_Of (H, V) > To_Big_Integer (0);
      end if;
      return False;
   end Is_Positive_Real;

   function Is_Negative_Real (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready
   is
      K : constant Cell_Kind := Kind_Of_Value (H, V);
   begin
      if Is_Fixnum (V) then
         return V.N < 0;
      elsif Is_Flonum (V) then
         return V.F < 0.0;
      elsif K = Cell_Bigint then
         return To_Big_Value (H, V) < To_Big_Integer (0);
      elsif K = Cell_Rational then
         return Numerator_Of (H, V) < To_Big_Integer (0);
      end if;
      return False;
   end Is_Negative_Real;

   function Is_Real_Value (H : Heap_Type; V : Value) return Boolean
   is
      K    : constant Cell_Kind := Kind_Of_Value (H, V);
      C    : Cell;
      Good : Boolean;
   begin
      if Is_Fixnum (V) or else Is_Flonum (V) then
         return True;
      elsif K = Cell_Bigint or else K = Cell_Rational then
         return True;
      elsif K = Cell_Complex and then Is_Handle (V) then
         Fetch (H, To_Handle (V), C, Good);
         return Good and then Is_Zero_Real (H, C.Cdr);
      end if;
      return False;
   end Is_Real_Value;

   function Is_Zero_Number (H : Heap_Type; V : Value) return Boolean
   is
      C    : Cell;
      Good : Boolean;
   begin
      if not Is_Real_Value (H, V) then
         return False;
      end if;
      if Kind_Of_Value (H, V) = Cell_Complex then
         if not Is_Handle (V) then
            return False;
         end if;
         Fetch (H, To_Handle (V), C, Good);
         return Good and then Is_Zero_Real (H, C.Car)
           and then Is_Zero_Real (H, C.Cdr);
      end if;
      return Is_Zero_Real (H, V);
   end Is_Zero_Number;

   function Is_Positive_Number (H : Heap_Type; V : Value) return Boolean
   is
      C    : Cell;
      Good : Boolean;
   begin
      if not Is_Real_Value (H, V) then
         return False;
      end if;
      if Kind_Of_Value (H, V) = Cell_Complex then
         if not Is_Handle (V) then
            return False;
         end if;
         Fetch (H, To_Handle (V), C, Good);
         return Good and then Is_Positive_Real (H, C.Car);
      end if;
      return Is_Positive_Real (H, V);
   end Is_Positive_Number;

   function Is_Negative_Number (H : Heap_Type; V : Value) return Boolean
   is
      C    : Cell;
      Good : Boolean;
   begin
      if not Is_Real_Value (H, V) then
         return False;
      end if;
      if Kind_Of_Value (H, V) = Cell_Complex then
         if not Is_Handle (V) then
            return False;
         end if;
         Fetch (H, To_Handle (V), C, Good);
         return Good and then Is_Negative_Real (H, C.Car);
      end if;
      return Is_Negative_Real (H, V);
   end Is_Negative_Number;

   function Is_Odd_Integer (H : Heap_Type; V : Value) return Boolean is
     (To_Big_Value (H, V) mod To_Big_Integer (2) /= To_Big_Integer (0));

   function Is_Even_Integer (H : Heap_Type; V : Value) return Boolean is
     (To_Big_Value (H, V) mod To_Big_Integer (2) = To_Big_Integer (0));

   function Is_Integer_Real (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready
   is
      K : constant Cell_Kind := Kind_Of_Value (H, V);
      F : Long_Float;
      I : Integer_64;
   begin
      if Is_Fixnum (V) then
         return True;
      elsif K = Cell_Bigint then
         return True;
      elsif Is_Flonum (V) then
         F := V.F;
         if not Float_In_Range (F) or else abs F > 9.0E18 then
            return False;
         end if;
         I := Integer_64 (F);
         return Long_Float (I) = F;
      end if;
      return False;
   end Is_Integer_Real;

   function Is_Integer_Value (H : Heap_Type; V : Value) return Boolean
   is
      K    : constant Cell_Kind := Kind_Of_Value (H, V);
      C    : Cell;
      Good : Boolean;
   begin
      if Is_Integer_Real (H, V) then
         return True;
      elsif K = Cell_Rational then
         return False;
      elsif K = Cell_Complex and then Is_Handle (V) then
         Fetch (H, To_Handle (V), C, Good);
         return Good and then Is_Zero_Real (H, C.Cdr)
           and then Is_Integer_Real (H, C.Car);
      end if;
      return False;
   end Is_Integer_Value;

   function Is_Rational_Real (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready
   is
      K : constant Cell_Kind := Kind_Of_Value (H, V);
   begin
      if Is_Fixnum (V) then
         return True;
      elsif Is_Flonum (V) then
         return Float_In_Range (V.F);
      elsif K = Cell_Bigint or else K = Cell_Rational then
         return True;
      end if;
      return False;
   end Is_Rational_Real;

   function Is_Rational_Value (H : Heap_Type; V : Value) return Boolean
   is
      C    : Cell;
      Good : Boolean;
   begin
      if Is_Rational_Real (H, V) then
         return True;
      elsif Kind_Of_Value (H, V) = Cell_Complex and then Is_Handle (V) then
         Fetch (H, To_Handle (V), C, Good);
         return Good and then Is_Zero_Real (H, C.Cdr)
           and then Is_Rational_Real (H, C.Car);
      end if;
      return False;
   end Is_Rational_Value;

   function Is_Complex_Value (H : Heap_Type; V : Value) return Boolean is
     (Is_Number (H, V));

   function Any_Tower_Value
     (H   : Heap_Type;
      Arr : Value_Array;
      Len : Natural) return Boolean
   is
      Res : Boolean := False;
   begin
      if Len > Arr'Length then
         return False;
      end if;
      for I in 1 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         if Is_Tower_Value (H, Arr (I)) then
            Res := True;
         end if;
      end loop;
      return Res;
   end Any_Tower_Value;

   function Any_Float (Arr : Value_Array; Len : Natural) return Boolean is
     (for some I in 1 .. Len => Arr (I).Kind = Kind_Flonum)
     with Pre => Len <= Arr'Length;

   procedure Safe_Divide
     (A      : Long_Float;
      B      : Long_Float;
      X      : out Long_Float;
      Status : out Error_Code)
   is
   begin
      X := 0.0;
      if B = 0.0 then
         Status := Error_Division_By_Zero;
         return;
      end if;
      if not Float_In_Range (A) or else not Float_In_Range (B) then
         Status := Error_Overflow;
         return;
      end if;
      if abs B >= 1.0
        or else (abs A <= 1.0E300 and then abs B >= 1.0E-8)
      then
         X := A / B;
         Status := No_Error;
      else
         Status := Error_Overflow;
      end if;
   end Safe_Divide;

   --  Exact integer or flonum as a double.  A bignum goes through the same
   --  bounded decimal parser the reader uses, so its magnitude is checked
   --  by one code path.
   --  Fixnum, flonum or bignum as a double.  Rational conversion is the
   --  public To_Float below; a rational's parts are integers by
   --  construction, so this helper never sees a rational and never
   --  recurses.
   procedure Scalar_To_Float
     (H  : Heap_Type;
      V  : Value;
      X  : out Long_Float;
      Ok : out Boolean)
     with Pre => H.Ready
   is
      C     : Cell;
      Good  : Boolean;
      Is_F  : Boolean;
   begin
      X := 0.0;
      Ok := False;
      if Is_Fixnum (V) then
         X := Long_Float (V.N);
         Ok := True;
      elsif Is_Flonum (V) then
         X := V.F;
         Ok := True;
      elsif Is_Handle (V) then
         Fetch (H, To_Handle (V), C, Good);
         if not Good then
            return;
         end if;
         if C.Kind = Cell_Bigint then
            Tr7.Reader.Parse_Float (Text_Of (C), Is_F, X, Ok);
            Ok := Ok and then Is_F;
            if not Ok then
               X := 0.0;
            end if;
         end if;
      end if;
   end Scalar_To_Float;

   procedure To_Float
     (H  : Heap_Type;
      V  : Value;
      X  : out Long_Float;
      Ok : out Boolean)
   is
      C      : Cell;
      Good   : Boolean;
      XN, XD : Long_Float;
      Status : Error_Code;
   begin
      if Is_Handle (V) then
         Fetch (H, To_Handle (V), C, Good);
         if Good and then C.Kind = Cell_Rational then
            Scalar_To_Float (H, C.Car, XN, Good);
            if not Good then
               X := 0.0;
               Ok := False;
               return;
            end if;
            Scalar_To_Float (H, C.Cdr, XD, Good);
            if not Good then
               X := 0.0;
               Ok := False;
               return;
            end if;
            Safe_Divide (XN, XD, X, Status);
            Ok := Status = No_Error;
            return;
         end if;
      end if;
      Scalar_To_Float (H, V, X, Ok);
   end To_Float;

   --  All operands as doubles, or Error_Type.  Used by the inexact branch.
   procedure All_To_Float
     (H      : Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Out_Arr : out Value_Array;
      Status : out Error_Code)
     with Pre => H.Ready and then Len <= Arr'Length
   is
      Good : Boolean;
   begin
      Out_Arr := [others => Void_Value];
      Status := Error_Type;
      for I in 1 .. Len loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (Len <= Arr'Length);
         To_Float (H, Arr (I), Out_Arr (I).F, Good);
         if not Good then
            return;
         end if;
         Out_Arr (I).Kind := Kind_Flonum;
      end loop;
      Status := No_Error;
   end All_To_Float;

   procedure Float_Add_All
     (Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
     with Pre => Len <= Arr'Length
   is
      Acc  : Long_Float := 0.0;
      Term : Long_Float;
   begin
      Result := Void_Value;
      for I in 1 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         pragma Loop_Invariant (abs Acc <= Long_Float'Last);
         Term := Arr (I).F;
         if not Float_In_Range (Acc) or else not Float_In_Range (Term) then
            Status := Error_Overflow;
            return;
         end if;
         if abs Acc <= 1.0 or else abs Term <= 1.0
           or else (abs Acc <= Long_Float'Last / 2.0
                    and then abs Term <= Long_Float'Last / 2.0)
         then
            Acc := Acc + Term;
         else
            Status := Error_Overflow;
            return;
         end if;
      end loop;
      Result := From_Flonum (Acc);
      Status := No_Error;
   end Float_Add_All;

   procedure Float_Sub_All
     (Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
     with Pre => Len <= Arr'Length and then Len >= 1
   is
      Acc  : Long_Float;
      Term : Long_Float;
   begin
      Result := Void_Value;
      Acc := Arr (1).F;
      if not Float_In_Range (Acc) then
         Status := Error_Overflow;
         return;
      end if;
      if Len = 1 then
         Acc := -Acc;
      else
         for I in 2 .. Len loop
            pragma Loop_Invariant (Len <= Arr'Length);
            pragma Loop_Invariant (abs Acc <= Long_Float'Last);
            Term := Arr (I).F;
            if not Float_In_Range (Acc) or else not Float_In_Range (Term) then
               Status := Error_Overflow;
               return;
            end if;
            if abs Acc <= 1.0 or else abs Term <= 1.0
              or else (abs Acc <= Long_Float'Last / 2.0
                       and then abs Term <= Long_Float'Last / 2.0)
            then
               Acc := Acc - Term;
            else
               Status := Error_Overflow;
               return;
            end if;
         end loop;
      end if;
      Result := From_Flonum (Acc);
      Status := No_Error;
   end Float_Sub_All;

   procedure Float_Mul_All
     (Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
     with Pre => Len <= Arr'Length
   is
      Acc  : Long_Float := 1.0;
      Term : Long_Float;
   begin
      Result := Void_Value;
      for I in 1 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         pragma Loop_Invariant (abs Acc <= Long_Float'Last);
         Term := Arr (I).F;
         if not Float_In_Range (Acc) or else not Float_In_Range (Term) then
            Status := Error_Overflow;
            return;
         end if;
         if abs Acc <= 1.0 or else abs Term <= 1.0
           or else (abs Acc <= 1.3E154 and then abs Term <= 1.3E154)
           or else (abs Acc <= Long_Float'Last / 2.0
                    and then abs Term <= 2.0)
         then
            Acc := Acc * Term;
         else
            Status := Error_Overflow;
            return;
         end if;
      end loop;
      Result := From_Flonum (Acc);
      Status := No_Error;
   end Float_Mul_All;

   --  Split a number into real and imaginary parts; a real number has an
   --  exact zero imaginary part.
   procedure Decompose
     (H  : Heap_Type;
      V  : Value;
      Re : out Value;
      Im : out Value)
     with Pre => H.Ready
   is
      C    : Cell;
      Good : Boolean;
   begin
      Re := V;
      Im := From_Fixnum (0);
      if not Is_Handle (V) then
         return;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      if Good and then C.Kind = Cell_Complex then
         Re := C.Car;
         Im := C.Cdr;
      end if;
   end Decompose;

   function Is_Complex_Cell (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready
   is
   begin
      return Kind_Of_Value (H, V) = Cell_Complex;
   end Is_Complex_Cell;

   function Any_Complex
     (H   : Heap_Type;
      Arr : Value_Array;
      Len : Natural) return Boolean
   is
      Res : Boolean := False;
   begin
      if Len > Arr'Length then
         return False;
      end if;
      for I in 1 .. Len loop
         pragma Loop_Invariant (Len <= Arr'Length);
         if Is_Complex_Cell (H, Arr (I)) then
            Res := True;
         end if;
      end loop;
      return Res;
   end Any_Complex;

   procedure Make_Complex
     (H      : in out Heap_Type;
      Re     : Value;
      Im     : Value;
      Result : out Value;
      Status : out Error_Code)
   is
      Hd   : Handle;
      Good : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if not Is_Number (H, Re) or else not Is_Number (H, Im) then
         return;
      end if;
      if not Is_Real_Value (H, Re) or else not Is_Real_Value (H, Im) then
         return;
      end if;
      if Is_Zero_Real (H, Im) and then Is_Exact (H, Im) then
         Result := Re;
         Status := No_Error;
         return;
      end if;
      New_Complex (H, Re, Im, Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end Make_Complex;

   procedure Make_Polar
     (H      : in out Heap_Type;
      R      : Value;
      Theta  : Value;
      Result : out Value;
      Status : out Error_Code)
   is
      RF, TF : Long_Float;
      GR, GT : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if not Is_Real_Value (H, R) or else not Is_Real_Value (H, Theta) then
         return;
      end if;
      To_Float (H, R, RF, GR);
      To_Float (H, Theta, TF, GT);
      if not GR or else not GT then
         Status := Error_Overflow;
         return;
      end if;
      declare
         C : Long_Float := Tr7.IEEE.Cos_Value (TF);
         S : Long_Float := Tr7.IEEE.Sin_Value (TF);
      begin
         --  The standard library's cosine and sine are bounded by one;
         --  the clamps make that a path fact for the product's range
         --  check without a contract on the trusted body.
         if not Float_In_Range (C) or else abs C > 1.0 then
            C := 0.0;
         end if;
         if not Float_In_Range (S) or else abs S > 1.0 then
            S := 0.0;
         end if;
         if not Float_In_Range (RF) then
            Status := Error_Overflow;
            return;
         end if;
         Make_Complex
           (H, From_Flonum (RF * C), From_Flonum (RF * S), Result, Status);
      end;
   end Make_Polar;

   procedure Real_Part
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
   is
      Re, Im : Value;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if not Is_Number (H, V) then
         return;
      end if;
      Decompose (H, V, Re, Im);
      pragma Unreferenced (Im);
      Result := Re;
      Status := No_Error;
   end Real_Part;

   procedure Imag_Part
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
   is
      Re, Im : Value;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if not Is_Number (H, V) then
         return;
      end if;
      Decompose (H, V, Re, Im);
      pragma Unreferenced (Re);
      Result := Im;
      Status := No_Error;
   end Imag_Part;

   procedure Magnitude
     (H      : in out Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
   is
      Re, Im : Value;
      X, Y   : Long_Float;
      GX, GY : Boolean;
      Sq     : Long_Float;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if not Is_Number (H, V) then
         return;
      end if;
      if not Is_Complex_Cell (H, V) then
         Abs_Value (H, V, Result, Status);
         return;
      end if;
      Decompose (H, V, Re, Im);
      To_Float (H, Re, X, GX);
      To_Float (H, Im, Y, GY);
      if not GX or else not GY
        or else not Float_In_Range (X) or else not Float_In_Range (Y)
        or else abs X > 1.0E154 or else abs Y > 1.0E154
      then
         Status := Error_Overflow;
         return;
      end if;
      declare
         XS : constant Long_Float := X * X;
         YS : constant Long_Float := Y * Y;
      begin
         if abs XS > Long_Float'Last / 2.0
           or else abs YS > Long_Float'Last / 2.0
         then
            Status := Error_Overflow;
            return;
         end if;
         Sq := XS + YS;
      end;
      if not Float_In_Range (Sq) then
         Status := Error_Overflow;
         return;
      end if;
      Result := From_Flonum (Tr7.IEEE.Sqrt_Value (Sq));
      Status := No_Error;
   end Magnitude;

   --  One real operation on parts that may be exact or inexact.  Exact
   --  operands take the rational path; one flonum makes the result a
   --  double, with the same guarded arithmetic the flat float path uses.
   procedure Real_Plus
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      X, Y : Long_Float;
      GX, GY : Boolean;
   begin
      if Is_Flonum (A) or else Is_Flonum (B) then
         To_Float (H, A, X, GX);
         To_Float (H, B, Y, GY);
         if not GX or else not GY then
            Result := Void_Value;
            Status := Error_Overflow;
            return;
         end if;
         if Float_In_Range (X) and then Float_In_Range (Y)
           and then (abs X <= 1.0 or else abs Y <= 1.0
                     or else (abs X <= Long_Float'Last / 2.0
                              and then abs Y <= Long_Float'Last / 2.0))
         then
            Result := From_Flonum (X + Y);
            Status := No_Error;
         else
            Result := Void_Value;
            Status := Error_Overflow;
         end if;
         return;
      end if;
      Real_Add (H, A, B, Result, Status);
   end Real_Plus;

   procedure Real_Minus
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      X, Y : Long_Float;
      GX, GY : Boolean;
   begin
      if Is_Flonum (A) or else Is_Flonum (B) then
         To_Float (H, A, X, GX);
         To_Float (H, B, Y, GY);
         if not GX or else not GY then
            Result := Void_Value;
            Status := Error_Overflow;
            return;
         end if;
         if Float_In_Range (X) and then Float_In_Range (Y)
           and then (abs X <= 1.0 or else abs Y <= 1.0
                     or else (abs X <= Long_Float'Last / 2.0
                              and then abs Y <= Long_Float'Last / 2.0))
         then
            Result := From_Flonum (X - Y);
            Status := No_Error;
         else
            Result := Void_Value;
            Status := Error_Overflow;
         end if;
         return;
      end if;
      Real_Sub (H, A, B, Result, Status);
   end Real_Minus;

   procedure Real_Times
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      X, Y : Long_Float;
      GX, GY : Boolean;
   begin
      if Is_Flonum (A) or else Is_Flonum (B) then
         To_Float (H, A, X, GX);
         To_Float (H, B, Y, GY);
         if not GX or else not GY then
            Result := Void_Value;
            Status := Error_Overflow;
            return;
         end if;
         if Float_In_Range (X) and then Float_In_Range (Y)
           and then (abs X <= 1.0 or else abs Y <= 1.0
                     or else (abs X <= 1.3E154 and then abs Y <= 1.3E154)
                     or else (abs X <= Long_Float'Last / 2.0
                              and then abs Y <= 2.0))
         then
            Result := From_Flonum (X * Y);
            Status := No_Error;
         else
            Result := Void_Value;
            Status := Error_Overflow;
         end if;
         return;
      end if;
      Real_Mul (H, A, B, Result, Status);
   end Real_Times;

   procedure Real_Quotient
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      X, Y : Long_Float;
      GX, GY : Boolean;
   begin
      if Is_Flonum (A) or else Is_Flonum (B) then
         To_Float (H, A, X, GX);
         To_Float (H, B, Y, GY);
         if not GX or else not GY then
            Result := Void_Value;
            Status := Error_Overflow;
            return;
         end if;
         Safe_Divide (X, Y, X, Status);
         if Status = No_Error then
            Result := From_Flonum (X);
         else
            Result := Void_Value;
         end if;
         return;
      end if;
      Real_Div (H, A, B, Result, Status);
   end Real_Quotient;

   procedure Negate_Value
     (H      : in out Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Re, Im : Value;
      NR, NI : Value;
      St     : Error_Code;
   begin
      if Is_Complex_Cell (H, V) then
         Decompose (H, V, Re, Im);
         Real_Minus (H, From_Fixnum (0), Re, NR, St);
         if St /= No_Error then
            Result := Void_Value;
            Status := St;
            return;
         end if;
         Real_Minus (H, From_Fixnum (0), Im, NI, St);
         if St /= No_Error then
            Result := Void_Value;
            Status := St;
            return;
         end if;
         Make_Complex (H, NR, NI, Result, Status);
         return;
      end if;
      Negate (H, V, Result, Status);
   end Negate_Value;

   procedure Add_Value
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      RA, IA, RB, IB : Value;
      R, I           : Value;
      St             : Error_Code;
   begin
      if Is_Complex_Cell (H, A) or else Is_Complex_Cell (H, B) then
         Decompose (H, A, RA, IA);
         Decompose (H, B, RB, IB);
         Real_Plus (H, RA, RB, R, St);
         if St /= No_Error then
            Result := Void_Value;
            Status := St;
            return;
         end if;
         Real_Plus (H, IA, IB, I, St);
         if St /= No_Error then
            Result := Void_Value;
            Status := St;
            return;
         end if;
         Make_Complex (H, R, I, Result, Status);
         return;
      end if;
      Real_Plus (H, A, B, Result, Status);
   end Add_Value;

   procedure Sub_Value
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      RA, IA, RB, IB : Value;
      R, I           : Value;
      St             : Error_Code;
   begin
      if Is_Complex_Cell (H, A) or else Is_Complex_Cell (H, B) then
         Decompose (H, A, RA, IA);
         Decompose (H, B, RB, IB);
         Real_Minus (H, RA, RB, R, St);
         if St /= No_Error then
            Result := Void_Value;
            Status := St;
            return;
         end if;
         Real_Minus (H, IA, IB, I, St);
         if St /= No_Error then
            Result := Void_Value;
            Status := St;
            return;
         end if;
         Make_Complex (H, R, I, Result, Status);
         return;
      end if;
      Real_Minus (H, A, B, Result, Status);
   end Sub_Value;

   procedure Mul_Value
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      RA, IA, RB, IB : Value;
      P, Q, R, I     : Value;
      St             : Error_Code;
   begin
      if Is_Complex_Cell (H, A) or else Is_Complex_Cell (H, B) then
         Decompose (H, A, RA, IA);
         Decompose (H, B, RB, IB);
         --  (a+bi)(c+di) = (ac-bd) + (ad+bc)i
         Real_Times (H, RA, RB, P, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Real_Times (H, IA, IB, Q, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Real_Minus (H, P, Q, R, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Real_Times (H, RA, IB, P, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Real_Times (H, IA, RB, Q, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Real_Plus (H, P, Q, I, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Make_Complex (H, R, I, Result, Status);
         return;
      end if;
      Real_Times (H, A, B, Result, Status);
   end Mul_Value;

   procedure Div_Value
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      RA, IA, RB, IB : Value;
      D, P, Q, R, I  : Value;
      St             : Error_Code;
   begin
      if Is_Complex_Cell (H, A) or else Is_Complex_Cell (H, B) then
         Decompose (H, A, RA, IA);
         Decompose (H, B, RB, IB);
         --  (a+bi)/(c+di) = ((ac+bd) + (bc-ad)i) / (c*c + d*d)
         Real_Times (H, RB, RB, P, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Real_Times (H, IB, IB, Q, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Real_Plus (H, P, Q, D, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         if Is_Zero_Real (H, D) then
            Result := Void_Value;
            Status := Error_Division_By_Zero;
            return;
         end if;
         Real_Times (H, RA, RB, P, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Real_Times (H, IA, IB, Q, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         declare
            Sum : Value;
         begin
            Real_Plus (H, P, Q, Sum, St);
            if St /= No_Error then
               Result := Void_Value; Status := St; return;
            end if;
            Real_Quotient (H, Sum, D, R, St);
         end;
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Real_Times (H, IA, RB, P, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Real_Times (H, RA, IB, Q, St);
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         declare
            Dif : Value;
         begin
            Real_Minus (H, P, Q, Dif, St);
            if St /= No_Error then
               Result := Void_Value; Status := St; return;
            end if;
            Real_Quotient (H, Dif, D, I, St);
         end;
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         if St /= No_Error then
            Result := Void_Value; Status := St; return;
         end if;
         Make_Complex (H, R, I, Result, Status);
         return;
      end if;
      Real_Quotient (H, A, B, Result, Status);
   end Div_Value;

   procedure Real_Equal
     (H      : Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Boolean)
     with Pre => H.Ready
   is
      X, Y   : Long_Float;
      GX, GY : Boolean;
      Cmp    : Integer;
      Ok     : Boolean;
   begin
      if Is_Exact_Real (H, A) and then Is_Exact_Real (H, B) then
         Compare_Real (H, A, B, Cmp, Ok);
         Result := Ok and then Cmp = 0;
         return;
      end if;
      To_Float (H, A, X, GX);
      To_Float (H, B, Y, GY);
      Result := GX and then GY and then X = Y;
   end Real_Equal;

   procedure Numeric_Equal
     (H      : Heap_Type;
      A      : Value;
      B      : Value;
      Result : out Boolean)
     with Pre => H.Ready
   is
      RA, IA, RB, IB : Value;
      ER, EI         : Boolean;
   begin
      if not Is_Number (H, A) or else not Is_Number (H, B) then
         Result := False;
         return;
      end if;
      Decompose (H, A, RA, IA);
      Decompose (H, B, RB, IB);
      Real_Equal (H, RA, RB, ER);
      Real_Equal (H, IA, IB, EI);
      Result := ER and then EI;
   end Numeric_Equal;

   procedure Add_All
     (H      : in out Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
   is
      Conv   : Value_Array;
      Cur    : Value;
      Tmp    : Value;
      St     : Error_Code;
      Has_Cx : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if Len > Arr'Length then
         return;
      end if;
      Has_Cx := Any_Complex (H, Arr, Len);
      if not Has_Cx and then Any_Float (Arr, Len) then
         All_To_Float (H, Arr, Len, Conv, Status);
         if Status /= No_Error then
            return;
         end if;
         Float_Add_All (Conv, Len, Result, Status);
         return;
      end if;
      if Len = 0 then
         Result := From_Fixnum (0);
         Status := No_Error;
         return;
      end if;
      for I in 1 .. Len loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (Len <= Arr'Length);
         if (if Has_Cx then not Is_Number (H, Arr (I))
             else not Is_Exact_Real (H, Arr (I)))
         then
            return;
         end if;
      end loop;
      Cur := Arr (1);
      for I in 2 .. Len loop
         pragma Loop_Invariant (H.Ready);
         Add_Value (H, Cur, Arr (I), Tmp, St);
         if St /= No_Error then
            Status := St;
            return;
         end if;
         Cur := Tmp;
      end loop;
      Result := Cur;
      Status := No_Error;
   end Add_All;

   procedure Sub_All
     (H      : in out Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
   is
      Conv   : Value_Array;
      Cur    : Value;
      Tmp    : Value;
      St     : Error_Code;
      Has_Cx : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if Len > Arr'Length then
         return;
      end if;
      if Len = 0 then
         Status := Error_Wrong_Arity;
         return;
      end if;
      Has_Cx := Any_Complex (H, Arr, Len);
      if not Has_Cx and then Any_Float (Arr, Len) then
         All_To_Float (H, Arr, Len, Conv, Status);
         if Status /= No_Error then
            return;
         end if;
         Float_Sub_All (Conv, Len, Result, Status);
         return;
      end if;
      for I in 1 .. Len loop
         pragma Loop_Invariant (H.Ready);
         if (if Has_Cx then not Is_Number (H, Arr (I))
             else not Is_Exact_Real (H, Arr (I)))
         then
            return;
         end if;
      end loop;
      if Len = 1 then
         Negate_Value (H, Arr (1), Result, Status);
         return;
      end if;
      Cur := Arr (1);
      for I in 2 .. Len loop
         pragma Loop_Invariant (H.Ready);
         Sub_Value (H, Cur, Arr (I), Tmp, St);
         if St /= No_Error then
            Status := St;
            return;
         end if;
         Cur := Tmp;
      end loop;
      Result := Cur;
      Status := No_Error;
   end Sub_All;

   procedure Mul_All
     (H      : in out Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
   is
      Conv   : Value_Array;
      Cur    : Value;
      Tmp    : Value;
      St     : Error_Code;
      Has_Cx : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if Len > Arr'Length then
         return;
      end if;
      Has_Cx := Any_Complex (H, Arr, Len);
      if not Has_Cx and then Any_Float (Arr, Len) then
         All_To_Float (H, Arr, Len, Conv, Status);
         if Status /= No_Error then
            return;
         end if;
         Float_Mul_All (Conv, Len, Result, Status);
         return;
      end if;
      for I in 1 .. Len loop
         pragma Loop_Invariant (H.Ready);
         if (if Has_Cx then not Is_Number (H, Arr (I))
             else not Is_Exact_Real (H, Arr (I)))
         then
            return;
         end if;
      end loop;
      Cur := From_Fixnum (1);
      for I in 1 .. Len loop
         pragma Loop_Invariant (H.Ready);
         Mul_Value (H, Cur, Arr (I), Tmp, St);
         if St /= No_Error then
            Status := St;
            return;
         end if;
         Cur := Tmp;
      end loop;
      Result := Cur;
      Status := No_Error;
   end Mul_All;

   procedure Float_Div_All
     (Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
     with Pre => Len <= Arr'Length and then Len >= 1
   is
      Acc  : Long_Float;
      Term : Long_Float;
      X    : Long_Float := 0.0;
   begin
      Result := Void_Value;
      Acc := Arr (1).F;
      if Len = 1 then
         Safe_Divide (1.0, Acc, X, Status);
      else
         for I in 2 .. Len loop
            pragma Loop_Invariant (Len <= Arr'Length);
            Term := Arr (I).F;
            Safe_Divide (Acc, Term, X, Status);
            if Status /= No_Error then
               return;
            end if;
            Acc := X;
         end loop;
         Status := No_Error;
      end if;
      if Status = No_Error then
         Result := From_Flonum (X);
      end if;
   end Float_Div_All;

   procedure Div_All
     (H      : in out Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
   is
      Conv   : Value_Array;
      Cur    : Value;
      Tmp    : Value;
      St     : Error_Code;
      Has_Cx : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if Len > Arr'Length then
         return;
      end if;
      if Len = 0 then
         Status := Error_Wrong_Arity;
         return;
      end if;
      Has_Cx := Any_Complex (H, Arr, Len);
      if not Has_Cx and then Any_Float (Arr, Len) then
         All_To_Float (H, Arr, Len, Conv, Status);
         if Status /= No_Error then
            return;
         end if;
         Float_Div_All (Conv, Len, Result, Status);
         return;
      end if;
      for I in 1 .. Len loop
         pragma Loop_Invariant (H.Ready);
         if (if Has_Cx then not Is_Number (H, Arr (I))
             else not Is_Exact_Real (H, Arr (I)))
         then
            return;
         end if;
      end loop;
      if Len = 1 then
         Div_Value (H, From_Fixnum (1), Arr (1), Result, Status);
         return;
      end if;
      Cur := Arr (1);
      for I in 2 .. Len loop
         pragma Loop_Invariant (H.Ready);
         Div_Value (H, Cur, Arr (I), Tmp, St);
         if St /= No_Error then
            Status := St;
            return;
         end if;
         Cur := Tmp;
      end loop;
      Result := Cur;
      Status := No_Error;
   end Div_All;





   function Real_Eqv
     (H : Heap_Type;
      A : Value;
      B : Value) return Boolean
     with Pre => H.Ready
   is
      Cmp : Integer;
      Ok  : Boolean;
   begin
      if Is_Exact (H, A) /= Is_Exact (H, B) then
         return False;
      end if;
      if Is_Flonum (A) and then Is_Flonum (B) then
         return A.F = B.F;
      end if;
      if Is_Exact_Real (H, A) and then Is_Exact_Real (H, B) then
         Compare_Real (H, A, B, Cmp, Ok);
         return Ok and then Cmp = 0;
      end if;
      return False;
   end Real_Eqv;

   procedure Integer_Divide
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Op     : Integer_Op;
      Result : out Value;
      Status : out Error_Code)
   is
   begin
      Result := Void_Value;
      Status := Error_Type;
      if not Is_Exact_Integer (H, A)
        or else not Is_Exact_Integer (H, B)
      then
         return;
      end if;
      declare
         X : constant Valid_Big_Integer := To_Big_Value (H, A);
         Y : constant Valid_Big_Integer := To_Big_Value (H, B);
      begin
         if Y = To_Big_Integer (0) then
            Status := Error_Division_By_Zero;
            return;
         end if;
         case Op is
            when Op_Quotient =>
               From_Big (H, X / Y, Result, Status);
            when Op_Remainder =>
               From_Big (H, X rem Y, Result, Status);
            when Op_Modulo =>
               --  Ada's mod for these bignums disagrees with the language
               --  rule when the divisor is negative (7 mod -3 came out
               --  -4), so derive it from rem and adjust the sign.  The
               --  result then carries the divisor's sign, as R7RS asks.
               declare
                  R : Valid_Big_Integer := X rem Y;
               begin
                  if R /= To_Big_Integer (0)
                    and then ((R > To_Big_Integer (0))
                                /= (Y > To_Big_Integer (0)))
                  then
                     R := R + Y;
                  end if;
                  From_Big (H, R, Result, Status);
               end;
         end case;
      end;
   end Integer_Divide;

   procedure Expt
     (H      : in out Heap_Type;
      Base   : Value;
      Exp    : Value;
      Result : out Value;
      Status : out Error_Code)
   is
      Cur : Value;
      Tmp : Value;
      St  : Error_Code;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if not Is_Exact_Real (H, Base)
        or else not Is_Exact_Integer (H, Exp)
      then
         return;
      end if;
      declare
         N0  : constant Valid_Big_Integer := To_Big_Value (H, Exp);
         Neg : constant Boolean := N0 < To_Big_Integer (0);
         N   : constant Valid_Big_Integer := (if Neg then -N0 else N0);
      begin
         if N > To_Big_Integer (10_000) then
            Status := Error_Overflow;
            return;
         end if;
         declare
            E : constant Natural := Natural (To_Integer (N));
         begin
            Cur := From_Fixnum (1);
            for I in 1 .. E loop
               pragma Loop_Invariant (H.Ready);
               Real_Mul (H, Cur, Base, Tmp, St);
               if St /= No_Error then
                  Status := St;
                  return;
               end if;
               Cur := Tmp;
            end loop;
            if Neg then
               if Is_Zero_Number (H, Cur) then
                  Status := Error_Division_By_Zero;
                  return;
               end if;
               Real_Div (H, From_Fixnum (1), Cur, Result, Status);
            else
               Result := Cur;
               Status := No_Error;
            end if;
         end;
      end;
   end Expt;



   function Eqv_Numeric
     (H : Heap_Type;
      A : Value;
      B : Value) return Boolean
   is
      RA, IA, RB, IB : Value;
   begin
      if not Is_Number (H, A) or else not Is_Number (H, B) then
         return False;
      end if;
      if Is_Exact (H, A) /= Is_Exact (H, B) then
         return False;
      end if;
      Decompose (H, A, RA, IA);
      Decompose (H, B, RB, IB);
      return Real_Eqv (H, RA, RB) and then Real_Eqv (H, IA, IB);
   end Eqv_Numeric;

   procedure Compare_All
     (H      : Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Mode   : Compare_Mode;
      Result : out Value;
      Status : out Error_Code)
   is
      Res    : Boolean := True;
      X, Y   : Long_Float;
      GX, GY : Boolean;
      Cmp    : Integer;
      Good   : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if Len > Arr'Length then
         return;
      end if;
      if Len = 0 then
         Result := True_Value;
         Status := No_Error;
         return;
      end if;
      for I in 1 .. Len loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (Len <= Arr'Length);
         if not Is_Number (H, Arr (I)) then
            return;
         end if;
      end loop;

      if Any_Complex (H, Arr, Len) then
         if Mode /= Cmp_Equal then
            return;
         end if;
         for I in 2 .. Len loop
            pragma Loop_Invariant (H.Ready);
            declare
               Same : Boolean;
            begin
               Numeric_Equal (H, Arr (I - 1), Arr (I), Same);
               Res := Res and then Same;
            end;
         end loop;
         Result := From_Boolean (Res);
         Status := No_Error;
         return;
      end if;

      if Any_Float (Arr, Len) then
         for I in 2 .. Len loop
            pragma Loop_Invariant (H.Ready);
            pragma Loop_Invariant (Len <= Arr'Length);
            To_Float (H, Arr (I - 1), X, GX);
            To_Float (H, Arr (I), Y, GY);
            if not GX or else not GY then
               return;
            end if;
            case Mode is
               when Cmp_Equal =>
                  Res := Res and then X = Y;
               when Cmp_Less =>
                  Res := Res and then X < Y;
               when Cmp_Greater =>
                  Res := Res and then X > Y;
               when Cmp_Less_Equal =>
                  Res := Res and then X <= Y;
               when Cmp_Greater_Equal =>
                  Res := Res and then X >= Y;
            end case;
         end loop;
         Result := From_Boolean (Res);
         Status := No_Error;
         return;
      end if;

      for I in 2 .. Len loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (Len <= Arr'Length);
         if not Is_Exact_Real (H, Arr (I - 1))
           or else not Is_Exact_Real (H, Arr (I))
         then
            return;
         end if;
         Compare_Real (H, Arr (I - 1), Arr (I), Cmp, Good);
         if not Good then
            return;
         end if;
         case Mode is
            when Cmp_Equal =>
               Res := Res and then Cmp = 0;
            when Cmp_Less =>
               Res := Res and then Cmp < 0;
            when Cmp_Greater =>
               Res := Res and then Cmp > 0;
            when Cmp_Less_Equal =>
               Res := Res and then Cmp <= 0;
            when Cmp_Greater_Equal =>
               Res := Res and then Cmp >= 0;
         end case;
      end loop;
      Result := From_Boolean (Res);
      Status := No_Error;
   end Compare_All;

   procedure Negate
     (H      : in out Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
   is
   begin
      Result := Void_Value;
      Status := Error_Type;
      if Is_Fixnum (V) then
         if V.N not in Fixnum_Min .. Fixnum_Max then
            return;
         end if;
         From_Big
           (H, -To_Big_Integer (Integer (V.N)), Result, Status);
         return;
      end if;
      if Is_Flonum (V) then
         Result := From_Flonum (-V.F);
         Status := No_Error;
         return;
      end if;
      if not Is_Exact_Real (H, V) then
         return;
      end if;
      Normalize
        (H, -Numerator_Of (H, V), Denominator_Of (H, V), Result, Status);
   end Negate;

   procedure Abs_Value
     (H      : in out Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
   is
   begin
      Result := Void_Value;
      Status := Error_Type;
      if Is_Fixnum (V) then
         if V.N not in Fixnum_Min .. Fixnum_Max then
            return;
         end if;
         From_Big
           (H, abs To_Big_Integer (Integer (V.N)), Result, Status);
         return;
      elsif Is_Flonum (V) then
         Result := From_Flonum (abs V.F);
         Status := No_Error;
         return;
      end if;
      if not Is_Exact_Real (H, V) then
         return;
      end if;
      if Is_Negative_Real (H, V) then
         Normalize
           (H, -Numerator_Of (H, V), Denominator_Of (H, V), Result, Status);
      else
         Normalize
           (H, Numerator_Of (H, V), Denominator_Of (H, V), Result, Status);
      end if;
   end Abs_Value;

   procedure Min_Max
     (H        : Heap_Type;
      Arr      : Value_Array;
      Len      : Natural;
      Pick_Max : Boolean;
      Result   : out Value;
      Status   : out Error_Code)
   is
      Best      : Value;
      Best_F    : Long_Float;
      Cur_F     : Long_Float;
      GF, GC    : Boolean;
      Cmp       : Integer;
      Good      : Boolean;
      Use_Float : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if Len = 0 or else Len > Arr'Length then
         Status := Error_Wrong_Arity;
         return;
      end if;
      for I in 1 .. Len loop
         pragma Loop_Invariant (H.Ready);
         if not Is_Number (H, Arr (I)) then
            return;
         end if;
      end loop;
      Best := Arr (1);
      Use_Float := Any_Float (Arr, Len);
      if Use_Float then
         To_Float (H, Best, Best_F, GF);
         if not GF then
            return;
         end if;
         for I in 2 .. Len loop
            pragma Loop_Invariant (H.Ready);
            To_Float (H, Arr (I), Cur_F, GC);
            if not GC then
               return;
            end if;
            if (Pick_Max and then Cur_F > Best_F)
              or else (not Pick_Max and then Cur_F < Best_F)
            then
               Best_F := Cur_F;
               Best := Arr (I);
            end if;
         end loop;
      else
         if not Is_Exact_Real (H, Best) then
            return;
         end if;
         for I in 2 .. Len loop
            pragma Loop_Invariant (H.Ready);
            if not Is_Exact_Real (H, Arr (I)) then
               return;
            end if;
            Compare_Real (H, Arr (I), Best, Cmp, Good);
            if not Good then
               return;
            end if;
            if (Pick_Max and then Cmp > 0)
              or else (not Pick_Max and then Cmp < 0)
            then
               Best := Arr (I);
            end if;
         end loop;
      end if;
      Result := Best;
      Status := No_Error;
   end Min_Max;

   procedure To_Inexact_Real
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready
   is
      X    : Long_Float;
      Good : Boolean;
   begin
      Result := Void_Value;
      Status := Error_Type;
      To_Float (H, V, X, Good);
      if not Good then
         return;
      end if;
      Result := From_Flonum (X);
      Status := No_Error;
   end To_Inexact_Real;

   procedure Exact_To_Inexact
     (H      : in out Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
   is
      Re, Im   : Value;
      NR, NI   : Value;
      SR, SI   : Error_Code;
   begin
      Result := Void_Value;
      Status := Error_Type;
      if not Is_Number (H, V) then
         return;
      end if;
      if not Is_Complex_Cell (H, V) then
         To_Inexact_Real (H, V, Result, Status);
         return;
      end if;
      Decompose (H, V, Re, Im);
      To_Inexact_Real (H, Re, NR, SR);
      if SR /= No_Error then
         Status := SR;
         return;
      end if;
      To_Inexact_Real (H, Im, NI, SI);
      if SI /= No_Error then
         Status := SI;
         return;
      end if;
      Make_Complex (H, NR, NI, Result, Status);
   end Exact_To_Inexact;

end Tr7.Numbers;
