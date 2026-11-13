with Ada.Numerics.Generic_Elementary_Functions;

package body Tr7.IEEE with
   SPARK_Mode => On
is

   package F is new Ada.Numerics.Generic_Elementary_Functions (Long_Float);

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

end Tr7.IEEE;
