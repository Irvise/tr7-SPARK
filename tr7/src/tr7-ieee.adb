with Ada.Numerics.Generic_Elementary_Functions;

package body Tr7.IEEE with
   SPARK_Mode => On
is

   package F is new Ada.Numerics.Generic_Elementary_Functions (Long_Float);

   --  C's pow, from libm (the Ada runtime already links it).  POSIX
   --  requires a correctly rounded result, while the generic's own "**"
   --  computes exp (Y * log X) and lands one ulp off for exact powers --
   --  (expt 2 100.0) is the case that showed it.  pow never raises; it
   --  reports domain errors as NaN, which callers check for.
   function C_Pow (X, Y : Long_Float) return Long_Float;
   pragma Import (C, C_Pow, "pow");

   function Plus_Infinity return Long_Float
     with SPARK_Mode => Off
   is
   begin
      return F.Exp (10_000.0);
   end Plus_Infinity;

   function Minus_Infinity return Long_Float
     with SPARK_Mode => Off
   is
   begin
      return -Plus_Infinity;
   end Minus_Infinity;

   function NaN return Long_Float
     with SPARK_Mode => Off
   is
      X : constant Long_Float := Plus_Infinity;
   begin
      return X - X;
   end NaN;

   function Power (X, Y : Long_Float) return Long_Float
     with SPARK_Mode => Off
   is
   begin
      return C_Pow (X, Y);
   exception
      when others =>
         --  pow does not raise; this is defence in depth so that no
         --  unexpected failure can escape the boundary.
         return NaN;
   end Power;

   function Sqrt_Value (X : Long_Float) return Long_Float
     with SPARK_Mode => Off
   is
   begin
      return F.Sqrt (X);
   end Sqrt_Value;

   function Cos_Value (X : Long_Float) return Long_Float
     with SPARK_Mode => Off
   is
   begin
      return F.Cos (X);
   end Cos_Value;

   function Sin_Value (X : Long_Float) return Long_Float
     with SPARK_Mode => Off
   is
   begin
      return F.Sin (X);
   end Sin_Value;

end Tr7.IEEE;
