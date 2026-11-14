--  Bignums: exact integers outside the fixnum range.
--
--  A bignum is an ordinary heap cell (Cell_Bigint) whose Name/Name_Len hold
--  the canonical signed decimal text.  That keeps the collector unchanged --
--  the value is inline, so there is no side table, no extra root and no
--  finalization -- and caps a bignum at Max_Text decimal digits (about 850
--  bits).  Arithmetic is delegated to Ada's standard big-integer library:
--  the text is parsed into a Big_Integer, the operation runs there, and the
--  canonical image is copied back into a cell.  The library is the trusted
--  arithmetic boundary in the same sense Tr7.IEEE is the trusted
--  elementary-function boundary; the representation and its limits are ours.
--
--  The package needs Ada 2022 for the standard Big_Integers unit.

pragma Ada_2022;

with Ada.Numerics.Big_Numbers.Big_Integers;
with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Heap; use Tr7.Heap;
with Tr7.Runtime; use Tr7.Runtime;
with Tr7.Values; use Tr7.Values;

package Tr7.Bignums with
   SPARK_Mode => On
is

   use Ada.Numerics.Big_Numbers.Big_Integers;

   --  V is a Cell_Bigint value.
   function Is_Bigint (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;

   --  V is an exact integer: a fixnum or a Cell_Bigint.
   function Is_Exact_Integer (H : Heap_Type; V : Value) return Boolean
     with Pre => H.Ready;

   --  Parse canonical decimal text (optional sign, then digits) into a
   --  Big_Integer.  Ok is false for empty or malformed input.  Written as a
   --  digit loop rather than From_String so every step is a proved
   --  operation on Valid_Big_Integer.
   procedure Parse
     (Text : String;
      B    : out Valid_Big_Integer;
      Ok   : out Boolean)
     with Pre => Text'First >= 1 and then Text'Last < Natural'Last;

   --  The canonical signed decimal image of B, copied into a text buffer.
   --  Ok is false when it does not fit Max_Text digits (the documented
   --  bignum precision limit).
   procedure Image
     (B   : Valid_Big_Integer;
      T   : out Text_Buffer;
      Len : out Natural;
      Ok  : out Boolean)
     with Post => (if Ok then Len <= Max_Text);

   --  Parse then re-image, which strips a leading plus and leading zeroes.
   procedure Canonical
     (Text : String;
      T    : out Text_Buffer;
      Len  : out Natural;
      Ok   : out Boolean)
     with
       Pre  => Text'First >= 1 and then Text'Last < Natural'Last,
       Post => (if Ok then Len <= Max_Text);

   --  The Big_Integer of an exact integer value.  The precondition is the
   --  caller's proof that the conversion is defined; the result is a
   --  Valid_Big_Integer on every path (zero for the unreachable failure
   --  case), which keeps the arithmetic loops free of uninitialized
   --  controlled objects.
   function To_Big_Value
     (H : Heap_Type;
      V : Value) return Valid_Big_Integer
     with Pre => H.Ready;

   --  Read an exact integer value (fixnum or bignum) as a Big_Integer.
   procedure To_Big
     (H  : Heap_Type;
      V  : Value;
      B  : out Valid_Big_Integer;
      Ok : out Boolean)
     with Pre => H.Ready;

   --  Store a Big_Integer as an exact integer value: a fixnum when it fits,
   --  otherwise a fresh Cell_Bigint.  Error_Overflow when its decimal image
   --  exceeds Max_Text digits or the heap is full.
   procedure From_Big
     (H      : in out Heap_Type;
      B      : Valid_Big_Integer;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   function Fits_Fixnum (B : Valid_Big_Integer) return Boolean is
     (B >= To_Big_Integer (Integer (Fixnum_Min))
        and then B <= To_Big_Integer (Integer (Fixnum_Max)));

   function To_Fixnum (B : Valid_Big_Integer) return Integer_64 is
     (Integer_64 (To_Integer (B)))
     with Pre => Fits_Fixnum (B);

   --  Normalize N/D: denominator positive, fraction reduced, and an exact
   --  integer when the denominator becomes one.  The result is a fixnum,
   --  a Cell_Bigint or a Cell_Rational, never a denominator of one.
   procedure From_Big_Ratio
     (H      : in out Heap_Type;
      N      : Valid_Big_Integer;
      D      : Valid_Big_Integer;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Make_Rational
     (H      : in out Heap_Type;
      Num    : Value;
      Den    : Value;
      Result : out Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   function Is_Zero (B : Valid_Big_Integer) return Boolean is
     (B = To_Big_Integer (0));

   function Sign (B : Valid_Big_Integer) return Integer is
     (if B > To_Big_Integer (0) then 1
      elsif B < To_Big_Integer (0) then -1
      else 0);

end Tr7.Bignums;
