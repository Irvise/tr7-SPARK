--  IEEE 754 special values.
--
--  Ada's standard elementary-function library is the portable way to obtain
--  infinities: Exp overflows to +Inf, and Inf - Inf is NaN on an IEEE
--  target.  Keeping these in one package makes the boundary explicit and
--  lets the reader accept the text the writer emits.


package Tr7.IEEE with
   SPARK_Mode => On
is

   function Plus_Infinity return Long_Float;
   function Minus_Infinity return Long_Float;
   function NaN return Long_Float;

   --  X raised to Y over the reals, from the standard elementary-function
   --  library.  Like the three values above, this is a trusted boundary:
   --  the body is SPARK_Mode => Off, and callers must check what comes back.
   --  A negative base with a fractional exponent is rejected before the
   --  call (it leaves the reals), and the body maps a rejected or
   --  undefined power to NaN so no exception escapes.
   function Power (X, Y : Long_Float) return Long_Float;

   --  Elementary functions for complex magnitude and polar construction.
   --  Like the special values above, their bodies are the trusted standard
   --  library boundary (SPARK_Mode => Off); there is no semantic contract
   --  beyond "the standard library's value".
   function Sqrt_Value (X : Long_Float) return Long_Float;
   function Cos_Value (X : Long_Float) return Long_Float;
   function Sin_Value (X : Long_Float) return Long_Float;

end Tr7.IEEE;
