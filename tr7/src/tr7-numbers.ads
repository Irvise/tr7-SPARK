--  Numeric-tower dispatch.
--
--  Fixnum/flonum arithmetic keeps its fast path in Tr7.Primitives.  This
--  unit owns the values that need cells -- bignums, exact rationals and
--  complex numbers -- and the mixed cases where one of them meets an
--  ordinary number.  Tr7.Primitives routes to it exactly when an operand is
--  one of those heap numbers, so the existing fixnum/flonum proofs are
--  untouched.
--
--  Exact arithmetic is carried out on Ada's Big_Integer, with rationals as
--  a normalized pair of them.  Inexact arithmetic converts exact operands
--  to Long_Float first, which is what R7RS's "inexact wins" rule asks for.

pragma Ada_2022;

with Tr7.Heap; use Tr7.Heap;
with Tr7.Runtime; use Tr7.Runtime;
with Tr7.Values; use Tr7.Values;

package Tr7.Numbers with
   SPARK_Mode => On
is

   type Compare_Mode is
     (Cmp_Equal, Cmp_Less, Cmp_Greater, Cmp_Less_Equal, Cmp_Greater_Equal);

   --  A number in the full tower: fixnum, flonum, bignum, rational or
   --  complex.
   function Is_Number (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;

   --  An exact number: fixnum, bignum, rational, or a complex whose parts
   --  are all exact.
   function Is_Exact (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;

   --  An exact integer value (fixnum or bignum).
   function Is_Exact_Integer (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;

   --  R7RS predicates over the tower.
   function Is_Integer_Value (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;
   function Is_Rational_Value (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;
   function Is_Real_Value (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;
   function Is_Complex_Value (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;

   --  Sign tests for real numbers.  NaN answers false to all three.
   function Is_Zero_Number (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;
   function Is_Positive_Number (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready and then Is_Real_Value (H, V);
   function Is_Negative_Number (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready and then Is_Real_Value (H, V);
   function Is_Odd_Integer (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;
   function Is_Even_Integer (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;

   --  V is a heap-backed tower value (bignum, rational or complex): the
   --  signal Tr7.Primitives uses to leave its fast paths.
   function Is_Tower_Value (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;

   function Any_Tower_Value
     (H   : Heap_Type;
      Arr : Value_Array;
      Len : Natural) return Boolean
     with
       Pre  => H.Ready,
       Post => (if Len > Arr'Length then Any_Tower_Value'Result = False);

   --  Exact/inexact real conversion.  Ok is false for a complex value (call
   --  the complex path instead) or an exact value whose magnitude does not
   --  fit a double.
   procedure To_Float
     (H  : Heap_Type;
      V  : Value;
      X  : out Long_Float;
      Ok : out Boolean)
     with Pre => H.Ready;

   procedure Add_All
     (H      : in out Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Sub_All
     (H      : in out Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Mul_All
     (H      : in out Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Div_All
     (H      : in out Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   type Integer_Op is (Op_Quotient, Op_Remainder, Op_Modulo);

   procedure Integer_Divide
     (H      : in out Heap_Type;
      A      : Value;
      B      : Value;
      Op     : Integer_Op;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Expt
     (H      : in out Heap_Type;
      Base   : Value;
      Exp    : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   function Eqv_Numeric
     (H : Heap_Type;
      A : Value;
      B : Value) return Boolean
     with Pre => H.Ready;

   procedure Compare_All
     (H      : Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Mode   : Compare_Mode;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready;

   procedure Negate
     (H      : in out Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Abs_Value
     (H      : in out Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Min_Max
     (H      : Heap_Type;
      Arr    : Value_Array;
      Len    : Natural;
      Pick_Max : Boolean;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready;

   --  Complex constructors and selectors.  Parts are real values; a
   --  zero exact imaginary part collapses to the real part.
   procedure Make_Complex
     (H      : in out Heap_Type;
      Re     : Value;
      Im     : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Make_Polar
     (H      : in out Heap_Type;
      R      : Value;
      Theta  : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Real_Part
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready;

   procedure Imag_Part
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
     with Pre => H.Ready;

   procedure Magnitude
     (H      : in out Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Exact_To_Inexact
     (H      : in out Heap_Type;
      V      : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

end Tr7.Numbers;
