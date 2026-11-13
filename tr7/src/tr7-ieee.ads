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

end Tr7.IEEE;
